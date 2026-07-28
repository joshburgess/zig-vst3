const std = @import("std");

pub const Format = enum {
    decimal,
    fractional_samples,
};

pub const Value = struct {
    whole_seconds: u64,
    fractional_numerator: u64,
    fractional_denominator: u64,
    format: Format,

    pub fn parse(encoded: []const u8) !Value {
        if (encoded.len == 0 or
            std.mem.trim(u8, encoded, " \t\r\n").len != encoded.len)
        {
            return error.InvalidAdmTime;
        }
        if (std.mem.indexOfScalar(u8, encoded, 'S')) |separator| {
            if (std.mem.indexOfScalarPos(
                u8,
                encoded,
                separator + 1,
                'S',
            ) != null) {
                return error.InvalidAdmTime;
            }
            return parseFractionalSamples(
                encoded[0..separator],
                encoded[separator + 1 ..],
            );
        }
        return parseDecimal(encoded);
    }

    pub fn compare(self: Value, other: Value) std.math.Order {
        const whole_order = std.math.order(
            self.whole_seconds,
            other.whole_seconds,
        );
        if (whole_order != .eq) return whole_order;
        return std.math.order(
            @as(u128, self.fractional_numerator) *
                other.fractional_denominator,
            @as(u128, other.fractional_numerator) *
                self.fractional_denominator,
        );
    }

    pub fn toSeconds(self: Value) f64 {
        return @as(f64, @floatFromInt(self.whole_seconds)) +
            @as(f64, @floatFromInt(self.fractional_numerator)) /
                @as(f64, @floatFromInt(self.fractional_denominator));
    }
};

fn parseDecimal(encoded: []const u8) !Value {
    const clock = try splitClock(encoded);
    const point = std.mem.indexOfScalar(u8, clock.seconds, '.') orelse
        return error.InvalidAdmTime;
    if (std.mem.indexOfScalarPos(
        u8,
        clock.seconds,
        point + 1,
        '.',
    ) != null) {
        return error.InvalidAdmTime;
    }
    const seconds = try parseUnsigned(clock.seconds[0..point]);
    if (clock.has_clock and seconds >= 60) return error.InvalidAdmTime;
    const fraction = clock.seconds[point + 1 ..];
    if (fraction.len < 5 or fraction.len > 19)
        return error.InvalidAdmTimePrecision;
    const numerator = try parseUnsigned(fraction);
    const denominator = try powerOfTen(fraction.len);
    const whole_seconds = try addClockSeconds(clock, seconds);
    return .{
        .whole_seconds = whole_seconds,
        .fractional_numerator = numerator,
        .fractional_denominator = denominator,
        .format = .decimal,
    };
}

fn parseFractionalSamples(prefix: []const u8, rate: []const u8) !Value {
    const denominator = try parseUnsigned(rate);
    if (denominator == 0) return error.InvalidAdmSampleRate;

    if (std.mem.indexOfScalar(u8, prefix, ':') == null) {
        if (std.mem.indexOfScalar(u8, prefix, '.') != null)
            return error.InvalidAdmTime;
        const samples = try parseUnsigned(prefix);
        return .{
            .whole_seconds = samples / denominator,
            .fractional_numerator = samples % denominator,
            .fractional_denominator = denominator,
            .format = .fractional_samples,
        };
    }

    const clock = try splitClock(prefix);
    const point = std.mem.indexOfScalar(u8, clock.seconds, '.') orelse
        return error.InvalidAdmTime;
    const seconds = try parseUnsigned(clock.seconds[0..point]);
    if (seconds >= 60) return error.InvalidAdmTime;
    const numerator_text = clock.seconds[point + 1 ..];
    if (numerator_text.len == 0 or numerator_text.len != rate.len)
        return error.InvalidAdmSampleFraction;
    const numerator = try parseUnsigned(numerator_text);
    if (numerator >= denominator) return error.InvalidAdmSampleFraction;
    return .{
        .whole_seconds = try addClockSeconds(clock, seconds),
        .fractional_numerator = numerator,
        .fractional_denominator = denominator,
        .format = .fractional_samples,
    };
}

const Clock = struct {
    hours: u64 = 0,
    minutes: u64 = 0,
    seconds: []const u8,
    has_clock: bool,
};

fn splitClock(encoded: []const u8) !Clock {
    const first = std.mem.indexOfScalar(u8, encoded, ':') orelse
        return .{ .seconds = encoded, .has_clock = false };
    const second = std.mem.indexOfScalarPos(
        u8,
        encoded,
        first + 1,
        ':',
    ) orelse return error.InvalidAdmTime;
    if (std.mem.indexOfScalarPos(u8, encoded, second + 1, ':') != null)
        return error.InvalidAdmTime;
    const hours = try parseUnsigned(encoded[0..first]);
    const minutes_text = encoded[first + 1 .. second];
    if (minutes_text.len != 2) return error.InvalidAdmTime;
    const minutes = try parseUnsigned(minutes_text);
    if (minutes >= 60) return error.InvalidAdmTime;
    return .{
        .hours = hours,
        .minutes = minutes,
        .seconds = encoded[second + 1 ..],
        .has_clock = true,
    };
}

fn addClockSeconds(clock: Clock, seconds: u64) !u64 {
    const hours = std.math.mul(
        u64,
        clock.hours,
        3600,
    ) catch return error.AdmTimeOverflow;
    const minutes = std.math.mul(
        u64,
        clock.minutes,
        60,
    ) catch return error.AdmTimeOverflow;
    return std.math.add(
        u64,
        std.math.add(
            u64,
            hours,
            minutes,
        ) catch return error.AdmTimeOverflow,
        seconds,
    ) catch return error.AdmTimeOverflow;
}

fn parseUnsigned(encoded: []const u8) !u64 {
    if (encoded.len == 0) return error.InvalidAdmTime;
    for (encoded) |byte| {
        if (!std.ascii.isDigit(byte)) return error.InvalidAdmTime;
    }
    return std.fmt.parseInt(u64, encoded, 10) catch
        return error.AdmTimeOverflow;
}

fn powerOfTen(exponent: usize) !u64 {
    var result: u64 = 1;
    var index: usize = 0;
    while (index < exponent) : (index += 1) {
        result = std.math.mul(u64, result, 10) catch
            return error.AdmTimeOverflow;
    }
    return result;
}

test "ADM time parses decimal and fractional sample forms exactly" {
    const decimal = try Value.parse("01:34:16.25000");
    try std.testing.expectEqual(@as(u64, 5656), decimal.whole_seconds);
    try std.testing.expectEqual(@as(u64, 25_000), decimal.fractional_numerator);
    try std.testing.expectEqual(@as(u64, 100_000), decimal.fractional_denominator);
    try std.testing.expectEqual(Format.decimal, decimal.format);

    const long_samples = try Value.parse("01:34:16.12000S48000");
    try std.testing.expectEqual(
        std.math.Order.eq,
        decimal.compare(long_samples),
    );
    try std.testing.expectEqual(
        Format.fractional_samples,
        long_samples.format,
    );

    const short_samples = try Value.parse("500000S48000");
    try std.testing.expectEqual(@as(u64, 10), short_samples.whole_seconds);
    try std.testing.expectEqual(
        @as(u64, 20_000),
        short_samples.fractional_numerator,
    );
    try std.testing.expectApproxEqAbs(
        10.0 + 20_000.0 / 48_000.0,
        short_samples.toSeconds(),
        1.0e-12,
    );
}

test "ADM time rejects malformed clocks fractions and overflow" {
    const malformed = [_][]const u8{
        "",
        " 00:00:00.00000",
        "00:60:00.00000",
        "00:00:60.00000",
        "00:00:00.0000",
        "00:00:00",
        "00:00:00.48000S48000",
        "00:00:00.12S48000",
        "12S0",
        "1.0S48000",
        "1S2S3",
    };
    for (malformed) |encoded| {
        const parsed: ?Value = Value.parse(encoded) catch null;
        try std.testing.expect(parsed == null);
    }
    try std.testing.expectError(
        error.AdmTimeOverflow,
        Value.parse("18446744073709551615:00:00.00000"),
    );
}
