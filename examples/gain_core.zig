const std = @import("std");
const plug = @import("zig-vst3-plugin");

pub const Gain = struct {
    pub const name = "zig-vst3-plugin Core Gain";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{ .id = 0, .name = "Gain", .short_name = "Gain", .units = "x", .min = 0.0, .max = 1.0, .default = 1.0 },
    };

    pub fn process(_: *Gain, context: *plug.process.ProcessContext(f32)) void {
        var segments = context.parameterBlockSegments();
        while (segments.next()) |segment| {
            const gain = @as(f32, @floatCast(context.parameterNormalizedAtOrBeforeOr(0, segment.start_offset, 1.0)));
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                for (segment.start_offset..segment.end_offset) |sample| {
                    output[sample] = input[sample] * gain;
                }
            }
        }
    }

    pub fn process64(_: *Gain, context: *plug.process.ProcessContext(f64)) void {
        var segments = context.parameterBlockSegments();
        while (segments.next()) |segment| {
            const gain = context.parameterNormalizedAtOrBeforeOr(0, segment.start_offset, 1.0);
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                for (segment.start_offset..segment.end_offset) |sample| {
                    output[sample] = input[sample] * gain;
                }
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(Gain);
pub const Instance = plug.plugin.PluginInstance(Gain);
pub const parameter_set = Spec.ParameterSet.init(.{});

test "gain core example declares reflected metadata" {
    const spec = Spec.init(.{});

    try std.testing.expectEqualStrings("zig-vst3-plugin Core Gain", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqual(@as(usize, 1), parameter_set.parameterCount());
    try std.testing.expectEqualStrings("Gain", parameter_set.shortName(0).?);
    try std.testing.expectEqualStrings("x", parameter_set.units(0).?);
    try std.testing.expectEqual(@as(f64, 1.0), spec.values.view(&parameter_set).loadNormalized("gain"));
    plug.plugin.validateLifecycle(Gain);
}

test "gain core example processes through zig-vst3-plugin context" {
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

    try std.testing.expectEqual(@as(?f64, 0.5), context.firstAnyParameterNormalized());
    try std.testing.expectEqual(@as(?f64, 0.5), context.latestAnyParameterNormalized());
    try std.testing.expectEqual(@as(f64, 0.5), context.firstAnyParameterNormalizedOr(1.0));
    try std.testing.expectEqual(@as(f64, 0.5), context.latestAnyParameterNormalizedOr(1.0));
    try std.testing.expect(context.onlyParameterChangesForId(0));
    try std.testing.expect(context.onlyParameterChangesAtOffset(0));
    try std.testing.expect(context.onlyParameterChangesForIdAtOffset(0, 0));
    try std.testing.expect(!context.onlyParameterChangesAtOffset(1));
    try std.testing.expectEqual(@as(f32, 0.125), output[0]);
    try std.testing.expectEqual(@as(f32, 0.25), output[1]);
    try std.testing.expectEqual(@as(f32, 0.5), output[2]);
}

test "gain core example splits blocks at automation changes" {
    var plugin = Gain{};
    const input = [_]f32{ 1.0, 1.0, 1.0, 1.0, 1.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        parameter_set.parameterChange("gain", 1, 0.5),
        parameter_set.parameterChange("gain", 3, 0.25),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(?f64, 0.5), context.firstAnyParameterNormalized());
    try std.testing.expectEqual(@as(?f64, 0.25), context.latestAnyParameterNormalized());
    try std.testing.expectEqual(@as(f64, 0.5), context.firstAnyParameterNormalizedOr(1.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.latestAnyParameterNormalizedOr(1.0));
    try std.testing.expect(context.onlyParameterChangesForId(0));
    try std.testing.expect(!context.onlyParameterChangesAtOffset(1));
    try std.testing.expect(!context.onlyParameterChangesForIdAtOffset(0, 1));
    try std.testing.expectEqual(@as(f32, 1.0), output[0]);
    try std.testing.expectEqual(@as(f32, 0.5), output[1]);
    try std.testing.expectEqual(@as(f32, 0.5), output[2]);
    try std.testing.expectEqual(@as(f32, 0.25), output[3]);
    try std.testing.expectEqual(@as(f32, 0.25), output[4]);
}

test "gain core example supports double precision processing" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f64{ 0.25, 0.5 };
    var output = [_]f64{ 0.0, 0.0 };
    const input_channels = [_][]const f64{&input};
    const output_channels = [_][]f64{&output};
    const changes = [_]plug.process.ParameterChange{
        instance.parameterChange("gain", 0, 0.5),
    };
    var context = try plug.process.ProcessContext(f64).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    instance.process64(&context);

    try std.testing.expectEqual(@as(f64, 0.125), output[0]);
    try std.testing.expectEqual(@as(f64, 0.25), output[1]);
}

test "gain core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]plug.process.ParameterChange{
        instance.parameterChange("gain", 0, 0.25),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(f32, 0.0625), output[0]);
    try std.testing.expectEqual(@as(f32, 0.125), output[1]);
}

test "gain core example formats and converts float parameters" {
    var instance = try Instance.init(std.testing.allocator, .{});
    var buffer: [16]u8 = undefined;

    try std.testing.expectEqual(@as(usize, 0), instance.parameterFieldIndex("gain"));
    try std.testing.expectEqual(@as(u32, 0), instance.parameterFieldId("gain"));
    try std.testing.expectEqualStrings("Gain", instance.parameterFieldName("gain"));
    try std.testing.expectEqualStrings("x", instance.parameterFieldUnits("gain"));
    try std.testing.expectEqual(@as(f64, 1.0), instance.parameterFieldDefaultNormalized("gain"));

    try std.testing.expectEqualStrings("0.500", try instance.formatParameterFieldPlain("gain", 0.5, &buffer));
    try std.testing.expectEqual(@as(f64, 0.25), try instance.parseParameterFieldPlain("gain", "0.25"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.parameterFieldPlainFromNormalized("gain", 0.75));
    try std.testing.expectEqual(@as(f64, 0.25), instance.parameterFieldNormalizedFromPlain("gain", 0.25));
    try std.testing.expect(instance.storeParameterPlainByName("Gain", 0.5));
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameter("gain"));
}

test "gain core example copies and resets parameter values" {
    var source = try Instance.init(std.testing.allocator, .{});
    var target = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(?usize, 1), source.storeParameterNormalizedCount("gain", 0.25));
    try std.testing.expectEqual(@as(?usize, 0), source.storeParameterNormalizedCount("gain", 0.25));

    target.copyParameterValuesFrom(&source);
    try std.testing.expectEqual(@as(f64, 0.25), target.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(usize, 1), target.parameterNonDefaultCount());
    try std.testing.expect(target.hasNonDefaultParameters());
    try std.testing.expect(!target.parametersAllDefaults());

    try std.testing.expectEqual(@as(?usize, 1), target.resetParameterToDefaultCount("gain"));
    try std.testing.expectEqual(@as(?usize, 0), target.resetParameterToDefaultCount("gain"));
    try std.testing.expectEqual(@as(usize, 0), target.parameterNonDefaultCount());
    try std.testing.expect(!target.hasNonDefaultParameters());
    try std.testing.expect(target.parametersAllDefaults());
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

test "gain core example can smooth normalized gain changes" {
    var smoother = plug.parameters.LinearSmoother.init(0.0);

    smoother.setTarget(1.0, 4);
    try std.testing.expect(smoother.active());
    try std.testing.expect(!smoother.finished());
    try std.testing.expectEqual(@as(usize, 4), smoother.remainingSamples());
    try std.testing.expectApproxEqAbs(1.0, smoother.targetDelta(), 0.000001);
    try std.testing.expect(smoother.needsSmoothing(0.25));
    try std.testing.expectApproxEqAbs(0.25, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.next(), 0.000001);
    smoother.reset(0.75);
    try std.testing.expectApproxEqAbs(0.75, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.75, smoother.targetValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.0, smoother.targetDelta(), 0.000001);
    try std.testing.expect(smoother.atTarget(0.0));
    try std.testing.expect(!smoother.active());
    try std.testing.expect(smoother.finished());
}

test "gain core example round-trips parameter state" {
    var instance = try Instance.init(std.testing.allocator, .{});
    var restored = try Instance.init(std.testing.allocator, .{});
    var bytes: [plug.state.encodedSize(Gain.Params)]u8 = undefined;

    try std.testing.expect(instance.storeParameterNormalized("gain", 0.25));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try instance.writeParameterState(out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    const report = try restored.readParameterStateReport(in_stream.reader());

    try std.testing.expectEqual(@as(usize, 1), report.decodedCount());
    try std.testing.expectEqual(@as(usize, 1), report.restoredCount());
    try std.testing.expectEqual(@as(usize, 0), report.ignoredCount());
    try std.testing.expect(report.hasDecodedEntries());
    try std.testing.expect(report.hasRestoredEntries());
    try std.testing.expect(!report.hasIgnoredEntries());
    try std.testing.expect(report.fullyHandled());
    try std.testing.expectEqual(plug.state.ReadParameterStateClassification.restored_all, report.classification());
    try std.testing.expect(report.isRestoredAllClassification());
    try std.testing.expect(!report.isPartialClassification());
    try std.testing.expect(report.restoredAllEntries());
    try std.testing.expect(!report.ignoredAllEntries());
    try std.testing.expectEqual(@as(f64, 0.25), restored.loadParameterNormalized("gain"));

    var json_bytes: [128]u8 = undefined;
    var json_stream = std.io.fixedBufferStream(&json_bytes);
    try restored.writeParameterStateJson(json_stream.writer());
    try std.testing.expectEqualStrings(
        "{\"version\":1,\"parameters\":[{\"id\":0,\"name\":\"Gain\",\"normalized\":0.25}]}",
        json_stream.getWritten(),
    );
}

test "gain core example resolves migrated state parameter ids" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const migrations = [_]plug.state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 11 },
        .{ .old_id = 11, .new_id = 0 },
    };

    try instance.validateParameterIdMigrations(&migrations);
    try std.testing.expectEqual(@as(u32, 0), instance.migratedParameterId(7, &migrations));
    try std.testing.expectEqual(@as(u32, 0), instance.migratedParameterId(11, &migrations));
    try std.testing.expectEqual(@as(u32, 42), instance.migratedParameterId(42, &migrations));
}
