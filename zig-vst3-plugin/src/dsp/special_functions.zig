const std = @import("std");

/// Computes the modified Bessel function of the first kind, order zero.
pub fn besselI0(value: anytype) @TypeOf(value) {
    const Sample = @TypeOf(value);
    if (Sample != f32 and Sample != f64)
        @compileError("besselI0 supports f32 and f64 values");
    if (!std.math.isFinite(value)) return 0.0;

    const scaled = value * value * 0.25;
    var sum: Sample = 1.0;
    var term: Sample = 1.0;
    var order: usize = 1;
    while (order <= 64) : (order += 1) {
        const divisor =
            @as(Sample, @floatFromInt(order)) *
            @as(Sample, @floatFromInt(order));
        term *= scaled / divisor;
        sum += term;
        if (!std.math.isFinite(sum)) return 0.0;
        if (term <= std.math.floatEps(Sample) * sum) break;
    }
    return sum;
}

pub fn EllipticIntegrals(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("elliptic integrals support f32 and f64 values");
    return struct {
        k: Sample,
        complementary: Sample,
    };
}

pub fn ellipticIntegralK(modulus: anytype) !EllipticIntegrals(
    @TypeOf(modulus),
) {
    const Sample = @TypeOf(modulus);
    if (Sample != f32 and Sample != f64)
        @compileError("ellipticIntegralK supports f32 and f64 values");
    if (!std.math.isFinite(modulus) or modulus < 0.0 or modulus >= 1.0)
        return error.InvalidEllipticModulus;
    const complementary_modulus = @sqrt(1.0 - modulus * modulus);
    return .{
        .k = completeEllipticK(Sample, modulus),
        .complementary = completeEllipticK(Sample, complementary_modulus),
    };
}

/// Evaluate the real incomplete integral of the first kind for parameter m.
pub fn ellipticIntegralF(
    amplitude: anytype,
    parameter: @TypeOf(amplitude),
) !@TypeOf(amplitude) {
    const Sample = @TypeOf(amplitude);
    if (Sample != f32 and Sample != f64)
        @compileError("ellipticIntegralF supports f32 and f64 values");
    if (!std.math.isFinite(amplitude) or
        !std.math.isFinite(parameter) or
        parameter < 0.0 or
        parameter > 1.0)
        return error.InvalidEllipticIntegralArgument;
    if (parameter == 0.0) return amplitude;

    const amplitude_f64: f64 = @floatCast(amplitude);
    const parameter_f64: f64 = @floatCast(parameter);
    if (parameter == 1.0) {
        if (@abs(amplitude_f64) >= std.math.pi / 2.0)
            return error.DivergentEllipticIntegral;
        const result = std.math.atanh(@sin(amplitude_f64));
        return @floatCast(result);
    }

    const reduced = centeredModulo(
        f64,
        amplitude_f64,
        std.math.pi,
    );
    const period_index =
        @round((amplitude_f64 - reduced) / std.math.pi);
    const sine = @sin(reduced);
    const cosine = @cos(reduced);
    const local = sine * try carlsonRf(
        cosine * cosine,
        1.0 - parameter_f64 * sine * sine,
        1.0,
    );
    const quarter_period =
        completeEllipticKFromParameter(f64, parameter_f64);
    const result = 2.0 * period_index * quarter_period + local;
    const converted: Sample = @floatCast(result);
    if (!std.math.isFinite(converted))
        return error.InvalidEllipticIntegralResult;
    return converted;
}

fn completeEllipticK(comptime Sample: type, modulus: Sample) Sample {
    return completeEllipticKFromParameter(
        Sample,
        modulus * modulus,
    );
}

fn completeEllipticKFromParameter(
    comptime Sample: type,
    parameter: Sample,
) Sample {
    if (parameter == 1.0) return std.math.inf(Sample);
    var arithmetic: Sample = 1.0;
    var geometric: Sample = @sqrt(1.0 - parameter);
    for (0..32) |_| {
        const next_arithmetic = (arithmetic + geometric) * 0.5;
        const next_geometric = @sqrt(arithmetic * geometric);
        arithmetic = next_arithmetic;
        geometric = next_geometric;
        if (@abs(arithmetic - geometric) <=
            std.math.floatEps(Sample) * arithmetic)
            break;
    }
    return std.math.pi / (2.0 * arithmetic);
}

fn carlsonRf(x: f64, y: f64, z: f64) !f64 {
    if (!std.math.isFinite(x) or
        !std.math.isFinite(y) or
        !std.math.isFinite(z) or
        x < 0.0 or
        y < 0.0 or
        z <= 0.0 or
        (x == 0.0 and y == 0.0))
        return error.InvalidCarlsonArgument;

    var current_x = x;
    var current_y = y;
    var current_z = z;
    var average: f64 = undefined;
    var delta_x: f64 = undefined;
    var delta_y: f64 = undefined;
    var delta_z: f64 = undefined;
    for (0..64) |_| {
        const root_x = @sqrt(current_x);
        const root_y = @sqrt(current_y);
        const root_z = @sqrt(current_z);
        const lambda =
            root_x * (root_y + root_z) + root_y * root_z;
        current_x = (current_x + lambda) * 0.25;
        current_y = (current_y + lambda) * 0.25;
        current_z = (current_z + lambda) * 0.25;
        average = (current_x + current_y + current_z) / 3.0;
        delta_x = (average - current_x) / average;
        delta_y = (average - current_y) / average;
        delta_z = (average - current_z) / average;
        if (@max(
            @abs(delta_x),
            @max(@abs(delta_y), @abs(delta_z)),
        ) < 0.0025) {
            const second_order =
                delta_x * delta_y - delta_z * delta_z;
            const third_order = delta_x * delta_y * delta_z;
            const correction =
                1.0 +
                (second_order / 24.0 -
                    0.1 -
                    3.0 * third_order / 44.0) *
                    second_order +
                third_order / 14.0;
            const result = correction / @sqrt(average);
            if (!std.math.isFinite(result))
                return error.InvalidEllipticIntegralResult;
            return result;
        }
    }
    return error.EllipticIntegralConvergenceFailure;
}

pub fn JacobiValues(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Jacobi elliptic functions support f32 and f64 values");
    return struct {
        sn: Sample,
        cn: Sample,
        dn: Sample,
        principal_amplitude: Sample,
    };
}

pub fn ComplexJacobiValues(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "complex Jacobi elliptic functions support f32 and f64 values",
        );
    const Complex = std.math.complex.Complex(Sample);
    return struct {
        sn: Complex,
        cn: Complex,
        dn: Complex,
    };
}

pub const JacobiFunction = enum {
    sn,
    cn,
    dn,
    ns,
    nc,
    nd,
    sc,
    sd,
    cs,
    cd,
    ds,
    dc,
};

pub const JacobiInverseBranch = struct {
    period_index: i32 = 0,
    reflected: bool = false,
};

/// Evaluates the real Jacobi elliptic functions for parameter m in [0, 1].
pub fn jacobiElliptic(
    argument: anytype,
    parameter: @TypeOf(argument),
) !JacobiValues(@TypeOf(argument)) {
    const Sample = @TypeOf(argument);
    if (Sample != f32 and Sample != f64)
        @compileError("jacobiElliptic supports f32 and f64 values");
    if (!std.math.isFinite(argument) or
        !std.math.isFinite(parameter) or
        parameter < 0.0 or
        parameter > 1.0)
        return error.InvalidJacobiArgument;
    if (parameter == 0.0) {
        return .{
            .sn = @sin(argument),
            .cn = @cos(argument),
            .dn = 1.0,
            .principal_amplitude = principalAngle(Sample, argument),
        };
    }
    if (parameter == 1.0) {
        const sn = std.math.tanh(argument);
        const dn = 1.0 / std.math.cosh(argument);
        return .{
            .sn = sn,
            .cn = dn,
            .dn = dn,
            .principal_amplitude = std.math.asin(sn),
        };
    }

    const quarter_period =
        completeEllipticKFromParameter(Sample, parameter);
    const period = 4.0 * quarter_period;
    const reduced = centeredModulo(Sample, argument, period);

    var arithmetic: Sample = 1.0;
    var geometric: Sample = @sqrt(1.0 - parameter);
    var ratios: [32]Sample = @splat(0.0);
    var count: usize = 0;
    while (count < ratios.len) : (count += 1) {
        const next_arithmetic = (arithmetic + geometric) * 0.5;
        const difference = (arithmetic - geometric) * 0.5;
        ratios[count] = difference / next_arithmetic;
        geometric = @sqrt(arithmetic * geometric);
        arithmetic = next_arithmetic;
        if (@abs(difference) <=
            std.math.floatEps(Sample) * arithmetic)
        {
            count += 1;
            break;
        }
    }
    if (count == ratios.len and
        @abs(arithmetic - geometric) >
            std.math.floatEps(Sample) * arithmetic)
        return error.JacobiConvergenceFailure;

    const scale = std.math.scalbn(
        arithmetic,
        @as(i32, @intCast(count)),
    );
    var amplitude = reduced * scale;
    var index = count;
    while (index > 0) {
        index -= 1;
        const correction = std.math.asin(
            ratios[index] * @sin(amplitude),
        );
        amplitude = (amplitude + correction) * 0.5;
    }

    const sn = @sin(amplitude);
    const cn = @cos(amplitude);
    const dn_squared = 1.0 - parameter * sn * sn;
    if (dn_squared < 0.0 or !std.math.isFinite(dn_squared))
        return error.JacobiConvergenceFailure;
    const dn = @sqrt(dn_squared);
    return .{
        .sn = sn,
        .cn = cn,
        .dn = dn,
        .principal_amplitude = principalAngle(Sample, amplitude),
    };
}

/// Evaluate one of the twelve real Jacobi functions for parameter m.
///
/// Quotient and reciprocal functions return `error.JacobiPole` when their
/// denominator is numerically indistinguishable from zero.
pub fn jacobiEllipticFunction(
    argument: anytype,
    parameter: @TypeOf(argument),
    function: JacobiFunction,
) !@TypeOf(argument) {
    const Sample = @TypeOf(argument);
    const values = try jacobiElliptic(argument, parameter);
    return switch (function) {
        .sn => values.sn,
        .cn => values.cn,
        .dn => values.dn,
        .ns => checkedJacobiRatio(Sample, 1.0, values.sn),
        .nc => checkedJacobiRatio(Sample, 1.0, values.cn),
        .nd => checkedJacobiRatio(Sample, 1.0, values.dn),
        .sc => checkedJacobiRatio(Sample, values.sn, values.cn),
        .sd => checkedJacobiRatio(Sample, values.sn, values.dn),
        .cs => checkedJacobiRatio(Sample, values.cn, values.sn),
        .cd => checkedJacobiRatio(Sample, values.cn, values.dn),
        .ds => checkedJacobiRatio(Sample, values.dn, values.sn),
        .dc => checkedJacobiRatio(Sample, values.dn, values.cn),
    };
}

/// Evaluate sn, cn, and dn for a complex argument and real parameter m.
pub fn complexJacobiElliptic(
    argument: anytype,
    parameter: @TypeOf(argument.re),
) !ComplexJacobiValues(@TypeOf(argument.re)) {
    const Sample = @TypeOf(argument.re);
    if (Sample != f32 and Sample != f64)
        @compileError("complexJacobiElliptic supports f32 and f64 values");
    const Complex = std.math.complex.Complex(Sample);
    if (@TypeOf(argument) != Complex)
        @compileError("argument must be std.math.complex.Complex(Sample)");
    if (!complexFinite(argument) or
        !std.math.isFinite(parameter) or
        parameter < 0.0 or
        parameter > 1.0)
        return error.InvalidComplexJacobiArgument;

    if (parameter == 0.0) {
        return checkedComplexJacobiResult(Sample, .{
            .sn = std.math.complex.sin(argument),
            .cn = std.math.complex.cos(argument),
            .dn = Complex.init(1.0, 0.0),
        });
    }
    if (parameter == 1.0) {
        const hyperbolic_cosine = std.math.complex.cosh(argument);
        if (complexSquaredMagnitude(hyperbolic_cosine) <=
            complexPoleThreshold(Sample))
            return error.ComplexJacobiPole;
        const reciprocal = hyperbolic_cosine.reciprocal();
        return checkedComplexJacobiResult(Sample, .{
            .sn = std.math.complex.sinh(argument).mul(reciprocal),
            .cn = reciprocal,
            .dn = reciprocal,
        });
    }

    const real_values = try jacobiElliptic(argument.re, parameter);
    const imaginary_values =
        try jacobiElliptic(argument.im, 1.0 - parameter);
    const denominator =
        imaginary_values.cn * imaginary_values.cn +
        parameter *
            real_values.sn *
            real_values.sn *
            imaginary_values.sn *
            imaginary_values.sn;
    if (!std.math.isFinite(denominator) or
        denominator <= complexPoleThreshold(Sample))
        return error.ComplexJacobiPole;

    return checkedComplexJacobiResult(Sample, .{
        .sn = Complex.init(
            real_values.sn * imaginary_values.dn / denominator,
            real_values.cn *
                real_values.dn *
                imaginary_values.sn *
                imaginary_values.cn /
                denominator,
        ),
        .cn = Complex.init(
            real_values.cn * imaginary_values.cn / denominator,
            -real_values.sn *
                real_values.dn *
                imaginary_values.sn *
                imaginary_values.dn /
                denominator,
        ),
        .dn = Complex.init(
            real_values.dn *
                imaginary_values.cn *
                imaginary_values.dn /
                denominator,
            -parameter *
                real_values.sn *
                real_values.cn *
                imaginary_values.sn /
                denominator,
        ),
    });
}

/// Evaluates the branch reached from u = 0 along the straight segment to u.
/// A pole on that continuation path or exhausted bounded refinement is an error.
pub fn complexParameterJacobiElliptic(
    argument: anytype,
    parameter: @TypeOf(argument),
) !ComplexJacobiValues(@TypeOf(argument.re)) {
    const Sample = @TypeOf(argument.re);
    if (Sample != f32 and Sample != f64)
        @compileError(
            "complexParameterJacobiElliptic supports f32 and f64 values",
        );
    const Complex = std.math.complex.Complex(Sample);
    if (@TypeOf(argument) != Complex)
        @compileError(
            "argument and parameter must be std.math.complex.Complex(Sample)",
        );
    if (!complexFinite(argument) or !complexFinite(parameter))
        return error.InvalidComplexJacobiParameterArgument;
    if (parameter.im == 0.0 and
        parameter.re >= 0.0 and parameter.re <= 1.0)
    {
        return complexJacobiElliptic(argument, parameter.re);
    }

    var coarse_steps: usize = 8;
    var coarse = try integrateComplexParameterJacobi(
        Sample,
        argument,
        parameter,
        coarse_steps,
    );
    while (coarse_steps < 16_384) {
        const fine_steps = coarse_steps * 2;
        const fine = try integrateComplexParameterJacobi(
            Sample,
            argument,
            parameter,
            fine_steps,
        );
        const difference = maximumComplexJacobiDifference(coarse, fine);
        const scale = @max(maximumComplexJacobiMagnitude(fine), 1.0);
        if (!std.math.isFinite(difference) or !std.math.isFinite(scale))
            return error.ComplexJacobiParameterBranchSingularity;
        const tolerance = 64.0 * std.math.floatEps(Sample) * scale;
        if (difference <= tolerance) {
            const result = extrapolateComplexJacobi(coarse, fine);
            if (!complexFinite(result.sn) or
                !complexFinite(result.cn) or
                !complexFinite(result.dn))
                return error.InvalidComplexJacobiParameterResult;
            const one = Complex.init(1.0, 0.0);
            const identity_tolerance =
                1_024.0 * std.math.floatEps(Sample) * scale;
            const circular_residual = result.sn.mul(result.sn)
                .add(result.cn.mul(result.cn)).sub(one);
            const parameter_residual = result.dn.mul(result.dn)
                .add(parameter.mul(result.sn.mul(result.sn))).sub(one);
            if (!complexFinite(circular_residual) or
                !complexFinite(parameter_residual) or
                complexMagnitude(circular_residual) > identity_tolerance or
                complexMagnitude(parameter_residual) > identity_tolerance)
                return error.ComplexJacobiParameterConvergenceFailure;
            return result;
        }
        coarse = fine;
        coarse_steps = fine_steps;
    }
    return error.ComplexJacobiParameterConvergenceFailure;
}

pub fn complexParameterJacobiEllipticFunction(
    argument: anytype,
    parameter: @TypeOf(argument),
    function: JacobiFunction,
) !@TypeOf(argument) {
    const Sample = @TypeOf(argument.re);
    const Complex = std.math.complex.Complex(Sample);
    const values = try complexParameterJacobiElliptic(
        argument,
        parameter,
    );
    const one = Complex.init(1.0, 0.0);
    return switch (function) {
        .sn => values.sn,
        .cn => values.cn,
        .dn => values.dn,
        .ns => checkedComplexJacobiRatio(Sample, one, values.sn),
        .nc => checkedComplexJacobiRatio(Sample, one, values.cn),
        .nd => checkedComplexJacobiRatio(Sample, one, values.dn),
        .sc => checkedComplexJacobiRatio(Sample, values.sn, values.cn),
        .sd => checkedComplexJacobiRatio(Sample, values.sn, values.dn),
        .cs => checkedComplexJacobiRatio(Sample, values.cn, values.sn),
        .cd => checkedComplexJacobiRatio(Sample, values.cn, values.dn),
        .ds => checkedComplexJacobiRatio(Sample, values.dn, values.sn),
        .dc => checkedComplexJacobiRatio(Sample, values.dn, values.cn),
    };
}

/// Evaluate one of the twelve complex Jacobi functions for real parameter m.
pub fn complexJacobiEllipticFunction(
    argument: anytype,
    parameter: @TypeOf(argument.re),
    function: JacobiFunction,
) !@TypeOf(argument) {
    const Sample = @TypeOf(argument.re);
    const Complex = std.math.complex.Complex(Sample);
    const values = try complexJacobiElliptic(argument, parameter);
    const one = Complex.init(1.0, 0.0);
    return switch (function) {
        .sn => values.sn,
        .cn => values.cn,
        .dn => values.dn,
        .ns => checkedComplexJacobiRatio(Sample, one, values.sn),
        .nc => checkedComplexJacobiRatio(Sample, one, values.cn),
        .nd => checkedComplexJacobiRatio(Sample, one, values.dn),
        .sc => checkedComplexJacobiRatio(Sample, values.sn, values.cn),
        .sd => checkedComplexJacobiRatio(Sample, values.sn, values.dn),
        .cs => checkedComplexJacobiRatio(Sample, values.cn, values.sn),
        .cd => checkedComplexJacobiRatio(Sample, values.cn, values.dn),
        .ds => checkedComplexJacobiRatio(Sample, values.dn, values.sn),
        .dc => checkedComplexJacobiRatio(Sample, values.dn, values.cn),
    };
}

pub fn complexJacobiCd(
    argument: anytype,
    parameter: @TypeOf(argument.re),
) !@TypeOf(argument) {
    return complexJacobiEllipticFunction(argument, parameter, .cd);
}

pub fn inverseComplexJacobiSn(
    value: anytype,
    parameter: @TypeOf(value.re),
) !@TypeOf(value) {
    const Sample = @TypeOf(value.re);
    if (Sample != f32 and Sample != f64)
        @compileError(
            "inverseComplexJacobiSn supports f32 and f64 values",
        );
    const Complex = std.math.complex.Complex(Sample);
    if (@TypeOf(value) != Complex)
        @compileError("value must be std.math.complex.Complex(Sample)");
    if (!complexFinite(value) or
        !std.math.isFinite(parameter) or
        parameter < 0.0 or
        parameter > 1.0)
        return error.InvalidInverseComplexJacobiArgument;

    if (parameter == 0.0)
        return checkedInverseComplexJacobiResult(
            std.math.complex.asin(value),
        );
    if (parameter == 1.0)
        return checkedInverseComplexJacobiResult(
            std.math.complex.atanh(value),
        );

    var transformed_moduli: [33]Sample = @splat(0.0);
    transformed_moduli[0] = @sqrt(parameter);
    var count: usize = 0;
    while (count + 1 < transformed_moduli.len) {
        const current = transformed_moduli[count];
        const ratio =
            current / (1.0 + @sqrt(1.0 - current * current));
        const next = ratio * ratio;
        count += 1;
        transformed_moduli[count] = next;
        if (next <= 4.0 * std.math.floatEps(Sample)) break;
    }
    if (transformed_moduli[count] >
        4.0 * std.math.floatEps(Sample))
        return error.InverseComplexJacobiConvergenceFailure;

    const one = Complex.init(1.0, 0.0);
    var reduced = value;
    for (1..count + 1) |index| {
        const scaled = complexScale(
            reduced,
            transformed_moduli[index - 1],
        );
        const root = std.math.complex.sqrt(
            one.sub(scaled.mul(scaled)),
        );
        const denominator = complexScale(
            one.add(root),
            1.0 + transformed_moduli[index],
        );
        if (!complexFinite(denominator) or
            complexSquaredMagnitude(denominator) <=
                complexPoleThreshold(Sample))
            return error.InverseComplexJacobiBranchSingularity;
        reduced = complexScale(reduced.div(denominator), 2.0);
        if (!complexFinite(reduced))
            return error.InvalidInverseComplexJacobiResult;
    }

    const quarter_period =
        completeEllipticKFromParameter(Sample, parameter);
    return checkedInverseComplexJacobiResult(
        complexScale(
            std.math.complex.asin(reduced),
            2.0 * quarter_period / std.math.pi,
        ),
    );
}

fn checkedComplexJacobiResult(
    comptime Sample: type,
    values: ComplexJacobiValues(Sample),
) !ComplexJacobiValues(Sample) {
    if (!complexFinite(values.sn) or
        !complexFinite(values.cn) or
        !complexFinite(values.dn))
        return error.InvalidComplexJacobiResult;
    return values;
}

fn checkedInverseComplexJacobiResult(value: anytype) !@TypeOf(value) {
    if (!complexFinite(value))
        return error.InvalidInverseComplexJacobiResult;
    return value;
}

fn checkedJacobiRatio(
    comptime Sample: type,
    numerator: Sample,
    denominator: Sample,
) !Sample {
    if (@abs(denominator) <= jacobiPoleThreshold(Sample))
        return error.JacobiPole;
    const result = numerator / denominator;
    if (!std.math.isFinite(result))
        return error.InvalidJacobiResult;
    return result;
}

fn checkedComplexJacobiRatio(
    comptime Sample: type,
    numerator: std.math.complex.Complex(Sample),
    denominator: std.math.complex.Complex(Sample),
) !std.math.complex.Complex(Sample) {
    if (complexSquaredMagnitude(denominator) <=
        complexPoleThreshold(Sample))
        return error.ComplexJacobiPole;
    const result = numerator.div(denominator);
    if (!complexFinite(result))
        return error.InvalidComplexJacobiResult;
    return result;
}

fn complexFinite(value: anytype) bool {
    return std.math.isFinite(value.re) and std.math.isFinite(value.im);
}

fn complexSquaredMagnitude(value: anytype) @TypeOf(value.re) {
    return value.re * value.re + value.im * value.im;
}

fn complexMagnitude(value: anytype) @TypeOf(value.re) {
    return std.math.hypot(value.re, value.im);
}

fn complexScale(value: anytype, scalar: @TypeOf(value.re)) @TypeOf(value) {
    return .{
        .re = value.re * scalar,
        .im = value.im * scalar,
    };
}

fn integrateComplexParameterJacobi(
    comptime Sample: type,
    argument: std.math.complex.Complex(Sample),
    parameter: std.math.complex.Complex(Sample),
    steps: usize,
) !ComplexJacobiValues(Sample) {
    const Complex = std.math.complex.Complex(Sample);
    var state = ComplexJacobiValues(Sample){
        .sn = Complex.init(0.0, 0.0),
        .cn = Complex.init(1.0, 0.0),
        .dn = Complex.init(1.0, 0.0),
    };
    const step = 1.0 / @as(Sample, @floatFromInt(steps));
    for (0..steps) |_| {
        const first = complexJacobiOdeDerivative(
            Sample,
            state,
            argument,
            parameter,
        );
        const second = complexJacobiOdeDerivative(
            Sample,
            addComplexJacobiScaled(state, first, step * 0.5),
            argument,
            parameter,
        );
        const third = complexJacobiOdeDerivative(
            Sample,
            addComplexJacobiScaled(state, second, step * 0.5),
            argument,
            parameter,
        );
        const fourth = complexJacobiOdeDerivative(
            Sample,
            addComplexJacobiScaled(state, third, step),
            argument,
            parameter,
        );
        state = advanceComplexJacobiRungeKutta(
            state,
            first,
            second,
            third,
            fourth,
            step,
        );
        if (!complexFinite(state.sn) or
            !complexFinite(state.cn) or
            !complexFinite(state.dn))
            return error.ComplexJacobiParameterBranchSingularity;
    }
    return state;
}

fn complexJacobiOdeDerivative(
    comptime Sample: type,
    state: ComplexJacobiValues(Sample),
    argument: std.math.complex.Complex(Sample),
    parameter: std.math.complex.Complex(Sample),
) ComplexJacobiValues(Sample) {
    return .{
        .sn = argument.mul(state.cn.mul(state.dn)),
        .cn = complexScale(
            argument.mul(state.sn.mul(state.dn)),
            -1.0,
        ),
        .dn = complexScale(
            argument.mul(parameter.mul(state.sn.mul(state.cn))),
            -1.0,
        ),
    };
}

fn addComplexJacobiScaled(
    base: anytype,
    increment: @TypeOf(base),
    scale: @TypeOf(base.sn.re),
) @TypeOf(base) {
    return .{
        .sn = base.sn.add(complexScale(increment.sn, scale)),
        .cn = base.cn.add(complexScale(increment.cn, scale)),
        .dn = base.dn.add(complexScale(increment.dn, scale)),
    };
}

fn advanceComplexJacobiRungeKutta(
    base: anytype,
    first: @TypeOf(base),
    second: @TypeOf(base),
    third: @TypeOf(base),
    fourth: @TypeOf(base),
    step: @TypeOf(base.sn.re),
) @TypeOf(base) {
    const scale = step / 6.0;
    return .{
        .sn = base.sn.add(complexScale(
            first.sn.add(complexScale(second.sn, 2.0))
                .add(complexScale(third.sn, 2.0)).add(fourth.sn),
            scale,
        )),
        .cn = base.cn.add(complexScale(
            first.cn.add(complexScale(second.cn, 2.0))
                .add(complexScale(third.cn, 2.0)).add(fourth.cn),
            scale,
        )),
        .dn = base.dn.add(complexScale(
            first.dn.add(complexScale(second.dn, 2.0))
                .add(complexScale(third.dn, 2.0)).add(fourth.dn),
            scale,
        )),
    };
}

fn maximumComplexJacobiDifference(first: anytype, second: @TypeOf(first)) @TypeOf(first.sn.re) {
    return @max(
        complexMagnitude(first.sn.sub(second.sn)),
        complexMagnitude(first.cn.sub(second.cn)),
        complexMagnitude(first.dn.sub(second.dn)),
    );
}

fn maximumComplexJacobiMagnitude(values: anytype) @TypeOf(values.sn.re) {
    return @max(
        complexMagnitude(values.sn),
        complexMagnitude(values.cn),
        complexMagnitude(values.dn),
    );
}

fn extrapolateComplexJacobi(coarse: anytype, fine: @TypeOf(coarse)) @TypeOf(coarse) {
    return .{
        .sn = fine.sn.add(complexScale(fine.sn.sub(coarse.sn), 1.0 / 15.0)),
        .cn = fine.cn.add(complexScale(fine.cn.sub(coarse.cn), 1.0 / 15.0)),
        .dn = fine.dn.add(complexScale(fine.dn.sub(coarse.dn), 1.0 / 15.0)),
    };
}

fn complexPoleThreshold(comptime Sample: type) Sample {
    const epsilon = std.math.floatEps(Sample);
    return 256.0 * epsilon * epsilon;
}

fn jacobiPoleThreshold(comptime Sample: type) Sample {
    return 16.0 * std.math.floatEps(Sample);
}

/// Return the principal real inverse of sn on [-K, K].
pub fn inverseJacobiSn(
    value: anytype,
    parameter: @TypeOf(value),
) !@TypeOf(value) {
    const Sample = @TypeOf(value);
    try validateInverseJacobiInput(Sample, value, parameter);
    const tolerance = 16.0 * std.math.floatEps(Sample);
    if (value < -1.0 - tolerance or value > 1.0 + tolerance)
        return error.InvalidInverseJacobiValue;
    const bounded = @min(@as(Sample, 1.0), @max(-1.0, value));
    if (@abs(bounded) == 1.0 and parameter < 1.0) {
        const quarter_period =
            completeEllipticKFromParameter(Sample, parameter);
        return if (bounded < 0.0)
            -quarter_period
        else
            quarter_period;
    }
    return ellipticIntegralF(std.math.asin(bounded), parameter);
}

/// Return the principal real inverse of cn on [0, 2K].
pub fn inverseJacobiCn(
    value: anytype,
    parameter: @TypeOf(value),
) !@TypeOf(value) {
    const Sample = @TypeOf(value);
    try validateInverseJacobiInput(Sample, value, parameter);
    const tolerance = 16.0 * std.math.floatEps(Sample);
    if (value < -1.0 - tolerance or
        value > 1.0 + tolerance or
        (parameter == 1.0 and value <= 0.0))
        return error.InvalidInverseJacobiValue;
    const bounded = @min(@as(Sample, 1.0), @max(-1.0, value));
    if (bounded == 1.0) return 0.0;
    if (bounded == -1.0) {
        return 2.0 * completeEllipticKFromParameter(
            Sample,
            parameter,
        );
    }
    return ellipticIntegralF(std.math.acos(bounded), parameter);
}

/// Return the principal nonnegative real inverse of dn on [0, K].
pub fn inverseJacobiDn(
    value: anytype,
    parameter: @TypeOf(value),
) !@TypeOf(value) {
    const Sample = @TypeOf(value);
    try validateInverseJacobiInput(Sample, value, parameter);
    if (parameter == 0.0) {
        if (value != 1.0)
            return error.InvalidInverseJacobiValue;
        return 0.0;
    }
    const minimum = @sqrt(1.0 - parameter);
    const tolerance = 16.0 * std.math.floatEps(Sample);
    if (value < minimum - tolerance or
        value > 1.0 + tolerance or
        (parameter == 1.0 and value == 0.0))
        return error.InvalidInverseJacobiValue;
    const bounded =
        @min(@as(Sample, 1.0), @max(minimum, value));
    if (bounded == 1.0) return 0.0;
    if (bounded == minimum) {
        return completeEllipticKFromParameter(Sample, parameter);
    }
    const sine_squared =
        @min(
            @as(Sample, 1.0),
            @max(
                @as(Sample, 0.0),
                (1.0 - bounded * bounded) / parameter,
            ),
        );
    return ellipticIntegralF(
        std.math.asin(@sqrt(sine_squared)),
        parameter,
    );
}

/// Return a real branch of inverse sn.
///
/// Each period contributes the roots `4 n K + u` and
/// `4 n K + 2 K - u`, where `u` is the principal inverse.
pub fn inverseJacobiSnBranch(
    value: anytype,
    parameter: @TypeOf(value),
    branch: JacobiInverseBranch,
) !@TypeOf(value) {
    const Sample = @TypeOf(value);
    const principal = try inverseJacobiSn(value, parameter);
    if (parameter == 1.0) {
        if (branch.period_index != 0 or branch.reflected)
            return error.DegenerateJacobiInverseBranch;
        return principal;
    }
    const quarter_period =
        completeEllipticKFromParameter(Sample, parameter);
    const period_shift =
        4.0 * quarter_period *
        @as(Sample, @floatFromInt(branch.period_index));
    const local = if (branch.reflected)
        2.0 * quarter_period - principal
    else
        principal;
    return checkedInverseJacobiBranchResult(period_shift + local);
}

/// Return a real branch of inverse cn.
///
/// Each period contributes the roots `4 n K + u` and `4 n K - u`.
pub fn inverseJacobiCnBranch(
    value: anytype,
    parameter: @TypeOf(value),
    branch: JacobiInverseBranch,
) !@TypeOf(value) {
    const Sample = @TypeOf(value);
    const principal = try inverseJacobiCn(value, parameter);
    if (parameter == 1.0 and branch.period_index != 0)
        return error.DegenerateJacobiInverseBranch;
    const local = if (branch.reflected) -principal else principal;
    if (parameter == 1.0) return local;
    const quarter_period =
        completeEllipticKFromParameter(Sample, parameter);
    const period_shift =
        4.0 * quarter_period *
        @as(Sample, @floatFromInt(branch.period_index));
    return checkedInverseJacobiBranchResult(period_shift + local);
}

/// Return a real branch of inverse dn.
///
/// Each period contributes the roots `2 n K + u` and `2 n K - u`.
pub fn inverseJacobiDnBranch(
    value: anytype,
    parameter: @TypeOf(value),
    branch: JacobiInverseBranch,
) !@TypeOf(value) {
    const Sample = @TypeOf(value);
    const principal = try inverseJacobiDn(value, parameter);
    if (parameter == 1.0 and branch.period_index != 0)
        return error.DegenerateJacobiInverseBranch;
    const local = if (branch.reflected) -principal else principal;
    if (parameter == 1.0) return local;
    const quarter_period =
        completeEllipticKFromParameter(Sample, parameter);
    const period_shift =
        2.0 * quarter_period *
        @as(Sample, @floatFromInt(branch.period_index));
    return checkedInverseJacobiBranchResult(period_shift + local);
}

fn checkedInverseJacobiBranchResult(value: anytype) !@TypeOf(value) {
    if (!std.math.isFinite(value))
        return error.InvalidInverseJacobiResult;
    return value;
}

fn validateInverseJacobiInput(
    comptime Sample: type,
    value: Sample,
    parameter: Sample,
) !void {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "inverse Jacobi functions support f32 and f64 values",
        );
    if (!std.math.isFinite(value) or
        !std.math.isFinite(parameter) or
        parameter < 0.0 or
        parameter > 1.0)
        return error.InvalidInverseJacobiArgument;
}

fn principalAngle(comptime Sample: type, angle: Sample) Sample {
    return centeredModulo(Sample, angle, std.math.tau);
}

fn centeredModulo(
    comptime Sample: type,
    value: Sample,
    period: Sample,
) Sample {
    if (!std.math.isFinite(period)) return value;
    const remainder = @mod(value, period);
    const half_period = period * 0.5;
    return if (remainder >= half_period)
        remainder - period
    else
        remainder;
}

test "Bessel I0 matches known even values" {
    try std.testing.expectEqual(@as(f64, 1.0), besselI0(@as(f64, 0.0)));
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.266_065_877_752_008_2),
        besselI0(@as(f64, 1.0)),
        0.000_000_000_000_01,
    );
    try std.testing.expectApproxEqAbs(
        besselI0(@as(f64, 3.0)),
        besselI0(@as(f64, -3.0)),
        0.000_000_000_000_01,
    );
}

test "Bessel I0 contains non-finite and overflowing input" {
    try std.testing.expectEqual(
        @as(f32, 0.0),
        besselI0(std.math.nan(f32)),
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        besselI0(std.math.inf(f64)),
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        besselI0(@as(f64, 1.0e200)),
    );
}

test "complete elliptic integrals match known moduli" {
    const symmetric = try ellipticIntegralK(
        @as(f64, 1.0 / @sqrt(2.0)),
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.854_074_677_301_371_9),
        symmetric.k,
        0.000_000_000_000_01,
    );
    try std.testing.expectApproxEqAbs(
        symmetric.k,
        symmetric.complementary,
        0.000_000_000_000_01,
    );
    const half = try ellipticIntegralK(@as(f32, 0.5));
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.685_750_4),
        half.k,
        0.000_001,
    );
}

test "complete elliptic integrals handle endpoints and invalid moduli" {
    const zero = try ellipticIntegralK(@as(f64, 0.0));
    try std.testing.expectEqual(@as(f64, std.math.pi / 2.0), zero.k);
    try std.testing.expect(std.math.isInf(zero.complementary));
    try std.testing.expectError(
        error.InvalidEllipticModulus,
        ellipticIntegralK(@as(f64, 1.0)),
    );
    try std.testing.expectError(
        error.InvalidEllipticModulus,
        ellipticIntegralK(std.math.nan(f32)),
    );
}

test "incomplete elliptic integral matches known and periodic values" {
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.083_216_772_845_168_7),
        try ellipticIntegralF(@as(f64, 1.0), 0.5),
        1.0e-14,
    );
    const complete =
        (try ellipticIntegralK(@as(f64, @sqrt(0.5)))).k;
    try std.testing.expectApproxEqAbs(
        complete,
        try ellipticIntegralF(@as(f64, std.math.pi / 2.0), 0.5),
        1.0e-14,
    );
    const local = try ellipticIntegralF(@as(f64, 0.3), 0.5);
    try std.testing.expectApproxEqAbs(
        2.0 * complete + local,
        try ellipticIntegralF(@as(f64, std.math.pi + 0.3), 0.5),
        1.0e-14,
    );
    try std.testing.expectEqual(
        @as(f32, -0.75),
        try ellipticIntegralF(@as(f32, -0.75), 0.0),
    );
    try std.testing.expectError(
        error.DivergentEllipticIntegral,
        ellipticIntegralF(
            @as(f64, std.math.pi / 2.0),
            1.0,
        ),
    );
    try std.testing.expectError(
        error.InvalidEllipticIntegralArgument,
        ellipticIntegralF(@as(f32, 1.0), -0.1),
    );
}

test "near-one elliptic parameters retain finite quarter periods" {
    const parameter_f64 = std.math.nextAfter(f64, 1.0, 0.0);
    const quarter_f64 =
        completeEllipticKFromParameter(f64, parameter_f64);
    try std.testing.expect(std.math.isFinite(quarter_f64));
    try std.testing.expectEqual(
        quarter_f64,
        try inverseJacobiSn(@as(f64, 1.0), parameter_f64),
    );
    const endpoint_f64 =
        try jacobiElliptic(quarter_f64, parameter_f64);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        endpoint_f64.sn,
        2.0e-14,
    );
    const local_f64 =
        try ellipticIntegralF(@as(f64, 0.25), parameter_f64);
    try std.testing.expectApproxEqAbs(
        2.0 * quarter_f64 + local_f64,
        try ellipticIntegralF(
            @as(f64, std.math.pi + 0.25),
            parameter_f64,
        ),
        2.0e-13,
    );

    const parameter_f32 = std.math.nextAfter(f32, 1.0, 0.0);
    const quarter_f32 =
        completeEllipticKFromParameter(f32, parameter_f32);
    try std.testing.expect(std.math.isFinite(quarter_f32));
    try std.testing.expectEqual(
        quarter_f32,
        try inverseJacobiSn(@as(f32, 1.0), parameter_f32),
    );
    const endpoint_f32 =
        try jacobiElliptic(quarter_f32, parameter_f32);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        endpoint_f32.sn,
        0.000_002,
    );
}

test "Jacobi elliptic functions match known real values" {
    const values = try jacobiElliptic(@as(f64, 1.0), 0.5);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.803_001_824_895_643_9),
        values.sn,
        0.000_000_000_000_01,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.595_976_567_672_140_7),
        values.cn,
        0.000_000_000_000_01,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.823_161_001_631_596_3),
        values.dn,
        0.000_000_000_000_01,
    );
}

test "Jacobi elliptic functions match SciPy 1.17 vectors" {
    const arguments = [_]f64{ -3.0, -1.25, -0.1, 0.0, 0.3, 1.7, 4.0 };
    const expected = [_]JacobiValues(f64){
        .{
            .sn = -0.9906305999378325,
            .cn = -0.1365687170138534,
            .dn = 0.3417395397376911,
            .principal_amplitude = 0.0,
        },
        .{
            .sn = -0.8605123274668937,
            .cn = 0.5094296166081331,
            .dn = 0.5775523187121306,
            .principal_amplitude = 0.0,
        },
        .{
            .sn = -0.09968452956968084,
            .cn = 0.9950190925627866,
            .dn = 0.9955183047578906,
            .principal_amplitude = 0.0,
        },
        .{
            .sn = 0.0,
            .cn = 1.0,
            .dn = 1.0,
            .principal_amplitude = 0.0,
        },
        .{
            .sn = 0.29173204781861856,
            .cn = 0.9565000848277826,
            .dn = 0.9609386926583817,
            .principal_amplitude = 0.0,
        },
        .{
            .sn = 0.9522305421080186,
            .cn = 0.3053800823181972,
            .dn = 0.4288721198784107,
            .principal_amplitude = 0.0,
        },
        .{
            .sn = 0.8306764615215464,
            .cn = -0.5567554366811723,
            .dn = 0.6156126660869142,
            .principal_amplitude = 0.0,
        },
    };
    for (arguments, expected) |argument, reference| {
        const actual = try jacobiElliptic(argument, 0.9);
        try std.testing.expectApproxEqAbs(reference.sn, actual.sn, 2.0e-14);
        try std.testing.expectApproxEqAbs(reference.cn, actual.cn, 2.0e-14);
        try std.testing.expectApproxEqAbs(reference.dn, actual.dn, 2.0e-14);
    }
}

test "Jacobi elliptic identities and endpoints remain bounded" {
    inline for (.{ 0.0, 0.25, 0.75, 1.0 }) |parameter| {
        const values = try jacobiElliptic(@as(f64, 2.25), parameter);
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            values.sn * values.sn + values.cn * values.cn,
            0.000_000_000_000_1,
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            values.dn * values.dn +
                parameter * values.sn * values.sn,
            0.000_000_000_000_1,
        );
    }
    try std.testing.expectError(
        error.InvalidJacobiArgument,
        jacobiElliptic(@as(f32, 1.0), 1.1),
    );
}

test "all real Jacobi functions match quotient references" {
    const functions = [_]JacobiFunction{
        .sn,
        .cn,
        .dn,
        .ns,
        .nc,
        .nd,
        .sc,
        .sd,
        .cs,
        .cd,
        .ds,
        .dc,
    };
    const expected = [_]f64{
        0.803_001_824_895_643_9,
        0.595_976_567_672_140_7,
        0.823_161_001_631_596_3,
        1.245_327_182_326_089_4,
        1.677_918_318_006_960_8,
        1.214_829_174_387_379,
        1.347_371_471_385_418_8,
        0.975_510_043_969_533_6,
        0.742_185_819_751_520_9,
        0.724_009_721_659_370_5,
        1.025_104_770_762_597_3,
        1.381_196_923_306_613_3,
    };
    for (functions, expected) |function, reference| {
        try std.testing.expectApproxEqAbs(
            reference,
            try jacobiEllipticFunction(
                @as(f64, 1.0),
                0.5,
                function,
            ),
            3.0e-14,
        );
    }

    const f32_value = try jacobiEllipticFunction(
        @as(f32, 0.75),
        0.25,
        .sd,
    );
    try std.testing.expect(std.math.isFinite(f32_value));
}

test "real Jacobi quotient poles are explicit" {
    try std.testing.expectError(
        error.JacobiPole,
        jacobiEllipticFunction(@as(f64, 0.0), 0.5, .ns),
    );
    try std.testing.expectError(
        error.JacobiPole,
        jacobiEllipticFunction(@as(f64, 0.0), 0.5, .cs),
    );
    try std.testing.expectError(
        error.JacobiPole,
        jacobiEllipticFunction(@as(f64, 0.0), 0.5, .ds),
    );

    const quarter_period =
        completeEllipticKFromParameter(f64, 0.5);
    try std.testing.expectError(
        error.JacobiPole,
        jacobiEllipticFunction(quarter_period, 0.5, .nc),
    );
    try std.testing.expectError(
        error.JacobiPole,
        jacobiEllipticFunction(quarter_period, 0.5, .sc),
    );
    try std.testing.expectError(
        error.JacobiPole,
        jacobiEllipticFunction(quarter_period, 0.5, .dc),
    );
}

test "Jacobi elliptic functions contain extreme finite arguments" {
    const argument = std.math.floatMax(f64);
    inline for (.{
        0.0,
        0.5,
        std.math.nextAfter(f64, 1.0, 0.0),
    }) |parameter| {
        const values = try jacobiElliptic(argument, parameter);
        try std.testing.expect(std.math.isFinite(values.sn));
        try std.testing.expect(std.math.isFinite(values.cn));
        try std.testing.expect(std.math.isFinite(values.dn));
        try std.testing.expect(
            std.math.isFinite(values.principal_amplitude),
        );
        try std.testing.expect(
            values.principal_amplitude >= -std.math.pi and
                values.principal_amplitude < std.math.pi,
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            values.sn * values.sn + values.cn * values.cn,
            2.0e-14,
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            values.dn * values.dn +
                parameter * values.sn * values.sn,
            2.0e-14,
        );
    }
}

test "complex Jacobi elliptic functions match independent ODE vectors" {
    const Complex = std.math.complex.Complex(f64);
    const Reference = struct {
        argument: Complex,
        parameter: f64,
        values: ComplexJacobiValues(f64),
    };
    const references = [_]Reference{
        .{
            .argument = Complex.init(0.25, 0.5),
            .parameter = 0.2,
            .values = .{
                .sn = Complex.init(
                    0.285_638_124_095_013_88,
                    0.504_946_625_918_997_5,
                ),
                .cn = Complex.init(
                    1.091_261_138_047_000_1,
                    -0.132_170_020_508_324_22,
                ),
                .dn = Complex.init(
                    1.017_585_374_531_450_7,
                    -0.028_347_893_082_095_82,
                ),
            },
        },
        .{
            .argument = Complex.init(-1.125, 0.375),
            .parameter = 0.5,
            .values = .{
                .sn = Complex.init(
                    -0.905_361_230_365_387_3,
                    0.149_723_795_137_065_91,
                ),
                .cn = Complex.init(
                    0.520_225_016_282_517_9,
                    0.260_568_244_774_018_6,
                ),
                .dn = Complex.init(
                    0.780_328_952_014_391_6,
                    0.086_857_035_760_586_32,
                ),
            },
        },
        .{
            .argument = Complex.init(2.0, -0.75),
            .parameter = 0.9,
            .values = .{
                .sn = Complex.init(
                    1.020_999_395_673_144_9,
                    -0.036_901_360_838_391_28,
                ),
                .cn = Complex.init(
                    0.149_572_586_952_990_86,
                    0.251_892_862_743_330_17,
                ),
                .dn = Complex.init(
                    0.278_939_495_220_117,
                    0.121_562_707_988_712_17,
                ),
            },
        },
        .{
            .argument = Complex.init(0.75, 0.4),
            .parameter = 0.0,
            .values = .{
                .sn = Complex.init(
                    0.736_900_831_035_454,
                    0.300_542_904_653_953,
                ),
                .cn = Complex.init(
                    0.791_008_620_921_221_4,
                    -0.279_984_706_036_932_37,
                ),
                .dn = Complex.init(1.0, 0.0),
            },
        },
        .{
            .argument = Complex.init(-0.6, 0.3),
            .parameter = 1.0,
            .values = .{
                .sn = Complex.init(
                    -0.572_635_206_667_451_6,
                    0.214_204_993_249_061_95,
                ),
                .cn = Complex.init(
                    0.859_273_116_851_825_4,
                    0.142_750_096_765_251_74,
                ),
                .dn = Complex.init(
                    0.859_273_116_851_825_4,
                    0.142_750_096_765_251_74,
                ),
            },
        },
    };
    for (references) |reference| {
        const actual = try complexJacobiElliptic(
            reference.argument,
            reference.parameter,
        );
        try expectComplexApproxEq(reference.values.sn, actual.sn, 3.0e-13);
        try expectComplexApproxEq(reference.values.cn, actual.cn, 3.0e-13);
        try expectComplexApproxEq(reference.values.dn, actual.dn, 3.0e-13);
    }
}

test "complex-parameter Jacobi functions match independent ODE vectors" {
    const Complex = std.math.complex.Complex(f64);
    const Reference = struct {
        argument: Complex,
        parameter: Complex,
        values: ComplexJacobiValues(f64),
    };
    const references = [_]Reference{
        .{
            .argument = Complex.init(0.7, -0.35),
            .parameter = Complex.init(0.25, 0.2),
            .values = .{
                .sn = Complex.init(
                    0.665_339_136_284_985_9,
                    -0.266_281_894_820_936_6,
                ),
                .cn = Complex.init(
                    0.821_430_805_362_076_1,
                    0.215_681_911_065_412_6,
                ),
                .dn = Complex.init(
                    0.914_467_549_274_894,
                    0.007_780_406_867_867_052,
                ),
            },
        },
        .{
            .argument = Complex.init(-1.1, 0.45),
            .parameter = Complex.init(0.6, -0.3),
            .values = .{
                .sn = Complex.init(
                    -0.922_083_590_625_726_9,
                    0.144_899_298_432_499_3,
                ),
                .cn = Complex.init(
                    0.493_900_702_934_968_85,
                    0.270_518_475_847_122_9,
                ),
                .dn = Complex.init(
                    0.804_527_059_369_794_7,
                    0.254_251_125_622_993_23,
                ),
            },
        },
        .{
            .argument = Complex.init(0.2, 0.8),
            .parameter = Complex.init(-0.4, 0.25),
            .values = .{
                .sn = Complex.init(
                    0.201_093_309_928_522_03,
                    0.862_589_397_423_541,
                ),
                .cn = Complex.init(
                    1.311_908_593_931_351,
                    -0.132_220_306_993_599_3,
                ),
                .dn = Complex.init(
                    0.913_745_493_720_091_3,
                    0.172_189_222_877_025_12,
                ),
            },
        },
        .{
            .argument = Complex.init(1.35, -0.2),
            .parameter = Complex.init(1.2, 0.15),
            .values = .{
                .sn = Complex.init(
                    0.847_794_932_626_524_7,
                    -0.062_811_720_141_308_56,
                ),
                .cn = Complex.init(
                    0.542_962_180_783_963_5,
                    0.098_075_814_356_845_26,
                ),
                .dn = Complex.init(
                    0.356_489_505_248_061_94,
                    0.028_867_412_176_018_976,
                ),
            },
        },
    };
    for (references) |reference| {
        const actual = try complexParameterJacobiElliptic(
            reference.argument,
            reference.parameter,
        );
        try expectComplexApproxEq(reference.values.sn, actual.sn, 2.0e-12);
        try expectComplexApproxEq(reference.values.cn, actual.cn, 2.0e-12);
        try expectComplexApproxEq(reference.values.dn, actual.dn, 2.0e-12);
    }
}

test "complex-parameter Jacobi functions retain real paths and identities" {
    const Complex = std.math.complex.Complex(f64);
    const argument = Complex.init(0.65, -0.4);
    for ([_]f64{ 0.0, 0.2, 0.5, 0.9, 1.0 }) |parameter| {
        const expected = try complexJacobiElliptic(argument, parameter);
        const actual = try complexParameterJacobiElliptic(
            argument,
            Complex.init(parameter, 0.0),
        );
        try std.testing.expectEqualDeep(expected, actual);
    }

    const parameter = Complex.init(0.35, -0.2);
    const values = try complexParameterJacobiElliptic(
        argument,
        parameter,
    );
    const one = Complex.init(1.0, 0.0);
    try expectComplexApproxEq(
        one,
        values.sn.mul(values.sn).add(values.cn.mul(values.cn)),
        2.0e-13,
    );
    try expectComplexApproxEq(
        one,
        values.dn.mul(values.dn)
            .add(parameter.mul(values.sn.mul(values.sn))),
        2.0e-13,
    );
    const conjugate = try complexParameterJacobiElliptic(
        argument.conjugate(),
        parameter.conjugate(),
    );
    try expectComplexApproxEq(values.sn.conjugate(), conjugate.sn, 3.0e-13);
    try expectComplexApproxEq(values.cn.conjugate(), conjugate.cn, 3.0e-13);
    try expectComplexApproxEq(values.dn.conjugate(), conjugate.dn, 3.0e-13);
}

test "complex-parameter Jacobi selector covers quotients and poles" {
    const Complex = std.math.complex.Complex(f64);
    const argument = Complex.init(0.7, -0.35);
    const parameter = Complex.init(0.25, 0.2);
    const values = try complexParameterJacobiElliptic(
        argument,
        parameter,
    );
    const one = Complex.init(1.0, 0.0);
    const expected = [_]Complex{
        values.sn,
        values.cn,
        values.dn,
        one.div(values.sn),
        one.div(values.cn),
        one.div(values.dn),
        values.sn.div(values.cn),
        values.sn.div(values.dn),
        values.cn.div(values.sn),
        values.cn.div(values.dn),
        values.dn.div(values.sn),
        values.dn.div(values.cn),
    };
    inline for (std.meta.fields(JacobiFunction), 0..) |field, index| {
        const function: JacobiFunction = @enumFromInt(field.value);
        try expectComplexApproxEq(
            expected[index],
            try complexParameterJacobiEllipticFunction(
                argument,
                parameter,
                function,
            ),
            2.0e-13,
        );
    }

    inline for (.{ JacobiFunction.ns, .cs, .ds }) |function| {
        try std.testing.expectError(
            error.ComplexJacobiPole,
            complexParameterJacobiEllipticFunction(
                Complex.init(0.0, 0.0),
                parameter,
                function,
            ),
        );
    }
}

test "complex-parameter Jacobi functions contain invalid and f32 inputs" {
    const Complex32 = std.math.complex.Complex(f32);
    const single = try complexParameterJacobiElliptic(
        Complex32.init(0.7, -0.35),
        Complex32.init(0.25, 0.2),
    );
    try expectComplexApproxEq(
        Complex32.init(0.665_339_1, -0.266_281_9),
        single.sn,
        3.0e-5,
    );
    try expectComplexApproxEq(
        Complex32.init(0.821_430_8, 0.215_681_91),
        single.cn,
        3.0e-5,
    );
    try expectComplexApproxEq(
        Complex32.init(0.914_467_6, 0.007_780_407),
        single.dn,
        3.0e-5,
    );

    const Complex64 = std.math.complex.Complex(f64);
    try std.testing.expectError(
        error.InvalidComplexJacobiParameterArgument,
        complexParameterJacobiElliptic(
            Complex64.init(std.math.nan(f64), 0.0),
            Complex64.init(0.25, 0.2),
        ),
    );
    try std.testing.expectError(
        error.InvalidComplexJacobiParameterArgument,
        complexParameterJacobiElliptic(
            Complex64.init(0.5, 0.0),
            Complex64.init(0.25, std.math.inf(f64)),
        ),
    );
    try std.testing.expectError(
        error.ComplexJacobiParameterBranchSingularity,
        complexParameterJacobiElliptic(
            Complex64.init(std.math.floatMax(f64), 1.0),
            Complex64.init(0.25, 0.2),
        ),
    );
}

test "complex Jacobi cd and inverse sn match independent ODE vectors" {
    const Complex = std.math.complex.Complex(f64);
    const first_argument = Complex.init(0.25, 0.5);
    const first = try complexJacobiCd(first_argument, 0.2);
    try expectComplexApproxEq(
        Complex.init(
            1.075_186_481_930_692_7,
            -0.099_933_383_105_139_36,
        ),
        first,
        4.0e-13,
    );

    const second_argument = Complex.init(-1.125, 0.375);
    const second = try complexJacobiCd(second_argument, 0.5);
    try expectComplexApproxEq(
        Complex.init(
            0.695_228_599_086_763,
            0.256_536_360_677_881_55,
        ),
        second,
        4.0e-13,
    );

    const first_values = try complexJacobiElliptic(first_argument, 0.2);
    try expectComplexApproxEq(
        first_argument,
        try inverseComplexJacobiSn(first_values.sn, 0.2),
        5.0e-13,
    );
    const second_values = try complexJacobiElliptic(second_argument, 0.5);
    try expectComplexApproxEq(
        second_argument,
        try inverseComplexJacobiSn(second_values.sn, 0.5),
        5.0e-13,
    );
}

test "complex inverse sn round trips its principal rectangle densely" {
    const Complex = std.math.complex.Complex(f64);
    inline for (.{ 0.0, 0.1, 0.5, 0.9, 1.0 }) |parameter| {
        for (0..17) |real_index| {
            const real =
                -0.75 +
                1.5 * @as(f64, @floatFromInt(real_index)) / 16.0;
            for (0..13) |imaginary_index| {
                const imaginary =
                    -0.5 +
                    @as(f64, @floatFromInt(imaginary_index)) / 12.0;
                const argument = Complex.init(real, imaginary);
                const values =
                    try complexJacobiElliptic(argument, parameter);
                try expectComplexApproxEq(
                    argument,
                    try inverseComplexJacobiSn(values.sn, parameter),
                    2.0e-12,
                );
            }
        }
    }
}

test "all complex Jacobi functions match independent quotient vectors" {
    const Complex = std.math.complex.Complex(f64);
    const argument = Complex.init(0.25, 0.5);
    const functions = [_]JacobiFunction{
        .sn,
        .cn,
        .dn,
        .ns,
        .nc,
        .nd,
        .sc,
        .sd,
        .cs,
        .cd,
        .ds,
        .dc,
    };
    const expected = [_]Complex{
        Complex.init(
            0.285_638_124_095_013_88,
            0.504_946_625_918_997_5,
        ),
        Complex.init(
            1.091_261_138_047_000_1,
            -0.132_170_020_508_324_22,
        ),
        Complex.init(
            1.017_585_374_531_450_7,
            -0.028_347_893_082_095_82,
        ),
        Complex.init(
            0.848_698_378_830_729_5,
            -1.500_315_772_522_540_4,
        ),
        Complex.init(
            0.903_122_791_608_669_7,
            0.109_383_312_322_546_82,
        ),
        Complex.init(
            0.981_956_461_516_789_8,
            0.027_355_342_833_193_158,
        ),
        Complex.init(
            0.202_733_565_533_438_66,
            0.487_272_850_552_454_95,
        ),
        Complex.init(
            0.266_671_213_546_155_25,
            0.503_649_330_853_110_3,
        ),
        Complex.init(
            0.727_854_792_318_199_4,
            -1.749_408_779_488_250_5,
        ),
        Complex.init(
            1.075_186_481_930_692_7,
            -0.099_933_383_105_139_38,
        ),
        Complex.init(
            0.821_092_266_577_852,
            -1.550_758_198_199_833_5,
        ),
        Complex.init(
            0.922_105_330_589_682_5,
            0.085_705_230_500_702_99,
        ),
    };
    for (functions, expected) |function, reference| {
        try expectComplexApproxEq(
            reference,
            try complexJacobiEllipticFunction(
                argument,
                0.2,
                function,
            ),
            5.0e-13,
        );
    }

    const Complex32 = std.math.complex.Complex(f32);
    const f32_value = try complexJacobiEllipticFunction(
        Complex32.init(0.25, -0.5),
        0.5,
        .dc,
    );
    try std.testing.expect(complexFinite(f32_value));
}

test "complex Jacobi quotient poles are explicit" {
    const Complex = std.math.complex.Complex(f64);
    inline for (.{ JacobiFunction.ns, .cs, .ds }) |function| {
        try std.testing.expectError(
            error.ComplexJacobiPole,
            complexJacobiEllipticFunction(
                Complex.init(0.0, 0.0),
                0.5,
                function,
            ),
        );
    }
}

test "complex Jacobi identities conjugates and periods remain consistent" {
    const Complex = std.math.complex.Complex(f64);
    inline for (.{ 0.0, 0.2, 0.5, 0.9, 1.0 }) |parameter| {
        const argument = Complex.init(-0.625, 0.375);
        const values = try complexJacobiElliptic(argument, parameter);
        try expectComplexApproxEq(
            Complex.init(1.0, 0.0),
            values.sn.mul(values.sn).add(values.cn.mul(values.cn)),
            3.0e-13,
        );
        try expectComplexApproxEq(
            Complex.init(1.0, 0.0),
            values.dn.mul(values.dn).add(
                values.sn.mul(values.sn).mul(
                    Complex.init(parameter, 0.0),
                ),
            ),
            3.0e-13,
        );

        const conjugate = try complexJacobiElliptic(
            argument.conjugate(),
            parameter,
        );
        try expectComplexApproxEq(
            values.sn.conjugate(),
            conjugate.sn,
            3.0e-13,
        );
        try expectComplexApproxEq(
            values.cn.conjugate(),
            conjugate.cn,
            3.0e-13,
        );
        try expectComplexApproxEq(
            values.dn.conjugate(),
            conjugate.dn,
            3.0e-13,
        );
    }

    const parameter = 0.5;
    const quarter_period =
        (try ellipticIntegralK(@as(f64, @sqrt(parameter)))).k;
    const argument = Complex.init(0.25, 0.375);
    const original = try complexJacobiElliptic(argument, parameter);
    const periodic = try complexJacobiElliptic(
        Complex.init(argument.re + 4.0 * quarter_period, argument.im),
        parameter,
    );
    try expectComplexApproxEq(original.sn, periodic.sn, 5.0e-13);
    try expectComplexApproxEq(original.cn, periodic.cn, 5.0e-13);
    try expectComplexApproxEq(original.dn, periodic.dn, 5.0e-13);
}

test "complex Jacobi agrees with real evaluation and checks failures" {
    const Complex64 = std.math.complex.Complex(f64);
    inline for (.{ 0.0, 0.25, 0.75, 1.0 }) |parameter| {
        const real = try jacobiElliptic(@as(f64, 0.625), parameter);
        const complex = try complexJacobiElliptic(
            Complex64.init(0.625, 0.0),
            parameter,
        );
        try std.testing.expectApproxEqAbs(real.sn, complex.sn.re, 2.0e-14);
        try std.testing.expectApproxEqAbs(real.cn, complex.cn.re, 2.0e-14);
        try std.testing.expectApproxEqAbs(real.dn, complex.dn.re, 2.0e-14);
        try std.testing.expectEqual(@as(f64, 0.0), complex.sn.im);
        try std.testing.expectEqual(@as(f64, 0.0), complex.cn.im);
        try std.testing.expectEqual(@as(f64, 0.0), complex.dn.im);
    }

    const Complex32 = std.math.complex.Complex(f32);
    const single = try complexJacobiElliptic(
        Complex32.init(0.25, -0.5),
        0.5,
    );
    try std.testing.expect(complexFinite(single.sn));
    try std.testing.expect(complexFinite(single.cn));
    try std.testing.expect(complexFinite(single.dn));
    try std.testing.expect(complexFinite(
        try complexJacobiCd(Complex32.init(0.25, -0.5), 0.5),
    ));
    const single_inverse =
        try inverseComplexJacobiSn(single.sn, 0.5);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        single_inverse.re,
        0.000_01,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, -0.5),
        single_inverse.im,
        0.000_01,
    );

    try std.testing.expectError(
        error.InvalidComplexJacobiArgument,
        complexJacobiElliptic(
            Complex64.init(std.math.nan(f64), 0.0),
            0.5,
        ),
    );
    try std.testing.expectError(
        error.InvalidComplexJacobiArgument,
        complexJacobiElliptic(Complex64.init(0.0, 0.0), 1.1),
    );
    try std.testing.expectError(
        error.ComplexJacobiPole,
        complexJacobiElliptic(
            Complex64.init(0.0, std.math.pi / 2.0),
            1.0,
        ),
    );
    const complementary_quarter_period =
        (try ellipticIntegralK(@as(f64, @sqrt(0.5)))).k;
    try std.testing.expectError(
        error.ComplexJacobiPole,
        complexJacobiElliptic(
            Complex64.init(0.0, complementary_quarter_period),
            0.5,
        ),
    );
    try std.testing.expectError(
        error.InvalidComplexJacobiResult,
        complexJacobiElliptic(Complex64.init(0.0, 1.0e3), 0.0),
    );
    try std.testing.expectError(
        error.InvalidInverseComplexJacobiArgument,
        inverseComplexJacobiSn(
            Complex64.init(std.math.nan(f64), 0.0),
            0.5,
        ),
    );
    try std.testing.expectError(
        error.InvalidInverseComplexJacobiArgument,
        inverseComplexJacobiSn(Complex64.init(0.0, 0.0), -0.1),
    );
    try std.testing.expectError(
        error.InvalidInverseComplexJacobiResult,
        inverseComplexJacobiSn(Complex64.init(1.0, 0.0), 1.0),
    );
}

test "principal inverse Jacobi functions round trip densely" {
    inline for (.{ 0.0, 0.25, 0.75, 0.99 }) |parameter| {
        const quarter_period =
            (try ellipticIntegralK(
                @as(f64, @sqrt(parameter)),
            )).k;
        for (0..257) |point| {
            const unit =
                @as(f64, @floatFromInt(point)) / 256.0;

            const sn_argument =
                -quarter_period + 2.0 * quarter_period * unit;
            const sn_values =
                try jacobiElliptic(sn_argument, parameter);
            try std.testing.expectApproxEqAbs(
                sn_argument,
                try inverseJacobiSn(sn_values.sn, parameter),
                2.0e-12,
            );

            const cn_argument =
                2.0 * quarter_period * unit;
            const cn_values =
                try jacobiElliptic(cn_argument, parameter);
            try std.testing.expectApproxEqAbs(
                cn_argument,
                try inverseJacobiCn(cn_values.cn, parameter),
                2.0e-12,
            );

            if (parameter != 0.0) {
                const dn_argument = quarter_period * unit;
                const dn_values =
                    try jacobiElliptic(dn_argument, parameter);
                try std.testing.expectApproxEqAbs(
                    dn_argument,
                    try inverseJacobiDn(dn_values.dn, parameter),
                    3.0e-12,
                );
            }
        }
    }
}

test "inverse Jacobi branch selection covers real periodic roots" {
    const parameter: f64 = 0.5;
    const quarter_period =
        completeEllipticKFromParameter(f64, parameter);

    const sn_principal =
        try inverseJacobiSn(@as(f64, 0.35), parameter);
    const sn_periodic = try inverseJacobiSnBranch(
        @as(f64, 0.35),
        parameter,
        .{ .period_index = 2 },
    );
    const sn_reflected = try inverseJacobiSnBranch(
        @as(f64, 0.35),
        parameter,
        .{ .period_index = -1, .reflected = true },
    );
    try std.testing.expectApproxEqAbs(
        8.0 * quarter_period + sn_principal,
        sn_periodic,
        2.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        -2.0 * quarter_period - sn_principal,
        sn_reflected,
        2.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.35),
        (try jacobiElliptic(sn_periodic, parameter)).sn,
        2.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.35),
        (try jacobiElliptic(sn_reflected, parameter)).sn,
        2.0e-14,
    );

    const cn_principal =
        try inverseJacobiCn(@as(f64, -0.35), parameter);
    const cn_periodic = try inverseJacobiCnBranch(
        @as(f64, -0.35),
        parameter,
        .{ .period_index = 1, .reflected = true },
    );
    try std.testing.expectApproxEqAbs(
        4.0 * quarter_period - cn_principal,
        cn_periodic,
        2.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -0.35),
        (try jacobiElliptic(cn_periodic, parameter)).cn,
        2.0e-14,
    );

    const dn_principal =
        try inverseJacobiDn(@as(f64, 0.85), parameter);
    const dn_periodic = try inverseJacobiDnBranch(
        @as(f64, 0.85),
        parameter,
        .{ .period_index = -2, .reflected = true },
    );
    try std.testing.expectApproxEqAbs(
        -4.0 * quarter_period - dn_principal,
        dn_periodic,
        2.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.85),
        (try jacobiElliptic(dn_periodic, parameter)).dn,
        2.0e-14,
    );
}

test "inverse Jacobi branches contain degenerate real periods" {
    try std.testing.expectError(
        error.DegenerateJacobiInverseBranch,
        inverseJacobiSnBranch(
            @as(f64, 0.5),
            1.0,
            .{ .reflected = true },
        ),
    );
    try std.testing.expectError(
        error.DegenerateJacobiInverseBranch,
        inverseJacobiCnBranch(
            @as(f64, 0.5),
            1.0,
            .{ .period_index = 1 },
        ),
    );
    try std.testing.expectError(
        error.DegenerateJacobiInverseBranch,
        inverseJacobiDnBranch(
            @as(f64, 0.5),
            1.0,
            .{ .period_index = -1 },
        ),
    );

    const reflected_cn = try inverseJacobiCnBranch(
        @as(f64, 0.5),
        1.0,
        .{ .reflected = true },
    );
    const reflected_dn = try inverseJacobiDnBranch(
        @as(f64, 0.5),
        1.0,
        .{ .reflected = true },
    );
    try std.testing.expect(reflected_cn < 0.0);
    try std.testing.expect(reflected_dn < 0.0);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        (try jacobiElliptic(reflected_cn, 1.0)).cn,
        2.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        (try jacobiElliptic(reflected_dn, 1.0)).dn,
        2.0e-14,
    );

    const f32_branch = try inverseJacobiSnBranch(
        @as(f32, -0.25),
        0.75,
        .{ .period_index = 1, .reflected = true },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, -0.25),
        (try jacobiElliptic(f32_branch, 0.75)).sn,
        0.000_002,
    );
}

fn expectComplexApproxEq(
    expected: anytype,
    actual: @TypeOf(expected),
    tolerance: @TypeOf(expected.re),
) !void {
    try std.testing.expectApproxEqAbs(expected.re, actual.re, tolerance);
    try std.testing.expectApproxEqAbs(expected.im, actual.im, tolerance);
}

test "principal inverse Jacobi functions match SciPy 1.17 vectors" {
    const sn_values = [_]f64{ -0.9, -0.25, 0.0, 0.4, 0.95 };
    const sn_expected = [_]f64{
        -1.2353737360892976,
        -0.25402669629472113,
        0.0,
        0.417345159667567,
        1.412065177433101,
    };
    for (sn_values, sn_expected) |value, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            try inverseJacobiSn(value, 0.5),
            2.0e-14,
        );
    }

    const cn_values = [_]f64{ 0.95, 0.4, 0.0, -0.4, -0.95 };
    const cn_expected = [_]f64{
        0.3202352577344983,
        1.2869254185586048,
        1.8540746773013719,
        2.421223936044139,
        3.3879140968682457,
    };
    for (cn_values, cn_expected) |value, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            try inverseJacobiCn(value, 0.5),
            2.0e-14,
        );
    }

    const dn_values = [_]f64{ 1.0, 0.99, 0.7949747468305833 };
    const dn_expected = [_]f64{
        0.0,
        0.20152282757226203,
        1.1222641955187922,
    };
    for (dn_values, dn_expected) |value, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            try inverseJacobiDn(value, 0.5),
            2.0e-14,
        );
    }
}

test "inverse Jacobi endpoints and invalid domains are checked" {
    const quarter_period =
        (try ellipticIntegralK(@as(f64, @sqrt(0.5)))).k;
    try std.testing.expectApproxEqAbs(
        quarter_period,
        try inverseJacobiSn(@as(f64, 1.0), 0.5),
        1.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        2.0 * quarter_period,
        try inverseJacobiCn(@as(f64, -1.0), 0.5),
        1.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        quarter_period,
        try inverseJacobiDn(@as(f64, @sqrt(0.5)), 0.5),
        1.0e-14,
    );
    try std.testing.expectEqual(
        @as(f32, 0.0),
        try inverseJacobiDn(@as(f32, 1.0), 0.0),
    );
    const f32_values =
        try jacobiElliptic(@as(f32, 0.75), 0.5);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.75),
        try inverseJacobiSn(f32_values.sn, 0.5),
        0.000_002,
    );
    try std.testing.expectError(
        error.InvalidInverseJacobiValue,
        inverseJacobiSn(@as(f32, 1.1), 0.5),
    );
    try std.testing.expectError(
        error.InvalidInverseJacobiValue,
        inverseJacobiCn(@as(f64, -0.1), 1.0),
    );
    try std.testing.expectError(
        error.InvalidInverseJacobiValue,
        inverseJacobiDn(@as(f64, 0.1), 0.5),
    );
    try std.testing.expectError(
        error.InvalidInverseJacobiArgument,
        inverseJacobiSn(std.math.nan(f64), 0.5),
    );
}
