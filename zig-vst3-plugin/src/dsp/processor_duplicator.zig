const std = @import("std");
const buffer_regions = @import("buffer_regions.zig");

pub fn ProcessorDuplicator(
    comptime Sample: type,
    comptime Processor: type,
    comptime maximum_channels: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("ProcessorDuplicator supports f32 and f64 samples");
    if (maximum_channels == 0)
        @compileError("ProcessorDuplicator channel capacity must be nonzero");

    return struct {
        const Self = @This();

        processors: [maximum_channels]Processor,
        channel_count: usize,

        pub fn init(prototype: Processor, channel_count: usize) !Self {
            try validateChannelCount(channel_count);
            return .{
                .processors = @splat(prototype),
                .channel_count = channel_count,
            };
        }

        pub fn setChannelCount(self: *Self, channel_count: usize) !void {
            try validateChannelCount(channel_count);
            if (@hasDecl(Processor, "valid")) {
                for (self.processors[0..channel_count]) |processor| {
                    if (!processor.valid())
                        return error.InvalidProcessorDuplicatorProcessorState;
                }
            }
            self.channel_count = channel_count;
        }

        pub fn get(self: *Self, channel: usize) !*Processor {
            if (self.channel_count == 0 or
                self.channel_count > maximum_channels or
                channel >= self.channel_count or
                channel >= maximum_channels)
                return error.ProcessorDuplicatorChannelOutOfRange;
            return &self.processors[channel];
        }

        pub fn processSample(
            self: *Self,
            channel: usize,
            input: Sample,
        ) !Sample {
            const processor = try self.get(channel);
            const accepted = if (std.math.isFinite(input)) input else 0.0;
            const output = processor.processSample(accepted);
            return if (std.math.isFinite(output)) output else 0.0;
        }

        pub fn processChannel(
            self: *Self,
            channel: usize,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len)
                return error.ProcessorDuplicatorBufferLengthMismatch;
            if (!buffer_regions.exactOrDisjoint(Sample, input, output))
                return error.ProcessorDuplicatorBufferOverlap;
            _ = try self.get(channel);
            for (input, output) |input_sample, *output_sample|
                output_sample.* = try self.processSample(channel, input_sample);
        }

        pub fn valid(self: *const Self) bool {
            validateChannelCount(self.channel_count) catch return false;
            if (@hasDecl(Processor, "valid")) {
                for (self.processors[0..self.channel_count]) |processor| {
                    if (!processor.valid()) return false;
                }
            }
            return true;
        }

        fn validateChannelCount(channel_count: usize) !void {
            if (channel_count == 0 or channel_count > maximum_channels)
                return error.InvalidProcessorDuplicatorChannelCount;
        }
    };
}

const Scale = struct {
    gain: f32,

    fn processSample(self: *Scale, input: f32) f32 {
        return input * self.gain;
    }

    fn valid(self: *const Scale) bool {
        return std.math.isFinite(self.gain);
    }
};

test "processor duplicator gives every channel independent state" {
    const Duplicator = ProcessorDuplicator(f32, Scale, 4);
    var duplicator = try Duplicator.init(.{ .gain = 1.0 }, 2);
    (try duplicator.get(0)).gain = 0.5;
    (try duplicator.get(1)).gain = 2.0;
    try std.testing.expectEqual(
        @as(f32, 0.5),
        try duplicator.processSample(0, 1.0),
    );
    try std.testing.expectEqual(
        @as(f32, 2.0),
        try duplicator.processSample(1, 1.0),
    );
}

test "processor duplicator processes bounded channel blocks" {
    const Duplicator = ProcessorDuplicator(f32, Scale, 4);
    var duplicator = try Duplicator.init(.{ .gain = 0.25 }, 2);
    var output: [3]f32 = undefined;
    try duplicator.processChannel(1, &.{ 0.0, 2.0, 4.0 }, &output);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.5, 1.0 },
        &output,
    );
}

test "processor duplicator rejects bounds and reports invalid members" {
    const Duplicator = ProcessorDuplicator(f32, Scale, 2);
    try std.testing.expectError(
        error.InvalidProcessorDuplicatorChannelCount,
        Duplicator.init(.{ .gain = 1.0 }, 3),
    );
    var duplicator = try Duplicator.init(.{ .gain = 1.0 }, 2);
    try std.testing.expectError(
        error.ProcessorDuplicatorChannelOutOfRange,
        duplicator.processSample(2, 1.0),
    );
    duplicator.processors[0].gain = std.math.nan(f32);
    try std.testing.expect(!duplicator.valid());
    try std.testing.expectEqual(
        @as(f32, 0.0),
        try duplicator.processSample(0, 1.0),
    );
    duplicator.channel_count = 100;
    try std.testing.expectError(
        error.ProcessorDuplicatorChannelOutOfRange,
        duplicator.processSample(0, 1.0),
    );
}

test "processor duplicator permits in-place buffers and rejects shifted overlap" {
    const Duplicator = ProcessorDuplicator(f32, Scale, 2);
    var duplicator = try Duplicator.init(.{ .gain = 0.5 }, 1);
    var storage = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const retained = storage;
    const duplicator_before = duplicator;
    try std.testing.expectError(
        error.ProcessorDuplicatorBufferOverlap,
        duplicator.processChannel(0, storage[0..3], storage[1..4]),
    );
    try std.testing.expectEqualDeep(duplicator_before, duplicator);
    try std.testing.expectEqualSlices(f32, &retained, &storage);

    try duplicator.processChannel(0, &storage, &storage);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, 1.0, 1.5, 2.0 },
        &storage,
    );
}
