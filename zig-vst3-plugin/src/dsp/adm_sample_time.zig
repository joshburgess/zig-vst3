const std = @import("std");
const adm_time = @import("adm_time.zig");

const ExactTime = struct {
    whole_seconds: u128,
    fractional_numerator: u128,
    fractional_denominator: u128,
};

pub const Position = struct {
    numerator: u512,
    denominator: u128,

    pub fn compare(
        self: Position,
        other: Position,
    ) std.math.Order {
        return std.math.order(
            @as(u1024, self.numerator) * other.denominator,
            @as(u1024, other.numerator) * self.denominator,
        );
    }

    pub fn ceil(self: Position) !u64 {
        if (self.denominator == 0)
            return error.InvalidAdmSampleTime;
        const quotient = self.numerator / self.denominator;
        const rounded = quotient +
            @intFromBool(self.numerator % self.denominator != 0);
        if (rounded > std.math.maxInt(u64))
            return error.AdmSampleTimeOverflow;
        return @intCast(rounded);
    }
};

pub fn zero() adm_time.Value {
    return .{
        .whole_seconds = 0,
        .fractional_numerator = 0,
        .fractional_denominator = 1,
        .format = .decimal,
    };
}

pub fn compareSum(
    first: adm_time.Value,
    second: adm_time.Value,
    expected: adm_time.Value,
) !std.math.Order {
    const sum = try exactTime(first, second);
    try validate(expected);
    const whole_order = std.math.order(
        sum.whole_seconds,
        @as(u128, expected.whole_seconds),
    );
    if (whole_order != .eq) return whole_order;
    return std.math.order(
        @as(u256, sum.fractional_numerator) *
            expected.fractional_denominator,
        @as(u256, expected.fractional_numerator) *
            sum.fractional_denominator,
    );
}

pub fn position(
    first: adm_time.Value,
    second: ?adm_time.Value,
    sample_rate: u32,
) !Position {
    const time = try exactTime(first, second);
    const denominator = time.fractional_denominator;
    const seconds_numerator =
        @as(u512, time.whole_seconds) *
        @as(u512, denominator) +
        time.fractional_numerator;
    return .{
        .numerator = seconds_numerator * sample_rate,
        .denominator = denominator,
    };
}

pub fn interpolationPhase(
    comptime Sample: type,
    start: Position,
    end: Position,
    sample: u64,
) Sample {
    const sample_at_start_scale =
        @as(u1024, sample) * start.denominator;
    if (sample_at_start_scale <= start.numerator) return 0.0;
    const numerator =
        (sample_at_start_scale - start.numerator) *
        end.denominator;
    const denominator =
        @as(u1024, end.numerator) * start.denominator -
        @as(u1024, start.numerator) * end.denominator;
    if (denominator == 0) return 1.0;
    const phase =
        wideUnsignedToF64(numerator) /
        wideUnsignedToF64(denominator);
    return @floatCast(std.math.clamp(phase, 0.0, 1.0));
}

fn exactTime(
    first: adm_time.Value,
    second: ?adm_time.Value,
) !ExactTime {
    try validate(first);
    const additional = second orelse zero();
    try validate(additional);
    const denominator =
        @as(u128, first.fractional_denominator) *
        additional.fractional_denominator;
    const numerator =
        @as(u256, first.fractional_numerator) *
        additional.fractional_denominator +
        @as(u256, additional.fractional_numerator) *
            first.fractional_denominator;
    const carry = numerator / denominator;
    const whole = @as(u256, first.whole_seconds) +
        additional.whole_seconds +
        carry;
    if (whole > std.math.maxInt(u128))
        return error.AdmSampleTimeOverflow;
    return .{
        .whole_seconds = @intCast(whole),
        .fractional_numerator = @intCast(numerator % denominator),
        .fractional_denominator = denominator,
    };
}

fn validate(value: adm_time.Value) !void {
    if (value.fractional_denominator == 0 or
        value.fractional_numerator >= value.fractional_denominator)
    {
        return error.InvalidAdmSampleTime;
    }
}

fn wideUnsignedToF64(value: u1024) f64 {
    if (value == 0) return 0.0;
    const used_bits: u16 = @intCast(1024 - @clz(value));
    const shift: u16 = used_bits -| 53;
    const mantissa: u64 = @intCast(value >> @intCast(shift));
    return std.math.ldexp(
        @as(f64, @floatFromInt(mantissa)),
        @as(i32, @intCast(shift)),
    );
}

test "ADM sample time preserves exact positions and interpolation phase" {
    const start = try position(
        try adm_time.Value.parse("9007199254740993S1"),
        null,
        4,
    );
    const end = try position(
        try adm_time.Value.parse("9007199254740993S1"),
        try adm_time.Value.parse("1S1"),
        4,
    );
    try std.testing.expectEqual(
        @as(u64, 36_028_797_018_963_972),
        try start.ceil(),
    );
    try std.testing.expectEqual(
        @as(f64, 0.5),
        interpolationPhase(
            f64,
            start,
            end,
            36_028_797_018_963_974,
        ),
    );
}

test "ADM sample time compares unlike exact representations" {
    const first = try adm_time.Value.parse("0.50000");
    const duration = try adm_time.Value.parse("24000S48000");
    const expected = try adm_time.Value.parse("1.00000");
    try std.testing.expectEqual(
        std.math.Order.eq,
        try compareSum(first, duration, expected),
    );

    var malformed = first;
    malformed.fractional_denominator = 0;
    try std.testing.expectError(
        error.InvalidAdmSampleTime,
        position(malformed, null, 48_000),
    );
}
