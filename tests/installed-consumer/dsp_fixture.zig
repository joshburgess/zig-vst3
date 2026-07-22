const plugin = @import("zig-vst3-plugin");
const std = @import("std");

const GainModel = struct {
    gain: f32,

    pub fn reset(_: *GainModel) void {}

    pub fn processBlock(self: *GainModel, input: []const f32, output: []f32) void {
        for (input, output) |sample, *destination| destination.* = sample * self.gain;
    }
};

test "installed package exposes DSP fixture rendering and comparison" {
    const input = [_]f32{ -1.0, -0.5, 0.0, 0.5, 1.0 };
    const expected = [_]f32{ -0.25, -0.125, 0.0, 0.125, 0.25 };
    var output: [input.len]f32 = undefined;
    var model = GainModel{ .gain = 0.25 };
    const processor = plugin.dsp.BlockProcessor(f32).init(GainModel, &model);

    try plugin.dsp.fixture_runner.renderFixed(f32, processor, &input, &output, 2);
    const comparison = try plugin.dsp.fixture_runner.compare(f32, &expected, &output, .{
        .maximum_absolute = 0.0,
        .maximum_relative = 0.0,
        .maximum_rms = 0.0,
    });
    try std.testing.expect(comparison.passed);
}
