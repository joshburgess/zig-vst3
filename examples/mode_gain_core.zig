const std = @import("std");
const plug = @import("zig-plug");

const Mode = enum { clean, boost, mute };
const ModeParam = plug.parameters.EnumParam(Mode);

pub const ModeGain = struct {
    pub const name = "zig-plug Core Mode Gain";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        mode: ModeParam = .{ .id = 0, .name = "Mode", .default = .clean },
    };

    pub fn processWithParameters(
        _: *ModeGain,
        context: *plug.process.ProcessContext(f32),
        set: *const Spec.ParameterSet,
        values: *const Spec.ParameterValues,
    ) void {
        const gain: f32 = switch (values.loadField(set, "mode")) {
            .clean => 1.0,
            .boost => 2.0,
            .mute => 0.0,
        };
        for (0..context.outputs.channels.len) |channel| {
            const input = context.inputs.channel(channel) orelse continue;
            const output = context.outputs.channel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(ModeGain);
pub const Instance = plug.plugin.PluginInstance(ModeGain);
pub const parameter_set = Spec.ParameterSet.init(.{});

test "mode gain core example declares reflected enum parameter" {
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-plug Core Mode Gain", Spec.name);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(Mode.clean, spec.values.loadField(&parameter_set, "mode"));
    plug.plugin.validateLifecycle(ModeGain);
}

test "mode gain core example applies enum parameter changes" {
    var instance = try Instance.init(std.testing.allocator, .{});
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

    instance.process(&context);

    try std.testing.expectEqual(@as(f32, 0.5), output[0]);
    try std.testing.expectEqual(@as(f32, 1.0), output[1]);
    try std.testing.expectEqual(@as(f32, 2.0), output[2]);
}

test "mode gain core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 1.0 },
    };
    var context = plug.process.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .inputs = try plug.process.AudioInputs(f32).init(&input_channels),
        .outputs = try plug.process.AudioOutputs(f32).init(&output_channels),
        .parameter_changes = try plug.process.ParameterChanges.init(&changes, input.len),
    };

    instance.process(&context);

    try std.testing.expectEqual(Mode.mute, instance.loadParameter("mode"));
    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expectEqual(@as(f32, 0.0), output[1]);
}
