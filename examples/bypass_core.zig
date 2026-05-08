const std = @import("std");
const plug = @import("zig-plug");

pub const Bypass = struct {
    pub const name = "zig-plug Core Bypass";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        bypass: plug.parameters.BoolParam = .{ .id = 0, .name = "Bypass", .default = false },
    };

    pub fn processWithParameters(
        _: *Bypass,
        context: *plug.process.ProcessContext(f32),
        set: *const Spec.ParameterSet,
        values: *const Spec.ParameterValues,
    ) void {
        const bypassed = values.loadField(set, "bypass");
        for (0..context.outputs.channels.len) |channel| {
            const input = context.inputs.channel(channel) orelse continue;
            const output = context.outputs.channel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = if (bypassed) input[sample] else 0.0;
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(Bypass);
pub const Instance = plug.plugin.PluginInstance(Bypass);
pub const parameter_set = Spec.ParameterSet.init(.{});

test "bypass core example declares reflected bool parameter" {
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-plug Core Bypass", Spec.name);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(false, spec.values.loadField(&parameter_set, "bypass"));
    plug.plugin.validateLifecycle(Bypass);
}

test "bypass core example applies parameter changes by id" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5, 1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 1.0 },
    };
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
    context.parameter_changes = try plug.process.ParameterChanges.init(&changes, input.len);

    instance.process(&context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, 0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(true, instance.loadParameter("bypass"));
}

test "bypass core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 1.0 },
    };
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
    context.parameter_changes = try plug.process.ParameterChanges.init(&changes, input.len);

    instance.process(&context);

    try std.testing.expectEqual(true, instance.loadParameter("bypass"));
    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, 0.5), output[1]);
}
