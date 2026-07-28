const std = @import("std");

pub fn AudioBlock(comptime Sample: type, comptime maximum_channels: usize) type {
    validateType(Sample, maximum_channels);

    return struct {
        const Self = @This();

        channels: [maximum_channels][]Sample,
        channel_count: usize,
        frame_count: usize,

        /// The channel slices and their sample storage must outlive the block.
        pub fn init(source: []const []Sample) !Self {
            const frame_count = try validateShape(Sample, maximum_channels, source);
            var channels: [maximum_channels][]Sample = undefined;
            for (source, 0..) |channel_samples, index|
                channels[index] = channel_samples;
            return .{
                .channels = channels,
                .channel_count = source.len,
                .frame_count = frame_count,
            };
        }

        pub fn channel(self: *const Self, index: usize) ![]Sample {
            if (index >= self.channel_count) return error.AudioBlockChannelOutOfRange;
            return self.channels[index];
        }

        pub fn subBlock(self: *const Self, offset: usize, count: usize) !Self {
            if (offset > self.frame_count or count > self.frame_count - offset)
                return error.AudioBlockFrameRangeOutOfBounds;
            var channels: [maximum_channels][]Sample = undefined;
            for (0..self.channel_count) |index|
                channels[index] = self.channels[index][offset..][0..count];
            return .{
                .channels = channels,
                .channel_count = self.channel_count,
                .frame_count = count,
            };
        }

        pub fn subsetChannels(
            self: *const Self,
            offset: usize,
            count: usize,
        ) !Self {
            if (offset > self.channel_count or count > self.channel_count - offset)
                return error.AudioBlockChannelRangeOutOfBounds;
            if (count == 0) return error.AudioBlockRequiresChannels;
            var channels: [maximum_channels][]Sample = undefined;
            for (0..count) |index| channels[index] = self.channels[offset + index];
            return .{
                .channels = channels,
                .channel_count = count,
                .frame_count = self.frame_count,
            };
        }

        pub fn asConst(self: *const Self) ConstAudioBlock(Sample, maximum_channels) {
            var channels: [maximum_channels][]const Sample = undefined;
            for (0..self.channel_count) |index| channels[index] = self.channels[index];
            return .{
                .channels = channels,
                .channel_count = self.channel_count,
                .frame_count = self.frame_count,
            };
        }

        pub fn clear(self: *Self) void {
            for (0..self.channel_count) |index|
                @memset(self.channels[index], 0.0);
        }

        pub fn fill(self: *Self, value: Sample) !void {
            if (!std.math.isFinite(value)) return error.AudioBlockNonFiniteValue;
            for (0..self.channel_count) |index|
                @memset(self.channels[index], value);
        }

        pub fn multiply(self: *Self, gain: Sample) !void {
            if (!std.math.isFinite(gain)) return error.AudioBlockNonFiniteValue;
            for (0..self.channel_count) |channel_index| {
                for (self.channels[channel_index]) |sample| {
                    if (!std.math.isFinite(sample) or
                        !std.math.isFinite(sample * gain))
                        return error.AudioBlockNonFiniteValue;
                }
            }
            for (0..self.channel_count) |channel_index| {
                for (self.channels[channel_index]) |*sample|
                    sample.* *= gain;
            }
        }

        pub fn copyFrom(
            self: *Self,
            source: ConstAudioBlock(Sample, maximum_channels),
        ) !void {
            if (self.channel_count != source.channel_count or
                self.frame_count != source.frame_count)
                return error.AudioBlockShapeMismatch;
            for (0..self.channel_count) |index|
                @memcpy(self.channels[index], source.channels[index]);
        }

        pub fn addFrom(
            self: *Self,
            source: ConstAudioBlock(Sample, maximum_channels),
        ) !void {
            try self.addScaled(source, 1.0);
        }

        pub fn addScaled(
            self: *Self,
            source: ConstAudioBlock(Sample, maximum_channels),
            gain: Sample,
        ) !void {
            try validateMatchingShape(self, source);
            if (!std.math.isFinite(gain))
                return error.AudioBlockNonFiniteValue;
            for (0..self.channel_count) |channel_index| {
                for (
                    self.channels[channel_index],
                    source.channels[channel_index],
                ) |destination_sample, source_sample| {
                    const result = destination_sample + source_sample * gain;
                    if (!std.math.isFinite(destination_sample) or
                        !std.math.isFinite(source_sample) or
                        !std.math.isFinite(result))
                        return error.AudioBlockNonFiniteValue;
                }
            }
            for (0..self.channel_count) |channel_index| {
                for (
                    self.channels[channel_index],
                    source.channels[channel_index],
                ) |*destination_sample, source_sample|
                    destination_sample.* += source_sample * gain;
            }
        }

        pub fn subtractFrom(
            self: *Self,
            source: ConstAudioBlock(Sample, maximum_channels),
        ) !void {
            try self.addScaled(source, -1.0);
        }

        pub fn replaceWithSum(
            self: *Self,
            left: ConstAudioBlock(Sample, maximum_channels),
            right: ConstAudioBlock(Sample, maximum_channels),
        ) !void {
            try self.replaceWithBinary(left, right, .sum);
        }

        pub fn replaceWithProduct(
            self: *Self,
            left: ConstAudioBlock(Sample, maximum_channels),
            right: ConstAudioBlock(Sample, maximum_channels),
        ) !void {
            try self.replaceWithBinary(left, right, .product);
        }

        fn replaceWithBinary(
            self: *Self,
            left: ConstAudioBlock(Sample, maximum_channels),
            right: ConstAudioBlock(Sample, maximum_channels),
            operation: BinaryOperation,
        ) !void {
            try validateMatchingShape(self, left);
            try validateMatchingShape(self, right);
            for (0..self.channel_count) |channel_index| {
                for (
                    left.channels[channel_index],
                    right.channels[channel_index],
                ) |left_sample, right_sample| {
                    const result = switch (operation) {
                        .sum => left_sample + right_sample,
                        .product => left_sample * right_sample,
                    };
                    if (!std.math.isFinite(left_sample) or
                        !std.math.isFinite(right_sample) or
                        !std.math.isFinite(result))
                        return error.AudioBlockNonFiniteValue;
                }
            }
            for (0..self.channel_count) |channel_index| {
                for (
                    self.channels[channel_index],
                    left.channels[channel_index],
                    right.channels[channel_index],
                ) |*destination_sample, left_sample, right_sample| {
                    destination_sample.* = switch (operation) {
                        .sum => left_sample + right_sample,
                        .product => left_sample * right_sample,
                    };
                }
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.channel_count == 0 or
                self.channel_count > maximum_channels)
                return false;
            for (0..self.channel_count) |index| {
                if (self.channels[index].len != self.frame_count) return false;
            }
            return true;
        }
    };
}

const BinaryOperation = enum { sum, product };

fn validateMatchingShape(destination: anytype, source: anytype) !void {
    if (destination.channel_count != source.channel_count or
        destination.frame_count != source.frame_count)
        return error.AudioBlockShapeMismatch;
}

pub fn ConstAudioBlock(
    comptime Sample: type,
    comptime maximum_channels: usize,
) type {
    validateType(Sample, maximum_channels);

    return struct {
        const Self = @This();

        channels: [maximum_channels][]const Sample,
        channel_count: usize,
        frame_count: usize,

        /// The channel slices and their sample storage must outlive the block.
        pub fn init(source: []const []const Sample) !Self {
            const frame_count = try validateShape(
                Sample,
                maximum_channels,
                source,
            );
            var channels: [maximum_channels][]const Sample = undefined;
            for (source, 0..) |channel_samples, index|
                channels[index] = channel_samples;
            return .{
                .channels = channels,
                .channel_count = source.len,
                .frame_count = frame_count,
            };
        }

        pub fn channel(self: *const Self, index: usize) ![]const Sample {
            if (index >= self.channel_count) return error.AudioBlockChannelOutOfRange;
            return self.channels[index];
        }

        pub fn subBlock(self: *const Self, offset: usize, count: usize) !Self {
            if (offset > self.frame_count or count > self.frame_count - offset)
                return error.AudioBlockFrameRangeOutOfBounds;
            var channels: [maximum_channels][]const Sample = undefined;
            for (0..self.channel_count) |index|
                channels[index] = self.channels[index][offset..][0..count];
            return .{
                .channels = channels,
                .channel_count = self.channel_count,
                .frame_count = count,
            };
        }

        pub fn minimum(self: *const Self) !Sample {
            if (self.frame_count == 0) return error.AudioBlockRequiresFrames;
            var result = std.math.floatMax(Sample);
            for (0..self.channel_count) |channel_index| {
                for (self.channels[channel_index]) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.AudioBlockNonFiniteValue;
                    result = @min(result, sample);
                }
            }
            return result;
        }

        pub fn maximum(self: *const Self) !Sample {
            if (self.frame_count == 0) return error.AudioBlockRequiresFrames;
            var result = -std.math.floatMax(Sample);
            for (0..self.channel_count) |channel_index| {
                for (self.channels[channel_index]) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.AudioBlockNonFiniteValue;
                    result = @max(result, sample);
                }
            }
            return result;
        }

        pub fn peakMagnitude(self: *const Self) !Sample {
            var result: Sample = 0.0;
            for (0..self.channel_count) |channel_index| {
                for (self.channels[channel_index]) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.AudioBlockNonFiniteValue;
                    result = @max(result, @abs(sample));
                }
            }
            return result;
        }

        pub fn sumSquares(self: *const Self) !Sample {
            var result: Sample = 0.0;
            for (0..self.channel_count) |channel_index| {
                for (self.channels[channel_index]) |sample| {
                    const square = sample * sample;
                    if (!std.math.isFinite(sample) or
                        !std.math.isFinite(square) or
                        !std.math.isFinite(result + square))
                        return error.AudioBlockNonFiniteValue;
                    result += square;
                }
            }
            return result;
        }

        pub fn valid(self: *const Self) bool {
            if (self.channel_count == 0 or
                self.channel_count > maximum_channels)
                return false;
            for (0..self.channel_count) |index| {
                if (self.channels[index].len != self.frame_count) return false;
            }
            return true;
        }
    };
}

fn validateType(comptime Sample: type, comptime maximum_channels: usize) void {
    if (Sample != f32 and Sample != f64)
        @compileError("audio blocks support f32 and f64 samples");
    if (maximum_channels == 0)
        @compileError("audio blocks require at least one channel");
}

fn validateShape(
    comptime Sample: type,
    comptime maximum_channels: usize,
    source: anytype,
) !usize {
    _ = Sample;
    if (source.len == 0) return error.AudioBlockRequiresChannels;
    if (source.len > maximum_channels) return error.AudioBlockTooManyChannels;
    const frame_count = source[0].len;
    for (source[1..]) |channel_samples| {
        if (channel_samples.len != frame_count)
            return error.AudioBlockChannelLengthMismatch;
    }
    return frame_count;
}

test "audio block views share bounded channel storage" {
    var left = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    var right = [_]f32{ 5.0, 6.0, 7.0, 8.0 };
    var block = try AudioBlock(f32, 2).init(&.{ left[0..], right[0..] });
    var middle = try block.subBlock(1, 2);
    try middle.multiply(0.5);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1.0, 1.0, 1.5, 4.0 },
        &left,
    );
    var right_only = try block.subsetChannels(1, 1);
    right_only.clear();
    try std.testing.expectEqualSlices(f32, &.{ 0.0, 0.0, 0.0, 0.0 }, &right);
}

test "audio blocks copy matching const views" {
    const source_left = [_]f64{ 0.25, 0.5 };
    const source_right = [_]f64{ 0.75, 1.0 };
    var destination_left = [_]f64{ 0.0, 0.0 };
    var destination_right = [_]f64{ 0.0, 0.0 };
    const source = try ConstAudioBlock(f64, 2).init(
        &.{ source_left[0..], source_right[0..] },
    );
    var destination = try AudioBlock(f64, 2).init(
        &.{ destination_left[0..], destination_right[0..] },
    );
    try destination.copyFrom(source);
    try std.testing.expectEqualSlices(f64, &source_left, &destination_left);
    try std.testing.expectEqualSlices(f64, &source_right, &destination_right);
    try std.testing.expect(destination.valid());
}

test "audio block construction and ranges reject invalid shapes" {
    var short = [_]f32{1.0};
    var long = [_]f32{ 1.0, 2.0 };
    try std.testing.expectError(
        error.AudioBlockChannelLengthMismatch,
        AudioBlock(f32, 2).init(&.{ short[0..], long[0..] }),
    );
    var block = try AudioBlock(f32, 2).init(&.{long[0..]});
    try std.testing.expectError(
        error.AudioBlockFrameRangeOutOfBounds,
        block.subBlock(1, 2),
    );
    try std.testing.expectError(
        error.AudioBlockChannelOutOfRange,
        block.channel(1),
    );
}

test "audio block arithmetic processes matching multichannel views" {
    var destination_left = [_]f32{ 1.0, 2.0 };
    var destination_right = [_]f32{ 3.0, 4.0 };
    const source_left = [_]f32{ 0.5, 1.0 };
    const source_right = [_]f32{ 1.5, 2.0 };
    const source = try ConstAudioBlock(f32, 2).init(
        &.{ source_left[0..], source_right[0..] },
    );
    var destination = try AudioBlock(f32, 2).init(
        &.{ destination_left[0..], destination_right[0..] },
    );
    try destination.addScaled(source, 2.0);
    try std.testing.expectEqualSlices(f32, &.{ 2.0, 4.0 }, &destination_left);
    try std.testing.expectEqualSlices(f32, &.{ 6.0, 8.0 }, &destination_right);

    const factors_left = [_]f32{ 2.0, 3.0 };
    const factors_right = [_]f32{ 4.0, 5.0 };
    const factors = try ConstAudioBlock(f32, 2).init(
        &.{ factors_left[0..], factors_right[0..] },
    );
    try destination.replaceWithProduct(source, factors);
    try std.testing.expectEqualSlices(f32, &.{ 1.0, 3.0 }, &destination_left);
    try std.testing.expectEqualSlices(f32, &.{ 6.0, 10.0 }, &destination_right);
    try destination.replaceWithSum(source, factors);
    try destination.subtractFrom(source);
    try std.testing.expectEqualSlices(f32, &factors_left, &destination_left);
    try std.testing.expectEqualSlices(f32, &factors_right, &destination_right);
}

test "audio block arithmetic rejects overflow transactionally" {
    var destination_samples = [_]f64{ 1.0, 2.0 };
    const source_samples = [_]f64{ 1.0, std.math.floatMax(f64) };
    const source = try ConstAudioBlock(f64, 1).init(&.{source_samples[0..]});
    var destination = try AudioBlock(f64, 1).init(
        &.{destination_samples[0..]},
    );
    const before = destination_samples;
    try std.testing.expectError(
        error.AudioBlockNonFiniteValue,
        destination.addScaled(source, 2.0),
    );
    try std.testing.expectEqualSlices(f64, &before, &destination_samples);
    try std.testing.expectError(
        error.AudioBlockNonFiniteValue,
        destination.multiply(std.math.floatMax(f64)),
    );
    try std.testing.expectEqualSlices(f64, &before, &destination_samples);
}

test "const audio block reports bounded aggregate values" {
    const left = [_]f64{ -0.5, 0.25 };
    const right = [_]f64{ 1.0, -0.75 };
    const block = try ConstAudioBlock(f64, 2).init(
        &.{ left[0..], right[0..] },
    );
    try std.testing.expectEqual(@as(f64, -0.75), try block.minimum());
    try std.testing.expectEqual(@as(f64, 1.0), try block.maximum());
    try std.testing.expectEqual(@as(f64, 1.0), try block.peakMagnitude());
    try std.testing.expectEqual(@as(f64, 1.875), try block.sumSquares());

    const empty = [_]f64{};
    const empty_block = try ConstAudioBlock(f64, 1).init(&.{empty[0..]});
    try std.testing.expectError(
        error.AudioBlockRequiresFrames,
        empty_block.minimum(),
    );
    try std.testing.expectEqual(@as(f64, 0.0), try empty_block.sumSquares());
}
