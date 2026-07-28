const std = @import("std");

pub const MixingRule = enum {
    linear,
    equal_power,
    balanced,
    sine_3_db,
    sine_4_5_db,
    sine_6_db,
    square_root_3_db,
    square_root_4_5_db,
};

pub const Config = struct {
    wet: f64 = 0.5,
    wet_latency_samples: f64 = 0.0,
    rule: MixingRule = .equal_power,
};

pub fn DryWetMixer(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime maximum_latency_samples: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("DryWetMixer supports f32 and f64 samples");
    if (maximum_frames == 0)
        @compileError("DryWetMixer frame capacity must be nonzero");
    if (maximum_latency_samples == 0)
        @compileError("DryWetMixer latency capacity must be nonzero");

    const history_capacity = maximum_latency_samples + 2;

    return struct {
        const Self = @This();

        config: Config,
        history: [history_capacity]Sample = @splat(0.0),
        write_index: usize = 0,
        pending_dry: [maximum_frames]Sample = undefined,
        pending_count: usize = 0,

        pub fn init(config: Config) !Self {
            try validateConfig(config);
            return .{ .config = config };
        }

        pub fn configure(self: *Self, config: Config) !void {
            try validateConfig(config);
            if (self.pending_count != 0) return error.DryBlockPending;
            self.config = config;
        }

        pub fn reset(self: *Self) void {
            self.history = @splat(0.0);
            self.write_index = 0;
            self.pending_count = 0;
        }

        pub fn pushDry(self: *Self, dry: []const Sample) !void {
            if (!self.valid()) return error.InvalidDryWetState;
            if (self.pending_count != 0) return error.DryBlockPending;
            if (dry.len == 0) return;
            if (dry.len > maximum_frames) return error.DryWetCapacityExceeded;
            for (dry) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFiniteDryWetInput;
            }

            for (dry, self.pending_dry[0..dry.len]) |sample, *delayed| {
                self.history[self.write_index] = sample;
                delayed.* = self.readDelay(self.config.wet_latency_samples);
                self.write_index = (self.write_index + 1) % history_capacity;
            }
            self.pending_count = dry.len;
        }

        pub fn mixWet(self: *Self, wet: []Sample) !void {
            if (!self.valid()) return error.InvalidDryWetState;
            if (self.pending_count == 0) return error.NoDryBlock;
            if (wet.len != self.pending_count)
                return error.DryWetFrameMismatch;
            for (wet) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFiniteDryWetInput;
            }

            const gains = mixingGains(
                Sample,
                self.config.wet,
                self.config.rule,
            );
            for (wet, self.pending_dry[0..self.pending_count]) |
                *wet_sample,
                dry_sample,
            | {
                wet_sample.* =
                    dry_sample * gains.dry +
                    wet_sample.* * gains.wet;
            }
            self.pending_count = 0;
        }

        pub fn valid(self: *const Self) bool {
            validateConfig(self.config) catch return false;
            if (self.write_index >= history_capacity or
                self.pending_count > maximum_frames)
                return false;
            for (self.history) |sample| {
                if (!std.math.isFinite(sample)) return false;
            }
            for (self.pending_dry[0..self.pending_count]) |sample| {
                if (!std.math.isFinite(sample)) return false;
            }
            return true;
        }

        fn readDelay(self: *const Self, delay_samples: f64) Sample {
            const integer_delay: usize =
                @intFromFloat(@floor(delay_samples));
            const fraction: Sample = @floatCast(
                delay_samples - @floor(delay_samples),
            );
            const newer = self.sampleBack(integer_delay);
            const older = self.sampleBack(integer_delay + 1);
            return newer * (1.0 - fraction) + older * fraction;
        }

        fn sampleBack(self: *const Self, distance: usize) Sample {
            const index =
                (self.write_index + history_capacity -
                    distance % history_capacity) %
                history_capacity;
            return self.history[index];
        }

        fn validateConfig(config: Config) !void {
            if (!std.math.isFinite(config.wet) or
                config.wet < 0.0 or
                config.wet > 1.0 or
                !std.math.isFinite(config.wet_latency_samples) or
                config.wet_latency_samples < 0.0 or
                config.wet_latency_samples >
                    @as(f64, @floatFromInt(maximum_latency_samples)))
                return error.InvalidDryWetConfig;
        }
    };
}

pub fn mixingGains(
    comptime Sample: type,
    wet: f64,
    rule: MixingRule,
) GainPair(Sample) {
    if (Sample != f32 and Sample != f64)
        @compileError("mixingGains supports f32 and f64 samples");
    if (!std.math.isFinite(wet) or wet < 0.0 or wet > 1.0)
        return .{ .dry = 1.0, .wet = 0.0 };
    return switch (rule) {
        .linear => .{
            .dry = @floatCast(1.0 - wet),
            .wet = @floatCast(wet),
        },
        .equal_power => .{
            .dry = @floatCast(@cos(wet * std.math.pi * 0.5)),
            .wet = @floatCast(@sin(wet * std.math.pi * 0.5)),
        },
        .balanced => .{
            .dry = @floatCast(2.0 * @min(0.5, 1.0 - wet)),
            .wet = @floatCast(2.0 * @min(0.5, wet)),
        },
        .sine_3_db => sineGains(Sample, wet, 1.0),
        .sine_4_5_db => sineGains(Sample, wet, 1.5),
        .sine_6_db => sineGains(Sample, wet, 2.0),
        .square_root_3_db => .{
            .dry = @floatCast(@sqrt(1.0 - wet)),
            .wet = @floatCast(@sqrt(wet)),
        },
        .square_root_4_5_db => .{
            .dry = @floatCast(std.math.pow(f64, @sqrt(1.0 - wet), 1.5)),
            .wet = @floatCast(std.math.pow(f64, @sqrt(wet), 1.5)),
        },
    };
}

fn sineGains(
    comptime Sample: type,
    wet: f64,
    exponent: f64,
) GainPair(Sample) {
    return .{
        .dry = @floatCast(std.math.pow(
            f64,
            @sin((1.0 - wet) * std.math.pi * 0.5),
            exponent,
        )),
        .wet = @floatCast(std.math.pow(
            f64,
            @sin(wet * std.math.pi * 0.5),
            exponent,
        )),
    };
}

fn GainPair(comptime Sample: type) type {
    return struct {
        dry: Sample,
        wet: Sample,
    };
}

test "dry wet mixer compensates integer and fractional latency" {
    const Mixer = DryWetMixer(f64, 8, 4);
    var mixer = try Mixer.init(.{
        .wet = 0.0,
        .wet_latency_samples = 2.0,
        .rule = .linear,
    });
    try mixer.pushDry(&.{ 1.0, 0.0, 0.0, 0.0 });
    var wet: [4]f64 = @splat(0.0);
    try mixer.mixWet(&wet);
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.0, 0.0, 1.0, 0.0 },
        &wet,
    );

    try mixer.configure(.{
        .wet = 0.0,
        .wet_latency_samples = 1.5,
        .rule = .linear,
    });
    mixer.reset();
    try mixer.pushDry(&.{ 1.0, 0.0, 0.0 });
    var fractional: [3]f64 = @splat(0.0);
    try mixer.mixWet(&fractional);
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.0, 0.5, 0.5 },
        &fractional,
    );
}

test "dry wet mixer applies all gain laws" {
    const Mixer = DryWetMixer(f32, 4, 2);
    var mixer = try Mixer.init(.{
        .wet = 0.5,
        .rule = .equal_power,
    });
    try mixer.pushDry(&.{1.0});
    var wet = [_]f32{1.0};
    try mixer.mixWet(&wet);
    try std.testing.expectApproxEqAbs(
        @as(f32, @sqrt(2.0)),
        wet[0],
        0.000_001,
    );

    try mixer.configure(.{ .wet = 0.25, .rule = .linear });
    try mixer.pushDry(&.{1.0});
    wet[0] = 1.0;
    try mixer.mixWet(&wet);
    try std.testing.expectEqual(@as(f32, 1.0), wet[0]);

    const center_expectations = [_]struct {
        rule: MixingRule,
        gain: f64,
    }{
        .{ .rule = .linear, .gain = 0.5 },
        .{ .rule = .equal_power, .gain = std.math.sqrt1_2 },
        .{ .rule = .balanced, .gain = 1.0 },
        .{ .rule = .sine_3_db, .gain = std.math.sqrt1_2 },
        .{
            .rule = .sine_4_5_db,
            .gain = std.math.pow(f64, std.math.sqrt1_2, 1.5),
        },
        .{ .rule = .sine_6_db, .gain = 0.5 },
        .{ .rule = .square_root_3_db, .gain = std.math.sqrt1_2 },
        .{
            .rule = .square_root_4_5_db,
            .gain = std.math.pow(f64, std.math.sqrt1_2, 1.5),
        },
    };
    for (center_expectations) |expected| {
        const gains = mixingGains(f64, 0.5, expected.rule);
        try std.testing.expectApproxEqAbs(expected.gain, gains.dry, 0.000_001);
        try std.testing.expectApproxEqAbs(expected.gain, gains.wet, 0.000_001);
        const dry_endpoint = mixingGains(f64, 0.0, expected.rule);
        const wet_endpoint = mixingGains(f64, 1.0, expected.rule);
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            dry_endpoint.dry,
            0.000_001,
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            wet_endpoint.wet,
            0.000_001,
        );
    }
}

test "dry wet sequencing failures preserve pending data" {
    const Mixer = DryWetMixer(f32, 4, 2);
    var mixer = try Mixer.init(.{});
    try mixer.pushDry(&.{ 1.0, 2.0 });
    try std.testing.expectError(
        error.DryBlockPending,
        mixer.pushDry(&.{1.0}),
    );
    try std.testing.expectError(
        error.DryBlockPending,
        mixer.configure(.{ .wet = 0.25 }),
    );
    var wrong_size = [_]f32{1.0};
    try std.testing.expectError(
        error.DryWetFrameMismatch,
        mixer.mixWet(&wrong_size),
    );
    try std.testing.expectEqual(@as(usize, 2), mixer.pending_count);
    var invalid = [_]f32{ 1.0, std.math.nan(f32) };
    try std.testing.expectError(
        error.NonFiniteDryWetInput,
        mixer.mixWet(&invalid),
    );
    try std.testing.expectEqual(@as(usize, 2), mixer.pending_count);
}
