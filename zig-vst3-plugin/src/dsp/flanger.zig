const std = @import("std");
const modulated_delay = @import("modulated_delay.zig");
const modulation_rate = @import("modulation_rate.zig");

pub const Config = struct {
    sample_rate: f64,
    rate_hz: f64 = 0.25,
    center_delay_ms: f64 = 2.0,
    depth_ms: f64 = 1.0,
    feedback: f64 = 0.5,
    mix: f64 = 0.5,
};

pub fn Flanger(
    comptime Sample: type,
    comptime maximum_delay_samples: usize,
) type {
    const Core = modulated_delay.Processor(Sample, maximum_delay_samples);
    return struct {
        const Self = @This();

        core: Core,

        pub fn init(config: Config) !Self {
            return .{ .core = Core.init(toCore(config)) catch
                return error.InvalidFlangerConfig };
        }

        pub fn configure(self: *Self, config: Config) !void {
            self.core.configure(toCore(config)) catch
                return error.InvalidFlangerConfig;
        }

        pub fn configureSmooth(
            self: *Self,
            config: Config,
            smoothing_seconds: f64,
        ) !void {
            self.core.configureSmooth(
                toCore(config),
                smoothing_seconds,
            ) catch return error.InvalidFlangerConfig;
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
            ) catch return error.InvalidFlangerTempo;
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
            ) catch return error.InvalidFlangerTempo;
        }

        pub fn reset(self: *Self, phase: f64) !void {
            self.core.reset(phase) catch return error.InvalidFlangerPhase;
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
                error.ModulatedDelayBufferLengthMismatch => return error.FlangerBufferLengthMismatch,
                error.ModulatedDelayBufferOverlap => return error.FlangerBufferOverlap,
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
                .feedback = config.feedback,
                .mix = config.mix,
                .mixing_rule = .linear,
            };
        }
    };
}

test "flanger produces feedback comb echoes" {
    const Effect = Flanger(f64, 32);
    var effect = try Effect.init(.{
        .sample_rate = 1_000.0,
        .rate_hz = 0.0,
        .center_delay_ms = 2.0,
        .depth_ms = 0.0,
        .feedback = 0.5,
        .mix = 1.0,
    });
    var output: [9]f64 = undefined;
    try effect.process(
        &.{ 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
        &output,
    );
    try std.testing.expectEqual(@as(f64, 1.0), output[2]);
    try std.testing.expectEqual(@as(f64, 0.5), output[5]);
    try std.testing.expectEqual(@as(f64, 0.25), output[8]);
}

test "flanger rejects impossible delay range" {
    const Effect = Flanger(f32, 128);
    try std.testing.expectError(
        error.InvalidFlangerConfig,
        Effect.init(.{
            .sample_rate = 48_000.0,
            .center_delay_ms = 1.0,
            .depth_ms = 2.0,
        }),
    );
}

test "flanger exposes tempo synchronization and smoothing" {
    const Effect = Flanger(f32, 512);
    var effect = try Effect.init(.{ .sample_rate = 48_000.0 });
    try effect.syncTempo(90.0, .dotted_quarter, 0.01);
    try std.testing.expectEqual(@as(f64, 1.0), effect.core.config.rate_hz);
    try std.testing.expect(effect.valid());
}

test "flanger translates shifted overlap without mutation" {
    const Effect = Flanger(f32, 512);
    var effect = try Effect.init(.{ .sample_rate = 48_000.0 });
    var storage = [_]f32{ 1.0, 0.5, 0.25, 0.0 };
    const retained = storage;
    const before = effect;
    try std.testing.expectError(
        error.FlangerBufferOverlap,
        effect.process(storage[0..3], storage[1..4]),
    );
    try std.testing.expectEqualDeep(before, effect);
    try std.testing.expectEqualSlices(f32, &retained, &storage);
}
