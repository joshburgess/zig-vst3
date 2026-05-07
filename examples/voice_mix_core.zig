const std = @import("std");
const plug = @import("zig-plug-core");

pub const VoiceMix = struct {
    values: Spec.ParameterValues,

    pub const name = "zig-plug Core Voice Mix";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        voices: plug.parameters.IntParam = plug.parameters.IntParam.init(0, "Voices", 1, 4, 1),
    };

    pub fn init(_: std.mem.Allocator) !VoiceMix {
        return .{ .values = Spec.ParameterValues.init(&parameter_set) };
    }

    pub fn process(self: *VoiceMix, context: *plug.process.ProcessContext(f32)) void {
        self.values.applyChanges(&parameter_set, context.parameter_changes);
        const normalized = self.values.loadById(&parameter_set, 0) orelse 0.0;
        const voices = plug.parameters.IntParam.init(0, "Voices", 1, 4, 1).denormalize(normalized);
        const gain: f32 = @floatFromInt(voices);
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
pub const parameter_set = Spec.ParameterSet.init(.{});

test "voice mix core example declares reflected int parameter" {
    var plugin = try VoiceMix.init(std.testing.allocator);

    try std.testing.expectEqualStrings("zig-plug Core Voice Mix", Spec.name);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(?f64, 0.0), plugin.values.loadById(&parameter_set, 0));
    plug.plugin.validateLifecycle(VoiceMix);
}

test "voice mix core example applies int parameter changes" {
    var plugin = try VoiceMix.init(std.testing.allocator);
    const input = [_]f32{ 0.25, 0.5, 1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
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

    plugin.process(&context);

    try std.testing.expectEqual(@as(f32, 1.0), output[0]);
    try std.testing.expectEqual(@as(f32, 2.0), output[1]);
    try std.testing.expectEqual(@as(f32, 4.0), output[2]);
}
