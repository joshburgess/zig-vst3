const std = @import("std");
const plug = @import("zig-plug");

pub const Gain = struct {
    pub const name = "zig-plug Core Gain";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };

    pub fn process(_: *Gain, context: *plug.process.ProcessContext(f32)) void {
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                const gain = context.parameterNormalizedAtOrBeforeOr(0, sample, 1.0);
                output[sample] = input[sample] * @as(f32, @floatCast(gain));
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(Gain);
pub const Instance = plug.plugin.PluginInstance(Gain);
pub const parameter_set = Spec.ParameterSet.init(.{});

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
        parameter_set.parameterChange("gain", 0, 0.5),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.125), output[0]);
    try std.testing.expectEqual(@as(f32, 0.25), output[1]);
    try std.testing.expectEqual(@as(f32, 0.5), output[2]);
}

test "gain core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        parameter_set.parameterChange("gain", 0, 0.25),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(f32, 0.0625), output[0]);
    try std.testing.expectEqual(@as(f32, 0.125), output[1]);
}

test "gain core example applies sample-offset parameter changes" {
    var plugin = Gain{};
    const input = [_]f32{ 0.25, 0.5, 1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        parameter_set.parameterChange("gain", 1, 0.5),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, 0.25), output[1]);
    try std.testing.expectEqual(@as(f32, 0.5), output[2]);
}
