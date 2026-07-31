const core = @import("zig-vst3-plugin-core");
const std = @import("std");
const vst3 = @import("zig-vst3");
const clock = @import("ara_playback_core.zig");

const base = vst3.pluginterfaces.base;
const vst = vst3.pluginterfaces.vst;
const types = base.types;
const raw = vst3.ara_document_controller.raw;

const ara_limits = vst3.ara_model.Limits{
    .musical_contexts = 2,
    .region_sequences = 2,
    .audio_sources = 2,
    .audio_modifications = 2,
    .playback_regions = 4,
    .audio_readers = 4,
    .content_readers = 2,
    .model_observers = 4,
    .name_bytes = 63,
    .persistent_id_bytes = 63,
    .archive_extension_bytes = 32_768,
};

pub const AraController =
    vst3.ara_document_controller.Controller(ara_limits);

const ProductAnalysisExtension = struct {
    pub fn Type(comptime ControllerType: type) type {
        return vst3.ara_tuning_analysis.Analyzer(
            ControllerType,
            .{
                .sources = 2,
                .channels = 2,
                .frames = 64_000,
                .note_entries = 256,
            },
        );
    }
};

const ProductAraFactory = vst3.ara_factory.Factory(
    .{
        .factory_id = "dev.zig-vst3.ara-playback.factory",
        .plugin_name = "zig-vst3 ARA Playback",
        .manufacturer_name = "zig-vst3",
        .information_url = "https://github.com/joshburgess/zig-vst3",
        .version = vst3.version,
        .document_archive_id = "dev.zig-vst3.ara-playback.archive",
        .analyzeable_content_types = &.{
            raw.kARAContentTypeNotes,
            raw.kARAContentTypeStaticTuning,
            raw.kARAContentTypeTempoEntries,
            raw.kARAContentTypeBarSignatures,
            raw.kARAContentTypeKeySignatures,
            raw.kARAContentTypeSheetChords,
        },
        .controller_extension = ProductAnalysisExtension,
        .supported_playback_transformation_flags = raw.kARAPlaybackTransformationTimestretch |
            raw.kARAPlaybackTransformationTimestretchReflectingTempo |
            raw.kARAPlaybackTransformationContentBasedFades,
    },
    ara_limits,
    4,
);
const ara_factory_pointer: *const vst3.ara_vst3.Factory =
    @ptrCast(ProductAraFactory.factoryPointer());

const SourceCache = vst3.ara_source_cache.PagedCache(
    AraController,
    f64,
    .{
        .sources = 2,
        .channels = 2,
        .page_slots = 4,
        .frames_per_page = 64,
        .publication_slots = 4,
    },
);

const AraRenderer = vst3.ara_playback_renderer.Renderer(
    AraController,
    f64,
    .{
        .regions = 4,
        .channels = 2,
        .maximum_block_frames = 256,
        .maximum_source_frames_per_region = 256,
        .interpolation = .windowed_sinc_8,
    },
);

const ContentFades = vst3.ara_content_fades.Analyzer(
    AraController,
    f64,
    .{
        .regions = 4,
        .channels = 2,
        .analysis_frames = 256,
    },
);

const TempoWarp = vst3.ara_tempo_warp.Builder(
    AraController,
    .{
        .regions = 4,
        .tempo_points = 64,
        .warp_points = 128,
    },
);

const spectral_frame_capacity = 1_024;
const SpectralSource = vst3.ara_spectral_transform.PreparedSource(
    AraController,
    f64,
    16,
    4,
    2,
    spectral_frame_capacity,
    4,
);
const SpectralGain = vst3.ara_spectral_transform.LinearGain(f64, 16);

const SourceId = @FieldType(
    AraController.PlaybackRegionRenderDescription,
    "audio_source",
);

const Definition = struct {
    source_cache: SourceCache = SourceCache.init(),
    content_fades: ContentFades = .{},
    tempo_warp: TempoWarp = .{},
    spectral_source: SpectralSource = .{},
    spectral_gain: SpectralGain = .{},
    ara_renderer: ?*AraRenderer = null,
    render_scratch: [2][256]f64 = @splat(@splat(0)),
    render_failures: u64 = 0,

    pub const name = "zig-vst3 ARA Playback";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const audio_input = false;
    pub const audio_output_layout: core.plugin.AudioBusLayout =
        .stereo;
    pub const event_input = false;
    pub const follow_host_transport = true;
    pub const Params = struct {};

    pub fn process(
        self: *@This(),
        context: *core.process.ProcessContext(f32),
    ) void {
        const renderer = self.ara_renderer orelse {
            context.clearOutputs();
            return;
        };
        const project_time_samples =
            context.projectTimeSamples() orelse {
                context.clearOutputs();
                return;
            };
        const left = context.outputChannel(0) orelse {
            context.clearOutputs();
            return;
        };
        const right = context.outputChannel(1) orelse {
            context.clearOutputs();
            return;
        };
        if (left.len > self.render_scratch[0].len) {
            context.clearOutputs();
            self.render_failures +|= 1;
            return;
        }
        const block_start_time = clock.BlockClock.seconds(
            project_time_samples,
            context.sampleRate(),
        ) catch {
            context.clearOutputs();
            self.render_failures +|= 1;
            return;
        };
        const outputs = [_][]f64{
            self.render_scratch[0][0..left.len],
            self.render_scratch[1][0..right.len],
        };
        renderer.render(
            block_start_time,
            context.sampleRate(),
            &outputs,
        ) catch {
            context.clearOutputs();
            self.render_failures +|= 1;
            return;
        };
        for (left, outputs[0]) |*destination, sample|
            destination.* = @floatCast(sample);
        for (right, outputs[1]) |*destination, sample|
            destination.* = @floatCast(sample);
    }

    pub fn process64(
        self: *@This(),
        context: *core.process.ProcessContext(f64),
    ) void {
        const renderer = self.ara_renderer orelse {
            context.clearOutputs();
            return;
        };
        const project_time_samples =
            context.projectTimeSamples() orelse {
                context.clearOutputs();
                return;
            };
        const left = context.outputChannel(0) orelse {
            context.clearOutputs();
            return;
        };
        const right = context.outputChannel(1) orelse {
            context.clearOutputs();
            return;
        };
        const outputs = [_][]f64{ left, right };
        const block_start_time = clock.BlockClock.seconds(
            project_time_samples,
            context.sampleRate(),
        ) catch {
            context.clearOutputs();
            self.render_failures +|= 1;
            return;
        };
        renderer.render(
            block_start_time,
            context.sampleRate(),
            &outputs,
        ) catch {
            context.clearOutputs();
            self.render_failures +|= 1;
        };
    }

    pub fn loadRegion(
        self: *@This(),
        controller: *AraController,
        description: *const AraController.PlaybackRegionRenderDescription,
    ) !u64 {
        if (description.transformation.reflect_tempo)
            _ = try self.tempo_warp
                .prepareRegionFromHostSource(
                controller,
                description,
            );
        const generation =
            try self.source_cache.loadRegion(
                controller,
                description,
            );
        if (description.source_sample_count > 0 and
            description.source_sample_count <= spectral_frame_capacity)
            _ = try self.spectral_source.prepare(
                description,
                self.source_cache.provider(AraRenderer),
                self.spectral_gain.transform(
                    SpectralSource.SpectralEngine.Transform,
                ),
            );
        if (description.transformation.fade_head or
            description.transformation.fade_tail)
            _ = try self.content_fades.analyzeRegion(
                controller,
                description,
            );
        if (self.ara_renderer) |renderer|
            renderer.refreshSourceState();
        return generation;
    }

    pub fn invalidateSource(
        self: *@This(),
        source_id: SourceId,
    ) !u64 {
        const generation =
            try self.source_cache.invalidate(source_id);
        _ = try self.spectral_source.invalidate();
        self.content_fades.invalidateSource(source_id);
        self.tempo_warp.invalidateSource(source_id);
        if (self.ara_renderer) |renderer|
            renderer.refreshSourceState();
        return generation;
    }
};

pub const Spec = core.plugin.PluginSpec(Definition);

pub const component_cid = vst3.tuid.inlineUid(
    0x45C5C64B,
    0x265849B6,
    0xA1FA4C6F,
    0xB0914294,
);
pub const controller_class_cid = vst3.tuid.inlineUid(
    0x4F9AC872,
    0x847849EF,
    0x97F8F44D,
    0xDBCC7A36,
);
pub const ara_main_factory_cid = vst3.tuid.inlineUid(
    0x2353977B,
    0x1F34442B,
    0x8F653B1B,
    0x3C89BBA2,
);

pub const Effect =
    vst3.zig_vst3_plugin_effect.HighLevelEffect(
        Definition,
        struct {
            pub const component_name = "AraPlaybackComponent";
            pub const controller_cid =
                controller_class_cid;
            pub const AraExtension = AraRenderer;
            pub const AraEntryPoint = AraRenderer.EntryPoint;
            pub const ara_factory = ara_factory_pointer;

            pub fn initAraExtension(
                processor: anytype,
            ) AraExtension {
                const plugin =
                    &processor.runtime.instance.plugin;
                var provider = plugin.spectral_source
                    .providerWithFallback(
                    AraRenderer,
                    plugin.source_cache.provider(AraRenderer),
                );
                plugin.content_fades.configureProvider(
                    AraRenderer,
                    &provider,
                );
                plugin.tempo_warp.configureProvider(
                    AraRenderer,
                    &provider,
                );
                return AraRenderer.init(provider);
            }

            pub fn bindAraExtension(
                processor: anytype,
                extension: *AraExtension,
            ) void {
                processor.runtime.instance.plugin.ara_renderer =
                    extension;
            }

            pub fn unbindAraExtension(
                processor: anytype,
                extension: *AraExtension,
            ) void {
                const plugin =
                    &processor.runtime.instance.plugin;
                if (plugin.ara_renderer == extension)
                    plugin.ara_renderer = null;
            }
        },
    );

const Controller =
    vst3.zig_vst3_plugin_effect.HighLevelEditController(
        Definition,
        "AraPlaybackController",
    );

const AraRegistration =
    vst3.ara_registration.MainFactoryRegistration(
        struct {
            pub const cid = ara_main_factory_cid;
            pub const name = "zig-vst3 ARA Main Factory";
            pub const vendor = Spec.vendor;
            pub const version = vst3.version;
            pub const factory =
                ara_factory_pointer;
        },
    );

const product_classes = [_]vst3.factory.ClassInfo{
    .{
        .cid = component_cid,
        .category = Spec.component_category,
        .name = Spec.component_class_name,
        .create = Effect.create,
    },
    .{
        .cid = controller_class_cid,
        .category = Spec.controller_category,
        .name = Spec.controller_class_name,
        .create = Controller.create,
    },
};
const factory_classes =
    vst3.ara_registration.appendMainFactoryClass(
        &product_classes,
        AraRegistration,
    );

const Factory = vst3.factory.StaticFactory3(
    .{
        .vendor = Spec.vendor,
        .url = Spec.url,
        .email = Spec.email,
    },
    &factory_classes,
);

comptime {
    vst3.entry.exportPlugin(Factory);
}

const TestAudio = struct {
    const ContentKind = enum {
        none,
        source_tempo,
        context_tempo,
    };

    samples: [2][64_000]f64 = @splat(@splat(0.0)),
    source_tempo: [2]raw.ARAContentTempoEntry = .{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 0.001, .quarterPosition = 2.0 },
    },
    context_tempo: [2]raw.ARAContentTempoEntry = .{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 0.001, .quarterPosition = 2.0 },
    },
    content_kind: ContentKind = .none,
    opened_content_readers: usize = 0,
    destroyed_content_readers: usize = 0,
    open_readers: usize = 0,
    destroyed_readers: usize = 0,
    next_reader_address: usize = 0x1000,
};

fn testAudio(
    host_ref: raw.ARAAudioAccessControllerHostRef,
) ?*TestAudio {
    const pointer = host_ref orelse return null;
    return @ptrCast(@alignCast(pointer));
}

fn testContent(
    host_ref: raw.ARAContentAccessControllerHostRef,
) ?*TestAudio {
    const pointer = host_ref orelse return null;
    return @ptrCast(@alignCast(pointer));
}

fn createAudioReader(
    host_ref: raw.ARAAudioAccessControllerHostRef,
    _: raw.ARAAudioSourceHostRef,
    use_64_bit_samples: raw.ARABool,
) callconv(.c) raw.ARAAudioReaderHostRef {
    if (use_64_bit_samples == raw.kARAFalse) return null;
    const audio = testAudio(host_ref) orelse return null;
    const address = audio.next_reader_address;
    audio.next_reader_address += 0x1000;
    audio.open_readers += 1;
    return @ptrFromInt(address);
}

fn readAudioSamples(
    host_ref: raw.ARAAudioAccessControllerHostRef,
    _: raw.ARAAudioReaderHostRef,
    sample_position: raw.ARASamplePosition,
    samples_per_channel: raw.ARASampleCount,
    buffers: [*c]const ?*anyopaque,
) callconv(.c) raw.ARABool {
    if (sample_position < 0 or
        samples_per_channel < 0 or
        buffers == null)
        return raw.kARAFalse;
    const audio = testAudio(host_ref) orelse
        return raw.kARAFalse;
    const start: usize = @intCast(sample_position);
    const count: usize = @intCast(samples_per_channel);
    if (start > audio.samples[0].len or
        count > audio.samples[0].len - start)
        return raw.kARAFalse;
    for (0..audio.samples.len) |channel| {
        const destination_pointer =
            buffers[channel] orelse return raw.kARAFalse;
        const destination: [*]f64 =
            @ptrCast(@alignCast(destination_pointer));
        @memcpy(
            destination[0..count],
            audio.samples[channel][start..][0..count],
        );
    }
    return raw.kARATrue;
}

fn destroyAudioReader(
    host_ref: raw.ARAAudioAccessControllerHostRef,
    _: raw.ARAAudioReaderHostRef,
) callconv(.c) void {
    const audio = testAudio(host_ref) orelse return;
    if (audio.open_readers == 0) return;
    audio.open_readers -= 1;
    audio.destroyed_readers += 1;
}

fn analysisProgress(
    _: raw.ARAModelUpdateControllerHostRef,
    _: raw.ARAAudioSourceHostRef,
    _: raw.ARAAnalysisProgressState,
    _: f32,
) callconv(.c) void {}

fn sourceContentChanged(
    _: raw.ARAModelUpdateControllerHostRef,
    _: raw.ARAAudioSourceHostRef,
    _: [*c]const raw.ARAContentTimeRange,
    _: raw.ARAContentUpdateFlags,
) callconv(.c) void {}

fn contextContentAvailable(
    _: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAMusicalContextHostRef,
    content_type: raw.ARAContentType,
) callconv(.c) raw.ARABool {
    return if (content_type ==
        raw.kARAContentTypeTempoEntries)
        raw.kARATrue
    else
        raw.kARAFalse;
}

fn contextContentGrade(
    _: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAMusicalContextHostRef,
    _: raw.ARAContentType,
) callconv(.c) raw.ARAContentGrade {
    return raw.kARAContentGradeApproved;
}

fn sourceContentAvailable(
    _: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAAudioSourceHostRef,
    content_type: raw.ARAContentType,
) callconv(.c) raw.ARABool {
    return if (content_type ==
        raw.kARAContentTypeTempoEntries)
        raw.kARATrue
    else
        raw.kARAFalse;
}

fn sourceContentGrade(
    _: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAAudioSourceHostRef,
    _: raw.ARAContentType,
) callconv(.c) raw.ARAContentGrade {
    return raw.kARAContentGradeApproved;
}

fn createContextContentReader(
    host_ref: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAMusicalContextHostRef,
    _: raw.ARAContentType,
    _: [*c]const raw.ARAContentTimeRange,
) callconv(.c) raw.ARAContentReaderHostRef {
    const audio = testContent(host_ref) orelse return null;
    if (audio.content_kind != .none) return null;
    audio.content_kind = .context_tempo;
    audio.opened_content_readers += 1;
    return @ptrFromInt(0x4000);
}

fn createSourceContentReader(
    host_ref: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAAudioSourceHostRef,
    _: raw.ARAContentType,
    _: [*c]const raw.ARAContentTimeRange,
) callconv(.c) raw.ARAContentReaderHostRef {
    const audio = testContent(host_ref) orelse return null;
    if (audio.content_kind != .none) return null;
    audio.content_kind = .source_tempo;
    audio.opened_content_readers += 1;
    return @ptrFromInt(0x5000);
}

fn contentEventCount(
    host_ref: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAContentReaderHostRef,
) callconv(.c) raw.ARAInt32 {
    const audio = testContent(host_ref) orelse return -1;
    return switch (audio.content_kind) {
        .none => -1,
        .source_tempo => @intCast(audio.source_tempo.len),
        .context_tempo => @intCast(audio.context_tempo.len),
    };
}

fn contentEventData(
    host_ref: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAContentReaderHostRef,
    event_index: raw.ARAInt32,
) callconv(.c) ?*const anyopaque {
    if (event_index < 0) return null;
    const audio = testContent(host_ref) orelse return null;
    const index: usize = @intCast(event_index);
    return switch (audio.content_kind) {
        .none => null,
        .source_tempo => if (index < audio.source_tempo.len)
            &audio.source_tempo[index]
        else
            null,
        .context_tempo => if (index < audio.context_tempo.len)
            &audio.context_tempo[index]
        else
            null,
    };
}

fn destroyContentReader(
    host_ref: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAContentReaderHostRef,
) callconv(.c) void {
    const audio = testContent(host_ref) orelse return;
    if (audio.content_kind == .none) return;
    audio.content_kind = .none;
    audio.destroyed_content_readers += 1;
}

fn testHost(
    audio: *TestAudio,
) raw.ARADocumentControllerHostInstance {
    const Host = struct {
        const audio_interface =
            raw.ARAAudioAccessControllerInterface{
                .structSize = @sizeOf(
                    raw.ARAAudioAccessControllerInterface,
                ),
                .createAudioReaderForSource = createAudioReader,
                .readAudioSamples = readAudioSamples,
                .destroyAudioReader = destroyAudioReader,
            };
        const archive =
            raw.ARAArchivingControllerInterface{
                .structSize = @sizeOf(
                    raw.ARAArchivingControllerInterface,
                ),
            };
        const content =
            raw.ARAContentAccessControllerInterface{
                .structSize = @sizeOf(
                    raw.ARAContentAccessControllerInterface,
                ),
                .isMusicalContextContentAvailable = contextContentAvailable,
                .getMusicalContextContentGrade = contextContentGrade,
                .createMusicalContextContentReader = createContextContentReader,
                .isAudioSourceContentAvailable = sourceContentAvailable,
                .getAudioSourceContentGrade = sourceContentGrade,
                .createAudioSourceContentReader = createSourceContentReader,
                .getContentReaderEventCount = contentEventCount,
                .getContentReaderDataForEvent = contentEventData,
                .destroyContentReader = destroyContentReader,
            };
        const model_update =
            raw.ARAModelUpdateControllerInterface{
                .structSize = @sizeOf(
                    raw.ARAModelUpdateControllerInterface,
                ),
                .notifyAudioSourceAnalysisProgress = analysisProgress,
                .notifyAudioSourceContentChanged = sourceContentChanged,
            };
        const playback =
            raw.ARAPlaybackControllerInterface{
                .structSize = @sizeOf(
                    raw.ARAPlaybackControllerInterface,
                ),
            };
    };
    return .{
        .structSize = @sizeOf(raw.ARADocumentControllerHostInstance),
        .audioAccessControllerHostRef = @ptrCast(audio),
        .audioAccessControllerInterface = &Host.audio_interface,
        .archivingControllerInterface = &Host.archive,
        .contentAccessControllerHostRef = @ptrCast(audio),
        .contentAccessControllerInterface = &Host.content,
        .modelUpdateControllerInterface = &Host.model_update,
        .playbackControllerInterface = &Host.playback,
    };
}

fn expectApproxSlices(
    comptime Sample: type,
    expected: []const Sample,
    actual: []const Sample,
    tolerance: Sample,
) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expected_sample, actual_sample|
        try std.testing.expectApproxEqAbs(
            expected_sample,
            actual_sample,
            tolerance,
        );
}

test "ARA playback product factory includes its main factory" {
    try std.testing.expectEqual(
        @as(usize, 6),
        ProductAraFactory.factory.analyzeableContentTypesCount,
    );
    try std.testing.expectEqual(
        raw.kARAContentTypeNotes,
        ProductAraFactory.factory.analyzeableContentTypes[0],
    );
    try std.testing.expectEqual(
        raw.kARAContentTypeStaticTuning,
        ProductAraFactory.factory.analyzeableContentTypes[1],
    );
    try std.testing.expectEqual(
        raw.kARAContentTypeTempoEntries,
        ProductAraFactory.factory.analyzeableContentTypes[2],
    );
    try std.testing.expectEqual(
        raw.kARAContentTypeBarSignatures,
        ProductAraFactory.factory.analyzeableContentTypes[3],
    );
    try std.testing.expectEqual(
        raw.kARAContentTypeKeySignatures,
        ProductAraFactory.factory.analyzeableContentTypes[4],
    );
    try std.testing.expectEqual(
        raw.kARAContentTypeSheetChords,
        ProductAraFactory.factory.analyzeableContentTypes[5],
    );
    try std.testing.expectEqual(
        raw.kARAPlaybackTransformationTimestretch |
            raw.kARAPlaybackTransformationTimestretchReflectingTempo |
            raw.kARAPlaybackTransformationContentBasedFades,
        ProductAraFactory.factory
            .supportedPlaybackTransformationFlags,
    );
    ProductAraFactory.resetForTesting();
    var assert_function: raw.ARAAssertFunction = null;
    var configuration = raw.ARAInterfaceConfiguration{
        .structSize = @sizeOf(raw.ARAInterfaceConfiguration),
        .desiredApiGeneration = raw.kARAAPIGeneration_2_3_Final,
        .assertFunctionAddress = &assert_function,
    };
    ProductAraFactory.factory.initializeARAWithConfiguration.?(
        &configuration,
    );
    try std.testing.expect(
        ProductAraFactory.takeLastError() == null,
    );
    var audio = TestAudio{};
    var host = testHost(&audio);
    var document_properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "ARA analysis product test",
    };
    const instance_pointer =
        ProductAraFactory.factory
            .createDocumentControllerWithDocument.?(
            &host,
            &document_properties,
        );
    try std.testing.expect(instance_pointer != null);
    const instance: *const raw.ARADocumentControllerInstance =
        @ptrCast(instance_pointer);
    const controller_api: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 2),
        controller_api.getProcessingAlgorithmsCount.?(
            instance.documentControllerRef,
        ),
    );
    const algorithm_properties =
        controller_api.getProcessingAlgorithmProperties.?(
            instance.documentControllerRef,
            0,
        );
    try std.testing.expect(algorithm_properties != null);
    try std.testing.expectEqualStrings(
        "dev.zig-vst3.analysis.general",
        std.mem.sliceTo(algorithm_properties[0].persistentID, 0),
    );
    for (&audio.samples[0], 0..) |*sample, sample_index| {
        const time =
            @as(f64, @floatFromInt(sample_index)) / 8_000.0;
        sample.* = 0.4 * @sin(
            2.0 * std.math.pi * 440.0 * time,
        );
        audio.samples[1][sample_index] = -sample.*;
    }
    controller_api.beginEditing.?(
        instance.documentControllerRef,
    );
    var source_properties = raw.ARAAudioSourceProperties{
        .structSize = @sizeOf(raw.ARAAudioSourceProperties),
        .name = "A4",
        .persistentID = "analysis-a4",
        .sampleCount = 512,
        .sampleRate = 8_000.0,
        .channelCount = 2,
        .merits64BitSamples = raw.kARATrue,
    };
    const source_ref = controller_api.createAudioSource.?(
        instance.documentControllerRef,
        null,
        &source_properties,
    );
    try std.testing.expect(source_ref != null);
    controller_api.endEditing.?(
        instance.documentControllerRef,
    );
    controller_api.enableAudioSourceSamplesAccess.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARATrue,
    );
    const note_request =
        [_]raw.ARAContentType{raw.kARAContentTypeNotes};
    controller_api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        source_ref,
        note_request.len,
        &note_request,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        controller_api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeNotes,
        ),
    );
    const note_reader =
        controller_api.createAudioSourceContentReader.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeNotes,
            null,
        );
    try std.testing.expect(note_reader != null);
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 1),
        controller_api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            note_reader,
        ),
    );
    const note_pointer =
        controller_api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            note_reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const note: *const raw.ARAContentNote =
        @ptrCast(@alignCast(note_pointer));
    try std.testing.expectEqual(@as(i32, 69), note.pitchNumber);
    try std.testing.expectApproxEqAbs(
        @as(f32, 440.0),
        note.frequency,
        1.0,
    );
    controller_api.destroyContentReader.?(
        instance.documentControllerRef,
        note_reader,
    );

    for (&audio.samples[0], 0..) |*sample, sample_index| {
        const pulse = sample_index % 4_000;
        const beat = sample_index / 4_000;
        const time =
            @as(f64, @floatFromInt(sample_index)) / 8_000.0;
        const accent: f64 = switch (beat % 4) {
            0 => 1.0,
            2 => 0.85,
            else => 0.7,
        };
        const transient = if (pulse < 40)
            accent *
                (1.0 -
                    @as(f64, @floatFromInt(pulse)) / 40.0)
        else
            0.0;
        const envelope =
            @min(1.0, @as(f64, @floatFromInt(pulse)) / 160.0);
        sample.* = transient;
        for ([_]u8{ 60, 64, 67 }) |pitch| {
            const frequency =
                440.0 * std.math.pow(
                    f64,
                    2.0,
                    (@as(f64, @floatFromInt(pitch)) - 69.0) /
                        12.0,
                );
            sample.* += 0.1 * envelope * @sin(
                2.0 * std.math.pi * frequency * time,
            );
        }
        audio.samples[1][sample_index] = sample.*;
    }
    controller_api.beginEditing.?(
        instance.documentControllerRef,
    );
    var meter_source_properties = raw.ARAAudioSourceProperties{
        .structSize = @sizeOf(raw.ARAAudioSourceProperties),
        .name = "4/4 pulse train",
        .persistentID = "analysis-meter",
        .sampleCount = audio.samples[0].len,
        .sampleRate = 8_000.0,
        .channelCount = 2,
        .merits64BitSamples = raw.kARATrue,
    };
    const meter_source_ref = controller_api.createAudioSource.?(
        instance.documentControllerRef,
        null,
        &meter_source_properties,
    );
    try std.testing.expect(meter_source_ref != null);
    controller_api.endEditing.?(
        instance.documentControllerRef,
    );
    controller_api.enableAudioSourceSamplesAccess.?(
        instance.documentControllerRef,
        meter_source_ref,
        raw.kARATrue,
    );
    const meter_request =
        [_]raw.ARAContentType{
            raw.kARAContentTypeBarSignatures,
        };
    controller_api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        meter_source_ref,
        meter_request.len,
        &meter_request,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        controller_api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            meter_source_ref,
            raw.kARAContentTypeBarSignatures,
        ),
    );
    const meter_reader =
        controller_api.createAudioSourceContentReader.?(
            instance.documentControllerRef,
            meter_source_ref,
            raw.kARAContentTypeBarSignatures,
            null,
        );
    try std.testing.expect(meter_reader != null);
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 1),
        controller_api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            meter_reader,
        ),
    );
    const meter_pointer =
        controller_api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            meter_reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const meter: *const raw.ARAContentBarSignature =
        @ptrCast(@alignCast(meter_pointer));
    try std.testing.expectEqual(@as(i32, 4), meter.numerator);
    try std.testing.expectEqual(@as(i32, 4), meter.denominator);
    try std.testing.expectEqual(@as(f64, 0.0), meter.position);
    controller_api.destroyContentReader.?(
        instance.documentControllerRef,
        meter_reader,
    );
    const key_request =
        [_]raw.ARAContentType{
            raw.kARAContentTypeKeySignatures,
            raw.kARAContentTypeSheetChords,
        };
    controller_api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        meter_source_ref,
        key_request.len,
        &key_request,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        controller_api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            meter_source_ref,
            raw.kARAContentTypeKeySignatures,
        ),
    );
    const key_reader =
        controller_api.createAudioSourceContentReader.?(
            instance.documentControllerRef,
            meter_source_ref,
            raw.kARAContentTypeKeySignatures,
            null,
        );
    try std.testing.expect(key_reader != null);
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 1),
        controller_api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            key_reader,
        ),
    );
    const key_pointer =
        controller_api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            key_reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const key: *const raw.ARAContentKeySignature =
        @ptrCast(@alignCast(key_pointer));
    try std.testing.expectEqual(@as(i32, 0), key.root);
    try std.testing.expectEqual(@as(u8, 0xff), key.intervals[0]);
    try std.testing.expectEqual(@as(u8, 0xff), key.intervals[4]);
    try std.testing.expectEqual(@as(u8, 0xff), key.intervals[7]);
    controller_api.destroyContentReader.?(
        instance.documentControllerRef,
        key_reader,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        controller_api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            meter_source_ref,
            raw.kARAContentTypeSheetChords,
        ),
    );
    const chord_reader =
        controller_api.createAudioSourceContentReader.?(
            instance.documentControllerRef,
            meter_source_ref,
            raw.kARAContentTypeSheetChords,
            null,
        );
    try std.testing.expect(chord_reader != null);
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 1),
        controller_api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            chord_reader,
        ),
    );
    const chord_pointer =
        controller_api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            chord_reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const chord: *const raw.ARAContentChord =
        @ptrCast(@alignCast(chord_pointer));
    try std.testing.expectEqual(@as(i32, 0), chord.root);
    try std.testing.expectEqual(@as(i32, 0), chord.bass);
    try std.testing.expectEqual(@as(u8, 1), chord.intervals[0]);
    try std.testing.expectEqual(@as(u8, 3), chord.intervals[4]);
    try std.testing.expectEqual(@as(u8, 5), chord.intervals[7]);
    controller_api.destroyContentReader.?(
        instance.documentControllerRef,
        chord_reader,
    );
    controller_api.enableAudioSourceSamplesAccess.?(
        instance.documentControllerRef,
        meter_source_ref,
        raw.kARAFalse,
    );
    controller_api.enableAudioSourceSamplesAccess.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAFalse,
    );
    controller_api.destroyDocumentController.?(
        instance.documentControllerRef,
    );
    ProductAraFactory.factory.uninitializeARA.?();
    try std.testing.expect(
        ProductAraFactory.takeLastError() == null,
    );

    const factory = Factory.getPluginFactory() orelse
        return error.MissingFactory;
    try std.testing.expectEqual(
        @as(types.int32, 3),
        factory.vtable.countClasses(factory),
    );
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        factory.vtable.createInstance(
            factory,
            @ptrCast(&ara_main_factory_cid),
            @ptrCast(&vst3.ara_vst3.main_factory_iid),
            &out,
        ),
    );
    const main_factory: *vst3.ara_vst3.IMainFactory =
        @ptrCast(@alignCast(out orelse
            return error.MissingFactory));
    defer _ = main_factory.vtable.release(main_factory);
    try std.testing.expect(
        main_factory.vtable.getFactory(main_factory) ==
            ara_factory_pointer,
    );
}

test "ARA playback product bounds inline spectral storage" {
    try std.testing.expect(@sizeOf(SpectralSource) <= 160 * 1024);
}

const BoundedStackCreation = struct {
    succeeded: bool = false,
};

fn createEffectWithBoundedStack(context: *BoundedStackCreation) void {
    var component_out: ?*anyopaque = null;
    if (Effect.create(
        @ptrCast(&vst.ivstcomponent.icomponent_iid),
        &component_out,
    ) != types.kResultOk) return;
    const component: *vst.ivstcomponent.IComponent =
        @ptrCast(@alignCast(component_out orelse return));
    _ = component.vtable.release(component);
    context.succeeded = true;
}

test "ARA playback product constructs on a bounded host stack" {
    var context = BoundedStackCreation{};
    const thread = try std.Thread.spawn(
        .{ .stack_size = 1024 * 1024 },
        createEffectWithBoundedStack,
        .{&context},
    );
    thread.join();
    try std.testing.expect(context.succeeded);
}

test "ARA playback product fills cache and renders through VST3" {
    var audio = TestAudio{};
    @memcpy(
        audio.samples[0][0..8],
        &[_]f64{ 1, -1, 2, 3, 4, 5, 6, -7 },
    );
    @memcpy(
        audio.samples[1][0..8],
        &[_]f64{ 8, -9, 10, 11, 12, 13, 14, -15 },
    );
    var host = testHost(&audio);
    var document_properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "ARA playback product test",
    };
    var controller: AraController = undefined;
    try controller.init(
        ProductAraFactory.factoryPointer(),
        &host,
        &document_properties,
    );
    try controller.document.beginEditing();
    const musical_context =
        try controller.document.createMusicalContext(
            null,
            .{ .name = "Song", .order_index = 0 },
        );
    const sequence =
        try controller.document.createRegionSequence(
            null,
            .{
                .name = "Track",
                .order_index = 0,
                .musical_context = musical_context,
            },
        );
    const source =
        try controller.document.createAudioSource(
            null,
            .{
                .name = "Source",
                .persistent_id = "source",
                .sample_count = 8,
                .sample_rate = 8_000,
                .channel_count = 2,
            },
        );
    const modification =
        try controller.document.createAudioModification(
            source,
            null,
            .{
                .name = "Modification",
                .persistent_id = "modification",
            },
        );
    const region =
        try controller.document.createPlaybackRegion(
            modification,
            null,
            .{
                .name = "Region",
                .region_sequence = sequence,
                .start_in_modification_time = 0,
                .duration_in_modification_time = 0.001,
                .start_in_playback_time = 0,
                .duration_in_playback_time = 0.001,
                .transformation = .{
                    .time_stretch = true,
                    .reflect_tempo = true,
                    .fade_head = true,
                    .fade_tail = true,
                },
            },
        );
    _ = try controller.document.endEditing();
    try controller.setAudioSourceSamplesAccess(source, true);

    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        Effect.create(
            @ptrCast(&vst.ivstcomponent.icomponent_iid),
            &component_out,
        ),
    );
    const component: *vst.ivstcomponent.IComponent =
        @ptrCast(@alignCast(component_out orelse
            return error.MissingComponent));
    defer _ = component.vtable.release(component);
    const processor_impl = Effect.processorInstance(component);
    const plugin = &processor_impl.runtime.instance.plugin;
    const region_ref = try controller.playbackRegionRef(region);
    const render_description =
        try controller.playbackRegionRenderDescription(region_ref);
    _ = try plugin.loadRegion(
        &controller,
        &render_description,
    );
    try std.testing.expectEqual(@as(usize, 0), audio.open_readers);
    try std.testing.expectEqual(
        @as(usize, 2),
        audio.destroyed_content_readers,
    );
    const renderer = plugin.ara_renderer orelse
        return error.MissingRenderer;
    try std.testing.expectEqual(
        error.NotInitialized,
        renderer.takeError().?,
    );

    var entry_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.queryInterface(
            component,
            &vst3.ara_vst3.plug_in_entry_point_2_iid,
            &entry_out,
        ),
    );
    const entry: *vst3.ara_vst3.IPlugInEntryPoint2 =
        @ptrCast(@alignCast(entry_out orelse
            return error.MissingEntryPoint));
    defer _ = entry.vtable.release(entry);
    const extension_opaque =
        entry.vtable.bindToDocumentControllerWithRoles(
            entry,
            @ptrCast(&controller),
            vst3.ara_vst3.all_roles,
            vst3.ara_vst3.playback_renderer_role,
        ) orelse return error.MissingExtension;
    const extension: *const raw.ARAPlugInExtensionInstance =
        @ptrCast(@alignCast(extension_opaque));
    const playback = extension.playbackRendererInterface orelse
        return error.MissingPlaybackRenderer;
    playback[0].addPlaybackRegion.?(
        extension.playbackRendererRef,
        region_ref,
    );
    try std.testing.expectEqual(
        null,
        renderer.takeError(),
    );

    var direct_left: [4]f64 = @splat(-1);
    var direct_right: [4]f64 = @splat(-1);
    const direct_outputs = [_][]f64{
        &direct_left,
        &direct_right,
    };
    try renderer.render(0, 8_000, &direct_outputs);
    try expectApproxSlices(
        f64,
        &.{ 0, -0.15625, 1, 2.53125 },
        &direct_left,
        1.0e-12,
    );
    try expectApproxSlices(
        f64,
        &.{ 0, -1.40625, 5, 9.28125 },
        &direct_right,
        1.0e-12,
    );
    try renderer.render(0.0005, 8_000, &direct_outputs);
    try expectApproxSlices(
        f64,
        &.{ 4, 4.21875, 3, -1.09375 },
        &direct_left,
        1.0e-12,
    );
    try expectApproxSlices(
        f64,
        &.{ 12, 10.96875, 7, -2.34375 },
        &direct_right,
        1.0e-12,
    );

    plugin.spectral_gain = .{ .low = 0.5, .high = 0.5 };
    var spectral_state: [18]u8 = undefined;
    _ = try plugin.spectral_gain.encode(&spectral_state);
    plugin.spectral_gain = .{};
    plugin.spectral_gain = try SpectralGain.decode(&spectral_state);
    _ = try plugin.loadRegion(&controller, &render_description);
    try renderer.render(0, 8_000, &direct_outputs);
    try expectApproxSlices(
        f64,
        &.{ 0, -0.078125, 0.5, 1.265625 },
        &direct_left,
        1.0e-12,
    );
    try expectApproxSlices(
        f64,
        &.{ 0, -0.703125, 2.5, 4.640625 },
        &direct_right,
        1.0e-12,
    );
    plugin.spectral_gain = .{};
    _ = try plugin.loadRegion(&controller, &render_description);

    var audio_processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.queryInterface(
            component,
            &vst.ivstaudioprocessor.iaudio_processor_iid,
            &audio_processor_out,
        ),
    );
    const audio_processor: *vst.ivstaudioprocessor.IAudioProcessor =
        @ptrCast(@alignCast(audio_processor_out orelse
            return error.MissingProcessor));
    defer _ = audio_processor.vtable.release(audio_processor);
    var setup = vst.ivstaudioprocessor.ProcessSetup{
        .processMode = @intFromEnum(
            vst.ivstaudioprocessor.ProcessModes.kRealtime,
        ),
        .symbolicSampleSize = @intFromEnum(
            vst.ivstaudioprocessor.SymbolicSampleSizes.kSample32,
        ),
        .sampleRate = 8_000,
        .maxSamplesPerBlock = 4,
    };
    try std.testing.expectEqual(
        types.kResultOk,
        audio_processor.vtable.setupProcessing(
            audio_processor,
            &setup,
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.setActive(component, 1),
    );
    defer _ = component.vtable.setActive(component, 0);

    var left: [4]f32 = @splat(-1);
    var right: [4]f32 = @splat(-1);
    var output_channel_pointers = [_][*]f32{
        &left,
        &right,
    };
    var output_buses =
        [_]vst.ivstaudioprocessor.AudioBusBuffers{.{
            .numChannels = 2,
            .channelBuffers = .{
                .channelBuffers32 = output_channel_pointers[0..].ptr,
            },
        }};
    var process_context =
        vst.ivstprocesscontext.ProcessContext{
            .sampleRate = 8_000,
            .projectTimeSamples = 0,
        };
    var process_data = vst.ivstaudioprocessor.ProcessData{
        .processMode = @intFromEnum(
            vst.ivstaudioprocessor.ProcessModes.kRealtime,
        ),
        .symbolicSampleSize = @intFromEnum(
            vst.ivstaudioprocessor.SymbolicSampleSizes.kSample32,
        ),
        .numSamples = 4,
        .numInputs = 0,
        .numOutputs = 1,
        .outputs = &output_buses,
        .processContext = &process_context,
    };
    try std.testing.expectEqual(
        types.kResultOk,
        audio_processor.vtable.process(
            audio_processor,
            &process_data,
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, -0.15625, 1, 2.53125 },
        &left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, -1.40625, 5, 9.28125 },
        &right,
    );
    try std.testing.expectEqual(@as(u64, 0), plugin.render_failures);
    try std.testing.expectEqual(@as(usize, 4), audio.destroyed_readers);

    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.setActive(component, 0),
    );
    setup.symbolicSampleSize = @intFromEnum(
        vst.ivstaudioprocessor.SymbolicSampleSizes.kSample64,
    );
    try std.testing.expectEqual(
        types.kResultOk,
        audio_processor.vtable.setupProcessing(
            audio_processor,
            &setup,
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        component.vtable.setActive(component, 1),
    );

    var left64: [4]f64 = @splat(-1);
    var right64: [4]f64 = @splat(-1);
    var output_channel_pointers64 = [_][*]f64{
        &left64,
        &right64,
    };
    var output_buses64 =
        [_]vst.ivstaudioprocessor.AudioBusBuffers{.{
            .numChannels = 2,
            .channelBuffers = .{
                .channelBuffers64 = output_channel_pointers64[0..].ptr,
            },
        }};
    var process_data64 = vst.ivstaudioprocessor.ProcessData{
        .processMode = @intFromEnum(
            vst.ivstaudioprocessor.ProcessModes.kRealtime,
        ),
        .symbolicSampleSize = @intFromEnum(
            vst.ivstaudioprocessor.SymbolicSampleSizes.kSample64,
        ),
        .numSamples = 4,
        .numInputs = 0,
        .numOutputs = 1,
        .outputs = &output_buses64,
        .processContext = &process_context,
    };
    try std.testing.expectEqual(
        types.kResultOk,
        audio_processor.vtable.process(
            audio_processor,
            &process_data64,
        ),
    );
    try expectApproxSlices(
        f64,
        &.{ 0, -0.15625, 1, 2.53125 },
        &left64,
        1.0e-12,
    );
    try expectApproxSlices(
        f64,
        &.{ 0, -1.40625, 5, 9.28125 },
        &right64,
        1.0e-12,
    );

    _ = try plugin.invalidateSource(source);
    @memset(&left64, -1);
    @memset(&right64, -1);
    try std.testing.expectEqual(
        types.kResultOk,
        audio_processor.vtable.process(
            audio_processor,
            &process_data64,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{0} ** 4),
        &left64,
    );
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{0} ** 4),
        &right64,
    );
}
