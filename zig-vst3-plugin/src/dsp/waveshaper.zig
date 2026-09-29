const std = @import("std");
const dry_wet = @import("dry_wet.zig");

pub const Kind = enum {
    hard_clip,
    tanh,
    atan,
    cubic,
};

pub const Config = struct {
    kind: Kind = .tanh,
    drive_db: f64 = 0.0,
    output_db: f64 = 0.0,
    mix: f64 = 1.0,
    mixing_rule: dry_wet.MixingRule = .equal_power,

    pub fn validate(self: Config) !void {
        if (!std.math.isFinite(self.drive_db) or
            self.drive_db < -24.0 or
            self.drive_db > 48.0 or
            !std.math.isFinite(self.output_db) or
            self.output_db < -60.0 or
            self.output_db > 24.0 or
            !std.math.isFinite(self.mix) or
            self.mix < 0.0 or
            self.mix > 1.0)
            return error.InvalidWaveshaperConfig;
    }
};

pub fn WaveShaper(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Waveshaper supports f32 and f64 samples");

    return struct {
        const Self = @This();

        config: Config = .{},
        drive: Sample = 1.0,
        output_gain: Sample = 1.0,

        pub fn init(config: Config) !Self {
            var self = Self{};
            try self.configure(config);
            return self;
        }

        pub fn configure(self: *Self, config: Config) !void {
            try config.validate();
            const drive = dbToLinear(config.drive_db);
            const output_gain = dbToLinear(config.output_db);
            if (!std.math.isFinite(drive) or
                !std.math.isFinite(output_gain))
                return error.InvalidWaveshaperConfig;
            self.config = config;
            self.drive = @floatCast(drive);
            self.output_gain = @floatCast(output_gain);
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const dry = if (std.math.isFinite(input)) input else 0.0;
            if (!self.valid()) {
                self.* = .{};
                return dry;
            }
            const shaped =
                shape(Sample, dry * self.drive, self.config.kind) *
                self.output_gain;
            const gains = dry_wet.mixingGains(
                Sample,
                self.config.mix,
                self.config.mixing_rule,
            );
            const output = dry * gains.dry + shaped * gains.wet;
            return if (std.math.isFinite(output)) output else 0.0;
        }

        pub fn process(self: *Self, samples: []Sample) void {
            for (samples) |*sample|
                sample.* = self.processSample(sample.*);
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            const expected_drive: Sample =
                @floatCast(dbToLinear(self.config.drive_db));
            const expected_output: Sample =
                @floatCast(dbToLinear(self.config.output_db));
            return self.drive == expected_drive and
                self.output_gain == expected_output;
        }
    };
}

pub fn shape(
    comptime Sample: type,
    input: Sample,
    kind: Kind,
) Sample {
    if (Sample != f32 and Sample != f64)
        @compileError("waveshaper functions support f32 and f64 samples");
    if (!std.math.isFinite(input)) return 0.0;
    return switch (kind) {
        .hard_clip => std.math.clamp(input, -1.0, 1.0),
        .tanh => std.math.tanh(input),
        .atan => 2.0 * std.math.atan(input) / std.math.pi,
        .cubic => blk: {
            const clamped = std.math.clamp(input, -1.0, 1.0);
            break :blk 1.5 *
                (clamped - clamped * clamped * clamped / 3.0);
        },
    };
}

fn dbToLinear(value: f64) f64 {
    return std.math.pow(f64, 10.0, value / 20.0);
}

test "waveshaper functions are bounded and odd symmetric" {
    inline for (.{ Kind.hard_clip, Kind.tanh, Kind.atan, Kind.cubic }) |kind| {
        const positive = shape(f64, 2.0, kind);
        const negative = shape(f64, -2.0, kind);
        try std.testing.expect(positive <= 1.0);
        try std.testing.expect(positive >= 0.0);
        try std.testing.expectApproxEqAbs(
            positive,
            -negative,
            0.000_000_000_001,
        );
    }
    try std.testing.expectEqual(
        @as(f32, 1.0),
        shape(f32, 3.0, .hard_clip),
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        shape(f32, 3.0, .cubic),
        0.000_001,
    );
}

test "waveshaper config and dry mix are deterministic" {
    var shaper = try WaveShaper(f32).init(.{
        .kind = .hard_clip,
        .drive_db = 6.020_599_913,
        .mix = 1.0,
        .mixing_rule = .linear,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        shaper.processSample(0.75),
        0.000_001,
    );
    try shaper.configure(.{
        .kind = .hard_clip,
        .drive_db = 24.0,
        .mix = 0.0,
        .mixing_rule = .linear,
    });
    try std.testing.expectEqual(
        @as(f32, 0.75),
        shaper.processSample(0.75),
    );
}

test "waveshaper rejects configuration and contains hostile state" {
    var shaper = try WaveShaper(f64).init(.{});
    try std.testing.expectError(
        error.InvalidWaveshaperConfig,
        shaper.configure(.{ .drive_db = std.math.nan(f64) }),
    );
    try std.testing.expect(shaper.valid());
    shaper.drive = std.math.inf(f64);
    try std.testing.expectEqual(
        @as(f64, 0.25),
        shaper.processSample(0.25),
    );
    try std.testing.expect(shaper.valid());
    try std.testing.expectEqual(
        @as(f64, 0.0),
        shaper.processSample(std.math.nan(f64)),
    );
}
