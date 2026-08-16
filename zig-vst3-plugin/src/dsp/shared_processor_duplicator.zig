const std = @import("std");
const buffer_regions = @import("buffer_regions.zig");

/// Share caller-owned immutable state across independent channel processors.
pub fn SharedProcessorDuplicator(
    comptime Sample: type,
    comptime State: type,
    comptime Processor: type,
    comptime maximum_channels: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "SharedProcessorDuplicator supports f32 and f64 samples",
        );
    if (maximum_channels == 0)
        @compileError(
            "SharedProcessorDuplicator channel capacity must be nonzero",
        );

    return struct {
        const Self = @This();

        state: *const State,
        processors: [maximum_channels]Processor,
        channel_count: usize,

        /// The state pointer must remain valid until it is replaced or the duplicator is discarded.
        pub fn init(
            state: *const State,
            prototype: Processor,
            channel_count: usize,
        ) !Self {
            try validateChannelCount(channel_count);
            try validateState(state);
            return .{
                .state = state,
                .processors = @splat(prototype),
                .channel_count = channel_count,
            };
        }

        pub fn setState(self: *Self, state: *const State) !void {
            try validateState(state);
            self.state = state;
        }

        pub fn get(self: *Self, channel: usize) !*Processor {
            if (!self.validShape() or channel >= self.channel_count)
                return error.SharedProcessorChannelOutOfRange;
            return &self.processors[channel];
        }

        pub fn processSample(
            self: *Self,
            channel: usize,
            input: Sample,
        ) !Sample {
            const processor = try self.get(channel);
            if (!stateValid(self.state))
                return error.InvalidSharedProcessorState;
            const accepted = if (std.math.isFinite(input)) input else 0.0;
            const output = processor.processSample(accepted, self.state);
            return if (std.math.isFinite(output)) output else 0.0;
        }

        pub fn processChannel(
            self: *Self,
            channel: usize,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len)
                return error.SharedProcessorBufferLengthMismatch;
            if (!buffer_regions.exactOrDisjoint(Sample, input, output))
                return error.SharedProcessorBufferOverlap;
            _ = try self.get(channel);
            if (!stateValid(self.state))
                return error.InvalidSharedProcessorState;
            for (input, output) |input_sample, *output_sample|
                output_sample.* = try self.processSample(
                    channel,
                    input_sample,
                );
        }

        pub fn valid(self: *const Self) bool {
            if (!self.validShape() or !stateValid(self.state))
                return false;
            if (@hasDecl(Processor, "valid")) {
                for (self.processors[0..self.channel_count]) |processor| {
                    if (!processor.valid()) return false;
                }
            }
            return true;
        }

        fn validShape(self: *const Self) bool {
            return self.channel_count > 0 and
                self.channel_count <= maximum_channels;
        }

        fn validateChannelCount(channel_count: usize) !void {
            if (channel_count == 0 or channel_count > maximum_channels)
                return error.InvalidSharedProcessorChannelCount;
        }

        fn validateState(state: *const State) !void {
            if (!stateValid(state))
                return error.InvalidSharedProcessorState;
        }

        fn stateValid(state: *const State) bool {
            if (@hasDecl(State, "valid")) return state.valid();
            return true;
        }
    };
}

const SharedGain = struct {
    gain: f32,

    fn valid(self: *const SharedGain) bool {
        return std.math.isFinite(self.gain);
    }
};

const StatefulScale = struct {
    previous: f32 = 0.0,

    fn processSample(
        self: *StatefulScale,
        input: f32,
        state: *const SharedGain,
    ) f32 {
        const output = (input + self.previous) * state.gain;
        self.previous = input;
        return output;
    }

    fn valid(self: *const StatefulScale) bool {
        return std.math.isFinite(self.previous);
    }
};

test "shared processor state updates every independent channel" {
    const Duplicator = SharedProcessorDuplicator(
        f32,
        SharedGain,
        StatefulScale,
        4,
    );
    var unity = SharedGain{ .gain = 1.0 };
    var duplicator = try Duplicator.init(&unity, .{}, 2);
    try std.testing.expectEqual(
        @as(f32, 1.0),
        try duplicator.processSample(0, 1.0),
    );
    try std.testing.expectEqual(
        @as(f32, 2.0),
        try duplicator.processSample(1, 2.0),
    );

    var half = SharedGain{ .gain = 0.5 };
    try duplicator.setState(&half);
    try std.testing.expectEqual(
        @as(f32, 1.5),
        try duplicator.processSample(0, 2.0),
    );
    try std.testing.expectEqual(
        @as(f32, 2.5),
        try duplicator.processSample(1, 3.0),
    );
}

test "shared processor blocks retain per-channel histories" {
    const Duplicator = SharedProcessorDuplicator(
        f32,
        SharedGain,
        StatefulScale,
        2,
    );
    var state = SharedGain{ .gain = 0.25 };
    var duplicator = try Duplicator.init(&state, .{}, 2);
    var left: [3]f32 = undefined;
    var right: [3]f32 = undefined;
    try duplicator.processChannel(0, &.{ 1.0, 2.0, 3.0 }, &left);
    try duplicator.processChannel(1, &.{ 4.0, 5.0, 6.0 }, &right);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.25, 0.75, 1.25 },
        &left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1.0, 2.25, 2.75 },
        &right,
    );
}

test "shared processor state and bounds fail transactionally" {
    const Duplicator = SharedProcessorDuplicator(
        f32,
        SharedGain,
        StatefulScale,
        2,
    );
    var valid_state = SharedGain{ .gain = 1.0 };
    var duplicator = try Duplicator.init(&valid_state, .{}, 2);
    var invalid_state = SharedGain{ .gain = std.math.nan(f32) };
    try std.testing.expectError(
        error.InvalidSharedProcessorState,
        duplicator.setState(&invalid_state),
    );
    try std.testing.expectEqual(&valid_state, duplicator.state);
    try std.testing.expectError(
        error.SharedProcessorChannelOutOfRange,
        duplicator.processSample(2, 1.0),
    );
    try std.testing.expect(duplicator.valid());
}

test "shared processor permits in-place buffers and rejects shifted overlap" {
    const Duplicator = SharedProcessorDuplicator(
        f32,
        SharedGain,
        StatefulScale,
        2,
    );
    var state = SharedGain{ .gain = 0.5 };
    var duplicator = try Duplicator.init(&state, .{}, 1);
    var storage = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const retained = storage;
    const duplicator_before = duplicator;
    try std.testing.expectError(
        error.SharedProcessorBufferOverlap,
        duplicator.processChannel(0, storage[0..3], storage[1..4]),
    );
    try std.testing.expectEqualDeep(duplicator_before, duplicator);
    try std.testing.expectEqualSlices(f32, &retained, &storage);

    try duplicator.processChannel(0, &storage, &storage);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, 1.5, 2.5, 3.5 },
        &storage,
    );
}
