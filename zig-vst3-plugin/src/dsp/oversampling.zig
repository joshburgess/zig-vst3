const std = @import("std");
const fir = @import("fir.zig");
const fir_design = @import("fir_design.zig");

pub const Selection = enum {
    dummy,
    filtered,
};

pub fn DummyOversampler(
    comptime Sample: type,
    comptime maximum_frames: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("oversampling supports f32 and f64 samples");
    if (maximum_frames == 0)
        @compileError("oversampling frame capacity must be nonzero");

    return struct {
        const Self = @This();

        pub const oversampling_factor = 1;
        pub const latency_samples = 0;

        high_rate: [maximum_frames]Sample = undefined,
        pending_frames: usize = 0,

        pub fn init() Self {
            return .{};
        }

        pub fn reset(self: *Self) void {
            self.pending_frames = 0;
        }

        pub fn upsample(self: *Self, input: []const Sample) ![]Sample {
            if (!self.valid()) return error.InvalidOversamplerState;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            if (input.len == 0) return self.high_rate[0..0];
            if (input.len > maximum_frames)
                return error.OversamplingCapacityExceeded;
            for (input) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFiniteOversamplingInput;
            }
            @memcpy(self.high_rate[0..input.len], input);
            self.pending_frames = input.len;
            return self.high_rate[0..input.len];
        }

        pub fn downsample(self: *Self, output: []Sample) !void {
            if (!self.valid()) return error.InvalidOversamplerState;
            if (self.pending_frames == 0)
                return error.NoOversampledBlock;
            if (output.len != self.pending_frames)
                return error.OversamplingFrameMismatch;
            for (self.high_rate[0..self.pending_frames]) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFiniteOversamplingInput;
            }
            @memcpy(output, self.high_rate[0..self.pending_frames]);
            self.pending_frames = 0;
        }

        pub fn valid(self: *const Self) bool {
            return self.pending_frames <= maximum_frames;
        }
    };
}

pub fn SelectableOversampler(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime factor: usize,
) type {
    const Dummy = DummyOversampler(Sample, maximum_frames);
    const Filtered = Oversampler(Sample, maximum_frames, factor);

    return struct {
        const Self = @This();

        selection: Selection,
        dummy: Dummy = Dummy.init(),
        filtered: Filtered,

        pub fn init(selection: Selection) !Self {
            return .{
                .selection = selection,
                .filtered = try Filtered.init(),
            };
        }

        pub fn reset(self: *Self) void {
            self.dummy.reset();
            self.filtered.reset();
        }

        pub fn setSelection(
            self: *Self,
            selection: Selection,
        ) !void {
            if (self.pending())
                return error.OversampledBlockPending;
            self.selection = selection;
            self.reset();
        }

        pub fn oversamplingFactor(self: *const Self) usize {
            return switch (self.selection) {
                .dummy => 1,
                .filtered => factor,
            };
        }

        pub fn latencySamples(self: *const Self) usize {
            return switch (self.selection) {
                .dummy => 0,
                .filtered => Filtered.latency_samples,
            };
        }

        pub fn upsample(
            self: *Self,
            input: []const Sample,
        ) ![]Sample {
            return switch (self.selection) {
                .dummy => self.dummy.upsample(input),
                .filtered => self.filtered.upsample(input),
            };
        }

        pub fn downsample(
            self: *Self,
            output: []Sample,
        ) !void {
            switch (self.selection) {
                .dummy => try self.dummy.downsample(output),
                .filtered => try self.filtered.downsample(output),
            }
        }

        pub fn valid(self: *const Self) bool {
            return self.dummy.valid() and self.filtered.valid() and
                !(self.dummy.pending_frames != 0 and
                    self.filtered.pending_frames != 0);
        }

        fn pending(self: *const Self) bool {
            return self.dummy.pending_frames != 0 or
                self.filtered.pending_frames != 0;
        }
    };
}

pub fn Oversampler(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime factor: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("oversampling supports f32 and f64 samples");
    if (maximum_frames == 0)
        @compileError("oversampling frame capacity must be nonzero");
    if (factor != 2 and factor != 4 and factor != 8 and factor != 16)
        @compileError("oversampling factor must be 2, 4, 8, or 16");

    const tap_count = factor * 8 + 1;
    const Filter = fir.FirFilter(Sample, tap_count);
    const Designer = fir_design.Designer(Sample);

    return struct {
        const Self = @This();

        pub const oversampling_factor = factor;
        pub const latency_samples = 8;
        pub const filter_tap_count = tap_count;

        up_filter: Filter,
        down_filter: Filter,
        high_rate: [maximum_frames * factor]Sample = undefined,
        pending_frames: usize = 0,

        pub fn init() !Self {
            var coefficients: [tap_count]Sample = undefined;
            try Designer.lowPass(
                &coefficients,
                0.475 / @as(Sample, @floatFromInt(factor)),
                .blackman_harris,
            );
            return .{
                .up_filter = try Filter.init(&coefficients),
                .down_filter = try Filter.init(&coefficients),
            };
        }

        pub fn reset(self: *Self) void {
            self.up_filter.reset();
            self.down_filter.reset();
            self.pending_frames = 0;
        }

        pub fn upsample(self: *Self, input: []const Sample) ![]Sample {
            if (!self.valid()) return error.InvalidOversamplerState;
            if (self.pending_frames != 0) return error.OversampledBlockPending;
            if (input.len == 0) return self.high_rate[0..0];
            if (input.len > maximum_frames)
                return error.OversamplingCapacityExceeded;
            for (input) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFiniteOversamplingInput;
            }

            for (input, 0..) |sample, frame| {
                const first = frame * factor;
                self.high_rate[first] =
                    self.up_filter.processSample(sample) *
                    @as(Sample, @floatFromInt(factor));
                for (1..factor) |phase| {
                    self.high_rate[first + phase] =
                        self.up_filter.processSample(0.0) *
                        @as(Sample, @floatFromInt(factor));
                }
            }
            self.pending_frames = input.len;
            return self.high_rate[0 .. input.len * factor];
        }

        pub fn downsample(self: *Self, output: []Sample) !void {
            if (!self.valid()) return error.InvalidOversamplerState;
            if (self.pending_frames == 0) return error.NoOversampledBlock;
            if (output.len != self.pending_frames)
                return error.OversamplingFrameMismatch;

            for (self.high_rate[0 .. self.pending_frames * factor], 0..) |
                sample,
                index,
            | {
                const filtered = self.down_filter.processSample(sample);
                if (index % factor == 0)
                    output[index / factor] = filtered;
            }
            self.pending_frames = 0;
        }

        pub fn valid(self: *const Self) bool {
            return self.pending_frames <= maximum_frames and
                self.up_filter.valid() and
                self.down_filter.valid();
        }
    };
}

test "dummy oversampler preserves samples and mutable processing" {
    const Processor = DummyOversampler(f32, 4);
    var processor = Processor.init();
    const input = [_]f32{ -0.5, 0.0, 0.25, 1.0 };
    const high_rate = try processor.upsample(&input);
    try std.testing.expectEqual(@as(usize, 1), Processor.oversampling_factor);
    try std.testing.expectEqual(@as(usize, 0), Processor.latency_samples);
    for (high_rate) |*sample| sample.* *= 0.5;
    var output: [4]f32 = undefined;
    try processor.downsample(&output);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ -0.25, 0.0, 0.125, 0.5 },
        &output,
    );
}

test "selectable oversampler switches only between complete blocks" {
    const Processor = SelectableOversampler(f64, 16, 4);
    var processor = try Processor.init(.dummy);
    try std.testing.expectEqual(
        @as(usize, 1),
        processor.oversamplingFactor(),
    );
    const input: [16]f64 = @splat(0.25);
    _ = try processor.upsample(&input);
    try std.testing.expectError(
        error.OversampledBlockPending,
        processor.setSelection(.filtered),
    );
    var output: [16]f64 = undefined;
    try processor.downsample(&output);
    try processor.setSelection(.filtered);
    try std.testing.expectEqual(
        @as(usize, 4),
        processor.oversamplingFactor(),
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        processor.latencySamples(),
    );
    const high_rate = try processor.upsample(&input);
    try std.testing.expectEqual(@as(usize, 64), high_rate.len);
    try processor.downsample(&output);
    try std.testing.expect(processor.valid());
}

test "oversampler has bounded round-trip latency and block continuity" {
    const Processor = Oversampler(f64, 64, 4);
    var oversampler = try Processor.init();
    var impulse: [64]f64 = @splat(0.0);
    impulse[0] = 1.0;
    const high_rate = try oversampler.upsample(&impulse);
    try std.testing.expectEqual(@as(usize, 256), high_rate.len);
    var output: [64]f64 = undefined;
    try oversampler.downsample(&output);

    var peak_index: usize = 0;
    for (output, 0..) |sample, index| {
        if (@abs(sample) > @abs(output[peak_index]))
            peak_index = index;
    }
    try std.testing.expectEqual(
        @as(usize, Processor.latency_samples),
        peak_index,
    );

    oversampler.reset();
    var steady_input: [64]f64 = @splat(1.0);
    var steady_output: [64]f64 = undefined;
    for (0..4) |_| {
        _ = try oversampler.upsample(&steady_input);
        try oversampler.downsample(&steady_output);
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        steady_output[steady_output.len - 1],
        0.000_001,
    );
}

test "oversampler exposes mutable high-rate processing storage" {
    const Processor = Oversampler(f32, 8, 2);
    var oversampler = try Processor.init();
    var input: [8]f32 = @splat(0.25);
    var output: [8]f32 = undefined;
    for (0..8) |_| {
        const high_rate = try oversampler.upsample(&input);
        for (high_rate) |*sample| sample.* *= 2.0;
        try oversampler.downsample(&output);
    }
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        output[output.len - 1],
        0.000_01,
    );

    oversampler.reset();
    for (0..8) |_| {
        _ = try oversampler.upsample(&input);
        try oversampler.downsample(&output);
    }
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        output[output.len - 1],
        0.000_01,
    );
}

test "oversampler rejects invalid sequencing transactionally" {
    const Processor = Oversampler(f32, 4, 2);
    var oversampler = try Processor.init();
    var input = [_]f32{ 1.0, std.math.nan(f32) };
    try std.testing.expectError(
        error.NonFiniteOversamplingInput,
        oversampler.upsample(&input),
    );
    try std.testing.expectEqual(@as(usize, 0), oversampler.pending_frames);

    input[1] = 0.0;
    _ = try oversampler.upsample(&input);
    try std.testing.expectError(
        error.OversampledBlockPending,
        oversampler.upsample(&input),
    );
    var wrong_size: [1]f32 = undefined;
    try std.testing.expectError(
        error.OversamplingFrameMismatch,
        oversampler.downsample(&wrong_size),
    );
    try std.testing.expectEqual(input.len, oversampler.pending_frames);
}

test "every oversampling factor preserves latency" {
    inline for (.{ 2, 4, 8, 16 }) |current_factor| {
        const Processor = Oversampler(f32, 32, current_factor);
        var oversampler = try Processor.init();
        var input: [32]f32 = @splat(0.0);
        input[0] = 1.0;
        _ = try oversampler.upsample(&input);
        var output: [32]f32 = undefined;
        try oversampler.downsample(&output);

        var peak_index: usize = 0;
        for (output, 0..) |sample, index| {
            if (@abs(sample) > @abs(output[peak_index]))
                peak_index = index;
        }
        try std.testing.expectEqual(
            @as(usize, Processor.latency_samples),
            peak_index,
        );
    }
}

test "oversampling output is independent of block partitioning" {
    const Processor = Oversampler(f64, 64, 4);
    var input: [64]f64 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* = @sin(
            std.math.tau *
                0.03125 *
                @as(f64, @floatFromInt(index)),
        );
    }

    var whole = try Processor.init();
    _ = try whole.upsample(&input);
    var whole_output: [64]f64 = undefined;
    try whole.downsample(&whole_output);

    var partitioned = try Processor.init();
    _ = try partitioned.upsample(input[0..23]);
    var partitioned_output: [64]f64 = undefined;
    try partitioned.downsample(partitioned_output[0..23]);
    _ = try partitioned.upsample(input[23..]);
    try partitioned.downsample(partitioned_output[23..]);

    try std.testing.expectEqualSlices(
        f64,
        &whole_output,
        &partitioned_output,
    );
}
