const std = @import("std");
const plug = @import("zig-vst3-plugin");

pub const AuxiliaryOutputSplitter = struct {
    pub const name = "zig-vst3 Auxiliary Output Splitter";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .stereo;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .stereo;
    pub const audio_auxiliary_output_layouts: []const plug.plugin.AudioBusLayout = &.{ .mono, .stereo };
    pub const Params = struct {};

    pub fn process(_: *AuxiliaryOutputSplitter, context: *plug.process.ProcessContext(f32)) void {
        processBlock(f32, context);
    }

    pub fn process64(_: *AuxiliaryOutputSplitter, context: *plug.process.ProcessContext(f64)) void {
        processBlock(f64, context);
    }
};

fn processBlock(comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
    for (0..context.outputChannelCount()) |channel_index| {
        const input = context.inputChannel(channel_index) orelse continue;
        const output = context.outputChannel(channel_index) orelse continue;
        for (input, output) |sample, *destination| destination.* = sample;
    }

    const left = context.inputChannel(0) orelse return;
    const right = context.inputChannel(1) orelse return;
    if (context.auxiliaryOutputBus(0)) |mono_bus| {
        if (mono_bus.channel(0)) |auxiliary| {
            for (auxiliary, left, right) |*destination, left_sample, right_sample| {
                destination.* = (left_sample + right_sample) * 0.5;
            }
        }
    }
    if (context.auxiliaryOutputBus(1)) |stereo_bus| {
        if (stereo_bus.channel(0)) |auxiliary_left| {
            for (left, auxiliary_left) |sample, *destination| {
                destination.* = sample;
            }
        }
        if (stereo_bus.channel(1)) |auxiliary_right| {
            for (right, auxiliary_right) |sample, *destination| {
                destination.* = sample;
            }
        }
    }
}

pub const Spec = plug.plugin.PluginSpec(AuxiliaryOutputSplitter);
pub const Instance = plug.plugin.PluginInstance(AuxiliaryOutputSplitter);

test "auxiliary output splitter writes separate mono and stereo mixes" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const left = [_]f32{ 1.0, 0.5 };
    const right = [_]f32{ 0.0, -0.5 };
    var main_left = [_]f32{ 0.0, 0.0 };
    var main_right = [_]f32{ 0.0, 0.0 };
    var auxiliary_mono = [_]f32{ 0.0, 0.0 };
    var auxiliary_left = [_]f32{ 0.0, 0.0 };
    var auxiliary_right = [_]f32{ 0.0, 0.0 };
    var context = try plug.process.ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .input_channels = &[_][]const f32{ &left, &right },
        .output_channels = &[_][]f32{ &main_left, &main_right },
        .auxiliary_output_channels = &[_][]f32{
            &auxiliary_mono,
            &auxiliary_left,
            &auxiliary_right,
        },
        .auxiliary_output_bus_channel_counts = &.{ 1, 2 },
    });

    try std.testing.expectEqual(plug.plugin.AudioBusLayout.mono, Spec.audio_auxiliary_output_layout);
    try std.testing.expectEqual(@as(usize, 2), instance.audioAuxiliaryOutputBusCount());
    try std.testing.expectEqual(@as(u8, 1), instance.audioAuxiliaryOutputChannelCount());
    instance.process(&context);
    try std.testing.expectEqualSlices(f32, &left, &main_left);
    try std.testing.expectEqualSlices(f32, &right, &main_right);
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 0.0 }, &auxiliary_mono);
    try std.testing.expectEqualSlices(f32, &left, &auxiliary_left);
    try std.testing.expectEqualSlices(f32, &right, &auxiliary_right);
}

test "auxiliary output splitter accepts an inactive auxiliary bus" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const left = [_]f32{0.25};
    const right = [_]f32{-0.25};
    var main_left = [_]f32{0.0};
    var main_right = [_]f32{0.0};
    var context = try plug.process.ProcessContext(f32).init(
        48_000.0,
        &[_][]const f32{ &left, &right },
        &[_][]f32{ &main_left, &main_right },
    );

    instance.process(&context);
    try std.testing.expectEqualSlices(f32, &left, &main_left);
    try std.testing.expectEqualSlices(f32, &right, &main_right);
}

test "auxiliary output splitter supports in-place main audio buffers" {
    var instance = try Instance.init(std.testing.allocator, .{});
    var left = [_]f32{ 1.0, 0.5 };
    var right = [_]f32{ 0.0, -0.5 };
    var auxiliary = [_]f32{ 0.0, 0.0 };
    var context = try plug.process.ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .input_channels = &[_][]const f32{ &left, &right },
        .output_channels = &[_][]f32{ &left, &right },
        .auxiliary_output_channels = &[_][]f32{&auxiliary},
    });

    instance.process(&context);
    try std.testing.expectEqualSlices(f32, &.{ 1.0, 0.5 }, &left);
    try std.testing.expectEqualSlices(f32, &.{ 0.0, -0.5 }, &right);
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 0.0 }, &auxiliary);
}
