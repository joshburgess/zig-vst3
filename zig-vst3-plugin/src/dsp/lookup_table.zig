const std = @import("std");
const buffer_regions = @import("buffer_regions.zig");

pub fn LookupTable(comptime Sample: type, comptime point_count: usize) type {
    if (Sample != f32 and Sample != f64)
        @compileError("LookupTable supports f32 and f64 samples");
    if (point_count < 2)
        @compileError("LookupTable requires at least two points");

    return struct {
        const Self = @This();

        minimum: Sample,
        maximum: Sample,
        scale: Sample,
        points: [point_count]Sample,

        pub fn init(
            minimum: Sample,
            maximum: Sample,
            function: *const fn (Sample) Sample,
        ) !Self {
            if (!std.math.isFinite(minimum) or
                !std.math.isFinite(maximum) or
                maximum <= minimum)
                return error.InvalidLookupTableRange;

            const span = maximum - minimum;
            var points: [point_count]Sample = undefined;
            const denominator: Sample = @floatFromInt(point_count - 1);
            const scale = denominator / span;
            if (!std.math.isFinite(span) or span <= 0.0 or
                !std.math.isFinite(scale) or scale <= 0.0)
                return error.InvalidLookupTableRange;
            for (&points, 0..) |*point, index| {
                const proportion =
                    @as(Sample, @floatFromInt(index)) / denominator;
                point.* = function(
                    minimum + span * proportion,
                );
                if (!std.math.isFinite(point.*))
                    return error.InvalidLookupTableValue;
            }
            return .{
                .minimum = minimum,
                .maximum = maximum,
                .scale = scale,
                .points = points,
            };
        }

        pub fn processSample(self: *const Self, input: Sample) Sample {
            if (!self.metadataValid())
                return if (std.math.isFinite(input)) input else 0.0;
            const accepted = if (std.math.isFinite(input))
                input
            else
                self.minimum;
            const clamped = std.math.clamp(
                accepted,
                self.minimum,
                self.maximum,
            );
            const position = (clamped - self.minimum) * self.scale;
            if (!std.math.isFinite(position) or position < 0.0)
                return accepted;
            const lower: usize = @intFromFloat(@floor(position));
            if (lower >= point_count - 1) {
                const endpoint = self.points[point_count - 1];
                return if (std.math.isFinite(endpoint)) endpoint else accepted;
            }
            const fraction = position - @as(Sample, @floatFromInt(lower));
            const lower_value = self.points[lower];
            const upper_value = self.points[lower + 1];
            if (!std.math.isFinite(lower_value) or
                !std.math.isFinite(upper_value))
                return accepted;
            return lower_value * (1.0 - fraction) +
                upper_value * fraction;
        }

        pub fn process(
            self: *const Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len)
                return error.LookupTableBufferLengthMismatch;
            if (!buffer_regions.exactOrDisjoint(Sample, input, output))
                return error.LookupTableBufferOverlap;
            for (input, output) |input_sample, *output_sample|
                output_sample.* = self.processSample(input_sample);
        }

        pub fn valid(self: *const Self) bool {
            if (!self.metadataValid()) return false;
            for (self.points) |point| {
                if (!std.math.isFinite(point)) return false;
            }
            return true;
        }

        fn metadataValid(self: *const Self) bool {
            if (!std.math.isFinite(self.minimum) or
                !std.math.isFinite(self.maximum) or
                self.maximum <= self.minimum)
                return false;
            const expected_scale =
                @as(Sample, @floatFromInt(point_count - 1)) /
                (self.maximum - self.minimum);
            if (!std.math.isFinite(expected_scale) or
                expected_scale <= 0.0 or
                self.scale != expected_scale)
                return false;
            return true;
        }
    };
}

fn sine(value: f64) f64 {
    return @sin(value);
}

fn square(value: f32) f32 {
    return value * value;
}

fn constantOne(_: f32) f32 {
    return 1.0;
}

test "lookup table interpolates functions and includes both endpoints" {
    const Table = LookupTable(f64, 257);
    const table = try Table.init(-std.math.pi, std.math.pi, sine);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        table.processSample(0.0),
        0.0000001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        table.processSample(std.math.pi * 0.5),
        0.0001,
    );
    try std.testing.expectApproxEqAbs(
        table.points[0],
        table.processSample(-100.0),
        0.0,
    );
    try std.testing.expectApproxEqAbs(
        table.points[256],
        table.processSample(100.0),
        0.0,
    );
}

test "lookup table block processing matches scalar processing" {
    const table = try LookupTable(f32, 33).init(-1.0, 1.0, square);
    const input = [_]f32{ -1.0, -0.4, 0.0, 0.3, 1.0 };
    var output: [input.len]f32 = undefined;
    try table.process(&input, &output);
    for (input, output) |input_sample, output_sample|
        try std.testing.expectEqual(
            table.processSample(input_sample),
            output_sample,
        );
}

test "lookup table rejects invalid construction and contains hostile state" {
    const Table = LookupTable(f32, 8);
    try std.testing.expectError(
        error.InvalidLookupTableRange,
        Table.init(1.0, 1.0, square),
    );
    try std.testing.expectError(
        error.InvalidLookupTableRange,
        Table.init(
            -std.math.floatMax(f32),
            std.math.floatMax(f32),
            constantOne,
        ),
    );
    var table = try Table.init(-1.0, 1.0, square);
    table.points[3] = std.math.nan(f32);
    try std.testing.expectEqual(@as(f32, -0.14), table.processSample(-0.14));
    try std.testing.expect(!table.valid());
    table.minimum = std.math.nan(f32);
    try std.testing.expectEqual(
        @as(f32, 0.0),
        table.processSample(std.math.nan(f32)),
    );
    table = try Table.init(-1.0, 1.0, square);
    table.scale = 0.0;
    try std.testing.expectEqual(
        @as(f32, 0.5),
        table.processSample(0.5),
    );
}

test "lookup table permits in-place buffers and rejects shifted overlap" {
    const table = try LookupTable(f32, 8).init(-1.0, 1.0, square);
    var storage = [_]f32{ -1.0, -0.5, 0.5, 1.0 };
    const before = storage;
    try std.testing.expectError(
        error.LookupTableBufferOverlap,
        table.process(storage[0..3], storage[1..4]),
    );
    try std.testing.expectEqualDeep(before, storage);

    try table.process(&storage, &storage);
    for (storage) |sample| try std.testing.expect(std.math.isFinite(sample));
}
