const std = @import("std");
const plug = @import("zig-vst3-plugin");

pub const MonoGain = struct {
    pub const name = "zig-vst3 Mono Gain";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .mono;
    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 2.0,
            .default = 1.0,
        },
    };

    pub fn processWithParameterView(_: *MonoGain, context: *plug.process.ProcessContext(f32), parameters: plug.parameters.ParameterView(Params)) void {
        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        const gain: f32 = @floatCast(parameters.load("gain"));
        for (input, output) |sample, *destination| destination.* = sample * gain;
    }
};

pub const Spec = plug.plugin.PluginSpec(MonoGain);
pub const Instance = plug.plugin.PluginInstance(MonoGain);

test "mono gain declares and processes one audio channel" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);

    try std.testing.expectEqual(plug.plugin.AudioBusLayout.mono, Spec.audio_input_layout);
    try std.testing.expectEqual(@as(u8, 1), instance.audioInputChannelCount());
    try std.testing.expectEqual(@as(u8, 1), instance.audioOutputChannelCount());
    instance.process(&context);
    try std.testing.expectEqualSlices(f32, &input, &output);
}
