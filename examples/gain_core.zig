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
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqualStrings("zig-vst3-plugin Core Gain", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expect(instance.hasAudioInput());
    try std.testing.expect(instance.hasAudioOutput());
    try std.testing.expect(instance.hasEventInput());
    try std.testing.expect(!instance.hasEventOutput());
    try std.testing.expect(!instance.hasInitHook());
    try std.testing.expect(!instance.hasPrepareHook());
    try std.testing.expect(instance.hasProcessHook());
    try std.testing.expect(instance.hasProcess64Hook());
    try std.testing.expect(instance.hasAnyProcessHook());
    try std.testing.expect(!instance.hasDeinitHook());
    try (plug.plugin.PrepareConfig{ .sample_rate = 48_000.0, .max_block_size = 64 }).validate();
    try std.testing.expectError(error.InvalidSampleRate, (plug.plugin.PrepareConfig{ .sample_rate = 0.0, .max_block_size = 64 }).validate());
    try std.testing.expectError(error.InvalidMaxBlockSize, (plug.plugin.PrepareConfig{ .sample_rate = 48_000.0, .max_block_size = 0 }).validate());
    try instance.prepareChecked(.{ .sample_rate = 48_000.0, .max_block_size = 64 });
    try std.testing.expectError(error.InvalidSampleRate, instance.prepareChecked(.{ .sample_rate = std.math.nan(f64), .max_block_size = 64 }));
    try std.testing.expectEqual(@as(usize, 1), parameter_set.parameterCount());
    try std.testing.expectEqualStrings("Gain", parameter_set.shortName(0).?);
    try std.testing.expectEqualStrings("x", parameter_set.units(0).?);
    try std.testing.expectEqual(@as(?usize, 0), instance.parameterIndexOfId(0));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterIndexOfId(99));
    try std.testing.expectEqualStrings("Gain", instance.parameterShortName(0).?);
    try std.testing.expectEqualStrings("Gain", instance.parameterShortNameById(0).?);
    try std.testing.expectEqualStrings("Gain", instance.parameterShortNameByName("Gain").?);
    try std.testing.expectEqualStrings("x", instance.parameterUnits(0).?);
    try std.testing.expectEqualStrings("x", instance.parameterUnitsById(0).?);
    try std.testing.expectEqualStrings("x", instance.parameterUnitsByName("Gain").?);
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterDefaultNormalized(0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterDefaultNormalizedById(0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterDefaultNormalizedByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterDefaultPlain(0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterDefaultPlainById(0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterDefaultPlainByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterPlainMinimum(0));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterPlainMinimumById(0));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterPlainMinimumByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterPlainMaximum(0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterPlainMaximumById(0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterPlainMaximumByName("Gain"));
    try std.testing.expect(instance.parameterHasPlainRange(0));
    try std.testing.expect(instance.parameterHasPlainRangeById(0));
    try std.testing.expect(instance.parameterHasPlainRangeByName("Gain"));
    try std.testing.expect(!instance.parameterHasPlainRange(99));
    try std.testing.expect(!instance.parameterHasPlainRangeById(99));
    try std.testing.expect(!instance.parameterHasPlainRangeByName("Missing"));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateParameterId());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateParameterIdIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateParameterName());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateParameterNameIndex());
    try std.testing.expect(!instance.hasDuplicateParameterIds());
    try std.testing.expect(!instance.hasDuplicateParameterNames());
    try std.testing.expectEqual(@as(?anyerror, null), instance.firstParameterDescriptorError());
    try std.testing.expectEqual(@as(?usize, null), instance.firstParameterDescriptorErrorIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.firstParameterDescriptorErrorName());
    try std.testing.expect(instance.hasParameterId(0));
    try std.testing.expect(!instance.hasParameterId(99));
    try std.testing.expect(instance.hasParameterName("Gain"));
    try std.testing.expect(!instance.hasParameterName("Missing"));
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

    try std.testing.expectEqual(@as(usize, 1), context.inputChannelCount());
    try std.testing.expectEqual(@as(usize, 1), context.outputChannelCount());
    try std.testing.expect(!context.inputChannelsEmpty());
    try std.testing.expect(!context.outputChannelsEmpty());
    try std.testing.expect(context.hasInputChannels());
    try std.testing.expect(context.hasOutputChannels());
    try std.testing.expect(context.hasInputChannel(0));
    try std.testing.expect(!context.hasInputChannel(1));
    try std.testing.expect(!context.inputChannelEmpty(0));
    try std.testing.expect(context.inputChannelEmpty(1));
    try std.testing.expect(context.hasOutputChannel(0));
    try std.testing.expect(!context.hasOutputChannel(1));
    try std.testing.expect(!context.outputChannelEmpty(0));
    try std.testing.expect(context.outputChannelEmpty(1));
    try std.testing.expectEqual(@as(f32, 0.25), context.inputChannel(0).?[0]);
    try std.testing.expectEqual(@as(?[]const f32, null), context.inputChannel(1));
    try std.testing.expectEqual(@as(f32, 0.0), context.outputChannel(0).?[0]);
    try std.testing.expectEqual(@as(?[]f32, null), context.outputChannel(1));
    context.fillOutputs(0.75);
    try std.testing.expectEqual(@as(f32, 0.75), output[0]);
    context.clearOutputs();
    try std.testing.expectEqual(@as(f32, 0.0), output[0]);

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

test "gain core example can inspect audio buffer views" {
    const in_left = [_]f32{ 0.1, 0.2, 0.3 };
    const in_right = [_]f32{ 0.4, 0.5, 0.6 };
    const short_input = [_]f32{ 0.7, 0.8 };
    var out_left = [_]f32{ 0.0, 0.0, 0.0 };
    var out_right = [_]f32{ 0.0, 0.0, 0.0 };
    var short_output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{ &in_left, &in_right };
    const mismatched_input_channels = [_][]const f32{ &in_left, &short_input };
    const output_channels = [_][]f32{ &out_left, &out_right };
    const mismatched_output_channels = [_][]f32{ &out_left, &short_output };

    const inputs = try plug.process.AudioInputs(f32).init(&input_channels);
    try std.testing.expectEqual(@as(usize, 2), inputs.channelCount());
    try std.testing.expect(!inputs.isEmpty());
    try std.testing.expect(inputs.hasChannels());
    try std.testing.expectEqual(@as(usize, 3), inputs.frameCount());
    try std.testing.expect(inputs.hasChannel(1));
    try std.testing.expect(!inputs.channelEmpty(1));
    try std.testing.expectEqual(@as(f32, 0.4), inputs.channel(1).?[0]);
    try std.testing.expectEqual(@as(?[]const f32, null), inputs.channel(2));
    try std.testing.expect(!inputs.hasChannel(2));
    try std.testing.expect(inputs.channelEmpty(2));
    try std.testing.expectError(error.MismatchedFrameCount, plug.process.AudioInputs(f32).init(&mismatched_input_channels));

    const outputs = try plug.process.AudioOutputs(f32).init(&output_channels);
    try std.testing.expectEqual(@as(usize, 2), outputs.channelCount());
    try std.testing.expect(!outputs.isEmpty());
    try std.testing.expect(outputs.hasChannels());
    try std.testing.expectEqual(@as(usize, 3), outputs.frameCount());
    try std.testing.expect(outputs.hasChannel(1));
    try std.testing.expect(!outputs.channelEmpty(1));
    try std.testing.expectEqual(@as(f32, 0.0), outputs.channel(1).?[0]);
    try std.testing.expectEqual(@as(?[]f32, null), outputs.channel(2));
    try std.testing.expect(!outputs.hasChannel(2));
    try std.testing.expect(outputs.channelEmpty(2));
    outputs.fill(0.25);
    try std.testing.expectEqual(@as(f32, 0.25), out_left[0]);
    try std.testing.expectEqual(@as(f32, 0.25), out_right[2]);
    outputs.clear();
    try std.testing.expectEqual(@as(f32, 0.0), out_left[0]);
    try std.testing.expectEqual(@as(f32, 0.0), out_right[2]);
    try std.testing.expectError(error.MismatchedFrameCount, plug.process.AudioOutputs(f32).init(&mismatched_output_channels));
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

    try std.testing.expect(changes[0].isForId(0));
    try std.testing.expect(!changes[0].isForId(99));
    try std.testing.expect(changes[0].isAtOffset(1));
    try std.testing.expect(!changes[0].isAtOffset(2));
    try std.testing.expect(changes[0].isForIdAtOffset(0, 1));
    try std.testing.expect(!changes[0].isForIdAtOffset(99, 1));
    try std.testing.expect(!changes[0].isForIdAtOffset(0, 2));

    plugin.process(&context);

    try std.testing.expectEqual(@as(?f64, 0.5), context.firstAnyParameterNormalized());
    try std.testing.expectEqual(@as(?f64, 0.25), context.latestAnyParameterNormalized());
    try std.testing.expectEqual(@as(f64, 0.5), context.firstAnyParameterNormalizedOr(1.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.latestAnyParameterNormalizedOr(1.0));
    try std.testing.expectEqual(@as(usize, 2), context.parameterChangeCount());
    try std.testing.expect(!context.parameterChangesEmpty());
    try std.testing.expect(context.hasParameterChanges());
    try std.testing.expectEqual(@as(?usize, 1), context.firstParameterChangeOffset());
    try std.testing.expectEqual(@as(?usize, 3), context.latestParameterChangeOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.firstParameterChangeOffsetForId(0));
    try std.testing.expectEqual(@as(?usize, 3), context.latestParameterChangeOffsetForId(0));
    try std.testing.expectEqual(@as(?usize, null), context.firstParameterChangeOffsetForId(99));
    try std.testing.expectEqual(@as(?f64, 0.5), context.firstParameterNormalized(0));
    try std.testing.expectEqual(@as(?f64, 0.25), context.latestParameterNormalized(0));
    try std.testing.expectEqual(@as(?f64, 0.5), context.firstParameterNormalizedAtOffset(1));
    try std.testing.expectEqual(@as(?f64, 0.25), context.latestParameterNormalizedAtOffset(3));
    try std.testing.expectEqual(@as(?f64, 0.25), context.firstParameterNormalizedForIdAtOffset(0, 3));
    try std.testing.expectEqual(@as(f64, 0.75), context.firstParameterNormalizedForIdAtOffsetOr(99, 1, 0.75));
    try std.testing.expectEqual(@as(usize, 2), context.countParameterChanges(0));
    try std.testing.expectEqual(@as(usize, 1), context.countParameterChangesAtOffset(1));
    try std.testing.expectEqual(@as(usize, 1), context.countParameterChangesForIdAtOffset(0, 3));
    try std.testing.expect(context.hasParameterChange(0));
    try std.testing.expect(!context.hasParameterChange(99));
    try std.testing.expect(context.hasParameterChangeAtOffset(1));
    try std.testing.expect(!context.hasParameterChangeAtOffset(2));
    try std.testing.expect(context.hasParameterChangeForIdAtOffset(0, 3));
    try std.testing.expect(!context.hasParameterChangeForIdAtOffset(99, 3));
    try std.testing.expect(!context.parameterChangesForIdEmpty(0));
    try std.testing.expect(context.parameterChangesForIdEmpty(99));
    try std.testing.expect(!context.parameterChangesAtOffsetEmpty(1));
    try std.testing.expect(context.parameterChangesAtOffsetEmpty(2));
    try std.testing.expect(context.onlyParameterChangesForId(0));
    try std.testing.expect(!context.onlyParameterChangesAtOffset(1));
    try std.testing.expect(!context.onlyParameterChangesForIdAtOffset(0, 1));
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterChangeAtOrBefore(0, 2).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.25), context.latestParameterNormalizedAtOrBefore(0, 4));
    try std.testing.expectEqual(@as(f64, 1.0), context.parameterNormalizedAtOrBeforeOr(0, 0, 1.0));
    try std.testing.expectEqual(@as(f64, 0.5), context.parameterNormalizedAtOrBeforeOr(0, 2, 1.0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextParameterChangeOffset(0));
    try std.testing.expectEqual(@as(?usize, 3), context.nextParameterChangeOffsetForId(0, 1));
    const first_segment = context.parameterSegmentAt(0, 0, 1.0).?;
    try std.testing.expectEqual(
        plug.process.ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 1.0 },
        first_segment,
    );
    try std.testing.expectEqual(@as(usize, 1), first_segment.frameCount());
    try std.testing.expect(!first_segment.isEmpty());
    try std.testing.expect(first_segment.contains(0));
    try std.testing.expect(!first_segment.contains(1));
    try std.testing.expect(first_segment.startsAt(0));
    try std.testing.expect(first_segment.endsAt(1));
    try std.testing.expectEqual(
        plug.process.ParameterSegment{ .start_offset = 1, .end_offset = 3, .normalized = 0.5 },
        context.parameterSegmentAt(0, 1, 1.0).?,
    );
    try std.testing.expectEqual(
        plug.process.ParameterSegment{ .start_offset = 3, .end_offset = 5, .normalized = 0.25 },
        context.parameterSegmentAt(0, 3, 1.0).?,
    );
    var parameter_segments = context.parameterSegments(0, 1.0);
    try std.testing.expectEqual(
        plug.process.ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 1.0 },
        parameter_segments.next().?,
    );
    try std.testing.expectEqual(
        plug.process.ParameterSegment{ .start_offset = 1, .end_offset = 3, .normalized = 0.5 },
        parameter_segments.next().?,
    );
    try std.testing.expectEqual(
        plug.process.ParameterSegment{ .start_offset = 3, .end_offset = 5, .normalized = 0.25 },
        parameter_segments.next().?,
    );
    try std.testing.expectEqual(@as(?plug.process.ParameterSegment, null), parameter_segments.next());
    var block_segments = context.parameterBlockSegments();
    const first_block_segment = block_segments.next().?;
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 0, .end_offset = 1 }, first_block_segment);
    try std.testing.expectEqual(@as(usize, 1), first_block_segment.frameCount());
    try std.testing.expect(!first_block_segment.isEmpty());
    try std.testing.expect(first_block_segment.contains(0));
    try std.testing.expect(!first_block_segment.contains(1));
    try std.testing.expect(first_block_segment.startsAt(0));
    try std.testing.expect(first_block_segment.endsAt(1));
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 1, .end_offset = 3 }, block_segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 3, .end_offset = 5 }, block_segments.next().?);
    try std.testing.expectEqual(@as(?plug.process.BlockSegment, null), block_segments.next());
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
    try std.testing.expectEqual(@as(f64, 1.0), instance.parameterFieldDefaultPlain("gain"));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterFieldPlainMinimum("gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterFieldPlainMaximum("gain"));
    try std.testing.expect(instance.parameterFieldHasPlainRange("gain"));

    try std.testing.expectEqualStrings("0.500", try instance.formatParameterFieldPlain("gain", 0.5, &buffer));
    try std.testing.expectEqual(@as(f64, 0.25), try instance.parseParameterFieldPlain("gain", "0.25"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.parameterFieldPlainFromNormalized("gain", 0.75));
    try std.testing.expectEqual(@as(f64, 0.25), instance.parameterFieldNormalizedFromPlain("gain", 0.25));
    try std.testing.expect(instance.storeParameterPlainByName("Gain", 0.5));
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameter("gain"));
}

test "gain core example stores and resets float parameters by lookup" {
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(?f64, 1.0), instance.loadParameterIndex(0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.loadParameterPlainIndex(0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.loadParameterById(0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.loadParameterPlainById(0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.loadParameterByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.loadParameterPlainByName("Gain"));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterIndex(99));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterByName("Missing"));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsDefaultIndex(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsDefaultById(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsDefaultByName("Gain"));
    try std.testing.expect(instance.parameterIsDefault("gain"));

    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterIndexCount(0, 0.5));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterByIdCount(0, 0.5));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainByIdCount(0, 0.25));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterByNameCount("Gain", 0.75));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainByNameCount("Gain", 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterIndexCount(99, 0.5));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterByIdCount(99, 0.5));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainByNameCount("Missing", 0.5));
    try std.testing.expect(instance.parametersAllDefaults());

    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainIndexCount(0, 0.5));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsDefaultByName("Gain"));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterIndexToDefaultCount(0));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterToDefaultIndexCount(0));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterByIdCount(0, 0.5));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterByIdToDefaultCount(0));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterByNameCount("Gain", 0.5));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterToDefaultByNameCount("Gain"));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterIndexToDefaultCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterByIdToDefaultCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterToDefaultByNameCount("Missing"));
    try std.testing.expect(!instance.resetParameterToDefaultIndex(99));
    try std.testing.expect(!instance.resetParameterToDefaultById(99));
    try std.testing.expect(!instance.resetParameterToDefaultByName("Missing"));
}

test "gain core example applies reflected parameter changes directly" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const raw_changes = [_]plug.process.ParameterChange{
        instance.parameterChange("gain", 0, 0.5),
    };
    const changes = try plug.process.ParameterChanges.init(&raw_changes, 1);

    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesChangedCount(changes));
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesCount(changes));
    try std.testing.expectEqual(@as(usize, 0), instance.applyParameterChangesChangedCount(changes));

    try std.testing.expect(instance.resetParameterToDefault("gain"));
    instance.applyParameterChanges(changes);
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("gain"));
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
    var exponential = plug.parameters.ExponentialSmoother.init(0.0, 0.5);
    var logarithmic = plug.parameters.LogSmoother.init(0.25);

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

    exponential.setTarget(1.0);
    try std.testing.expectApproxEqAbs(0.5, exponential.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.75, exponential.next(), 0.000001);
    exponential.setCoefficient(2.0);
    try std.testing.expectApproxEqAbs(1.0, exponential.coefficientValue(), 0.000001);
    exponential.reset(0.25);
    try std.testing.expectApproxEqAbs(0.25, exponential.currentValue(), 0.000001);
    try std.testing.expect(exponential.atTarget(0.0));

    logarithmic.setTarget(1.0, 2);
    try std.testing.expect(logarithmic.active());
    try std.testing.expectApproxEqAbs(0.5, logarithmic.next(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, logarithmic.next(), 0.000001);
    try std.testing.expect(logarithmic.finished());
}

test "gain core example uses normalized and modulated parameter values" {
    var normalized = plug.parameters.NormalizedValue.init(2.0);
    var modulated = plug.parameters.ModulatedValue.init(0.5);

    try std.testing.expectEqual(@as(f64, 1.0), normalized.load());
    normalized.store(std.math.nan(f64));
    try std.testing.expectEqual(@as(f64, 0.0), normalized.load());

    try std.testing.expectEqual(@as(f64, 0.5), modulated.loadBase());
    try std.testing.expectEqual(@as(f64, 0.0), modulated.loadModulation());
    modulated.storeBase(0.25);
    modulated.storeModulation(0.5);
    try std.testing.expectEqual(@as(f64, 0.25), modulated.loadBase());
    try std.testing.expectEqual(@as(f64, 0.5), modulated.loadModulation());
    try std.testing.expectEqual(@as(f64, 0.75), modulated.load());
}

test "gain core example round-trips parameter state" {
    var instance = try Instance.init(std.testing.allocator, .{});
    var restored = try Instance.init(std.testing.allocator, .{});
    var bytes: [plug.state.encodedSize(Gain.Params)]u8 = undefined;

    try std.testing.expect(instance.storeParameterNormalized("gain", 0.25));
    try std.testing.expectEqual(@as(usize, plug.state.encodedSize(Gain.Params)), instance.encodedParameterStateSize());
    try std.testing.expectEqual(@as(usize, plug.state.encodedSize(Gain.Params)), instance.parameterStateEncodedSize());
    try std.testing.expectEqual(@as(usize, 1), instance.parameterStateEntryCount());

    var out_stream = std.io.fixedBufferStream(&bytes);
    try instance.writeParameterState(out_stream.writer());

    var header_stream = std.io.fixedBufferStream(&bytes);
    const header = try restored.readParameterStateHeader(header_stream.reader());
    const empty_header = plug.state.ParameterStateHeader{ .version = plug.state.format_version, .entry_count = 0 };
    const newer_header = plug.state.ParameterStateHeader{ .version = plug.state.format_version, .entry_count = 2 };

    try std.testing.expect(header.isCurrentVersion());
    try std.testing.expect(restored.parameterStateHeaderMatchesEntryCount(header));
    try std.testing.expect(!restored.parameterStateHeaderHasFewerEntries(header));
    try std.testing.expect(!restored.parameterStateHeaderHasMoreEntries(header));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateHeaderMissingEntryCount(header));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateHeaderExtraEntryCount(header));
    try std.testing.expect(!restored.parameterStateHeaderMatchesEntryCount(empty_header));
    try std.testing.expect(restored.parameterStateHeaderHasFewerEntries(empty_header));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateHeaderMissingEntryCount(empty_header));
    try std.testing.expect(!restored.parameterStateHeaderMatchesEntryCount(newer_header));
    try std.testing.expect(restored.parameterStateHeaderHasMoreEntries(newer_header));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateHeaderExtraEntryCount(newer_header));

    var in_stream = std.io.fixedBufferStream(&bytes);
    const report = try restored.readParameterStateReport(in_stream.reader());
    const empty_report = plug.state.ReadParameterStateReport{ .entry_count = 0, .restored_count = 0, .ignored_count = 0 };
    const newer_report = plug.state.ReadParameterStateReport{ .entry_count = 2, .restored_count = 1, .ignored_count = 1 };

    try std.testing.expectEqual(@as(usize, 1), report.decodedCount());
    try std.testing.expectEqual(@as(usize, 1), report.restoredCount());
    try std.testing.expectEqual(@as(usize, 0), report.ignoredCount());
    try std.testing.expect(restored.parameterStateReportMatchesDecodedCount(report));
    try std.testing.expect(restored.parameterStateReportMatchesRestoredCount(report));
    try std.testing.expect(!restored.parameterStateReportHasFewerDecodedEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasMoreDecodedEntries(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingDecodedEntryCount(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraDecodedEntryCount(report));
    try std.testing.expect(restored.parameterStateReportHasFewerDecodedEntries(empty_report));
    try std.testing.expect(restored.parameterStateReportHasFewerRestoredEntries(empty_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportMissingDecodedEntryCount(empty_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportMissingRestoredEntryCount(empty_report));
    try std.testing.expect(restored.parameterStateReportHasMoreDecodedEntries(newer_report));
    try std.testing.expect(restored.parameterStateReportMatchesRestoredCount(newer_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportExtraDecodedEntryCount(newer_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraRestoredEntryCount(newer_report));
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
