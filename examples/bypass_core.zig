const std = @import("std");
const plug = @import("zig-vst3-plugin");

pub const Bypass = struct {
    pub const name = "zig-vst3-plugin Core Bypass";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        bypass: plug.parameters.BoolParam = .{ .id = 0, .name = "Bypass", .default = false },
    };

    pub fn processWithParameterView(
        _: *Bypass,
        context: *plug.process.ProcessContext(f32),
        params: plug.parameters.ParameterView(Params),
    ) void {
        if (!params.load("bypass")) {
            context.clearOutputs();
            return;
        }
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample];
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(Bypass);
pub const Instance = plug.plugin.PluginInstance(Bypass);
pub const parameter_set = Spec.ParameterSet.init(.{});

test "bypass core example declares reflected bool parameter" {
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3-plugin Core Bypass", Spec.name);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 1), parameter_set.parameterCount());
    try std.testing.expectEqual(false, spec.values.view(&parameter_set).load("bypass"));
    plug.plugin.validateLifecycle(Bypass);
}

test "bypass core example applies reflected parameter changes" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5, 1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        instance.parameterChange("bypass", 0, true),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, 0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 1.0), output[2]);
    try std.testing.expectEqual(true, instance.loadParameter("bypass"));
}

test "bypass core example formats and parses bool parameters" {
    var instance = try Instance.init(std.testing.allocator, .{});
    var buffer: [16]u8 = undefined;

    try std.testing.expectEqual(@as(?u32, 0), instance.parameterIdByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsBypassByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterCanAutomateByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsReadOnlyByName("Bypass"));
    try std.testing.expectEqual(@as(?i32, 1), instance.parameterStepCountByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsListByName("Bypass"));
    const descriptor = instance.parameterFieldDescriptor("bypass");
    try std.testing.expectEqual(@as(f64, 0.0), descriptor.defaultNormalized());
    try std.testing.expectEqual(@as(f64, 1.0), descriptor.normalize(true));
    try std.testing.expect(!descriptor.denormalize(0.49));
    try std.testing.expect(descriptor.denormalize(0.5));
    try std.testing.expectEqualStrings("On", try descriptor.formatPlain(1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), descriptor.plainFromNormalized(1.0));
    try std.testing.expectEqual(@as(f64, 1.0), descriptor.normalizedFromPlain(0.75));
    try std.testing.expectEqual(@as(f64, 1.0), try descriptor.parsePlain("true"));
    try std.testing.expectError(error.InvalidBool, descriptor.parsePlain("maybe"));
    try std.testing.expect(!instance.parameterFieldIsBypass("bypass"));
    try std.testing.expect(instance.parameterFieldCanAutomate("bypass"));
    try std.testing.expect(!instance.parameterFieldIsReadOnly("bypass"));
    try std.testing.expectEqual(@as(i32, 1), instance.parameterFieldStepCount("bypass"));
    try std.testing.expect(!instance.parameterFieldIsList("bypass"));

    try std.testing.expectEqualStrings("On", try instance.formatParameterPlainByName("Bypass", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 0.0), try instance.parseParameterPlainByName("Bypass", "off"));
    try std.testing.expect(instance.storeParameterPlainByName("Bypass", 1.0));
    try std.testing.expectEqual(true, instance.loadParameter("bypass"));
    try std.testing.expect(instance.resetParameterToDefaultByName("Bypass"));
    try std.testing.expectEqual(false, instance.loadParameter("bypass"));
}

test "bypass core example exposes bound parameter flag metadata" {
    var instance = try Instance.init(std.testing.allocator, .{});

    const view = instance.parameterView();
    try std.testing.expectEqual(@as(?bool, false), view.isBypassByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, true), view.canAutomateById(0));
    try std.testing.expectEqual(@as(?bool, false), view.isReadOnly(0));
    try std.testing.expectEqual(@as(?i32, 1), view.stepCountByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, false), view.isListById(0));
    try std.testing.expect(!view.fieldIsBypass("bypass"));
    try std.testing.expect(view.fieldCanAutomate("bypass"));
    try std.testing.expect(!view.fieldIsReadOnly("bypass"));
    try std.testing.expectEqual(@as(i32, 1), view.fieldStepCount("bypass"));
    try std.testing.expect(!view.fieldIsList("bypass"));

    const editor = instance.parameterEditor();
    try std.testing.expectEqual(@as(?bool, false), editor.isBypass(0));
    try std.testing.expectEqual(@as(?bool, true), editor.canAutomateByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, false), editor.isReadOnlyById(0));
    try std.testing.expectEqual(@as(?i32, 1), editor.stepCount(0));
    try std.testing.expectEqual(@as(?bool, false), editor.isListByName("Bypass"));
    try std.testing.expect(editor.fieldCanAutomate("bypass"));
    try std.testing.expect(!editor.fieldIsReadOnly("bypass"));
    try std.testing.expectEqual(@as(i32, 1), editor.fieldStepCount("bypass"));
}

test "bypass core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        instance.parameterChange("bypass", 0, true),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    instance.process(&context);

    try std.testing.expectEqual(true, instance.loadParameter("bypass"));
    try std.testing.expectEqual(@as(f32, 0.25), output[0]);
    try std.testing.expectEqual(@as(f32, 0.5), output[1]);
}
