const std = @import("std");
const plug = @import("zig-plug");

const voice_unit_id: i32 = 1;
const voice_program_list_id: i32 = 7;

pub const VoiceMix = struct {
    pub const name = "zig-plug Core Voice Mix";
    pub const vendor = "zig-vst3";
    pub const units = plug.units.Config{
        .units = &.{
            plug.units.Unit.root("Main"),
            .{
                .id = voice_unit_id,
                .name = "Voices",
                .parent_id = plug.units.root_unit_id,
                .program_list_id = voice_program_list_id,
            },
        },
        .program_lists = &.{
            .{
                .id = voice_program_list_id,
                .name = "Voice Presets",
                .programs = &.{
                    .{
                        .name = "Single",
                        .parameters = &.{.{ .parameter_id = 0, .normalized = 0.0 }},
                        .info = &.{.{ .key = "voices", .value = "1" }},
                    },
                    .{
                        .name = "Quad",
                        .parameters = &.{.{ .parameter_id = 0, .normalized = 1.0 }},
                        .info = &.{.{ .key = "voices", .value = "4" }},
                    },
                },
            },
        },
    };
    pub const Params = struct {
        voices: plug.parameters.IntParam = .{ .id = 0, .name = "Voices", .min = 1, .max = 4, .default = 1, .unit_id = voice_unit_id },
    };

    pub fn processWithParameterView(
        _: *VoiceMix,
        context: *plug.process.ProcessContext(f32),
        params: plug.parameters.ParameterView(Params),
    ) void {
        const gain: f32 = @floatFromInt(params.load("voices"));
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
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
    try std.testing.expectEqual(@as(?i32, voice_unit_id), parameter_set.unitId(0));
    try std.testing.expectEqual(@as(i64, 1), spec.values.view(&parameter_set).load("voices"));
    plug.plugin.validateLifecycle(VoiceMix);
}

test "voice mix core example declares reflected unit and program metadata" {
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), instance.unitCount());
    try std.testing.expectEqualStrings("Voices", instance.unitById(voice_unit_id).?.name);
    try std.testing.expect(instance.hasUnit(voice_unit_id));
    try std.testing.expectEqualStrings("Voice Presets", instance.programListForUnit(voice_unit_id).?.name);
    try std.testing.expectEqual(@as(?usize, 2), instance.programCount(voice_program_list_id));
    try std.testing.expectEqualStrings("Quad", instance.programName(voice_program_list_id, 1).?);
    try std.testing.expectEqual(@as(?usize, 1), instance.programIndexOfName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(?usize, 1), instance.programParameterCount(voice_program_list_id, 1));
    try std.testing.expectEqual(@as(f64, 1.0), instance.programParameterById(voice_program_list_id, 1, 0).?.normalized);
    try std.testing.expectEqualStrings("4", instance.programInfoByName(voice_program_list_id, "Quad", "voices").?);
}

test "voice mix core example applies reflected program snapshots" {
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expect(try instance.applyProgramByName(voice_program_list_id, "Quad"));
    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expect(try instance.applyProgramByName(voice_program_list_id, "Single"));
    try std.testing.expectEqual(@as(i64, 1), instance.loadParameter("voices"));
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
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

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
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(i64, 4), instance.loadParameter("voices"));
    try std.testing.expectEqual(@as(f32, 1.0), output[0]);
    try std.testing.expectEqual(@as(f32, 2.0), output[1]);
}
