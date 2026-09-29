const std = @import("std");

pub const Waveform = enum {
    sine,
    triangle,
    saw,
    square,
};

pub fn Oscillator(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Oscillator supports f32 and f64 samples");

    return struct {
        const Self = @This();

        sample_rate: f64,
        frequency_hz: f64,
        phase: f64 = 0.0,
        waveform: Waveform = .sine,

        pub fn init(
            sample_rate: f64,
            frequency_hz: f64,
            waveform: Waveform,
        ) !Self {
            try validate(sample_rate, frequency_hz);
            return .{
                .sample_rate = sample_rate,
                .frequency_hz = frequency_hz,
                .waveform = waveform,
            };
        }

        pub fn configure(
            self: *Self,
            sample_rate: f64,
            frequency_hz: f64,
        ) !void {
            try validate(sample_rate, frequency_hz);
            self.sample_rate = sample_rate;
            self.frequency_hz = frequency_hz;
        }

        pub fn setFrequency(self: *Self, frequency_hz: f64) !void {
            try validate(self.sample_rate, frequency_hz);
            self.frequency_hz = frequency_hz;
        }

        pub fn reset(self: *Self, phase: f64) !void {
            if (!std.math.isFinite(phase))
                return error.InvalidOscillatorPhase;
            self.phase = phase - @floor(phase);
        }

        pub fn next(self: *Self) Sample {
            if (!self.valid()) return 0.0;
            const value: f64 = switch (self.waveform) {
                .sine => @sin(std.math.tau * self.phase),
                .triangle => 1.0 - 4.0 * @abs(self.phase - 0.5),
                .saw => 2.0 * self.phase - 1.0,
                .square => if (self.phase < 0.5) 1.0 else -1.0,
            };
            self.phase += self.frequency_hz / self.sample_rate;
            self.phase -= @floor(self.phase);
            return @floatCast(value);
        }

        pub fn process(self: *Self, output: []Sample) void {
            for (output) |*sample| sample.* = self.next();
        }

        pub fn valid(self: *const Self) bool {
            validate(self.sample_rate, self.frequency_hz) catch return false;
            return std.math.isFinite(self.phase) and
                self.phase >= 0.0 and
                self.phase < 1.0;
        }

        fn validate(sample_rate: f64, frequency_hz: f64) !void {
            if (!std.math.isFinite(sample_rate) or
                sample_rate < 1_000.0 or
                !std.math.isFinite(frequency_hz) or
                frequency_hz < 0.0 or
                frequency_hz > sample_rate * 0.5)
                return error.InvalidOscillatorConfig;
        }
    };
}

test "oscillator waveforms preserve phase across blocks" {
    var saw = try Oscillator(f32).init(8_000.0, 2_000.0, .saw);
    var first: [3]f32 = undefined;
    var second: [2]f32 = undefined;
    saw.process(&first);
    saw.process(&second);
    try std.testing.expectEqualSlices(
        f32,
        &.{ -1.0, -0.5, 0.0 },
        &first,
    );
    try std.testing.expectEqualSlices(f32, &.{ 0.5, -1.0 }, &second);

    var triangle = try Oscillator(f64).init(8_000.0, 2_000.0, .triangle);
    var triangle_samples: [4]f64 = undefined;
    triangle.process(&triangle_samples);
    try std.testing.expectEqualSlices(
        f64,
        &.{ -1.0, 0.0, 1.0, 0.0 },
        &triangle_samples,
    );
}

test "oscillator sine and square match quarter-cycle identities" {
    var sine = try Oscillator(f64).init(8_000.0, 2_000.0, .sine);
    var sine_samples: [4]f64 = undefined;
    sine.process(&sine_samples);
    for (
        [_]f64{ 0.0, 1.0, 0.0, -1.0 },
        sine_samples,
    ) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_001,
        );
    }

    var square = try Oscillator(f32).init(8_000.0, 2_000.0, .square);
    var square_samples: [4]f32 = undefined;
    square.process(&square_samples);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1.0, 1.0, -1.0, -1.0 },
        &square_samples,
    );
}

test "oscillator validates configuration and normalizes reset phase" {
    try std.testing.expectError(
        error.InvalidOscillatorConfig,
        Oscillator(f32).init(48_000.0, 25_000.0, .sine),
    );
    var oscillator = try Oscillator(f64).init(48_000.0, 0.0, .sine);
    try oscillator.reset(1.25);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        oscillator.next(),
        0.000_000_001,
    );
    try std.testing.expectError(
        error.InvalidOscillatorPhase,
        oscillator.reset(std.math.nan(f64)),
    );
    oscillator.sample_rate = 0.0;
    try std.testing.expectEqual(@as(f64, 0.0), oscillator.next());
}
