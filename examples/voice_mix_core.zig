const std = @import("std");
const plug = @import("zig-plug");

pub const VoiceMix = struct {
    pub const name = "zig-plug Core Voice Mix";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        voices: plug.parameters.IntParam = plug.parameters.IntParam.init(0, "Voices", 1, 4, 1),
    };

    pub fn processWithParameters(
        _: *VoiceMix,
        context: *plug.process.ProcessContext(f32),
        set: *const Spec.ParameterSet,
        values: *const Spec.ParameterValues,
    ) void {
        const gain: f32 = @floatFromInt(values.loadField(set, "voices"));
        for (0..context.outputs.channels.len) |channel| {
            const input = context.inputs.channel(channel) orelse continue;
            const output = context.outputs.channel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(VoiceMix);
pub const Instance = plug.plugin.PluginInstance(VoiceMix);
pub const parameter_set = Spec.ParameterSet.init(.{});

test "voice mix core example declares reflected int parameter" {
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-plug Core Voice Mix", Spec.name);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(i64, 1), spec.values.loadField(&parameter_set, "voices"));
    plug.plugin.validateLifecycle(VoiceMix);
}

test "voice mix core example applies int parameter changes" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5, 1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        parameter_set.parameterChange("voices", 0, 4),
    };
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
    try context.setParameterChanges(&changes);

    instance.process(&context);

    try std.testing.expectEqual(@as(f32, 1.0), output[0]);
    try std.testing.expectEqual(@as(f32, 2.0), output[1]);
    try std.testing.expectEqual(@as(f32, 4.0), output[2]);
}

test "voice mix core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        parameter_set.parameterChange("voices", 0, 4),
    };
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
    try context.setParameterChanges(&changes);

    instance.process(&context);

    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expectEqual(@as(f32, 1.0), output[0]);
    try std.testing.expectEqual(@as(f32, 2.0), output[1]);
}
