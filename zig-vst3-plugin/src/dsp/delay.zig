const std = @import("std");

pub const Interpolation = enum {
    linear,
    cubic,
};

pub fn DelayLine(comptime Sample: type, comptime capacity: usize) type {
    if (Sample != f32 and Sample != f64)
        @compileError("DelayLine supports f32 and f64 samples");
    if (capacity < 4)
        @compileError("DelayLine capacity must be at least four samples");

    return struct {
        const Self = @This();

        buffer: [capacity]Sample = @splat(0.0),
        write_index: usize = 0,

        pub fn reset(self: *Self) void {
            self.buffer = @splat(0.0);
            self.write_index = 0;
        }

        pub fn processSample(
            self: *Self,
            input: Sample,
            delay_samples: f64,
            interpolation: Interpolation,
        ) !Sample {
            try validateDelay(delay_samples, interpolation);
            return self.processValid(input, delay_samples, interpolation);
        }

        pub fn process(
            self: *Self,
            input: []const Sample,
            output: []Sample,
            delay_samples: f64,
            interpolation: Interpolation,
        ) !void {
            if (input.len != output.len)
                return error.DelayLineBufferLengthMismatch;
            try validateDelay(delay_samples, interpolation);
            for (input, output) |input_sample, *output_sample| {
                output_sample.* = self.processValid(
                    input_sample,
                    delay_samples,
                    interpolation,
                );
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.write_index >= capacity) return false;
            for (self.buffer) |sample| {
                if (!std.math.isFinite(sample)) return false;
            }
            return true;
        }

        fn processValid(
            self: *Self,
            input: Sample,
            delay_samples: f64,
            interpolation: Interpolation,
        ) Sample {
            if (self.write_index >= capacity) self.reset();
            self.buffer[self.write_index] =
                if (std.math.isFinite(input)) input else 0.0;

            const integer_delay: usize = @intFromFloat(@floor(delay_samples));
            const fraction: Sample = @floatCast(
                delay_samples - @floor(delay_samples),
            );
            const newer = self.sampleBack(integer_delay);
            const output = switch (interpolation) {
                .linear => blk: {
                    const older = self.sampleBack(integer_delay + 1);
                    break :blk newer * (1.0 - fraction) + older * fraction;
                },
                .cubic => blk: {
                    const recent = self.sampleBack(integer_delay - 1);
                    const older = self.sampleBack(integer_delay + 1);
                    const oldest = self.sampleBack(integer_delay + 2);
                    const c0 = newer;
                    const c1 = 0.5 * (older - recent);
                    const c2 = recent - 2.5 * newer +
                        2.0 * older - 0.5 * oldest;
                    const c3 = 0.5 * (oldest - recent) +
                        1.5 * (newer - older);
                    break :blk ((c3 * fraction + c2) * fraction + c1) *
                        fraction + c0;
                },
            };
            self.write_index = (self.write_index + 1) % capacity;
            return output;
        }

        fn sampleBack(self: *const Self, distance: usize) Sample {
            const index =
                (self.write_index + capacity - distance % capacity) % capacity;
            const sample = self.buffer[index];
            return if (std.math.isFinite(sample)) sample else 0.0;
        }

        fn validateDelay(
            delay_samples: f64,
            interpolation: Interpolation,
        ) !void {
            const maximum: f64 = @floatFromInt(switch (interpolation) {
                .linear => capacity - 1,
                .cubic => capacity - 2,
            });
            if (!std.math.isFinite(delay_samples) or
                delay_samples < 1.0 or
                delay_samples > maximum)
                return error.InvalidDelayLineDelay;
        }
    };
}

test "delay line preserves integer and fractional delays across blocks" {
    var integer = DelayLine(f32, 8){};
    var first_output: [3]f32 = undefined;
    var second_output: [2]f32 = undefined;
    try integer.process(
        &.{ 1.0, 2.0, 3.0 },
        &first_output,
        2.0,
        .linear,
    );
    try integer.process(
        &.{ 4.0, 5.0 },
        &second_output,
        2.0,
        .linear,
    );
    try std.testing.expectEqualSlices(f32, &.{ 0.0, 0.0, 1.0 }, &first_output);
    try std.testing.expectEqualSlices(f32, &.{ 2.0, 3.0 }, &second_output);

    var fractional = DelayLine(f64, 8){};
    var fractional_output: [4]f64 = undefined;
    try fractional.process(
        &.{ 1.0, 2.0, 3.0, 4.0 },
        &fractional_output,
        1.5,
        .linear,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.0, 0.5, 1.5, 2.5 },
        &fractional_output,
    );
}

test "delay line cubic interpolation is exact at integer positions" {
    var delay = DelayLine(f64, 8){};
    var output: [5]f64 = undefined;
    try delay.process(&.{ 1.0, 2.0, 3.0, 4.0, 5.0 }, &output, 2.0, .cubic);
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.0, 0.0, 1.0, 2.0, 3.0 },
        &output,
    );
}

test "delay line rejects invalid calls without advancing" {
    var delay = DelayLine(f32, 8){};
    try std.testing.expectError(
        error.InvalidDelayLineDelay,
        delay.processSample(1.0, 0.0, .linear),
    );
    var empty: [0]f32 = .{};
    try std.testing.expectError(
        error.DelayLineBufferLengthMismatch,
        delay.process(&.{1.0}, &empty, 1.0, .linear),
    );
    try std.testing.expectEqual(@as(usize, 0), delay.write_index);
    try std.testing.expectEqual(
        @as(f32, 0.0),
        try delay.processSample(std.math.nan(f32), 1.0, .linear),
    );
    delay.write_index = 100;
    try std.testing.expectEqual(
        @as(f32, 0.0),
        try delay.processSample(1.0, 1.0, .linear),
    );
    try std.testing.expect(delay.valid());
}
