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

const LifecycleProbe = struct {
    pub const name = "zig-vst3-plugin Lifecycle Probe";
    pub const vendor = "zig-vst3";
    pub const audio_input = false;
    pub const Params = struct {
        level: plug.parameters.FloatParam = .{ .id = 0, .name = "Level", .min = 0.0, .max = 1.0, .default = 0.5 },
    };

    prepared_sample_rate: f64 = 0.0,
    prepared_max_block_size: u32 = 0,
    processed64: bool = false,
    deinitialized: bool = false,

    pub fn prepare(self: *LifecycleProbe, config: plug.plugin.PrepareConfig) void {
        self.prepared_sample_rate = config.sample_rate;
        self.prepared_max_block_size = config.max_block_size;
    }

    pub fn process64WithParameterView(
        self: *LifecycleProbe,
        context: *plug.process.ProcessContext(f64),
        params: plug.parameters.ParameterView(Params),
    ) void {
        self.processed64 = true;
        const level = params.load("level");
        for (0..context.outputChannelCount()) |channel| {
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = level;
            }
        }
    }

    pub fn deinit(self: *LifecycleProbe) void {
        self.deinitialized = true;
    }
};

test "gain core example declares reflected metadata" {
    const spec = Spec.init(.{});
    var instance = try Instance.init(std.testing.allocator, .{});
    const CustomMetadata = struct {
        pub const name = "zig-vst3-plugin Custom Metadata";
        pub const vendor = "zig-vst3";
        pub const url = "https://example.test/zig-vst3-plugin";
        pub const email = "plugins@example.test";
        pub const component_class_name = "Custom Metadata Processor";
        pub const controller_class_name = "Custom Metadata Controller";
        pub const component_category = "Custom Processor Category";
        pub const controller_category = "Custom Controller Category";
        pub const Params = Gain.Params;
    };
    const CustomSpec = plug.plugin.PluginSpec(CustomMetadata);
    _ = try CustomSpec.initChecked(.{});

    try std.testing.expectEqualStrings("zig-vst3-plugin Core Gain", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqualStrings("", Spec.url);
    try std.testing.expectEqualStrings("", Spec.email);
    try std.testing.expectEqualStrings("zig-vst3-plugin Core Gain", Spec.component_class_name);
    try std.testing.expectEqualStrings("zig-vst3-plugin Core Gain Controller", Spec.controller_class_name);
    try std.testing.expectEqualStrings("Audio Module Class", Spec.component_category);
    try std.testing.expectEqualStrings("Component Controller Class", Spec.controller_category);
    try std.testing.expect(Spec.audio_input);
    try std.testing.expect(Spec.audio_output);
    try std.testing.expect(Spec.event_input);
    try std.testing.expect(!Spec.event_output);
    try std.testing.expectEqualStrings("https://example.test/zig-vst3-plugin", CustomSpec.url);
    try std.testing.expectEqualStrings("plugins@example.test", CustomSpec.email);
    try std.testing.expectEqualStrings("Custom Metadata Processor", CustomSpec.component_class_name);
    try std.testing.expectEqualStrings("Custom Metadata Controller", CustomSpec.controller_class_name);
    try std.testing.expectEqualStrings("Custom Processor Category", CustomSpec.component_category);
    try std.testing.expectEqualStrings("Custom Controller Category", CustomSpec.controller_category);
    try std.testing.expect(CustomSpec.audio_input);
    try std.testing.expect(CustomSpec.audio_output);
    try std.testing.expect(CustomSpec.event_input);
    try std.testing.expect(!CustomSpec.event_output);
    try std.testing.expectEqualStrings("zig-vst3-plugin Core Gain", instance.pluginName());
    try std.testing.expectEqualStrings("zig-vst3", instance.pluginVendor());
    try std.testing.expectEqualStrings("", instance.pluginUrl());
    try std.testing.expectEqualStrings("", instance.pluginEmail());
    try std.testing.expectEqualStrings("zig-vst3-plugin Core Gain", instance.componentClassName());
    try std.testing.expectEqualStrings("zig-vst3-plugin Core Gain Controller", instance.controllerClassName());
    try std.testing.expectEqualStrings("Audio Module Class", instance.componentCategory());
    try std.testing.expectEqualStrings("Component Controller Class", instance.controllerCategory());
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
    const units = Spec.Units{};
    try parameter_set.validateUniqueIds();
    try parameter_set.validateUniqueNames();
    try parameter_set.validateDescriptors();
    try parameter_set.validate();
    try parameter_set.validateUnitIds(units);
    try instance.validateUniqueParameterIds();
    try instance.validateUniqueParameterNames();
    try instance.validateParameterDescriptors();
    try instance.validateParameters();
    try instance.validateParameterUnitIds();
    try instance.validateUnits();
    try instance.validateProgramLists();
    try instance.validateUnitSet();
    try instance.validateProgramParameterIds();
    try std.testing.expectEqual(@as(usize, 1), parameter_set.parameterCount());
    try std.testing.expect(!parameter_set.parametersEmpty());
    try std.testing.expect(parameter_set.hasParameters());
    try std.testing.expectEqual(@as(?u32, 0), parameter_set.id(0));
    try std.testing.expectEqualStrings("Gain", parameter_set.name(0).?);
    try std.testing.expectEqualStrings("Gain", parameter_set.nameById(0).?);
    try std.testing.expectEqual(@as(?u32, 0), parameter_set.idByName("Gain"));
    try std.testing.expectEqualStrings("Gain", parameter_set.shortName(0).?);
    try std.testing.expectEqualStrings("Gain", parameter_set.shortNameById(0).?);
    try std.testing.expectEqualStrings("Gain", parameter_set.shortNameByName("Gain").?);
    try std.testing.expectEqualStrings("x", parameter_set.units(0).?);
    try std.testing.expectEqualStrings("x", parameter_set.unitsById(0).?);
    try std.testing.expectEqualStrings("x", parameter_set.unitsByName("Gain").?);
    try std.testing.expectEqual(@as(?f64, 1.0), parameter_set.defaultNormalized(0));
    try std.testing.expectEqual(@as(?f64, 1.0), parameter_set.defaultNormalizedById(0));
    try std.testing.expectEqual(@as(?f64, 1.0), parameter_set.defaultNormalizedByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), parameter_set.defaultPlain(0));
    try std.testing.expectEqual(@as(?f64, 1.0), parameter_set.defaultPlainById(0));
    try std.testing.expectEqual(@as(?f64, 1.0), parameter_set.defaultPlainByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 0.0), parameter_set.plainMinimum(0));
    try std.testing.expectEqual(@as(?f64, 0.0), parameter_set.plainMinimumById(0));
    try std.testing.expectEqual(@as(?f64, 0.0), parameter_set.plainMinimumByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), parameter_set.plainMaximum(0));
    try std.testing.expectEqual(@as(?f64, 1.0), parameter_set.plainMaximumById(0));
    try std.testing.expectEqual(@as(?f64, 1.0), parameter_set.plainMaximumByName("Gain"));
    try std.testing.expect(parameter_set.hasPlainRange(0));
    try std.testing.expect(parameter_set.hasPlainRangeById(0));
    try std.testing.expect(parameter_set.hasPlainRangeByName("Gain"));
    try std.testing.expect(!parameter_set.hasPlainRangeByName("Missing"));
    try std.testing.expectEqual(@as(?bool, false), parameter_set.isBypass(0));
    try std.testing.expectEqual(@as(?bool, false), parameter_set.isBypassById(0));
    try std.testing.expectEqual(@as(?bool, true), parameter_set.canAutomate(0));
    try std.testing.expectEqual(@as(?bool, true), parameter_set.canAutomateById(0));
    try std.testing.expectEqual(@as(?bool, false), parameter_set.isReadOnlyByName("Gain"));
    try std.testing.expectEqual(@as(?i32, plug.units.root_unit_id), parameter_set.unitId(0));
    try std.testing.expectEqual(@as(?i32, plug.units.root_unit_id), parameter_set.unitIdById(0));
    try std.testing.expectEqual(@as(?i32, plug.units.root_unit_id), parameter_set.unitIdByName("Gain"));
    try std.testing.expectEqual(@as(?i32, 0), parameter_set.stepCount(0));
    try std.testing.expectEqual(@as(?i32, 0), parameter_set.stepCountById(0));
    try std.testing.expectEqual(@as(?i32, 0), parameter_set.stepCountByName("Gain"));
    try std.testing.expectEqual(@as(?bool, false), parameter_set.isList(0));
    try std.testing.expectEqual(@as(?bool, false), parameter_set.isListById(0));
    try std.testing.expectEqual(@as(?bool, false), parameter_set.isListByName("Gain"));
    try std.testing.expectEqual(@as(?u32, 0), instance.parameterId(0));
    try std.testing.expectEqualStrings("Gain", instance.parameterName(0).?);
    try std.testing.expectEqualStrings("Gain", instance.parameterNameById(0).?);
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
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsBypass(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsBypassById(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterCanAutomate(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterCanAutomateById(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsReadOnly(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsReadOnlyById(0));
    try std.testing.expectEqual(@as(?i32, plug.units.root_unit_id), instance.parameterUnitId(0));
    try std.testing.expectEqual(@as(?i32, plug.units.root_unit_id), instance.parameterUnitIdById(0));
    try std.testing.expectEqual(@as(?i32, 0), instance.parameterStepCount(0));
    try std.testing.expectEqual(@as(?i32, 0), instance.parameterStepCountById(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsList(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsListById(0));
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

test "gain core example drives lifecycle hook variants" {
    const ProbeInstance = plug.plugin.PluginInstance(LifecycleProbe);
    var instance = try ProbeInstance.init(std.testing.allocator, .{});
    var output = [_]f64{ 0.0, 0.0 };
    const input_channels = [_][]const f64{};
    const output_channels = [_][]f64{&output};
    var context = try plug.process.ProcessContext(f64).init(48_000.0, &input_channels, &output_channels);

    try std.testing.expect(instance.hasPrepareHook());
    try std.testing.expect(instance.hasProcess64Hook());
    try std.testing.expect(instance.hasDeinitHook());
    instance.prepare(.{ .sample_rate = 96_000.0, .max_block_size = 128 });
    try std.testing.expectEqual(@as(f64, 96_000.0), instance.plugin.prepared_sample_rate);
    try std.testing.expectEqual(@as(u32, 128), instance.plugin.prepared_max_block_size);

    instance.process64(&context);
    try std.testing.expect(instance.plugin.processed64);
    try std.testing.expectEqual(@as(f64, 0.5), output[0]);
    try std.testing.expectEqual(@as(f64, 0.5), output[1]);

    instance.deinit();
    try std.testing.expect(instance.plugin.deinitialized);
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
    const context_inputs = context.inputAudio();
    const context_outputs = context.outputAudio();
    try std.testing.expectEqual(@as(usize, 1), context_inputs.channelCount());
    try std.testing.expectEqual(@as(usize, 1), context_outputs.channelCount());
    try std.testing.expectEqual(@as(usize, 3), context.inputFrameCount());
    try std.testing.expectEqual(@as(usize, 3), context.outputFrameCount());
    try std.testing.expectEqual(@as(usize, 3), context.frameCount());
    try std.testing.expectEqual(@as(f64, 48_000.0), context.sampleRate());
    try std.testing.expectEqual(@as(f64, 1.0 / 48_000.0), context.sampleDurationSeconds());
    try std.testing.expectEqual(@as(f64, 3.0 / 48_000.0), context.blockDurationSeconds());
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 0, .end_offset = 3 }, context.blockSegment());
    try std.testing.expect(context.containsSampleOffset(2));
    try std.testing.expect(!context.containsSampleOffset(3));
    try std.testing.expect(context.isEndOffset(3));
    try std.testing.expect(!context.isEndOffset(2));
    try std.testing.expect(context.isPastEndOffset(4));
    try std.testing.expect(!context.isPastEndOffset(3));
    try std.testing.expectEqual(@as(f64, 2.0 / 48_000.0), context.sampleOffsetSeconds(2));
    try std.testing.expectEqual(@as(usize, 1), context.remainingFramesFromOffset(2));
    try std.testing.expectEqual(@as(usize, 0), context.remainingFramesFromOffset(3));
    try std.testing.expectEqual(@as(f64, 1.0 / 48_000.0), context.remainingSecondsFromOffset(2));
    try std.testing.expectEqual(@as(f64, 0.0), context.remainingSecondsFromOffset(3));
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
    try std.testing.expectEqual(@as(f32, 0.25), context_inputs.channel(0).?[0]);
    try std.testing.expectEqual(@as(?f32, 0.5), context.inputSample(0, 1));
    try std.testing.expectEqual(@as(?f32, 0.5), context_inputs.sample(0, 1));
    try std.testing.expectEqual(@as(?f32, null), context.inputSample(0, 3));
    try std.testing.expectEqual(@as(?[]const f32, null), context.inputChannel(1));
    try std.testing.expectEqual(@as(f32, 0.0), context.outputChannel(0).?[0]);
    try std.testing.expectEqual(@as(f32, 0.0), context_outputs.channel(0).?[0]);
    try std.testing.expectEqual(@as(?f32, 0.0), context.outputSample(0, 1));
    try std.testing.expect(context.setOutputSample(0, 1, 0.5));
    try std.testing.expectEqual(@as(?f32, 0.5), context.outputSample(0, 1));
    try std.testing.expectEqual(@as(?f32, 0.5), context_outputs.sample(0, 1));
    try std.testing.expect(!context.setOutputSample(0, 3, 0.5));
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
    try std.testing.expectEqual(@as(?f32, 0.5), inputs.sample(1, 1));
    try std.testing.expectEqual(@as(?f32, null), inputs.sample(1, 3));
    try std.testing.expectEqual(@as(?f32, null), inputs.sample(2, 0));
    try std.testing.expectEqual(@as(?[]const f32, null), inputs.channel(2));
    try std.testing.expect(!inputs.hasChannel(2));
    try std.testing.expect(inputs.channelEmpty(2));
    const empty_inputs = try plug.process.AudioInputs(f32).init(&[_][]const f32{});
    try std.testing.expectEqual(@as(usize, 0), empty_inputs.channelCount());
    try std.testing.expect(empty_inputs.isEmpty());
    try std.testing.expect(!empty_inputs.hasChannels());
    try std.testing.expectEqual(@as(usize, 0), empty_inputs.frameCount());
    try std.testing.expectEqual(@as(?[]const f32, null), empty_inputs.channel(0));
    try std.testing.expect(!empty_inputs.hasChannel(0));
    try std.testing.expect(empty_inputs.channelEmpty(0));
    try std.testing.expectError(error.MismatchedFrameCount, plug.process.AudioInputs(f32).init(&mismatched_input_channels));

    const outputs = try plug.process.AudioOutputs(f32).init(&output_channels);
    try std.testing.expectEqual(@as(usize, 2), outputs.channelCount());
    try std.testing.expect(!outputs.isEmpty());
    try std.testing.expect(outputs.hasChannels());
    try std.testing.expectEqual(@as(usize, 3), outputs.frameCount());
    try std.testing.expect(outputs.hasChannel(1));
    try std.testing.expect(!outputs.channelEmpty(1));
    try std.testing.expectEqual(@as(f32, 0.0), outputs.channel(1).?[0]);
    try std.testing.expectEqual(@as(?f32, 0.0), outputs.sample(1, 1));
    try std.testing.expect(outputs.setSample(1, 1, 0.75));
    try std.testing.expectEqual(@as(?f32, 0.75), outputs.sample(1, 1));
    try std.testing.expectEqual(@as(f32, 0.75), out_right[1]);
    try std.testing.expect(!outputs.setSample(1, 3, 0.5));
    try std.testing.expect(!outputs.setSample(2, 0, 0.5));
    try std.testing.expectEqual(@as(?[]f32, null), outputs.channel(2));
    try std.testing.expect(!outputs.hasChannel(2));
    try std.testing.expect(outputs.channelEmpty(2));
    const empty_outputs = try plug.process.AudioOutputs(f32).init(&[_][]f32{});
    try std.testing.expectEqual(@as(usize, 0), empty_outputs.channelCount());
    try std.testing.expect(empty_outputs.isEmpty());
    try std.testing.expect(!empty_outputs.hasChannels());
    try std.testing.expectEqual(@as(usize, 0), empty_outputs.frameCount());
    try std.testing.expectEqual(@as(?[]f32, null), empty_outputs.channel(0));
    try std.testing.expect(!empty_outputs.hasChannel(0));
    try std.testing.expect(empty_outputs.channelEmpty(0));
    empty_outputs.fill(0.5);
    empty_outputs.clear();
    outputs.fill(0.25);
    try std.testing.expectEqual(@as(f32, 0.25), out_left[0]);
    try std.testing.expectEqual(@as(f32, 0.25), out_right[2]);
    outputs.clear();
    try std.testing.expectEqual(@as(f32, 0.0), out_left[0]);
    try std.testing.expectEqual(@as(f32, 0.0), out_right[2]);
    try std.testing.expectError(error.MismatchedFrameCount, plug.process.AudioOutputs(f32).init(&mismatched_output_channels));
}

test "gain core example can inspect parameter change views" {
    const changes = [_]plug.process.ParameterChange{
        parameter_set.parameterChange("gain", 1, 0.5),
        parameter_set.parameterChange("gain", 3, 0.25),
    };
    const view = try plug.process.ParameterChanges.init(&changes, 5);

    try std.testing.expectEqual(@as(usize, 2), view.changeCount());
    try std.testing.expect(!view.isEmpty());
    try std.testing.expect(view.hasChanges());
    try std.testing.expectEqual(@as(?usize, 1), view.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffset());
    try std.testing.expectEqual(changes[0], view.firstChange().?);
    try std.testing.expectEqual(changes[1], view.latestChange().?);
    try std.testing.expectEqual(@as(?usize, 1), view.firstSampleOffsetForId(0));
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffsetForId(0));
    try std.testing.expectEqual(@as(?usize, null), view.firstSampleOffsetForId(99));
    try std.testing.expectEqual(@as(?usize, 1), view.nextSampleOffset(0));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffset(3));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffsetForId(0, 1));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForId(99, 1));
    try std.testing.expectEqual(plug.process.ParameterChange{
        .id = 0,
        .sample_offset = 4,
        .normalized = 0.75,
    }, parameter_set.parameterChangeNormalized("gain", 4, 0.75));
    try std.testing.expectEqual(changes[0], view.first(0).?);
    try std.testing.expectEqual(changes[1], view.latest(0).?);
    try std.testing.expectEqual(changes[0], view.firstAtOffset(1).?);
    try std.testing.expectEqual(changes[1], view.latestAtOffset(3).?);
    try std.testing.expectEqual(changes[1], view.firstForIdAtOffset(0, 3).?);
    try std.testing.expectEqual(changes[1], view.latestForIdAtOffset(0, 3).?);
    try std.testing.expectEqual(@as(?plug.process.ParameterChange, null), view.firstAtOffset(2));
    try std.testing.expectEqual(@as(?plug.process.ParameterChange, null), view.firstForIdAtOffset(99, 3));
    try std.testing.expectEqual(@as(usize, 2), view.count(0));
    try std.testing.expectEqual(@as(usize, 1), view.countAtOffset(1));
    try std.testing.expectEqual(@as(usize, 1), view.countForIdAtOffset(0, 3));
    try std.testing.expect(view.has(0));
    try std.testing.expect(!view.has(99));
    try std.testing.expect(view.hasAtOffset(1));
    try std.testing.expect(!view.hasAtOffset(2));
    try std.testing.expect(view.hasForIdAtOffset(0, 3));
    try std.testing.expect(!view.hasForIdAtOffset(99, 3));
    try std.testing.expect(!view.empty(0));
    try std.testing.expect(view.empty(99));
    try std.testing.expect(!view.offsetEmpty(1));
    try std.testing.expect(view.offsetEmpty(2));
    try std.testing.expect(!view.idAtOffsetEmpty(0, 3));
    try std.testing.expect(view.idAtOffsetEmpty(99, 3));
    try std.testing.expect(view.only(0));
    try std.testing.expect(!view.onlyAtOffset(1));
    try std.testing.expect(!view.onlyForIdAtOffset(0, 1));

    const same_offset_changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 2, .normalized = 0.5 },
        .{ .id = 1, .sample_offset = 2, .normalized = 0.25 },
    };
    const same_offset = try plug.process.ParameterChanges.init(&same_offset_changes, 5);
    try std.testing.expect(same_offset.onlyAtOffset(2));
    try std.testing.expect(!same_offset.only(0));

    const same_id_offset_changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 2, .normalized = 0.5 },
        .{ .id = 0, .sample_offset = 2, .normalized = 0.25 },
    };
    const same_id_offset = try plug.process.ParameterChanges.init(&same_id_offset_changes, 5);
    try std.testing.expect(same_id_offset.onlyForIdAtOffset(0, 2));

    const outside_block = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 5, .normalized = 0.5 },
    };
    const outside_range = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 1, .normalized = 1.5 },
    };
    try std.testing.expectError(error.ParameterChangeOutsideBlock, plug.process.ParameterChanges.init(&outside_block, 5));
    try std.testing.expectError(error.ParameterChangeOutsideNormalizedRange, plug.process.ParameterChanges.init(&outside_range, 5));
}

test "gain core example validates process context attachments" {
    const input = [_]f32{0.25};
    var output = [_]f32{0.0};
    var long_output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const long_output_channels = [_][]f32{&long_output};

    try std.testing.expectError(error.InvalidSampleRate, plug.process.ProcessContext(f32).init(0.0, &input_channels, &output_channels));
    try std.testing.expectError(error.InvalidSampleRate, plug.process.ProcessContext(f32).init(std.math.nan(f64), &input_channels, &output_channels));
    try std.testing.expectError(error.MismatchedFrameCount, plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &long_output_channels));

    const outside_block_changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 1, .normalized = 0.5 },
    };
    const outside_range_changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = std.math.inf(f64) },
    };
    const outside_block_events = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 60, 0.75),
    };
    var context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);

    const valid_changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.5 },
    };
    const valid_events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
    };
    try context.setParameterChanges(&valid_changes);
    try std.testing.expectEqual(@as(usize, 1), context.parameterChangeCount());
    try context.setEvents(&valid_events);
    try std.testing.expectEqual(@as(usize, 1), context.inputEventCount());
    try context.setParameterChanges(&.{});
    try context.setEvents(&.{});
    try std.testing.expect(context.parameterChangesEmpty());
    try std.testing.expect(context.inputEventsEmpty());

    try std.testing.expectError(error.ParameterChangeOutsideBlock, context.setParameterChanges(&outside_block_changes));
    try std.testing.expectError(error.ParameterChangeOutsideNormalizedRange, context.setParameterChanges(&outside_range_changes));
    try std.testing.expectError(error.EventOutsideBlock, context.setEvents(&outside_block_events));
    try std.testing.expectError(error.ParameterChangeOutsideBlock, plug.process.ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .parameter_changes = &outside_block_changes },
    ));
    try std.testing.expectError(error.EventOutsideBlock, plug.process.ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .events = &outside_block_events },
    ));

    var output_event_storage: [1]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input.len);
    try context.setOutputEvents(&output_events);
    try std.testing.expect(context.hasOutputEventWriter());
    try std.testing.expect(context.outputEventWriter().? == &output_events);
    try std.testing.expectEqual(@as(usize, input.len), context.outputEventFrameCount());
    var mismatched_writer = plug.process.EventWriter.init(&output_event_storage, 2);
    try std.testing.expectError(error.MismatchedFrameCount, context.setOutputEvents(&mismatched_writer));
    try std.testing.expectEqual(@as(usize, input.len), context.outputEventFrameCount());
    try std.testing.expectError(error.MismatchedFrameCount, plug.process.ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .output_events = &mismatched_writer },
    ));
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
    const parameter_changes = context.parameterChanges();
    try std.testing.expectEqual(@as(usize, 2), parameter_changes.changeCount());
    try std.testing.expect(!parameter_changes.isEmpty());
    try std.testing.expect(parameter_changes.hasChanges());
    try std.testing.expectEqual(@as(?usize, 1), parameter_changes.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 3), parameter_changes.latestSampleOffset());
    try std.testing.expectEqual(@as(?usize, 1), parameter_changes.firstSampleOffsetForId(0));
    try std.testing.expectEqual(@as(?usize, 3), parameter_changes.latestSampleOffsetForId(0));
    try std.testing.expectEqual(@as(?usize, null), parameter_changes.firstSampleOffsetForId(99));
    try std.testing.expectEqual(changes[0], parameter_changes.firstChange().?);
    try std.testing.expectEqual(changes[1], parameter_changes.latestChange().?);
    try std.testing.expectEqual(changes[0], parameter_changes.first(0).?);
    try std.testing.expectEqual(changes[1], parameter_changes.latest(0).?);
    try std.testing.expectEqual(changes[0], parameter_changes.firstAtOffset(1).?);
    try std.testing.expectEqual(changes[1], parameter_changes.latestAtOffset(3).?);
    try std.testing.expectEqual(changes[1], parameter_changes.firstForIdAtOffset(0, 3).?);
    try std.testing.expectEqual(changes[1], parameter_changes.latestForIdAtOffset(0, 3).?);
    try std.testing.expectEqual(@as(usize, 2), parameter_changes.count(0));
    try std.testing.expectEqual(@as(usize, 1), parameter_changes.countAtOffset(1));
    try std.testing.expectEqual(@as(usize, 1), parameter_changes.countForIdAtOffset(0, 3));
    try std.testing.expect(parameter_changes.has(0));
    try std.testing.expect(!parameter_changes.has(99));
    try std.testing.expect(parameter_changes.hasAtOffset(1));
    try std.testing.expect(!parameter_changes.hasAtOffset(2));
    try std.testing.expect(parameter_changes.hasForIdAtOffset(0, 3));
    try std.testing.expect(parameter_changes.empty(99));
    try std.testing.expect(parameter_changes.offsetEmpty(2));
    try std.testing.expect(parameter_changes.idAtOffsetEmpty(99, 3));
    try std.testing.expect(parameter_changes.only(0));
    try std.testing.expect(!parameter_changes.onlyAtOffset(1));
    try std.testing.expect(!parameter_changes.onlyForIdAtOffset(0, 1));
    try std.testing.expectEqual(@as(?f64, 0.5), parameter_changes.firstAnyNormalized());
    try std.testing.expectEqual(@as(?f64, 0.25), parameter_changes.latestAnyNormalized());
    try std.testing.expectEqual(@as(f64, 0.5), parameter_changes.firstAnyNormalizedOr(1.0));
    try std.testing.expectEqual(@as(f64, 0.25), parameter_changes.latestAnyNormalizedOr(1.0));
    try std.testing.expectEqual(@as(?f64, 0.5), parameter_changes.firstNormalized(0));
    try std.testing.expectEqual(@as(?f64, 0.25), parameter_changes.latestNormalized(0));
    try std.testing.expectEqual(@as(f64, 0.5), parameter_changes.firstNormalizedOr(0, 1.0));
    try std.testing.expectEqual(@as(f64, 0.25), parameter_changes.latestNormalizedOr(0, 1.0));
    try std.testing.expectEqual(@as(?f64, 0.5), parameter_changes.firstNormalizedAtOffset(1));
    try std.testing.expectEqual(@as(?f64, 0.25), parameter_changes.latestNormalizedAtOffset(3));
    try std.testing.expectEqual(@as(f64, 0.5), parameter_changes.firstNormalizedAtOffsetOr(1, 1.0));
    try std.testing.expectEqual(@as(f64, 0.75), parameter_changes.firstNormalizedAtOffsetOr(2, 0.75));
    try std.testing.expectEqual(@as(f64, 0.25), parameter_changes.latestNormalizedAtOffsetOr(3, 1.0));
    try std.testing.expectEqual(@as(f64, 0.75), parameter_changes.latestNormalizedAtOffsetOr(2, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.25), parameter_changes.firstNormalizedForIdAtOffset(0, 3));
    try std.testing.expectEqual(@as(?f64, 0.25), parameter_changes.latestNormalizedForIdAtOffset(0, 3));
    try std.testing.expectEqual(@as(f64, 0.25), parameter_changes.firstNormalizedForIdAtOffsetOr(0, 3, 1.0));
    try std.testing.expectEqual(@as(f64, 0.75), parameter_changes.firstNormalizedForIdAtOffsetOr(99, 3, 0.75));
    try std.testing.expectEqual(@as(f64, 0.25), parameter_changes.latestNormalizedForIdAtOffsetOr(0, 3, 1.0));
    try std.testing.expectEqual(@as(f64, 0.75), parameter_changes.latestNormalizedForIdAtOffsetOr(99, 3, 0.75));
    try std.testing.expectEqual(changes[0], parameter_changes.latestAtOrBefore(0, 2).?);
    try std.testing.expectEqual(@as(?f64, 0.25), parameter_changes.latestNormalizedAtOrBefore(0, 4));
    try std.testing.expectEqual(@as(f64, 1.0), parameter_changes.normalizedAtOrBeforeOr(0, 0, 1.0));
    try std.testing.expectEqual(@as(f64, 0.5), parameter_changes.normalizedAtOrBeforeOr(0, 2, 1.0));
    try std.testing.expectEqual(@as(?usize, 1), parameter_changes.nextSampleOffset(0));
    try std.testing.expectEqual(@as(?usize, 3), parameter_changes.nextSampleOffsetForId(0, 1));
    var direct_id_changes = parameter_changes.forId(0);
    try std.testing.expectEqual(changes[0], direct_id_changes.next().?);
    try std.testing.expectEqual(changes[1], direct_id_changes.next().?);
    try std.testing.expectEqual(@as(?plug.process.ParameterChange, null), direct_id_changes.next());
    var direct_offset_changes = parameter_changes.atOffset(3);
    try std.testing.expectEqual(changes[1], direct_offset_changes.next().?);
    try std.testing.expectEqual(@as(?plug.process.ParameterChange, null), direct_offset_changes.next());
    var direct_id_offset_changes = parameter_changes.forIdAtOffset(0, 3);
    try std.testing.expectEqual(changes[1], direct_id_offset_changes.next().?);
    try std.testing.expectEqual(@as(?plug.process.ParameterChange, null), direct_id_offset_changes.next());
    try std.testing.expectEqual(
        plug.process.ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 1.0 },
        parameter_changes.segmentAt(0, 0, context.frameCount(), 1.0).?,
    );
    var direct_parameter_segments = parameter_changes.segments(0, context.frameCount(), 1.0);
    try std.testing.expectEqual(
        plug.process.ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 1.0 },
        direct_parameter_segments.next().?,
    );
    var direct_block_segments = parameter_changes.blockSegments(context.frameCount());
    try std.testing.expectEqual(
        plug.process.BlockSegment{ .start_offset = 0, .end_offset = 1 },
        direct_block_segments.next().?,
    );
    try std.testing.expectEqual(@as(usize, 2), context.parameterChangeCount());
    try std.testing.expect(!context.parameterChangesEmpty());
    try std.testing.expect(context.hasParameterChanges());
    try std.testing.expectEqual(changes[0], context.firstAnyParameterChange().?);
    try std.testing.expectEqual(changes[1], context.latestAnyParameterChange().?);
    try std.testing.expectEqual(@as(?usize, 1), context.firstParameterChangeOffset());
    try std.testing.expectEqual(@as(?usize, 3), context.latestParameterChangeOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.firstParameterChangeOffsetForId(0));
    try std.testing.expectEqual(@as(?usize, 3), context.latestParameterChangeOffsetForId(0));
    try std.testing.expectEqual(@as(?usize, null), context.firstParameterChangeOffsetForId(99));
    try std.testing.expectEqual(changes[0], context.firstParameterChange(0).?);
    try std.testing.expectEqual(changes[1], context.latestParameterChange(0).?);
    try std.testing.expectEqual(changes[0], context.firstParameterChangeAtOffset(1).?);
    try std.testing.expectEqual(changes[1], context.latestParameterChangeAtOffset(3).?);
    try std.testing.expectEqual(changes[1], context.firstParameterChangeForIdAtOffset(0, 3).?);
    try std.testing.expectEqual(changes[1], context.latestParameterChangeForIdAtOffset(0, 3).?);
    try std.testing.expectEqual(@as(?f64, 0.5), context.firstParameterNormalized(0));
    try std.testing.expectEqual(@as(?f64, 0.25), context.latestParameterNormalized(0));
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterNormalizedOr(0, 1.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.latestParameterNormalizedOr(0, 1.0));
    try std.testing.expectEqual(@as(f64, 0.75), context.firstParameterNormalizedOr(99, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.5), context.firstParameterNormalizedAtOffset(1));
    try std.testing.expectEqual(@as(?f64, 0.25), context.latestParameterNormalizedAtOffset(3));
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterNormalizedAtOffsetOr(1, 1.0));
    try std.testing.expectEqual(@as(f64, 0.75), context.firstParameterNormalizedAtOffsetOr(2, 0.75));
    try std.testing.expectEqual(@as(f64, 0.25), context.latestParameterNormalizedAtOffsetOr(3, 1.0));
    try std.testing.expectEqual(@as(f64, 0.75), context.latestParameterNormalizedAtOffsetOr(2, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.25), context.firstParameterNormalizedForIdAtOffset(0, 3));
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterNormalizedForIdAtOffsetOr(0, 1, 1.0));
    try std.testing.expectEqual(@as(f64, 0.75), context.firstParameterNormalizedForIdAtOffsetOr(99, 1, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.25), context.latestParameterNormalizedForIdAtOffset(0, 3));
    try std.testing.expectEqual(@as(f64, 0.25), context.latestParameterNormalizedForIdAtOffsetOr(0, 3, 1.0));
    try std.testing.expectEqual(@as(f64, 0.75), context.latestParameterNormalizedForIdAtOffsetOr(99, 3, 0.75));
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
    try std.testing.expect(!context.parameterChangesForIdAtOffsetEmpty(0, 3));
    try std.testing.expect(context.parameterChangesForIdAtOffsetEmpty(99, 3));
    try std.testing.expect(context.onlyParameterChangesForId(0));
    try std.testing.expect(!context.onlyParameterChangesAtOffset(1));
    try std.testing.expect(!context.onlyParameterChangesForIdAtOffset(0, 1));
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterChangeAtOrBefore(0, 2).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.25), context.latestParameterNormalizedAtOrBefore(0, 4));
    try std.testing.expectEqual(@as(f64, 1.0), context.parameterNormalizedAtOrBeforeOr(0, 0, 1.0));
    try std.testing.expectEqual(@as(f64, 0.5), context.parameterNormalizedAtOrBeforeOr(0, 2, 1.0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextParameterChangeOffset(0));
    try std.testing.expectEqual(@as(?usize, 3), context.nextParameterChangeOffsetForId(0, 1));
    var context_id_changes = context.parameterChangesForId(0);
    try std.testing.expectEqual(changes[0], context_id_changes.next().?);
    try std.testing.expectEqual(changes[1], context_id_changes.next().?);
    try std.testing.expectEqual(@as(?plug.process.ParameterChange, null), context_id_changes.next());
    var context_offset_changes = context.parameterChangesAtOffset(3);
    try std.testing.expectEqual(changes[1], context_offset_changes.next().?);
    try std.testing.expectEqual(@as(?plug.process.ParameterChange, null), context_offset_changes.next());
    var context_id_offset_changes = context.parameterChangesForIdAtOffset(0, 3);
    try std.testing.expectEqual(changes[1], context_id_offset_changes.next().?);
    try std.testing.expectEqual(@as(?plug.process.ParameterChange, null), context_id_offset_changes.next());
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

test "gain core example can process with reflected parameter storage" {
    const StorageGain = struct {
        pub const name = "zig-vst3-plugin Storage Gain";
        pub const vendor = "zig-vst3";
        pub const Params = Gain.Params;

        pub fn processWithParameters(
            _: *@This(),
            context: *plug.process.ProcessContext(f32),
            set: *const plug.parameters.ParameterSet(Params),
            values: *const plug.parameters.ParameterValues(Params),
        ) void {
            const gain = @as(f32, @floatCast(values.loadFieldNormalized(set, "gain")));
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                for (0..context.frameCount()) |sample| {
                    output[sample] = input[sample] * gain;
                }
            }
        }

        pub fn process64WithParameters(
            _: *@This(),
            context: *plug.process.ProcessContext(f64),
            set: *const plug.parameters.ParameterSet(Params),
            values: *const plug.parameters.ParameterValues(Params),
        ) void {
            const gain = values.loadFieldNormalized(set, "gain");
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                for (0..context.frameCount()) |sample| {
                    output[sample] = input[sample] * gain;
                }
            }
        }
    };
    const StorageInstance = plug.plugin.PluginInstance(StorageGain);
    var instance = try StorageInstance.init(std.testing.allocator, .{});
    const input32 = [_]f32{ 0.25, 0.5 };
    var output32 = [_]f32{ 0.0, 0.0 };
    const input64 = [_]f64{ 0.25, 0.5 };
    var output64 = [_]f64{ 0.0, 0.0 };
    const input_channels32 = [_][]const f32{&input32};
    const output_channels32 = [_][]f32{&output32};
    const input_channels64 = [_][]const f64{&input64};
    const output_channels64 = [_][]f64{&output64};
    const changes = [_]plug.process.ParameterChange{
        instance.parameterChange("gain", 0, 0.5),
    };
    var context32 = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels32, &output_channels32, .{
        .parameter_changes = &changes,
    });
    var context64 = try plug.process.ProcessContext(f64).init(48_000.0, &input_channels64, &output_channels64);

    try std.testing.expect(instance.hasProcessHook());
    try std.testing.expect(instance.hasProcess64Hook());
    instance.process(&context32);
    instance.process64(&context64);

    try std.testing.expectEqual(@as(f32, 0.125), output32[0]);
    try std.testing.expectEqual(@as(f32, 0.25), output32[1]);
    try std.testing.expectEqual(@as(f64, 0.125), output64[0]);
    try std.testing.expectEqual(@as(f64, 0.25), output64[1]);
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
    const descriptor = instance.parameterFieldDescriptor("gain");
    try std.testing.expectEqual(@as(u32, 0), descriptor.id);
    try std.testing.expectEqualStrings("Gain", descriptor.name);
    try std.testing.expect(descriptor.containsPlain(0.5));
    try std.testing.expect(!descriptor.containsPlain(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 0.0), descriptor.clampPlain(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 1.0), descriptor.clampPlain(2.0));
    try std.testing.expectEqual(@as(f64, 0.25), descriptor.normalize(0.25));
    try std.testing.expectEqual(@as(f64, 0.75), descriptor.denormalize(0.75));
    try std.testing.expectEqual(@as(f64, 1.0), descriptor.defaultNormalized());
    try std.testing.expectEqualStrings("50%", try descriptor.formatPercent(0.5, &buffer));
    try std.testing.expectEqualStrings("0.500", try descriptor.formatPlain(0.5, &buffer));
    try std.testing.expectEqual(@as(f64, 0.25), descriptor.plainFromNormalized(0.25));
    try std.testing.expectEqual(@as(f64, 0.25), descriptor.normalizedFromPlain(0.25));
    try std.testing.expectEqual(@as(f64, 0.25), try descriptor.parsePlain(" 0.25 "));
    try std.testing.expectEqualStrings("0.500", try parameter_set.formatFieldPlain("gain", 0.5, &buffer));
    try std.testing.expectEqual(@as(f64, 0.25), try parameter_set.parseFieldPlain("gain", "0.25"));
    try std.testing.expectEqual(@as(f64, 0.75), parameter_set.fieldPlainFromNormalized("gain", 0.75));
    try std.testing.expectEqual(@as(f64, 0.75), parameter_set.fieldNormalizedFromPlain("gain", 0.75));
    try std.testing.expectEqual(@as(?u32, null), parameter_set.duplicateId());
    try std.testing.expectEqual(@as(?usize, null), parameter_set.duplicateIdIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), parameter_set.duplicateName());
    try std.testing.expectEqual(@as(?usize, null), parameter_set.duplicateNameIndex());
    try std.testing.expect(!parameter_set.hasDuplicateIds());
    try std.testing.expect(!parameter_set.hasDuplicateNames());
    try std.testing.expectEqual(@as(?anyerror, null), parameter_set.firstDescriptorError());
    try std.testing.expectEqual(@as(?usize, null), parameter_set.firstDescriptorErrorIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), parameter_set.firstDescriptorErrorName());
    try std.testing.expectEqualStrings("0.250", try parameter_set.formatPlain(0, 0.25, &buffer));
    try std.testing.expectEqualStrings("0.250", try parameter_set.formatPlainById(0, 0.25, &buffer));
    try std.testing.expectEqualStrings("0.250", try parameter_set.formatPlainByName("Gain", 0.25, &buffer));
    try std.testing.expectEqual(@as(f64, 0.25), try parameter_set.parsePlain(0, "0.25"));
    try std.testing.expectEqual(@as(f64, 0.25), try parameter_set.parsePlainById(0, "0.25"));
    try std.testing.expectEqual(@as(f64, 0.25), try parameter_set.parsePlainByName("Gain", "0.25"));
    try std.testing.expectEqual(@as(?f64, 0.75), parameter_set.plainFromNormalized(0, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.75), parameter_set.plainFromNormalizedById(0, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.75), parameter_set.plainFromNormalizedByName("Gain", 0.75));
    try std.testing.expectEqual(@as(?f64, 0.75), parameter_set.normalizedFromPlain(0, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.75), parameter_set.normalizedFromPlainById(0, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.75), parameter_set.normalizedFromPlainByName("Gain", 0.75));
    try std.testing.expectError(error.InvalidParameterIndex, parameter_set.formatPlain(1, 0.5, &buffer));
    try std.testing.expectError(error.InvalidParameterId, parameter_set.parsePlainById(99, "0.5"));
    try std.testing.expectEqual(@as(?f64, null), parameter_set.plainFromNormalizedByName("Missing", 0.5));
    try std.testing.expectEqual(@as(u32, 0), instance.parameterFieldId("gain"));
    try std.testing.expectEqualStrings("Gain", instance.parameterFieldName("gain"));
    try std.testing.expectEqualStrings("Gain", instance.parameterFieldShortName("gain"));
    try std.testing.expectEqualStrings("x", instance.parameterFieldUnits("gain"));
    try std.testing.expectEqual(@as(f64, 1.0), instance.parameterFieldDefaultNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 1.0), instance.parameterFieldDefaultPlain("gain"));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterFieldPlainMinimum("gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterFieldPlainMaximum("gain"));
    try std.testing.expect(instance.parameterFieldHasPlainRange("gain"));
    try std.testing.expect(!instance.parameterFieldIsBypass("gain"));
    try std.testing.expect(instance.parameterFieldCanAutomate("gain"));
    try std.testing.expect(!instance.parameterFieldIsReadOnly("gain"));
    try std.testing.expectEqual(@as(i32, plug.units.root_unit_id), instance.parameterFieldUnitId("gain"));
    try std.testing.expectEqual(@as(i32, 0), instance.parameterFieldStepCount("gain"));
    try std.testing.expect(!instance.parameterFieldIsList("gain"));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterFieldOptionCount("gain"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterFieldOptionLabel("gain", 0));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterFieldOptionNormalized("gain", 0));
    try std.testing.expect(!instance.parameterFieldHasOptions("gain"));
    try std.testing.expect(instance.parameterFieldOptionsEmpty("gain"));

    try std.testing.expectEqualStrings("0.500", try instance.formatParameterFieldPlain("gain", 0.5, &buffer));
    try std.testing.expectEqual(@as(f64, 0.25), try instance.parseParameterFieldPlain("gain", "0.25"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.parameterFieldPlainFromNormalized("gain", 0.75));
    try std.testing.expectEqual(@as(f64, 0.25), instance.parameterFieldNormalizedFromPlain("gain", 0.25));
    try std.testing.expectEqualStrings("0.500", try instance.formatParameterPlainIndex(0, 0.5, &buffer));
    try std.testing.expectEqualStrings("0.250", try instance.formatParameterPlainById(0, 0.25, &buffer));
    try std.testing.expectEqual(@as(f64, 0.75), try instance.parseParameterPlainIndex(0, "0.75"));
    try std.testing.expectEqual(@as(f64, 0.25), try instance.parseParameterPlainById(0, "0.25"));
    try std.testing.expectEqual(@as(?f64, 0.75), instance.parameterPlainFromNormalizedIndex(0, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.25), instance.parameterNormalizedFromPlainIndex(0, 0.25));
    try std.testing.expectEqual(@as(?f64, 0.5), instance.parameterPlainFromNormalizedById(0, 0.5));
    try std.testing.expectEqual(@as(?f64, 0.5), instance.parameterNormalizedFromPlainById(0, 0.5));
    try std.testing.expectEqual(@as(?f64, 0.75), instance.parameterPlainFromNormalizedByName("Gain", 0.75));
    try std.testing.expectEqual(@as(?f64, 0.25), instance.parameterNormalizedFromPlainByName("Gain", 0.25));
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
    try std.testing.expect(instance.storeParameterPlainIndex(0, 0.25));
    try std.testing.expect(instance.storeParameterById(0, 0.5));
    try std.testing.expect(instance.storeParameterPlainById(0, 0.25));
    try std.testing.expect(instance.storeParameterByName("Gain", 0.75));
    try std.testing.expect(!instance.storeParameterByName("Missing", 0.5));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterIndexCount(99, 0.5));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterByIdCount(99, 0.5));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainByNameCount("Missing", 0.5));

    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainByNameCount("Gain", 1.0));
    try std.testing.expect(instance.parametersAllDefaults());
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterCount("gain", 0.5));
    try std.testing.expect(instance.storeParameter("gain", 0.25));
    try std.testing.expect(instance.storeParameterIndex(0, 0.5));
    try std.testing.expect(instance.resetParameterToDefault("gain"));
    try std.testing.expect(instance.parametersAllDefaults());
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainIndexCount(0, 0.5));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsDefaultByName("Gain"));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterIndexToDefaultCount(0));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterToDefaultIndexCount(0));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterByIdCount(0, 0.5));
    try std.testing.expect(instance.resetParameterToDefaultIndex(0));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterByIdCount(0, 0.5));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterByIdToDefaultCount(0));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterByIdCount(0, 0.5));
    try std.testing.expect(instance.resetParameterToDefaultById(0));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterByNameCount("Gain", 0.5));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterByNameToDefaultCount("Gain"));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterByNameCount("Gain", 0.5));
    try std.testing.expect(instance.resetParameterByNameToDefault("Gain"));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterByNameCount("Gain", 0.5));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterToDefaultByNameCount("Gain"));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterNormalizedCount("gain", 0.25));
    try std.testing.expectEqual(@as(usize, 1), instance.resetParametersToDefaultsCount());
    try std.testing.expectEqual(@as(usize, 0), instance.resetParametersToDefaultsCount());
    try std.testing.expect(instance.storeParameterNormalized("gain", 0.25));
    instance.resetParametersToDefaults();
    try std.testing.expect(instance.parametersAllDefaults());
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterIndexToDefaultCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterByIdToDefaultCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterToDefaultByIdCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterByNameToDefaultCount("Missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterToDefaultByNameCount("Missing"));
    try std.testing.expect(!instance.resetParameterIndexToDefault(99));
    try std.testing.expect(!instance.resetParameterToDefaultIndex(99));
    try std.testing.expect(!instance.resetParameterByIdToDefault(99));
    try std.testing.expect(!instance.resetParameterToDefaultById(99));
    try std.testing.expect(!instance.resetParameterByNameToDefault("Missing"));
    try std.testing.expect(!instance.resetParameterToDefaultByName("Missing"));
}

test "gain core example exposes bound instance parameter handles" {
    var instance = try Instance.init(std.testing.allocator, .{});

    const set = instance.parameterSet();
    try std.testing.expectEqual(@as(usize, 1), set.parameterCount());
    try std.testing.expectEqualStrings("Gain", set.name(0).?);
    try std.testing.expectEqual(@as(f64, 1.0), instance.parameterValuesConst().loadFieldNormalized(set, "gain"));

    const view = instance.parameterView();
    try view.validateUniqueIds();
    try view.validateUniqueNames();
    try view.validateDescriptors();
    try view.validate();
    try view.validateUnitIds(Spec.Units{});
    try std.testing.expectEqual(@as(f64, 1.0), view.loadNormalized("gain"));
    try std.testing.expectEqualStrings("Gain", view.fieldName("gain"));

    var editor = instance.parameterEditor();
    try editor.validateUniqueIds();
    try editor.validateUniqueNames();
    try editor.validateDescriptors();
    try editor.validate();
    try editor.validateUnitIds(Spec.Units{});
    try std.testing.expectEqual(@as(?usize, 1), editor.storeNormalizedCount("gain", 0.25));
    try std.testing.expectEqual(@as(f64, 0.25), instance.parameterValues().loadFieldNormalized(set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.25), instance.parameterValuesConst().loadFieldNormalized(set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.25), view.loadNormalized("gain"));
}

test "gain core example edits reflected parameter values directly" {
    var values = Spec.ParameterValues.init(&parameter_set);

    try std.testing.expectEqual(@as(?f64, 1.0), values.load(0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadPlain(&parameter_set, 0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadById(&parameter_set, 0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadPlainByName(&parameter_set, "Gain"));
    try std.testing.expectEqual(@as(f64, 1.0), values.loadFieldNormalized(&parameter_set, "gain"));
    try std.testing.expectEqual(@as(f64, 1.0), values.loadField(&parameter_set, "gain"));
    try std.testing.expectEqual(@as(?bool, true), values.isDefault(&parameter_set, 0));
    try std.testing.expectEqual(@as(?bool, true), values.isDefaultById(&parameter_set, 0));
    try std.testing.expect(values.fieldIsDefault(&parameter_set, "gain"));
    try std.testing.expect(values.allDefaults(&parameter_set));
    try std.testing.expect(!values.hasNonDefaults(&parameter_set));
    try std.testing.expectEqual(@as(usize, 0), values.nonDefaultCount(&parameter_set));

    try std.testing.expectEqual(@as(?usize, 1), values.storeCount(0, 0.5));
    try std.testing.expectEqual(@as(?usize, 0), values.storeCount(0, 0.5));
    try std.testing.expectEqual(@as(?usize, null), values.storeCount(99, 0.5));
    try std.testing.expectEqual(@as(?usize, null), values.storeCount(0, std.math.nan(f64)));
    try std.testing.expectEqual(@as(?usize, 1), values.storePlainCount(&parameter_set, 0, 0.25));
    try std.testing.expectEqual(@as(?usize, 1), values.storeByIdCount(&parameter_set, 0, 0.75));
    try std.testing.expectEqual(@as(?usize, 1), values.storePlainByNameCount(&parameter_set, "Gain", 0.5));
    try std.testing.expect(values.storePlain(&parameter_set, 0, 0.75));
    try std.testing.expect(values.storeById(&parameter_set, 0, 0.25));
    try std.testing.expect(values.storeByName(&parameter_set, "Gain", 0.5));
    try std.testing.expectEqual(@as(?usize, 0), values.storeByNameCount(&parameter_set, "Gain", 0.5));
    try std.testing.expect(values.storePlainById(&parameter_set, 0, 0.25));
    try std.testing.expect(values.storePlainByName(&parameter_set, "Gain", 0.5));
    try std.testing.expectEqual(@as(?usize, 1), values.storeFieldCount(&parameter_set, "gain", 0.25));
    try std.testing.expectEqual(@as(?usize, 1), values.storeFieldNormalizedCount(&parameter_set, "gain", 0.5));
    try std.testing.expectEqual(@as(?usize, null), values.storeByIdCount(&parameter_set, 99, 0.5));
    try std.testing.expectEqual(@as(?usize, null), values.storePlainByNameCount(&parameter_set, "Missing", 0.5));
    try std.testing.expect(!values.allDefaults(&parameter_set));
    try std.testing.expect(values.hasNonDefaults(&parameter_set));
    try std.testing.expectEqual(@as(usize, 1), values.nonDefaultCount(&parameter_set));

    var copied = Spec.ParameterValues.init(&parameter_set);
    try std.testing.expect(copied.storeById(&parameter_set, 0, 0.5));
    try std.testing.expect(copied.resetToDefaultById(&parameter_set, 0));
    try std.testing.expect(copied.storeByName(&parameter_set, "Gain", 0.5));
    try std.testing.expect(copied.resetToDefaultByName(&parameter_set, "Gain"));
    try std.testing.expect(copied.storePlain(&parameter_set, 0, 0.5));
    try std.testing.expect(copied.resetToDefault(&parameter_set, 0));
    try std.testing.expect(copied.store(0, 0.5));
    copied.resetToDefaults(&parameter_set);
    try std.testing.expect(copied.allDefaults(&parameter_set));
    try std.testing.expectEqual(@as(usize, 1), copied.copyFromCount(&values));
    try std.testing.expectEqual(@as(usize, 0), copied.copyFromCount(&values));
    copied.resetToDefaults(&parameter_set);
    copied.copyFrom(&values);
    try std.testing.expectEqual(@as(f64, 0.5), copied.loadFieldNormalized(&parameter_set, "gain"));
    try std.testing.expect(copied.storeField(&parameter_set, "gain", 0.75));
    try std.testing.expectEqual(@as(f64, 0.75), copied.loadField(&parameter_set, "gain"));
    try std.testing.expectEqual(@as(?usize, 1), copied.resetFieldToDefaultCount(&parameter_set, "gain"));
    try std.testing.expect(copied.resetFieldToDefault(&parameter_set, "gain"));
    try std.testing.expect(copied.storeFieldNormalized(&parameter_set, "gain", 0.5));

    var editor = copied.editor(&parameter_set);
    const view = copied.view(&parameter_set);
    var copied_from_view = Spec.ParameterValues.init(&parameter_set);
    const copied_from_view_editor = copied_from_view.editor(&parameter_set);
    try std.testing.expectEqual(@as(usize, 1), copied_from_view_editor.copyFromCount(view));
    try std.testing.expectEqual(@as(usize, 0), copied_from_view_editor.copyFromCount(view));
    copied_from_view.resetToDefaults(&parameter_set);
    copied_from_view_editor.copyFrom(view);
    try std.testing.expectEqual(@as(f64, 0.5), copied_from_view_editor.loadNormalized("gain"));
    try std.testing.expectEqual(@as(usize, 1), view.parameterCount());
    try std.testing.expect(!view.parametersEmpty());
    try std.testing.expect(view.hasParameters());
    try std.testing.expectEqual(@as(?u32, null), view.duplicateId());
    try std.testing.expectEqual(@as(?usize, null), view.duplicateIdIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), view.duplicateName());
    try std.testing.expectEqual(@as(?usize, null), view.duplicateNameIndex());
    try std.testing.expect(!view.hasDuplicateIds());
    try std.testing.expect(!view.hasDuplicateNames());
    try std.testing.expectEqual(@as(?anyerror, null), view.firstDescriptorError());
    try std.testing.expectEqual(@as(?usize, null), view.firstDescriptorErrorIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), view.firstDescriptorErrorName());
    try std.testing.expectEqual(@as(?u32, 0), view.id(0));
    try std.testing.expectEqualStrings("Gain", view.name(0).?);
    try std.testing.expectEqualStrings("Gain", view.nameById(0).?);
    try std.testing.expectEqual(@as(?u32, 0), view.idByName("Gain"));
    try std.testing.expectEqual(@as(?usize, 0), view.indexOfId(0));
    try std.testing.expectEqual(@as(?usize, 0), view.indexOfName("Gain"));
    try std.testing.expect(view.hasId(0));
    try std.testing.expect(view.hasName("Gain"));
    try std.testing.expectEqualStrings("Gain", view.shortNameByName("Gain").?);
    try std.testing.expectEqualStrings("x", view.unitsById(0).?);
    try std.testing.expectEqual(@as(?f64, 1.0), view.defaultNormalizedByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), view.defaultPlainById(0));
    try std.testing.expectEqual(@as(?f64, 0.0), view.plainMinimumByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), view.plainMaximumById(0));
    try std.testing.expect(view.hasPlainRangeByName("Gain"));
    try std.testing.expectEqual(@as(u32, 0), view.descriptor("gain").id);
    try std.testing.expectEqual(@as(usize, 0), view.indexOfField("gain"));
    try std.testing.expectEqual(@as(u32, 0), view.fieldId("gain"));
    try std.testing.expectEqualStrings("Gain", view.fieldName("gain"));
    try std.testing.expectEqualStrings("Gain", view.fieldShortName("gain"));
    try std.testing.expectEqualStrings("x", view.fieldUnits("gain"));
    try std.testing.expectEqual(@as(f64, 1.0), view.fieldDefaultNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 1.0), view.fieldDefaultPlain("gain"));
    try std.testing.expectEqual(@as(?f64, 0.0), view.fieldPlainMinimum("gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), view.fieldPlainMaximum("gain"));
    try std.testing.expect(view.fieldHasPlainRange("gain"));
    try std.testing.expect(!view.fieldIsBypass("gain"));
    try std.testing.expect(view.fieldCanAutomate("gain"));
    try std.testing.expect(!view.fieldIsReadOnly("gain"));
    try std.testing.expectEqual(@as(?bool, false), view.isBypassById(0));
    try std.testing.expectEqual(@as(?bool, true), view.canAutomate(0));
    try std.testing.expectEqual(@as(i32, plug.units.root_unit_id), view.fieldUnitId("gain"));
    try std.testing.expectEqual(@as(i32, 0), view.fieldStepCount("gain"));
    try std.testing.expect(!view.fieldIsList("gain"));
    try std.testing.expectEqual(@as(?usize, null), view.fieldOptionCount("gain"));
    try std.testing.expectEqual(@as(?[]const u8, null), view.fieldOptionLabel("gain", 0));
    try std.testing.expectEqual(@as(?f64, null), view.fieldOptionNormalized("gain", 0));
    try std.testing.expect(!view.fieldHasOptions("gain"));
    try std.testing.expect(view.fieldOptionsEmpty("gain"));
    var format_buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("0.500", try view.formatFieldPlain("gain", 0.5, &format_buffer));
    try std.testing.expectEqual(@as(f64, 0.25), try view.parseFieldPlain("gain", "0.25"));
    try std.testing.expectEqual(@as(f64, 0.5), view.fieldPlainFromNormalized("gain", 0.5));
    try std.testing.expectEqual(@as(f64, 0.5), view.fieldNormalizedFromPlain("gain", 0.5));
    try std.testing.expectEqual(plug.process.ParameterChange{
        .id = 0,
        .sample_offset = 4,
        .normalized = 0.5,
    }, view.parameterChange("gain", 4, 0.5));
    try std.testing.expectEqual(plug.process.ParameterChange{
        .id = 0,
        .sample_offset = 5,
        .normalized = 0.25,
    }, view.parameterChangeNormalized("gain", 5, 0.25));
    try std.testing.expectEqualStrings("0.500", try view.formatPlainByName("Gain", 0.5, &format_buffer));
    try std.testing.expectEqualStrings("0.250", try view.formatPlainIndex(0, 0.25, &format_buffer));
    try std.testing.expectEqual(@as(f64, 0.25), try view.parsePlainById(0, "0.25"));
    try std.testing.expectEqual(@as(f64, 0.75), try view.parsePlainIndex(0, "0.75"));
    try std.testing.expectEqual(@as(?f64, 0.5), view.plainFromNormalizedIndex(0, 0.5));
    try std.testing.expectEqual(@as(?f64, 0.25), view.normalizedFromPlainByName("Gain", 0.25));
    try std.testing.expectEqual(@as(f64, 0.5), view.loadNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 0.5), view.load("gain"));
    try std.testing.expectEqual(@as(?f64, 0.5), view.loadIndex(0));
    try std.testing.expectEqual(@as(?f64, 0.5), view.loadPlainIndex(0));
    try std.testing.expectEqual(@as(?f64, 0.5), view.loadById(0));
    try std.testing.expectEqual(@as(?f64, 0.5), view.loadPlainById(0));
    try std.testing.expectEqual(@as(?f64, 0.5), view.loadByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 0.5), view.loadPlainByName("Gain"));
    try std.testing.expect(!view.isDefault("gain"));
    try std.testing.expectEqual(@as(?bool, false), view.isDefaultIndex(0));
    try std.testing.expectEqual(@as(?bool, false), view.isDefaultById(0));
    try std.testing.expectEqual(@as(?bool, false), view.isDefaultByName("Gain"));
    try std.testing.expectEqual(@as(usize, 1), view.nonDefaultCount());
    try std.testing.expect(!view.allDefaults());
    try std.testing.expect(view.hasNonDefaults());
    try std.testing.expectEqual(@as(usize, 1), editor.parameterCount());
    try std.testing.expect(!editor.parametersEmpty());
    try std.testing.expect(editor.hasParameters());
    try std.testing.expectEqual(@as(?u32, null), editor.duplicateId());
    try std.testing.expectEqual(@as(?usize, null), editor.duplicateIdIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), editor.duplicateName());
    try std.testing.expectEqual(@as(?usize, null), editor.duplicateNameIndex());
    try std.testing.expect(!editor.hasDuplicateIds());
    try std.testing.expect(!editor.hasDuplicateNames());
    try std.testing.expectEqual(@as(?anyerror, null), editor.firstDescriptorError());
    try std.testing.expectEqual(@as(?usize, null), editor.firstDescriptorErrorIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), editor.firstDescriptorErrorName());
    try std.testing.expectEqual(@as(?u32, 0), editor.id(0));
    try std.testing.expectEqualStrings("Gain", editor.nameById(0).?);
    try std.testing.expectEqual(@as(?usize, 0), editor.indexOfName("Gain"));
    try std.testing.expect(editor.hasName("Gain"));
    try std.testing.expectEqual(@as(?bool, false), editor.isBypassById(0));
    try std.testing.expectEqual(@as(?bool, true), editor.canAutomate(0));
    try std.testing.expectEqual(@as(?bool, true), editor.canAutomateById(0));
    try std.testing.expectEqual(@as(?bool, false), editor.isReadOnlyByName("Gain"));
    try std.testing.expectEqual(@as(?i32, 0), editor.stepCountByName("Gain"));
    try std.testing.expect(!editor.isListByName("Gain").?);
    try std.testing.expectEqual(@as(u32, 0), editor.descriptor("gain").id);
    try std.testing.expectEqual(@as(usize, 0), editor.indexOfField("gain"));
    try std.testing.expectEqualStrings("Gain", editor.fieldShortName("gain"));
    try std.testing.expectEqual(@as(i32, plug.units.root_unit_id), editor.fieldUnitId("gain"));
    try std.testing.expect(!editor.fieldIsBypass("gain"));
    try std.testing.expect(editor.fieldCanAutomate("gain"));
    try std.testing.expect(!editor.fieldIsReadOnly("gain"));
    try std.testing.expectEqual(@as(i32, 0), editor.fieldStepCount("gain"));
    try std.testing.expect(!editor.fieldIsList("gain"));
    try std.testing.expect(!editor.fieldHasOptions("gain"));
    try std.testing.expect(editor.fieldOptionsEmpty("gain"));
    try std.testing.expectEqualStrings("0.750", try editor.formatFieldPlain("gain", 0.75, &format_buffer));
    try std.testing.expectEqualStrings("0.250", try editor.formatPlainIndex(0, 0.25, &format_buffer));
    try std.testing.expectEqual(@as(f64, 0.75), try editor.parsePlainByName("Gain", "0.75"));
    try std.testing.expectEqual(@as(f64, 0.25), try editor.parsePlainIndex(0, "0.25"));
    try std.testing.expectEqual(@as(?f64, 0.75), editor.plainFromNormalizedById(0, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.75), editor.normalizedFromPlainIndex(0, 0.75));
    try std.testing.expectEqual(plug.process.ParameterChange{
        .id = 0,
        .sample_offset = 6,
        .normalized = 0.75,
    }, editor.parameterChange("gain", 6, 0.75));
    try std.testing.expectEqual(plug.process.ParameterChange{
        .id = 0,
        .sample_offset = 7,
        .normalized = 0.5,
    }, editor.parameterChangeNormalized("gain", 7, 0.5));
    try std.testing.expect(editor.storeNormalized("gain", 0.75));
    try std.testing.expect(editor.store("gain", 0.5));
    try std.testing.expect(editor.storeIndex(0, 0.25));
    try std.testing.expectEqual(@as(?usize, 1), editor.storeIndexCount(0, 0.5));
    try std.testing.expectEqual(@as(?usize, 0), editor.storeIndexCount(0, 0.5));
    try std.testing.expect(editor.storePlainIndex(0, 0.75));
    try std.testing.expectEqual(@as(?usize, 1), editor.storePlainIndexCount(0, 0.25));
    try std.testing.expectEqual(@as(?usize, 1), editor.storePlainByIdCount(0, 0.5));
    try std.testing.expect(editor.storePlainById(0, 0.5));
    try std.testing.expect(!editor.storeIndex(99, 0.5));
    try std.testing.expectEqual(@as(?usize, 1), editor.storeNormalizedCount("gain", 0.25));
    try std.testing.expectEqual(@as(f64, 0.25), editor.view().loadNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), editor.resetToDefaultCount("gain"));
    try std.testing.expectEqual(@as(?usize, 0), editor.resetToDefaultIndexCount(0));
    try std.testing.expect(editor.storeIndex(0, 0.5));
    try std.testing.expect(editor.resetToDefaultIndex(0));
    try std.testing.expect(editor.allDefaults());
    try std.testing.expectEqual(@as(usize, 0), editor.nonDefaultCount());

    const editor_raw_changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.5 },
    };
    const editor_changes = try plug.process.ParameterChanges.init(&editor_raw_changes, 1);
    try std.testing.expectEqual(@as(usize, 1), editor.applyChangesChangedCount(editor_changes));
    try std.testing.expectEqual(@as(f64, 0.5), editor.loadNormalized("gain"));
    try std.testing.expectEqual(@as(usize, 1), editor.applyChangesCount(editor_changes));
    try std.testing.expectEqual(@as(usize, 0), editor.applyChangesChangedCount(editor_changes));
    editor.applyChanges(editor_changes);
    try std.testing.expectEqual(@as(f64, 0.5), editor.view().loadNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), editor.resetToDefaultCount("gain"));

    try std.testing.expectEqual(@as(?usize, 1), values.resetToDefaultCount(&parameter_set, 0));
    try std.testing.expectEqual(@as(?usize, 0), values.resetToDefaultByIdCount(&parameter_set, 0));
    try std.testing.expectEqual(@as(?usize, null), values.resetToDefaultByNameCount(&parameter_set, "Missing"));
    try std.testing.expectEqual(@as(usize, 0), values.resetToDefaultsCount(&parameter_set));
}

test "gain core example applies reflected parameter changes directly" {
    var instance = try Instance.init(std.testing.allocator, .{});
    try std.testing.expectEqual(plug.process.ParameterChange{
        .id = 0,
        .sample_offset = 2,
        .normalized = 0.25,
    }, instance.parameterChangeNormalized("gain", 2, 0.25));
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
    var header_bytes: [plug.state.encoded_header_size]u8 = undefined;

    try std.testing.expectEqual(@as(usize, 12), plug.state.encoded_header_size);
    try std.testing.expectEqual(@as(usize, 12), plug.state.encoded_entry_size);
    try std.testing.expectEqual(@as(usize, plug.state.encodedSize(Gain.Params)), plug.state.encodedSizeForCount(1));
    try std.testing.expectEqual(@as(usize, plug.state.encodedSize(Gain.Params)), try plug.state.encodedSizeForCountChecked(1));
    try std.testing.expectEqual(std.math.maxInt(usize), plug.state.encodedSizeForCount(std.math.maxInt(usize)));
    try std.testing.expectError(error.Overflow, plug.state.encodedSizeForCountChecked(std.math.maxInt(usize)));

    var header_out_stream = std.io.fixedBufferStream(&header_bytes);
    try plug.state.writeParameterStateHeaderForCount(1, header_out_stream.writer());
    var header_in_stream = std.io.fixedBufferStream(&header_bytes);
    try std.testing.expectEqual(
        plug.state.ParameterStateHeader{ .version = plug.state.format_version, .entry_count = 1 },
        try plug.state.readParameterStateHeader(header_in_stream.reader()),
    );
    try std.testing.expectError(
        error.ParameterStateTooLarge,
        plug.state.writeParameterStateHeaderForCount(@as(usize, std.math.maxInt(u16)) + 1, header_out_stream.writer()),
    );

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
    try std.testing.expectEqual(@as(usize, 1), header.entryCount());
    try std.testing.expect(header.hasEntries());
    try std.testing.expect(!header.hasNoEntries());
    try std.testing.expect(!header.entriesEmpty());
    try std.testing.expect(header.matchesEntryCount(1));
    try std.testing.expect(!header.hasFewerEntriesThan(1));
    try std.testing.expect(!header.hasMoreEntriesThan(1));
    try std.testing.expectEqual(@as(usize, 1), header.missingEntryCount(2));
    try std.testing.expectEqual(@as(usize, 1), header.extraEntryCount(0));
    try std.testing.expectEqual(@as(usize, plug.state.encodedSize(Gain.Params)), header.encodedSize());
    try std.testing.expectEqual(@as(usize, plug.state.encodedSize(Gain.Params)), try header.encodedSizeChecked());
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateHeaderEntryCount(header));
    try std.testing.expect(restored.parameterStateHeaderHasEntries(header));
    try std.testing.expect(!restored.parameterStateHeaderHasNoEntries(header));
    try std.testing.expect(!restored.parameterStateHeaderEntriesEmpty(header));
    try std.testing.expect(restored.parameterStateHeaderIsCurrentVersion(header));
    try std.testing.expectEqual(@as(usize, plug.state.encodedSize(Gain.Params)), restored.parameterStateHeaderEncodedSize(header));
    try std.testing.expectEqual(@as(usize, plug.state.encodedSize(Gain.Params)), try restored.parameterStateHeaderEncodedSizeChecked(header));
    try std.testing.expect(!empty_header.hasEntries());
    try std.testing.expect(empty_header.hasNoEntries());
    try std.testing.expect(empty_header.entriesEmpty());
    try std.testing.expect(!restored.parameterStateHeaderHasEntries(empty_header));
    try std.testing.expect(restored.parameterStateHeaderHasNoEntries(empty_header));
    try std.testing.expect(restored.parameterStateHeaderEntriesEmpty(empty_header));
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
    var directly_restored = try Instance.init(std.testing.allocator, .{});
    var direct_in_stream = std.io.fixedBufferStream(&bytes);
    try directly_restored.readParameterState(direct_in_stream.reader());
    const empty_report = plug.state.ReadParameterStateReport{ .entry_count = 0, .restored_count = 0, .ignored_count = 0 };
    const newer_report = plug.state.ReadParameterStateReport{ .entry_count = 2, .restored_count = 1, .ignored_count = 1 };
    const over_restored_report = plug.state.ReadParameterStateReport{ .entry_count = 2, .restored_count = 2, .ignored_count = 0 };
    const ignored_report = plug.state.ReadParameterStateReport{ .entry_count = 1, .restored_count = 0, .ignored_count = 1 };
    const unaccounted_report = plug.state.ReadParameterStateReport{ .entry_count = 2, .restored_count = 0, .ignored_count = 0 };

    try std.testing.expectEqual(@as(usize, 1), report.decodedCount());
    try std.testing.expectEqual(@as(usize, 1), report.restoredCount());
    try std.testing.expectEqual(@as(usize, 0), report.ignoredCount());
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportDecodedCount(report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportRestoredCount(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportIgnoredCount(report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportAccountedCount(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportUnaccountedCount(report));
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
    try std.testing.expect(restored.parameterStateReportHasMoreRestoredEntries(over_restored_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportExtraDecodedEntryCount(newer_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraRestoredEntryCount(newer_report));
    try std.testing.expect(!restored.parameterStateReportMatchesIgnoredCount(report));
    try std.testing.expect(restored.parameterStateReportHasFewerIgnoredEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasMoreIgnoredEntries(report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportMissingIgnoredEntryCount(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraIgnoredEntryCount(report));
    try std.testing.expect(restored.parameterStateReportMatchesIgnoredCount(ignored_report));
    try std.testing.expect(restored.parameterStateReportMatchesAccountedCount(report));
    try std.testing.expect(!restored.parameterStateReportHasFewerAccountedEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasMoreAccountedEntries(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingAccountedEntryCount(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraAccountedEntryCount(report));
    try std.testing.expect(restored.parameterStateReportMatchesAccountedCount(ignored_report));
    try std.testing.expect(!restored.parameterStateReportMatchesAccountedCount(empty_report));
    try std.testing.expect(restored.parameterStateReportHasFewerAccountedEntries(empty_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportMissingAccountedEntryCount(empty_report));
    try std.testing.expect(!restored.parameterStateReportMatchesUnaccountedCount(report));
    try std.testing.expect(restored.parameterStateReportHasFewerUnaccountedEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasMoreUnaccountedEntries(report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportMissingUnaccountedEntryCount(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraUnaccountedEntryCount(report));
    try std.testing.expect(restored.parameterStateReportHasMoreUnaccountedEntries(unaccounted_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportExtraUnaccountedEntryCount(unaccounted_report));
    try std.testing.expect(report.hasDecodedEntries());
    try std.testing.expect(report.hasRestoredEntries());
    try std.testing.expect(!report.hasIgnoredEntries());
    try std.testing.expect(report.fullyHandled());
    try std.testing.expectEqual(plug.state.ReadParameterStateClassification.restored_all, report.classification());
    try std.testing.expect(report.isRestoredAllClassification());
    try std.testing.expect(!report.isPartialClassification());
    try std.testing.expect(report.restoredAllEntries());
    try std.testing.expect(!report.ignoredAllEntries());
    try std.testing.expect(restored.parameterStateReportHasDecodedEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasNoDecodedEntries(report));
    try std.testing.expect(!restored.parameterStateReportDecodedEntriesEmpty(report));
    try std.testing.expect(restored.parameterStateReportHasRestoredEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasNoRestoredEntries(report));
    try std.testing.expect(!restored.parameterStateReportRestoredEntriesEmpty(report));
    try std.testing.expect(!restored.parameterStateReportHasIgnoredEntries(report));
    try std.testing.expect(restored.parameterStateReportHasNoIgnoredEntries(report));
    try std.testing.expect(restored.parameterStateReportIgnoredEntriesEmpty(report));
    try std.testing.expect(!restored.parameterStateReportHasUnaccountedEntries(report));
    try std.testing.expect(restored.parameterStateReportHasNoUnaccountedEntries(report));
    try std.testing.expect(restored.parameterStateReportUnaccountedEntriesEmpty(report));
    try std.testing.expect(restored.parameterStateReportHasAccountedEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasNoAccountedEntries(report));
    try std.testing.expect(!restored.parameterStateReportAccountedEntriesEmpty(report));
    try std.testing.expect(restored.parameterStateReportFullyHandled(report));
    try std.testing.expect(restored.parameterStateReportAccountedAllEntries(report));
    try std.testing.expect(!restored.parameterStateReportAccountedPartialEntries(report));
    try std.testing.expect(restored.parameterStateReportRestoredAllEntries(report));
    try std.testing.expect(!restored.parameterStateReportRestoredPartialEntries(report));
    try std.testing.expect(!restored.parameterStateReportIgnoredAllEntries(report));
    try std.testing.expect(!restored.parameterStateReportIgnoredPartialEntries(report));
    try std.testing.expect(!restored.parameterStateReportRestoredAndIgnoredEntries(report));
    try std.testing.expectEqual(plug.state.ReadParameterStateClassification.restored_all, restored.parameterStateReportClassification(report));
    try std.testing.expect(!restored.parameterStateReportIsEmptyClassification(report));
    try std.testing.expect(restored.parameterStateReportIsRestoredAllClassification(report));
    try std.testing.expect(!restored.parameterStateReportIsIgnoredAllClassification(report));
    try std.testing.expect(!restored.parameterStateReportIsRestoredAndIgnoredClassification(report));
    try std.testing.expect(!restored.parameterStateReportIsPartialClassification(report));
    try std.testing.expectEqual(@as(f64, 0.25), restored.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 0.25), directly_restored.loadParameterNormalized("gain"));

    var json_bytes: [128]u8 = undefined;
    var json_stream = std.io.fixedBufferStream(&json_bytes);
    try restored.writeParameterStateJson(json_stream.writer());
    try std.testing.expectEqualStrings(
        "{\"version\":1,\"parameters\":[{\"id\":0,\"name\":\"Gain\",\"normalized\":0.25}]}",
        json_stream.getWritten(),
    );
}

test "gain core example classifies parameter state reports" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const empty = plug.state.ReadParameterStateReport{ .entry_count = 0, .restored_count = 0, .ignored_count = 0 };
    const mixed = plug.state.ReadParameterStateReport{ .entry_count = 2, .restored_count = 1, .ignored_count = 1 };
    const ignored = plug.state.ReadParameterStateReport{ .entry_count = 2, .restored_count = 0, .ignored_count = 2 };
    const partial = plug.state.ReadParameterStateReport{ .entry_count = 3, .restored_count = 1, .ignored_count = 1 };

    try std.testing.expectEqual(@as(usize, 0), empty.accountedCount());
    try std.testing.expectEqual(@as(usize, 0), empty.unaccountedCount());
    try std.testing.expect(empty.hasNoDecodedEntries());
    try std.testing.expect(empty.decodedEntriesEmpty());
    try std.testing.expect(empty.accountedAllEntries());
    try std.testing.expectEqual(plug.state.ReadParameterStateClassification.empty, empty.classification());
    try std.testing.expect(empty.isEmptyClassification());
    try std.testing.expectEqual(@as(usize, 0), instance.parameterStateReportAccountedCount(empty));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterStateReportUnaccountedCount(empty));
    try std.testing.expect(instance.parameterStateReportHasNoDecodedEntries(empty));
    try std.testing.expect(instance.parameterStateReportDecodedEntriesEmpty(empty));
    try std.testing.expect(!instance.parameterStateReportHasAccountedEntries(empty));
    try std.testing.expect(instance.parameterStateReportHasNoAccountedEntries(empty));
    try std.testing.expect(instance.parameterStateReportAccountedEntriesEmpty(empty));
    try std.testing.expect(instance.parameterStateReportAccountedAllEntries(empty));
    try std.testing.expectEqual(plug.state.ReadParameterStateClassification.empty, instance.parameterStateReportClassification(empty));
    try std.testing.expect(instance.parameterStateReportIsEmptyClassification(empty));

    try std.testing.expect(instance.parameterStateReportRestoredAndIgnoredEntries(mixed));
    try std.testing.expectEqual(plug.state.ReadParameterStateClassification.restored_and_ignored, instance.parameterStateReportClassification(mixed));
    try std.testing.expect(instance.parameterStateReportIsRestoredAndIgnoredClassification(mixed));

    try std.testing.expectEqual(@as(usize, 2), ignored.accountedCount());
    try std.testing.expectEqual(@as(usize, 0), ignored.unaccountedCount());
    try std.testing.expect(ignored.hasIgnoredEntries());
    try std.testing.expect(!ignored.hasNoIgnoredEntries());
    try std.testing.expect(!ignored.ignoredEntriesEmpty());
    try std.testing.expect(ignored.hasNoRestoredEntries());
    try std.testing.expect(ignored.restoredEntriesEmpty());
    try std.testing.expect(ignored.matchesIgnoredCount(2));
    try std.testing.expect(ignored.hasMoreIgnoredEntriesThan(1));
    try std.testing.expectEqual(@as(usize, 0), ignored.missingIgnoredEntryCount(2));
    try std.testing.expectEqual(@as(usize, 1), ignored.extraIgnoredEntryCount(1));
    try std.testing.expect(ignored.fullyHandled());
    try std.testing.expect(ignored.ignoredAllEntries());
    try std.testing.expect(!ignored.ignoredPartialEntries());
    try std.testing.expectEqual(plug.state.ReadParameterStateClassification.ignored_all, ignored.classification());
    try std.testing.expect(ignored.isIgnoredAllClassification());
    try std.testing.expectEqual(@as(usize, 2), instance.parameterStateReportAccountedCount(ignored));
    try std.testing.expect(instance.parameterStateReportHasAccountedEntries(ignored));
    try std.testing.expect(!instance.parameterStateReportHasNoAccountedEntries(ignored));
    try std.testing.expect(!instance.parameterStateReportAccountedEntriesEmpty(ignored));
    try std.testing.expect(instance.parameterStateReportHasIgnoredEntries(ignored));
    try std.testing.expect(!instance.parameterStateReportHasNoIgnoredEntries(ignored));
    try std.testing.expect(!instance.parameterStateReportIgnoredEntriesEmpty(ignored));
    try std.testing.expect(instance.parameterStateReportHasNoRestoredEntries(ignored));
    try std.testing.expect(instance.parameterStateReportRestoredEntriesEmpty(ignored));
    try std.testing.expect(instance.parameterStateReportFullyHandled(ignored));
    try std.testing.expect(instance.parameterStateReportIgnoredAllEntries(ignored));
    try std.testing.expect(!instance.parameterStateReportIgnoredPartialEntries(ignored));
    try std.testing.expectEqual(plug.state.ReadParameterStateClassification.ignored_all, instance.parameterStateReportClassification(ignored));
    try std.testing.expect(instance.parameterStateReportIsIgnoredAllClassification(ignored));

    try std.testing.expectEqual(@as(usize, 2), partial.accountedCount());
    try std.testing.expectEqual(@as(usize, 1), partial.unaccountedCount());
    try std.testing.expect(partial.matchesAccountedCount(2));
    try std.testing.expect(partial.hasFewerAccountedEntriesThan(3));
    try std.testing.expect(partial.hasMoreAccountedEntriesThan(1));
    try std.testing.expectEqual(@as(usize, 1), partial.missingAccountedEntryCount(3));
    try std.testing.expectEqual(@as(usize, 1), partial.extraAccountedEntryCount(1));
    try std.testing.expect(partial.matchesUnaccountedCount(1));
    try std.testing.expect(partial.hasMoreUnaccountedEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), partial.missingUnaccountedEntryCount(2));
    try std.testing.expectEqual(@as(usize, 1), partial.extraUnaccountedEntryCount(0));
    try std.testing.expect(partial.hasUnaccountedEntries());
    try std.testing.expect(!partial.hasNoUnaccountedEntries());
    try std.testing.expect(!partial.unaccountedEntriesEmpty());
    try std.testing.expect(!partial.fullyHandled());
    try std.testing.expect(partial.accountedPartialEntries());
    try std.testing.expect(partial.restoredPartialEntries());
    try std.testing.expect(partial.ignoredPartialEntries());
    try std.testing.expect(partial.restoredAndIgnoredEntries());
    try std.testing.expectEqual(plug.state.ReadParameterStateClassification.partial, partial.classification());
    try std.testing.expect(partial.isPartialClassification());
    try std.testing.expectEqual(@as(usize, 2), instance.parameterStateReportAccountedCount(partial));
    try std.testing.expectEqual(@as(usize, 1), instance.parameterStateReportUnaccountedCount(partial));
    try std.testing.expect(instance.parameterStateReportHasAccountedEntries(partial));
    try std.testing.expect(!instance.parameterStateReportHasNoAccountedEntries(partial));
    try std.testing.expect(!instance.parameterStateReportAccountedEntriesEmpty(partial));
    try std.testing.expect(instance.parameterStateReportHasUnaccountedEntries(partial));
    try std.testing.expect(!instance.parameterStateReportHasNoUnaccountedEntries(partial));
    try std.testing.expect(!instance.parameterStateReportUnaccountedEntriesEmpty(partial));
    try std.testing.expect(!instance.parameterStateReportFullyHandled(partial));
    try std.testing.expect(instance.parameterStateReportAccountedPartialEntries(partial));
    try std.testing.expect(instance.parameterStateReportRestoredPartialEntries(partial));
    try std.testing.expect(instance.parameterStateReportIgnoredPartialEntries(partial));
    try std.testing.expect(instance.parameterStateReportRestoredAndIgnoredEntries(partial));
    try std.testing.expectEqual(plug.state.ReadParameterStateClassification.partial, instance.parameterStateReportClassification(partial));
    try std.testing.expect(instance.parameterStateReportIsPartialClassification(partial));
}

test "gain core example resolves migrated state parameter ids" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const migrations = [_]plug.state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 11 },
        .{ .old_id = 11, .new_id = 0 },
    };
    const identity = [_]plug.state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 7 },
    };
    const duplicate = [_]plug.state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 0 },
        .{ .old_id = 7, .new_id = 1 },
    };
    const ambiguous = [_]plug.state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 0 },
        .{ .old_id = 8, .new_id = 0 },
    };

    try instance.validateParameterIdMigrations(&migrations);
    try std.testing.expectEqual(@as(?usize, null), instance.identityParameterMigrationIndex(&migrations));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateParameterMigrationIndex(&migrations));
    try std.testing.expectEqual(@as(?usize, null), instance.ambiguousParameterMigrationIndex(&migrations));
    try std.testing.expectEqual(@as(u32, 0), instance.migratedParameterId(7, &migrations));
    try std.testing.expectEqual(@as(u32, 0), instance.migratedParameterId(11, &migrations));
    try std.testing.expectEqual(@as(u32, 42), instance.migratedParameterId(42, &migrations));
    try std.testing.expectEqual(@as(?usize, 0), instance.identityParameterMigrationIndex(&identity));
    try std.testing.expectError(error.IdentityParameterMigration, instance.validateParameterIdMigrations(&identity));
    try std.testing.expectEqual(@as(?usize, 1), instance.duplicateParameterMigrationIndex(&duplicate));
    try std.testing.expectError(error.DuplicateParameterMigration, instance.validateParameterIdMigrations(&duplicate));
    try std.testing.expectEqual(@as(?usize, 1), instance.ambiguousParameterMigrationIndex(&ambiguous));
    try std.testing.expectError(error.AmbiguousParameterMigration, instance.validateParameterIdMigrations(&ambiguous));
}

test "gain core example reads migrated parameter state" {
    const LegacyGain = struct {
        pub const name = "zig-vst3-plugin Legacy Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(7, "Gain", 0.0, 1.0, 1.0),
        };
    };
    const LegacyInstance = plug.plugin.PluginInstance(LegacyGain);
    var legacy = try LegacyInstance.init(std.testing.allocator, .{});
    var restored = try Instance.init(std.testing.allocator, .{});
    var reported = try Instance.init(std.testing.allocator, .{});
    const migrations = [_]plug.state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 11 },
        .{ .old_id = 11, .new_id = 0 },
    };
    var bytes: [plug.state.encodedSize(LegacyGain.Params)]u8 = undefined;

    try std.testing.expect(legacy.storeParameterNormalized("gain", 0.25));
    var out_stream = std.io.fixedBufferStream(&bytes);
    try legacy.writeParameterState(out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    try restored.readParameterStateWithMigrations(in_stream.reader(), &migrations);
    try std.testing.expectEqual(@as(f64, 0.25), restored.loadParameterNormalized("gain"));

    var report_stream = std.io.fixedBufferStream(&bytes);
    const report = try reported.readParameterStateWithMigrationsReport(report_stream.reader(), &migrations);
    try std.testing.expectEqual(plug.state.ReadParameterStateReport{ .entry_count = 1, .restored_count = 1, .ignored_count = 0 }, report);
    try std.testing.expect(report.isRestoredAllClassification());
    try std.testing.expectEqual(@as(f64, 0.25), reported.loadParameterNormalized("gain"));
}
