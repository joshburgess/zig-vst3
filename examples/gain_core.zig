const std = @import("std");
const plug = @import("zig-plug-core");

pub const Gain = struct {
    pub const name = "zig-plug Core Gain";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };

    pub fn process(_: *Gain, context: *plug.process.ProcessContext(f32)) void {
        const gain = if (context.parameter_changes.latest(0)) |change| change.normalized else 1.0;
        for (0..context.outputs.channels.len) |channel| {
            const input = context.inputs.channel(channel) orelse continue;
            const output = context.outputs.channel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * @as(f32, @floatCast(gain));
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(Gain);

test "gain core example declares reflected metadata" {
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-plug Core Gain", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(?f64, 1.0), spec.values.load(0));
    plug.plugin.validateLifecycle(Gain);
}

test "gain core example processes through zig-plug context" {
    var plugin = Gain{};
    const input = [_]f32{ 0.25, 0.5, 1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.5 },
    };
    var context = plug.process.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .inputs = try plug.process.AudioInputs(f32).init(&input_channels),
        .outputs = try plug.process.AudioOutputs(f32).init(&output_channels),
        .parameter_changes = try plug.process.ParameterChanges.init(&changes, input.len),
    };

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.125), output[0]);
    try std.testing.expectEqual(@as(f32, 0.25), output[1]);
    try std.testing.expectEqual(@as(f32, 0.5), output[2]);
}
