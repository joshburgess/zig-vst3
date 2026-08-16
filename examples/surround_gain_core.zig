const std = @import("std");
const plug = @import("zig-vst3-plugin");

pub const SurroundGain = struct {
    pub const name = "zig-vst3 Surround Gain";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .surround_5_1;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .surround_5_1;
    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 2.0,
            .default = 1.0,
        },
    };

    fn processBlock(
        comptime Sample: type,
        context: *plug.process.ProcessContext(Sample),
        parameters: plug.parameters.ParameterView(Params),
    ) void {
        const gain: Sample = @floatCast(parameters.load("gain"));
        for (0..context.outputChannelCount()) |channel_index| {
            const input = context.inputChannel(channel_index) orelse continue;
            const output = context.outputChannel(channel_index) orelse continue;
            for (input, output) |sample, *destination| destination.* = sample * gain;
        }
    }

    pub fn processWithParameterView(
        _: *@This(),
        context: *plug.process.ProcessContext(f32),
        parameters: plug.parameters.ParameterView(Params),
    ) void {
        processBlock(f32, context, parameters);
    }

    pub fn process64WithParameterView(
        _: *@This(),
        context: *plug.process.ProcessContext(f64),
        parameters: plug.parameters.ParameterView(Params),
    ) void {
        processBlock(f64, context, parameters);
    }
};

pub const Spec = plug.plugin.PluginSpec(SurroundGain);
pub const Instance = plug.plugin.PluginInstance(SurroundGain);

test "surround gain declares and processes six audio channels" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_][2]f32{
        .{ 0.0, 0.5 },
        .{ 1.0, 1.5 },
        .{ 2.0, 2.5 },
        .{ 3.0, 3.5 },
        .{ 4.0, 4.5 },
        .{ 5.0, 5.5 },
    };
    var output = [_][2]f32{.{ 0.0, 0.0 }} ** 6;
    var input_channels: [6][]const f32 = undefined;
    var output_channels: [6][]f32 = undefined;
    for (&input, &input_channels) |*samples, *channel| channel.* = samples;
    for (&output, &output_channels) |*samples, *channel| channel.* = samples;
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);

    try std.testing.expectEqual(plug.plugin.AudioBusLayout.surround_5_1, Spec.audio_input_layout);
    try std.testing.expectEqual(@as(u8, 6), instance.audioInputChannelCount());
    try std.testing.expectEqual(@as(u8, 6), instance.audioOutputChannelCount());
    instance.process(&context);
    try std.testing.expectEqual(input, output);
}
