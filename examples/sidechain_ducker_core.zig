const std = @import("std");
const plug = @import("zig-vst3-plugin");

pub const SidechainDucker = struct {
    pub const name = "zig-vst3 Sidechain Ducker";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .stereo;
    pub const audio_sidechain_layout: plug.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .stereo;
    pub const Params = struct {
        depth: plug.parameters.FloatParam = .{
            .id = 0,
            .name = "Depth",
            .min = 0.0,
            .max = 1.0,
            .default = 1.0,
        },
    };

    pub fn processWithParameterView(_: *SidechainDucker, context: *plug.process.ProcessContext(f32), parameters: plug.parameters.ParameterView(Params)) void {
        processBlock(f32, context, @floatCast(parameters.load("depth")));
    }

    pub fn process64WithParameterView(_: *SidechainDucker, context: *plug.process.ProcessContext(f64), parameters: plug.parameters.ParameterView(Params)) void {
        processBlock(f64, context, parameters.load("depth"));
    }
};

fn processBlock(comptime Sample: type, context: *plug.process.ProcessContext(Sample), depth: Sample) void {
    const key = context.sidechainInputChannel(0);
    for (0..context.outputChannelCount()) |channel_index| {
        const input = context.inputChannel(channel_index) orelse continue;
        const output = context.outputChannel(channel_index) orelse continue;
        for (input, output, 0..) |sample, *destination, frame_index| {
            const key_level = if (key) |samples| @min(@abs(samples[frame_index]), 1) else 0;
            destination.* = sample * (1 - depth * key_level);
        }
    }
}

pub const Spec = plug.plugin.PluginSpec(SidechainDucker);
pub const Instance = plug.plugin.PluginInstance(SidechainDucker);

test "sidechain ducker uses mono key input without mixing it into main audio" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input_left = [_]f32{ 1.0, 1.0, 1.0 };
    const input_right = [_]f32{ 0.5, 0.5, 0.5 };
    const key = [_]f32{ 0.0, 0.25, 1.0 };
    var output_left = [_]f32{ 0.0, 0.0, 0.0 };
    var output_right = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{ &input_left, &input_right };
    const sidechain_channels = [_][]const f32{&key};
    const output_channels = [_][]f32{ &output_left, &output_right };
    var context = try plug.process.ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .input_channels = &input_channels,
        .sidechain_input_channels = &sidechain_channels,
        .output_channels = &output_channels,
    });

    try std.testing.expectEqual(plug.plugin.AudioBusLayout.mono, Spec.audio_sidechain_layout);
    try std.testing.expectEqual(@as(u8, 1), instance.audioSidechainInputChannelCount());
    instance.process(&context);
    try std.testing.expectEqualSlices(f32, &.{ 1.0, 0.75, 0.0 }, &output_left);
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 0.375, 0.0 }, &output_right);
}

test "sidechain ducker passes main audio when the auxiliary bus is inactive" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ -0.5, 0.75 };
    var output = [_]f32{ 0.0, 0.0 };
    var context = try plug.process.ProcessContext(f32).init(
        48_000.0,
        &[_][]const f32{&input},
        &[_][]f32{&output},
    );

    instance.process(&context);
    try std.testing.expectEqualSlices(f32, &input, &output);
}
