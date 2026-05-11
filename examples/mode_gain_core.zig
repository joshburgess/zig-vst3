const std = @import("std");
const plug = @import("zig-vst3-plugin");

const Mode = enum { clean, boost, mute };
const ModeParam = plug.parameters.EnumParam(Mode);

pub const ModeGain = struct {
    pub const name = "zig-vst3-plugin Core Mode Gain";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        mode: ModeParam = .{ .id = 0, .name = "Mode", .default = .clean },
    };

    pub fn processWithParameterView(
        _: *ModeGain,
        context: *plug.process.ProcessContext(f32),
        params: plug.parameters.ParameterView(Params),
    ) void {
        const gain: f32 = switch (params.load("mode")) {
            .clean => 1.0,
            .boost => 2.0,
            .mute => 0.0,
        };
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
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

    try std.testing.expectEqualStrings("zig-vst3-plugin Core Mode Gain", Spec.name);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 1), parameter_set.parameterCount());
    try std.testing.expectEqual(Mode.clean, spec.values.view(&parameter_set).load("mode"));
    plug.plugin.validateLifecycle(ModeGain);
}

test "mode gain core example applies enum parameter changes" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5, 1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        instance.parameterChange("mode", 0, .boost),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(f32, 0.5), output[0]);
    try std.testing.expectEqual(@as(f32, 1.0), output[1]);
    try std.testing.expectEqual(@as(f32, 2.0), output[2]);
}

test "mode gain core example formats and parses enum parameters" {
    var instance = try Instance.init(std.testing.allocator, .{});
    var buffer: [16]u8 = undefined;

    try std.testing.expectEqual(@as(?u32, 0), instance.parameterIdByName("Mode"));
    try std.testing.expectEqual(@as(?usize, 0), instance.parameterIndexOfId(0));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultNormalizedByName("Mode"));
    try std.testing.expect(instance.parameterIsListByName("Mode").?);
    try std.testing.expectEqual(@as(?i32, 2), instance.parameterStepCountByName("Mode"));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterOptionCount(0));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterOptionCountById(0));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterOptionCountByName("Mode"));
    try std.testing.expectEqualStrings("clean", instance.parameterOptionLabel(0, 0).?);
    try std.testing.expectEqualStrings("boost", instance.parameterOptionLabelById(0, 1).?);
    try std.testing.expectEqualStrings("mute", instance.parameterOptionLabelByName("Mode", 2).?);
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterOptionNormalized(0, 0));
    try std.testing.expectEqual(@as(?f64, 0.5), instance.parameterOptionNormalizedById(0, 1));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterOptionNormalizedByName("Mode", 2));
    try std.testing.expect(instance.parameterHasOptions(0));
    try std.testing.expect(instance.parameterHasOptionsById(0));
    try std.testing.expect(instance.parameterHasOptionsByName("Mode"));
    try std.testing.expect(!instance.parameterOptionsEmpty(0));
    try std.testing.expect(!instance.parameterOptionsEmptyById(0));
    try std.testing.expect(!instance.parameterOptionsEmptyByName("Mode"));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterFieldOptionCount("mode"));
    try std.testing.expectEqualStrings("mute", instance.parameterFieldOptionLabel("mode", 2).?);
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterFieldOptionNormalized("mode", 2));
    try std.testing.expect(instance.parameterFieldHasOptions("mode"));
    try std.testing.expect(!instance.parameterFieldOptionsEmpty("mode"));

    try std.testing.expectEqualStrings("boost", try instance.formatParameterPlainByName("Mode", 0.5, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterPlainByName("Mode", "mute"));
    try std.testing.expect(instance.storeParameterPlainByName("Mode", 2.0));
    try std.testing.expectEqual(Mode.mute, instance.loadParameter("mode"));
    try std.testing.expect(instance.resetParameterToDefaultByName("Mode"));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
}

test "mode gain core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        instance.parameterChange("mode", 0, .mute),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    instance.process(&context);

    try std.testing.expectEqual(Mode.mute, instance.loadParameter("mode"));
    try std.testing.expectEqual(@as(f32, 0.0), output[0]);
    try std.testing.expectEqual(@as(f32, 0.0), output[1]);
}
