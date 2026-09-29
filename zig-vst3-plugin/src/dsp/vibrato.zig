const std = @import("std");
const modulated_delay = @import("modulated_delay.zig");
const modulation_rate = @import("modulation_rate.zig");

pub const Config = struct {
    sample_rate: f64,
    rate_hz: f64 = 5.0,
    center_delay_ms: f64 = 6.0,
    depth_ms: f64 = 2.0,
};

pub fn Vibrato(
    comptime Sample: type,
    comptime maximum_delay_samples: usize,
) type {
    const Core = modulated_delay.Processor(Sample, maximum_delay_samples);
    return struct {
        const Self = @This();

        core: Core,

        pub fn init(config: Config) !Self {
            return .{ .core = Core.init(toCore(config)) catch
                return error.InvalidVibratoConfig };
        }

        pub fn configure(self: *Self, config: Config) !void {
            self.core.configure(toCore(config)) catch
                return error.InvalidVibratoConfig;
        }

        pub fn configureSmooth(
            self: *Self,
            config: Config,
            smoothing_seconds: f64,
        ) !void {
            self.core.configureSmooth(
                toCore(config),
                smoothing_seconds,
            ) catch return error.InvalidVibratoConfig;
        }

        pub fn syncTempo(
            self: *Self,
            bpm: f64,
            division: modulation_rate.NoteDivision,
            smoothing_seconds: f64,
        ) !void {
            self.core.syncTempo(
                bpm,
                division,
                smoothing_seconds,
            ) catch return error.InvalidVibratoTempo;
        }

        pub fn syncTransport(
            self: *Self,
            transport: ?@import("../process/context.zig").Transport,
            fallback_bpm: f64,
            division: modulation_rate.NoteDivision,
            smoothing_seconds: f64,
        ) !void {
            self.core.syncTransport(
                transport,
                fallback_bpm,
                division,
                smoothing_seconds,
            ) catch return error.InvalidVibratoTempo;
        }

        pub fn reset(self: *Self, phase: f64) !void {
            self.core.reset(phase) catch return error.InvalidVibratoPhase;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            return self.core.processSample(input);
        }

        pub fn process(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            self.core.process(input, output) catch |err| switch (err) {
                error.ModulatedDelayBufferLengthMismatch => return error.VibratoBufferLengthMismatch,
                error.ModulatedDelayBufferOverlap => return error.VibratoBufferOverlap,
            };
        }

        pub fn valid(self: *const Self) bool {
            return self.core.valid();
        }

        fn toCore(config: Config) modulated_delay.Config {
            return .{
                .sample_rate = config.sample_rate,
                .rate_hz = config.rate_hz,
                .center_delay_ms = config.center_delay_ms,
                .depth_ms = config.depth_ms,
                .feedback = 0.0,
                .mix = 1.0,
                .mixing_rule = .linear,
            };
        }
    };
}

test "vibrato exposes only its delayed path" {
    const Effect = Vibrato(f64, 32);
    var effect = try Effect.init(.{
        .sample_rate = 1_000.0,
        .rate_hz = 0.0,
        .center_delay_ms = 3.0,
        .depth_ms = 0.0,
    });
    var output: [6]f64 = undefined;
    try effect.process(&.{ 1.0, 0.0, 0.0, 0.0, 0.0, 0.0 }, &output);
    try std.testing.expectEqual(@as(f64, 0.0), output[0]);
    try std.testing.expectEqual(@as(f64, 1.0), output[3]);
}

test "vibrato preserves state across block partitions" {
    const Effect = Vibrato(f32, 512);
    const config = Config{
        .sample_rate = 48_000.0,
        .rate_hz = 4.0,
        .center_delay_ms = 5.0,
        .depth_ms = 2.0,
    };
    var input: [64]f32 = undefined;
    for (&input, 0..) |*sample, index|
        sample.* = @as(f32, @floatFromInt(index)) / 64.0;
    var whole = try Effect.init(config);
    var whole_output: [64]f32 = undefined;
    try whole.process(&input, &whole_output);
    var split = try Effect.init(config);
    var split_output: [64]f32 = undefined;
    try split.process(input[0..19], split_output[0..19]);
    try split.process(input[19..], split_output[19..]);
    try std.testing.expectEqualSlices(f32, &whole_output, &split_output);
}

test "vibrato rejects invalid configuration" {
    const Effect = Vibrato(f32, 256);
    try std.testing.expectError(
        error.InvalidVibratoConfig,
        Effect.init(.{
            .sample_rate = 48_000.0,
            .center_delay_ms = 1.0,
            .depth_ms = 2.0,
        }),
    );
}

test "vibrato exposes tempo synchronization and smoothing" {
    const Effect = Vibrato(f32, 512);
    var effect = try Effect.init(.{ .sample_rate = 48_000.0 });
    try effect.syncTempo(120.0, .eighth, 0.01);
    try std.testing.expectEqual(@as(f64, 4.0), effect.core.config.rate_hz);
    try std.testing.expect(effect.valid());
}

test "vibrato translates shifted overlap without mutation" {
    const Effect = Vibrato(f32, 512);
    var effect = try Effect.init(.{ .sample_rate = 48_000.0 });
    var storage = [_]f32{ 1.0, 0.5, 0.25, 0.0 };
    const retained = storage;
    const before = effect;
    try std.testing.expectError(
        error.VibratoBufferOverlap,
        effect.process(storage[0..3], storage[1..4]),
    );
    try std.testing.expectEqualDeep(before, effect);
    try std.testing.expectEqualSlices(f32, &retained, &storage);
}
