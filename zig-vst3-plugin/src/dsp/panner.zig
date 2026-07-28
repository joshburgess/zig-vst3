const std = @import("std");
const dry_wet = @import("dry_wet.zig");

pub const Rule = dry_wet.MixingRule;

pub fn StereoPanner(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("StereoPanner supports f32 and f64 samples");

    return struct {
        const Self = @This();

        pan: f64 = 0.0,
        rule: Rule = .equal_power,
        left_gain: Sample = @floatCast(std.math.sqrt1_2),
        right_gain: Sample = @floatCast(std.math.sqrt1_2),

        pub fn init(pan: f64) !Self {
            return initWithRule(pan, .equal_power);
        }

        pub fn initWithRule(pan: f64, rule: Rule) !Self {
            try validatePan(pan);
            const gains = calculateGains(Sample, pan, rule);
            return .{
                .pan = pan,
                .rule = rule,
                .left_gain = gains.dry,
                .right_gain = gains.wet,
            };
        }

        pub fn setPan(self: *Self, pan: f64) !void {
            try validatePan(pan);
            const gains = calculateGains(Sample, pan, self.rule);
            self.pan = pan;
            self.left_gain = gains.dry;
            self.right_gain = gains.wet;
        }

        pub fn setRule(self: *Self, rule: Rule) void {
            const gains = calculateGains(Sample, self.pan, rule);
            self.rule = rule;
            self.left_gain = gains.dry;
            self.right_gain = gains.wet;
        }

        pub fn processSample(self: *const Self, input: Sample) [2]Sample {
            if (!self.processingValid() or !std.math.isFinite(input))
                return .{ 0.0, 0.0 };
            return .{
                input * self.left_gain,
                input * self.right_gain,
            };
        }

        pub fn process(
            self: *const Self,
            input: []const Sample,
            left: []Sample,
            right: []Sample,
        ) !void {
            if (input.len != left.len or input.len != right.len)
                return error.PannerBufferLengthMismatch;
            for (input, left, right) |input_sample, *left_sample, *right_sample| {
                const output = self.processSample(input_sample);
                left_sample.* = output[0];
                right_sample.* = output[1];
            }
        }

        pub fn valid(self: *const Self) bool {
            validatePan(self.pan) catch return false;
            const expected = calculateGains(Sample, self.pan, self.rule);
            return self.left_gain == expected.dry and
                self.right_gain == expected.wet;
        }

        fn processingValid(self: *const Self) bool {
            validatePan(self.pan) catch return false;
            return std.math.isFinite(self.left_gain) and
                self.left_gain >= 0.0 and
                std.math.isFinite(self.right_gain) and
                self.right_gain >= 0.0;
        }

        fn validatePan(pan: f64) !void {
            if (!std.math.isFinite(pan) or pan < -1.0 or pan > 1.0)
                return error.InvalidPannerPosition;
        }
    };
}

fn calculateGains(comptime Sample: type, pan: f64, rule: Rule) @TypeOf(
    dry_wet.mixingGains(Sample, 0.5, rule),
) {
    return dry_wet.mixingGains(Sample, (pan + 1.0) * 0.5, rule);
}

test "stereo panner uses an equal-power law" {
    var center = try StereoPanner(f64).init(0.0);
    const centered = center.processSample(1.0);
    try std.testing.expectApproxEqAbs(
        @as(f64, std.math.sqrt1_2),
        centered[0],
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        centered[0] * centered[0] + centered[1] * centered[1],
        0.000_000_001,
    );

    try center.setPan(-1.0);
    try std.testing.expectEqualDeep([2]f64{ 1.0, 0.0 }, center.processSample(1.0));
    try center.setPan(1.0);
    const right = center.processSample(1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), right[0], 0.000_000_001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), right[1], 0.000_000_001);
}

test "stereo panner supports every gain law" {
    inline for (std.meta.tags(Rule)) |rule| {
        var panner = try StereoPanner(f64).initWithRule(0.0, rule);
        const center = panner.processSample(1.0);
        try std.testing.expect(std.math.isFinite(center[0]));
        try std.testing.expect(std.math.isFinite(center[1]));
        try std.testing.expectApproxEqAbs(center[0], center[1], 0.000_001);
        try panner.setPan(-1.0);
        try std.testing.expectEqualDeep(
            [2]f64{ 1.0, 0.0 },
            panner.processSample(1.0),
        );
        try panner.setPan(1.0);
        try std.testing.expectApproxEqAbs(
            @as(f64, 0.0),
            panner.processSample(1.0)[0],
            0.000_001,
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            panner.processSample(1.0)[1],
            0.000_001,
        );
    }
}

test "stereo panner validates position and buffers" {
    var panner = try StereoPanner(f32).init(0.25);
    try std.testing.expectError(
        error.InvalidPannerPosition,
        panner.setPan(std.math.nan(f64)),
    );
    var left: [1]f32 = undefined;
    var right: [2]f32 = undefined;
    try std.testing.expectError(
        error.PannerBufferLengthMismatch,
        panner.process(&.{ 1.0, 2.0 }, &left, &right),
    );
    try std.testing.expectEqualDeep(
        [2]f32{ 0.0, 0.0 },
        panner.processSample(std.math.inf(f32)),
    );
    panner.pan = 2.0;
    try std.testing.expectEqualDeep(
        [2]f32{ 0.0, 0.0 },
        panner.processSample(1.0),
    );
}
