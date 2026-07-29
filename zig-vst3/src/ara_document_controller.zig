const std = @import("std");
const ara = @import("zig-vst3-ara");
const model_api = @import("ara_model.zig");

pub const raw = ara.raw;

pub const Error = model_api.Error || error{
    InvalidController,
    ControllerDestroyed,
    InvalidStructSize,
    MissingHostInterface,
    InvalidProperties,
    InvalidReference,
    UnsupportedChannelArrangement,
    UnsupportedTransformation,
    InvalidFilter,
    ArchiveAccessFailed,
    InvalidArchive,
    ArchiveTooLarge,
    AudioAccessDisabled,
    AudioAccessFailed,
    AudioReaderUnavailable,
    InvalidAudioBuffer,
    ContentReaderUnavailable,
    ContentCountOverflow,
    InvalidProcessingAlgorithm,
};

pub fn Controller(comptime limits: model_api.Limits) type {
    const Model = model_api.Document(limits);
    const archive_capacity =
        20 +
        (limits.audio_sources + limits.audio_modifications) *
            (2 + limits.persistent_id_bytes) +
        limits.archive_extension_bytes;

    return struct {
        const Self = @This();
        pub const ReleaseCallback =
            *const fn (?*anyopaque, *Self) void;
        pub const maximum_audio_channels = 64;

        pub const ContentObject = union(enum) {
            audio_source: Model.AudioSourceId,
            audio_modification: Model.AudioModificationId,
            playback_region: Model.PlaybackRegionId,
        };

        pub const ContentProvider = struct {
            context: ?*anyopaque,
            vtable: *const VTable,

            pub const VTable = struct {
                archive_size: ?*const fn (
                    ?*anyopaque,
                    []const Model.AudioSourceId,
                ) usize = null,
                store_archive: ?*const fn (
                    ?*anyopaque,
                    []const Model.AudioSourceId,
                    []u8,
                ) bool = null,
                restore_archive: ?*const fn (
                    ?*anyopaque,
                    []const ArchiveSourceMapping,
                    []const u8,
                ) bool = null,
                analysis_incomplete: ?*const fn (
                    ?*anyopaque,
                    Model.AudioSourceId,
                    raw.ARAContentType,
                ) bool = null,
                request_analysis: ?*const fn (
                    ?*anyopaque,
                    Model.AudioSourceId,
                    []const raw.ARAContentType,
                ) bool = null,
                source_content_changed: ?*const fn (
                    ?*anyopaque,
                    Model.AudioSourceId,
                    ?raw.ARAContentTimeRange,
                    raw.ARAContentUpdateFlags,
                ) void = null,
                processing_algorithms_count: ?*const fn (
                    ?*anyopaque,
                ) usize = null,
                processing_algorithm_properties: ?*const fn (
                    ?*anyopaque,
                    usize,
                ) ?*const raw.ARAProcessingAlgorithmProperties = null,
                processing_algorithm_for_source: ?*const fn (
                    ?*anyopaque,
                    Model.AudioSourceId,
                ) ?usize = null,
                request_processing_algorithm: ?*const fn (
                    ?*anyopaque,
                    Model.AudioSourceId,
                    usize,
                ) bool = null,
                is_available: *const fn (
                    ?*anyopaque,
                    *const ContentObject,
                    raw.ARAContentType,
                ) bool,
                grade: *const fn (
                    ?*anyopaque,
                    *const ContentObject,
                    raw.ARAContentType,
                ) raw.ARAContentGrade,
                event_count: *const fn (
                    ?*anyopaque,
                    *const ContentObject,
                    raw.ARAContentType,
                    ?*const raw.ARAContentTimeRange,
                    *usize,
                ) bool,
                event_data: *const fn (
                    ?*anyopaque,
                    *const ContentObject,
                    raw.ARAContentType,
                    ?*const raw.ARAContentTimeRange,
                    usize,
                ) ?*const anyopaque,
            };
        };

        pub const ArchiveSourceMapping = struct {
            archive_id: []const u8,
            current_id: ?Model.AudioSourceId,
        };

        pub const ModelPublicationSink = struct {
            context: ?*anyopaque = null,
            changed: *const fn (
                ?*anyopaque,
                *Self,
                u64,
            ) void,
        };

        pub const ModelObserverId = struct {
            index: u16,
            generation: u32,
        };

        const ModelObserverSlot = struct {
            generation: u32 = 1,
            sink: ?ModelPublicationSink = null,
        };

        pub const PlaybackRegionRenderDescription = struct {
            model_revision: u64,
            playback_region: Model.PlaybackRegionId,
            audio_modification: Model.AudioModificationId,
            audio_source: Model.AudioSourceId,
            source_sample_count: i64,
            source_sample_rate: f64,
            source_channel_count: i32,
            source_samples_access_enabled: bool,
            transformation: model_api.PlaybackTransformation,
            start_in_modification_time: f64,
            duration_in_modification_time: f64,
            start_in_playback_time: f64,
            duration_in_playback_time: f64,
        };

        const ContentReaderId = struct {
            index: u16,
            generation: u32,
        };

        const ContentReader = struct {
            object: ContentObject,
            content_type: raw.ARAContentType,
            range: ?raw.ARAContentTimeRange,
            event_count: usize,
        };

        const ContentReaderSlot = struct {
            generation: u32 = 1,
            value: ?ContentReader = null,
        };

        const AudioReaderId = struct {
            index: u16,
            generation: u32,
        };

        const AudioReaderState = struct {
            source_id: Model.AudioSourceId,
            host_reader: raw.ARAAudioReaderHostRef,
            use_64_bit_samples: bool,
        };

        const AudioReaderSlot = struct {
            generation: u32 = 1,
            value: ?AudioReaderState = null,
            closing: std.atomic.Value(bool) =
                std.atomic.Value(bool).init(false),
            active_reads: std.atomic.Value(u32) =
                std.atomic.Value(u32).init(0),
        };

        const AudioReadLease = struct {
            slot: *AudioReaderSlot,
            state: *const AudioReaderState,

            fn release(self: AudioReadLease) void {
                const previous =
                    self.slot.active_reads.fetchSub(
                        1,
                        .release,
                    );
                std.debug.assert(previous != 0);
            }
        };

        pub const AudioReader = struct {
            controller: *Self,
            reader_id: AudioReaderId,
            source_id: Model.AudioSourceId,
            host_reader: raw.ARAAudioReaderHostRef,
            use_64_bit_samples: bool,
            closed: bool = false,

            pub fn readF32(
                self: *AudioReader,
                sample_position: i64,
                buffers: []const []f32,
            ) Error!void {
                if (self.use_64_bit_samples)
                    return error.InvalidAudioBuffer;
                try self.read(f32, sample_position, buffers);
            }

            pub fn readF64(
                self: *AudioReader,
                sample_position: i64,
                buffers: []const []f64,
            ) Error!void {
                if (!self.use_64_bit_samples)
                    return error.InvalidAudioBuffer;
                try self.read(f64, sample_position, buffers);
            }

            pub fn close(self: *AudioReader) void {
                if (self.closed) return;
                self.controller.closeAudioReader(
                    self.reader_id,
                );
                self.closed = true;
            }

            fn read(
                self: *AudioReader,
                comptime Sample: type,
                sample_position: i64,
                buffers: []const []Sample,
            ) Error!void {
                if (self.closed) return error.AudioReaderUnavailable;
                const lease = self.controller.acquireAudioReader(
                    self.reader_id,
                ) orelse
                    return error.AudioReaderUnavailable;
                defer lease.release();
                const state = lease.state;
                if (state.source_id.index != self.source_id.index or
                    state.source_id.generation !=
                        self.source_id.generation or
                    state.host_reader != self.host_reader or
                    state.use_64_bit_samples !=
                        self.use_64_bit_samples)
                    return error.AudioReaderUnavailable;
                const source = self.controller.document.audioSource(
                    self.source_id,
                ) orelse return error.InvalidHandle;
                if (!source.samples_access_enabled)
                    return error.AudioAccessDisabled;
                if (source.channel_count <= 0 or
                    buffers.len != @as(usize, @intCast(
                        source.channel_count,
                    )) or
                    buffers.len > maximum_audio_channels)
                    return error.InvalidAudioBuffer;
                const sample_count = if (buffers.len == 0)
                    0
                else
                    buffers[0].len;
                for (buffers) |buffer| {
                    if (buffer.len != sample_count)
                        return error.InvalidAudioBuffer;
                }
                if (sample_count > std.math.maxInt(i64))
                    return error.InvalidAudioBuffer;
                var pointers: [maximum_audio_channels]?*anyopaque =
                    @splat(null);
                for (buffers, 0..) |buffer, channel| {
                    pointers[channel] = @ptrCast(buffer.ptr);
                }
                const host_interface =
                    self.controller.audioAccessInterface() orelse
                    return error.MissingHostInterface;
                const callback = host_interface.readAudioSamples orelse
                    return error.MissingHostInterface;
                const succeeded = callback(
                    self.controller.host.audioAccessControllerHostRef,
                    self.host_reader,
                    sample_position,
                    @intCast(sample_count),
                    &pointers,
                );
                if (succeeded != raw.kARATrue)
                    return error.AudioAccessFailed;
            }
        };

        pub const interface = raw.ARADocumentControllerInterface{
            .structSize = @sizeOf(raw.ARADocumentControllerInterface),
            .destroyDocumentController = destroyDocumentController,
            .getFactory = getFactory,
            .beginEditing = beginEditing,
            .endEditing = endEditing,
            .notifyModelUpdates = notifyModelUpdates,
            .beginRestoringDocumentFromArchive = beginRestoringDocumentFromArchive,
            .endRestoringDocumentFromArchive = endRestoringDocumentFromArchive,
            .storeDocumentToArchive = storeDocumentToArchive,
            .updateDocumentProperties = updateDocumentProperties,
            .createMusicalContext = createMusicalContext,
            .updateMusicalContextProperties = updateMusicalContextProperties,
            .updateMusicalContextContent = updateMusicalContextContent,
            .destroyMusicalContext = destroyMusicalContext,
            .createAudioSource = createAudioSource,
            .updateAudioSourceProperties = updateAudioSourceProperties,
            .updateAudioSourceContent = updateAudioSourceContent,
            .enableAudioSourceSamplesAccess = enableAudioSourceSamplesAccess,
            .deactivateAudioSourceForUndoHistory = deactivateAudioSourceForUndoHistory,
            .destroyAudioSource = destroyAudioSource,
            .createAudioModification = createAudioModification,
            .cloneAudioModification = cloneAudioModification,
            .updateAudioModificationProperties = updateAudioModificationProperties,
            .deactivateAudioModificationForUndoHistory = deactivateAudioModificationForUndoHistory,
            .destroyAudioModification = destroyAudioModification,
            .createPlaybackRegion = createPlaybackRegion,
            .updatePlaybackRegionProperties = updatePlaybackRegionProperties,
            .destroyPlaybackRegion = destroyPlaybackRegion,
            .isAudioSourceContentAvailable = isAudioSourceContentAvailable,
            .isAudioSourceContentAnalysisIncomplete = isAudioSourceContentAnalysisIncomplete,
            .requestAudioSourceContentAnalysis = requestAudioSourceContentAnalysis,
            .getAudioSourceContentGrade = getAudioSourceContentGrade,
            .createAudioSourceContentReader = createAudioSourceContentReader,
            .isAudioModificationContentAvailable = isAudioModificationContentAvailable,
            .getAudioModificationContentGrade = getAudioModificationContentGrade,
            .createAudioModificationContentReader = createAudioModificationContentReader,
            .isPlaybackRegionContentAvailable = isPlaybackRegionContentAvailable,
            .getPlaybackRegionContentGrade = getPlaybackRegionContentGrade,
            .createPlaybackRegionContentReader = createPlaybackRegionContentReader,
            .getContentReaderEventCount = getContentReaderEventCount,
            .getContentReaderDataForEvent = getContentReaderDataForEvent,
            .destroyContentReader = destroyContentReader,
            .createRegionSequence = createRegionSequence,
            .updateRegionSequenceProperties = updateRegionSequenceProperties,
            .destroyRegionSequence = destroyRegionSequence,
            .getPlaybackRegionHeadAndTailTime = getPlaybackRegionHeadAndTailTime,
            .restoreObjectsFromArchive = restoreObjectsFromArchive,
            .storeObjectsToArchive = storeObjectsToArchive,
            .getProcessingAlgorithmsCount = getProcessingAlgorithmsCount,
            .getProcessingAlgorithmProperties = getProcessingAlgorithmProperties,
            .getProcessingAlgorithmForAudioSource = getProcessingAlgorithmForAudioSource,
            .requestProcessingAlgorithmForAudioSource = requestProcessingAlgorithmForAudioSource,
            .isLicensedForCapabilities = isLicensedForCapabilities,
            .isAudioModificationPreservingAudioSourceSignal = isAudioModificationPreservingAudioSourceSignal,
        };

        document: Model = .{},
        host: raw.ARADocumentControllerHostInstance,
        factory: *const raw.ARAFactory,
        instance: raw.ARADocumentControllerInstance = .{},
        document_name: [limits.name_bytes]u8 = @splat(0),
        document_name_len: u16 = 0,
        last_error: ?Error = null,
        destroyed: bool = false,
        release_context: ?*anyopaque = null,
        release_callback: ?ReleaseCallback = null,
        archive_buffer: [archive_capacity]u8 = @splat(0),
        pending_archive_size: usize = 0,
        pending_archive_reader: raw.ARAArchiveReaderHostRef = null,
        audio_readers: [limits.audio_readers]AudioReaderSlot =
            @splat(.{}),
        content_provider: ?ContentProvider = null,
        model_observers: [limits.model_observers]ModelObserverSlot =
            @splat(.{}),
        document_data_changed_pending: bool = false,
        content_readers: [limits.content_readers]ContentReaderSlot =
            @splat(.{}),

        pub fn init(
            self: *Self,
            factory: *const raw.ARAFactory,
            host: *const raw.ARADocumentControllerHostInstance,
            properties: *const raw.ARADocumentProperties,
        ) Error!void {
            return self.initWithRelease(
                factory,
                host,
                properties,
                null,
                null,
            );
        }

        pub fn initWithRelease(
            self: *Self,
            factory: *const raw.ARAFactory,
            host: *const raw.ARADocumentControllerHostInstance,
            properties: *const raw.ARADocumentProperties,
            release_context: ?*anyopaque,
            release_callback: ?ReleaseCallback,
        ) Error!void {
            try validateHost(host);
            if (properties.structSize < raw.kARADocumentPropertiesMinSize)
                return error.InvalidStructSize;
            self.* = .{
                .host = host.*,
                .factory = factory,
                .release_context = release_context,
                .release_callback = release_callback,
            };
            try self.setDocumentName(cString(
                properties.name,
                limits.name_bytes,
            ) catch return error.InvalidProperties);
            self.instance = .{
                .structSize = @sizeOf(raw.ARADocumentControllerInstance),
                .documentControllerRef = @ptrCast(self),
                .documentControllerInterface = &interface,
            };
        }

        pub fn documentControllerInstance(
            self: *const Self,
        ) *const raw.ARADocumentControllerInstance {
            return &self.instance;
        }

        pub fn takeLastError(self: *Self) ?Error {
            const result = self.last_error;
            self.last_error = null;
            return result;
        }

        pub fn documentName(self: *const Self) []const u8 {
            return self.document_name[0..self.document_name_len];
        }

        pub fn fromDocumentControllerRef(
            controller_ref: raw.ARADocumentControllerRef,
        ) Error!*Self {
            return usable(controller_ref);
        }

        pub fn addModelPublicationSink(
            self: *Self,
            sink: ModelPublicationSink,
        ) Error!ModelObserverId {
            if (self.destroyed) return error.ControllerDestroyed;
            if (self.document.isEditing()) return error.ObjectInUse;
            for (&self.model_observers, 0..) |*slot, index| {
                if (slot.sink != null) continue;
                slot.sink = sink;
                return .{
                    .index = @intCast(index),
                    .generation = slot.generation,
                };
            }
            return error.CapacityExceeded;
        }

        pub fn removeModelPublicationSink(
            self: *Self,
            observer_id: ModelObserverId,
        ) void {
            if (observer_id.index >= self.model_observers.len)
                return;
            const slot = &self.model_observers[observer_id.index];
            if (slot.generation != observer_id.generation)
                return;
            slot.sink = null;
            slot.generation +%= 1;
            if (slot.generation == 0) slot.generation = 1;
        }

        pub fn markDocumentDataChanged(self: *Self) Error!void {
            if (self.destroyed) return error.ControllerDestroyed;
            self.document_data_changed_pending = true;
        }

        pub fn resolvePlaybackRegionRef(
            self: *const Self,
            playback_region_ref: raw.ARAPlaybackRegionRef,
        ) Error!Model.PlaybackRegionId {
            if (self.destroyed) return error.ControllerDestroyed;
            const id = decodeRef(
                Model.PlaybackRegionId,
                playback_region_ref,
            ) orelse return error.InvalidReference;
            if (self.document.playbackRegion(id) == null)
                return error.InvalidHandle;
            return id;
        }

        pub fn playbackRegionRef(
            self: *const Self,
            playback_region_id: Model.PlaybackRegionId,
        ) Error!raw.ARAPlaybackRegionRef {
            if (self.destroyed) return error.ControllerDestroyed;
            if (self.document.playbackRegion(
                playback_region_id,
            ) == null)
                return error.InvalidHandle;
            return encodeRef(
                raw.ARAPlaybackRegionRef,
                playback_region_id,
            );
        }

        pub fn playbackRegionRenderDescription(
            self: *const Self,
            playback_region_ref: raw.ARAPlaybackRegionRef,
        ) Error!PlaybackRegionRenderDescription {
            const region_id =
                try self.resolvePlaybackRegionRef(
                    playback_region_ref,
                );
            const region =
                self.document.playbackRegion(region_id) orelse
                return error.InvalidHandle;
            const modification = self.document.audioModification(
                region.audio_modification,
            ) orelse return error.InvalidHandle;
            const source = self.document.audioSource(
                modification.audio_source,
            ) orelse return error.InvalidHandle;
            return .{
                .model_revision = self.document.currentRevision(),
                .playback_region = region_id,
                .audio_modification = region.audio_modification,
                .audio_source = modification.audio_source,
                .source_sample_count = source.sample_count,
                .source_sample_rate = source.sample_rate,
                .source_channel_count = source.channel_count,
                .source_samples_access_enabled = source.samples_access_enabled,
                .transformation = region.transformation,
                .start_in_modification_time = region.start_in_modification_time,
                .duration_in_modification_time = region.duration_in_modification_time,
                .start_in_playback_time = region.start_in_playback_time,
                .duration_in_playback_time = region.duration_in_playback_time,
            };
        }

        pub fn openAudioReader(
            self: *Self,
            source_id: Model.AudioSourceId,
            use_64_bit_samples: bool,
        ) Error!AudioReader {
            const source = self.document.audioSource(source_id) orelse
                return error.InvalidHandle;
            if (!source.samples_access_enabled)
                return error.AudioAccessDisabled;
            if (source.channel_count > maximum_audio_channels)
                return error.InvalidChannelCount;
            const reader_index = self.vacantAudioReaderIndex() orelse
                return error.CapacityExceeded;
            const host_interface = self.audioAccessInterface() orelse
                return error.MissingHostInterface;
            const callback =
                host_interface.createAudioReaderForSource orelse
                return error.MissingHostInterface;
            const host_source: raw.ARAAudioSourceHostRef =
                if (source.host_ref) |pointer|
                    @ptrCast(pointer)
                else
                    null;
            const host_reader = callback(
                self.host.audioAccessControllerHostRef,
                host_source,
                if (use_64_bit_samples)
                    raw.kARATrue
                else
                    raw.kARAFalse,
            ) orelse return error.AudioReaderUnavailable;
            const reader_id = AudioReaderId{
                .index = @intCast(reader_index),
                .generation = self.audio_readers[reader_index].generation,
            };
            self.audio_readers[reader_index].value = .{
                .source_id = source_id,
                .host_reader = host_reader,
                .use_64_bit_samples = use_64_bit_samples,
            };
            return .{
                .controller = self,
                .reader_id = reader_id,
                .source_id = source_id,
                .host_reader = host_reader,
                .use_64_bit_samples = use_64_bit_samples,
            };
        }

        pub fn setAudioSourceSamplesAccess(
            self: *Self,
            source_id: Model.AudioSourceId,
            enabled: bool,
        ) Error!void {
            const source = self.document.audioSource(source_id) orelse
                return error.InvalidHandle;
            if (source.samples_access_enabled == enabled) return;
            if (!enabled)
                self.closeAudioReadersForSource(source_id);
            try self.document.enableAudioSourceSamplesAccess(
                source_id,
                enabled,
            );
            self.publishModelObservers();
        }

        pub fn setContentProvider(
            self: *Self,
            provider: ?ContentProvider,
        ) Error!void {
            for (&self.content_readers) |*slot| {
                if (slot.value != null) return error.ObjectInUse;
            }
            self.content_provider = provider;
        }

        pub fn notifyAudioSourceAnalysisProgress(
            self: *Self,
            source_id: Model.AudioSourceId,
            state: raw.ARAAnalysisProgressState,
            progress: f32,
        ) Error!void {
            const source = self.document.audioSource(source_id) orelse
                return error.InvalidHandle;
            if ((state != raw.kARAAnalysisProgressStarted and
                state != raw.kARAAnalysisProgressUpdated and
                state != raw.kARAAnalysisProgressCompleted) or
                !std.math.isFinite(progress) or
                progress < 0.0 or
                progress > 1.0)
                return error.InvalidProperties;
            const host_interface = self.modelUpdateInterface() orelse
                return error.MissingHostInterface;
            if (!ara.implementsField(
                raw.ARAModelUpdateControllerInterface,
                host_interface,
                "notifyAudioSourceAnalysisProgress",
            ))
                return error.MissingHostInterface;
            const callback =
                host_interface.notifyAudioSourceAnalysisProgress orelse
                return error.MissingHostInterface;
            callback(
                self.host.modelUpdateControllerHostRef,
                audioSourceHostRef(source),
                state,
                progress,
            );
        }

        pub fn notifyAudioSourceContentChanged(
            self: *Self,
            source_id: Model.AudioSourceId,
            range: ?raw.ARAContentTimeRange,
            flags: raw.ARAContentUpdateFlags,
        ) Error!void {
            const source = self.document.audioSource(source_id) orelse
                return error.InvalidHandle;
            try validateContentRange(range);
            if (flags & ~content_update_flags_mask != 0)
                return error.InvalidProperties;
            const host_interface = self.modelUpdateInterface() orelse
                return error.MissingHostInterface;
            if (!ara.implementsField(
                raw.ARAModelUpdateControllerInterface,
                host_interface,
                "notifyAudioSourceContentChanged",
            ))
                return error.MissingHostInterface;
            const callback =
                host_interface.notifyAudioSourceContentChanged orelse
                return error.MissingHostInterface;
            var range_value = range;
            callback(
                self.host.modelUpdateControllerHostRef,
                audioSourceHostRef(source),
                if (range_value) |*value| value else null,
                flags,
            );
        }

        pub fn EventType(
            comptime content_type: raw.ARAContentType,
        ) type {
            return switch (content_type) {
                raw.kARAContentTypeNotes => raw.ARAContentNote,
                raw.kARAContentTypeTempoEntries => raw.ARAContentTempoEntry,
                raw.kARAContentTypeBarSignatures => raw.ARAContentBarSignature,
                raw.kARAContentTypeStaticTuning => raw.ARAContentTuning,
                raw.kARAContentTypeKeySignatures => raw.ARAContentKeySignature,
                raw.kARAContentTypeSheetChords => raw.ARAContentChord,
                else => @compileError("unsupported ARA content type"),
            };
        }

        pub fn hostMusicalContextContentAvailable(
            self: *const Self,
            context_id: Model.MusicalContextId,
            comptime content_type: raw.ARAContentType,
        ) Error!bool {
            _ = EventType(content_type);
            const context =
                self.document.musicalContext(context_id) orelse
                return error.InvalidHandle;
            const host_interface =
                self.contentAccessInterface() orelse
                return error.MissingHostInterface;
            const callback =
                host_interface.isMusicalContextContentAvailable orelse
                return error.MissingHostInterface;
            const available = callback(
                self.host.contentAccessControllerHostRef,
                musicalContextHostRef(context),
                content_type,
            );
            if (available != raw.kARAFalse and
                available != raw.kARATrue)
                return error.InvalidProperties;
            return available == raw.kARATrue;
        }

        pub fn hostMusicalContextContentGrade(
            self: *const Self,
            context_id: Model.MusicalContextId,
            comptime content_type: raw.ARAContentType,
        ) Error!raw.ARAContentGrade {
            _ = EventType(content_type);
            const context =
                self.document.musicalContext(context_id) orelse
                return error.InvalidHandle;
            const host_interface =
                self.contentAccessInterface() orelse
                return error.MissingHostInterface;
            const callback =
                host_interface.getMusicalContextContentGrade orelse
                return error.MissingHostInterface;
            const grade = callback(
                self.host.contentAccessControllerHostRef,
                musicalContextHostRef(context),
                content_type,
            );
            if (grade < raw.kARAContentGradeInitial or
                grade > raw.kARAContentGradeApproved)
                return error.InvalidProperties;
            return grade;
        }

        pub fn copyHostMusicalContextContent(
            self: *const Self,
            context_id: Model.MusicalContextId,
            comptime content_type: raw.ARAContentType,
            range: ?raw.ARAContentTimeRange,
            output: []EventType(content_type),
        ) Error!usize {
            try validateContentRange(range);
            if (!try self.hostMusicalContextContentAvailable(
                context_id,
                content_type,
            ))
                return error.ContentReaderUnavailable;
            const context =
                self.document.musicalContext(context_id) orelse
                return error.InvalidHandle;
            const host_interface =
                self.contentAccessInterface() orelse
                return error.MissingHostInterface;
            const create =
                host_interface.createMusicalContextContentReader orelse
                return error.MissingHostInterface;
            const count_events =
                host_interface.getContentReaderEventCount orelse
                return error.MissingHostInterface;
            const event_data =
                host_interface.getContentReaderDataForEvent orelse
                return error.MissingHostInterface;
            const destroy =
                host_interface.destroyContentReader orelse
                return error.MissingHostInterface;
            var range_value = range;
            const reader = create(
                self.host.contentAccessControllerHostRef,
                musicalContextHostRef(context),
                content_type,
                if (range_value) |*value| value else null,
            ) orelse return error.ContentReaderUnavailable;
            defer destroy(
                self.host.contentAccessControllerHostRef,
                reader,
            );
            const event_count_value = count_events(
                self.host.contentAccessControllerHostRef,
                reader,
            );
            if (event_count_value < 0)
                return error.ContentCountOverflow;
            const event_count: usize =
                @intCast(event_count_value);
            if (event_count > output.len)
                return error.CapacityExceeded;
            for (output[0..event_count], 0..) |*destination, index| {
                const pointer = event_data(
                    self.host.contentAccessControllerHostRef,
                    reader,
                    @intCast(index),
                ) orelse return error.ContentReaderUnavailable;
                const event: *const EventType(content_type) =
                    @ptrCast(@alignCast(pointer));
                destination.* = event.*;
            }
            return event_count;
        }

        pub fn hostAudioSourceContentAvailable(
            self: *const Self,
            source_id: Model.AudioSourceId,
            comptime content_type: raw.ARAContentType,
        ) Error!bool {
            _ = EventType(content_type);
            const source =
                self.document.audioSource(source_id) orelse
                return error.InvalidHandle;
            const host_interface =
                self.contentAccessInterface() orelse
                return error.MissingHostInterface;
            const callback =
                host_interface.isAudioSourceContentAvailable orelse
                return error.MissingHostInterface;
            const available = callback(
                self.host.contentAccessControllerHostRef,
                audioSourceHostRef(source),
                content_type,
            );
            if (available != raw.kARAFalse and
                available != raw.kARATrue)
                return error.InvalidProperties;
            return available == raw.kARATrue;
        }

        pub fn hostAudioSourceContentGrade(
            self: *const Self,
            source_id: Model.AudioSourceId,
            comptime content_type: raw.ARAContentType,
        ) Error!raw.ARAContentGrade {
            _ = EventType(content_type);
            const source =
                self.document.audioSource(source_id) orelse
                return error.InvalidHandle;
            const host_interface =
                self.contentAccessInterface() orelse
                return error.MissingHostInterface;
            const callback =
                host_interface.getAudioSourceContentGrade orelse
                return error.MissingHostInterface;
            const grade = callback(
                self.host.contentAccessControllerHostRef,
                audioSourceHostRef(source),
                content_type,
            );
            if (grade < raw.kARAContentGradeInitial or
                grade > raw.kARAContentGradeApproved)
                return error.InvalidProperties;
            return grade;
        }

        pub fn copyHostAudioSourceContent(
            self: *const Self,
            source_id: Model.AudioSourceId,
            comptime content_type: raw.ARAContentType,
            range: ?raw.ARAContentTimeRange,
            output: []EventType(content_type),
        ) Error!usize {
            try validateContentRange(range);
            if (!try self.hostAudioSourceContentAvailable(
                source_id,
                content_type,
            ))
                return error.ContentReaderUnavailable;
            const source =
                self.document.audioSource(source_id) orelse
                return error.InvalidHandle;
            const host_interface =
                self.contentAccessInterface() orelse
                return error.MissingHostInterface;
            const create =
                host_interface.createAudioSourceContentReader orelse
                return error.MissingHostInterface;
            const count_events =
                host_interface.getContentReaderEventCount orelse
                return error.MissingHostInterface;
            const event_data =
                host_interface.getContentReaderDataForEvent orelse
                return error.MissingHostInterface;
            const destroy =
                host_interface.destroyContentReader orelse
                return error.MissingHostInterface;
            var range_value = range;
            const reader = create(
                self.host.contentAccessControllerHostRef,
                audioSourceHostRef(source),
                content_type,
                if (range_value) |*value| value else null,
            ) orelse return error.ContentReaderUnavailable;
            defer destroy(
                self.host.contentAccessControllerHostRef,
                reader,
            );
            const event_count_value = count_events(
                self.host.contentAccessControllerHostRef,
                reader,
            );
            if (event_count_value < 0)
                return error.ContentCountOverflow;
            const event_count: usize =
                @intCast(event_count_value);
            if (event_count > output.len)
                return error.CapacityExceeded;
            for (output[0..event_count], 0..) |*destination, index| {
                const pointer = event_data(
                    self.host.contentAccessControllerHostRef,
                    reader,
                    @intCast(index),
                ) orelse return error.ContentReaderUnavailable;
                const event: *const EventType(content_type) =
                    @ptrCast(@alignCast(pointer));
                destination.* = event.*;
            }
            return event_count;
        }

        fn setDocumentName(
            self: *Self,
            name: []const u8,
        ) Error!void {
            if (name.len > self.document_name.len)
                return error.NameTooLong;
            @memset(&self.document_name, 0);
            @memcpy(self.document_name[0..name.len], name);
            self.document_name_len = @intCast(name.len);
        }

        fn record(self: *Self, failure: Error) void {
            self.last_error = failure;
        }

        fn usable(
            controller_ref: raw.ARADocumentControllerRef,
        ) Error!*Self {
            const self = fromControllerRef(controller_ref) orelse
                return error.InvalidController;
            if (self.destroyed) return error.ControllerDestroyed;
            return self;
        }

        fn fromControllerRef(
            controller_ref: raw.ARADocumentControllerRef,
        ) ?*Self {
            const pointer = controller_ref orelse return null;
            return @ptrCast(@alignCast(pointer));
        }

        fn destroyDocumentController(
            controller_ref: raw.ARADocumentControllerRef,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            self.closeAllAudioReaders();
            self.closeAllContentReaders();
            if (self.document.editing)
                _ = self.document.endEditing() catch {};
            self.destroyed = true;
            if (self.release_callback) |callback|
                callback(self.release_context, self);
        }

        fn getFactory(
            controller_ref: raw.ARADocumentControllerRef,
        ) callconv(.c) [*c]const raw.ARAFactory {
            const self = usable(controller_ref) catch return null;
            return self.factory;
        }

        fn beginEditing(
            controller_ref: raw.ARADocumentControllerRef,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            self.document.beginEditing() catch |failure| {
                self.record(failure);
            };
        }

        fn endEditing(
            controller_ref: raw.ARADocumentControllerRef,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            self.finishEditing() catch |failure|
                self.record(failure);
        }

        fn notifyModelUpdates(
            controller_ref: raw.ARADocumentControllerRef,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            if (self.document.isEditing()) {
                self.record(error.ObjectInUse);
                return;
            }
            self.flushDocumentDataChanged();
        }

        fn beginRestoringDocumentFromArchive(
            controller_ref: raw.ARADocumentControllerRef,
            archive_reader: raw.ARAArchiveReaderHostRef,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            if (self.pending_archive_size != 0) {
                self.record(error.InvalidArchive);
                return raw.kARAFalse;
            }
            const size = self.readArchive(archive_reader) catch |failure| {
                self.record(failure);
                return raw.kARAFalse;
            };
            self.pending_archive_size = size;
            self.pending_archive_reader = archive_reader;
            return raw.kARATrue;
        }

        fn endRestoringDocumentFromArchive(
            controller_ref: raw.ARADocumentControllerRef,
            archive_reader: raw.ARAArchiveReaderHostRef,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            if (self.pending_archive_size == 0 or
                self.pending_archive_reader != archive_reader)
            {
                self.record(error.InvalidArchive);
                return raw.kARAFalse;
            }
            defer {
                self.pending_archive_size = 0;
                self.pending_archive_reader = null;
            }
            self.decodeArchive(
                self.archive_buffer[0..self.pending_archive_size],
                null,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAFalse;
            };
            return raw.kARATrue;
        }

        fn storeDocumentToArchive(
            controller_ref: raw.ARADocumentControllerRef,
            archive_writer: raw.ARAArchiveWriterHostRef,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            self.storeArchive(
                archive_writer,
                null,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAFalse;
            };
            return raw.kARATrue;
        }

        fn updateDocumentProperties(
            controller_ref: raw.ARADocumentControllerRef,
            properties_pointer: [*c]const raw.ARADocumentProperties,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const properties = requiredPointer(
                raw.ARADocumentProperties,
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return;
            };
            if (properties.structSize <
                raw.kARADocumentPropertiesMinSize)
            {
                self.record(error.InvalidStructSize);
                return;
            }
            const name = cString(
                properties.name,
                limits.name_bytes,
            ) catch {
                self.record(error.InvalidProperties);
                return;
            };
            self.setDocumentName(name) catch |failure| {
                self.record(failure);
                return;
            };
        }

        fn createMusicalContext(
            controller_ref: raw.ARADocumentControllerRef,
            host_ref: raw.ARAMusicalContextHostRef,
            properties_pointer: [*c]const raw.ARAMusicalContextProperties,
        ) callconv(.c) raw.ARAMusicalContextRef {
            const self = usable(controller_ref) catch return null;
            const properties = self.musicalContextProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            const id = self.document.createMusicalContext(
                eraseHostRef(host_ref),
                properties,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            return encodeRef(raw.ARAMusicalContextRef, id);
        }

        fn updateMusicalContextProperties(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAMusicalContextRef,
            properties_pointer: [*c]const raw.ARAMusicalContextProperties,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.MusicalContextId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            const properties = self.musicalContextProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return;
            };
            self.document.updateMusicalContext(
                id,
                properties,
            ) catch |failure| self.record(failure);
        }

        fn updateMusicalContextContent(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAMusicalContextRef,
            range: [*c]const raw.ARAContentTimeRange,
            flags: raw.ARAContentUpdateFlags,
        ) callconv(.c) void {
            _ = range;
            _ = flags;
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.MusicalContextId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            if (self.document.musicalContext(id) == null)
                self.record(error.InvalidHandle);
        }

        fn destroyMusicalContext(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAMusicalContextRef,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.MusicalContextId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            self.document.destroyMusicalContext(id) catch |failure|
                self.record(failure);
        }

        fn createAudioSource(
            controller_ref: raw.ARADocumentControllerRef,
            host_ref: raw.ARAAudioSourceHostRef,
            properties_pointer: [*c]const raw.ARAAudioSourceProperties,
        ) callconv(.c) raw.ARAAudioSourceRef {
            const self = usable(controller_ref) catch return null;
            const properties = self.audioSourceProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            const id = self.document.createAudioSource(
                eraseHostRef(host_ref),
                properties,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            return encodeRef(raw.ARAAudioSourceRef, id);
        }

        fn updateAudioSourceProperties(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
            properties_pointer: [*c]const raw.ARAAudioSourceProperties,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.AudioSourceId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            const properties = self.audioSourceProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return;
            };
            self.document.updateAudioSource(
                id,
                properties,
            ) catch |failure| self.record(failure);
        }

        fn updateAudioSourceContent(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
            range: [*c]const raw.ARAContentTimeRange,
            flags: raw.ARAContentUpdateFlags,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const object = self.audioSourceContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return;
            };
            const source_id = switch (object) {
                .audio_source => |id| id,
                else => return,
            };
            const checked_range = contentRange(range) catch |failure| {
                self.record(failure);
                return;
            };
            if (flags & ~content_update_flags_mask != 0) {
                self.record(error.InvalidProperties);
                return;
            }
            const provider = self.content_provider orelse return;
            const callback =
                provider.vtable.source_content_changed orelse return;
            callback(
                provider.context,
                source_id,
                checked_range,
                flags,
            );
        }

        fn enableAudioSourceSamplesAccess(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
            enabled: raw.ARABool,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.AudioSourceId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            ara.validateBoolean(enabled) catch {
                self.record(error.InvalidProperties);
                return;
            };
            self.setAudioSourceSamplesAccess(
                id,
                enabled == raw.kARATrue,
            ) catch |failure| self.record(failure);
        }

        fn deactivateAudioSourceForUndoHistory(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
            deactivate: raw.ARABool,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.AudioSourceId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            ara.validateBoolean(deactivate) catch {
                self.record(error.InvalidProperties);
                return;
            };
            self.document.deactivateAudioSourceForUndoHistory(
                id,
                deactivate == raw.kARATrue,
            ) catch |failure| self.record(failure);
        }

        fn destroyAudioSource(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.AudioSourceId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            self.document.destroyAudioSource(id) catch |failure|
                self.record(failure);
        }

        fn createAudioModification(
            controller_ref: raw.ARADocumentControllerRef,
            source_ref: raw.ARAAudioSourceRef,
            host_ref: raw.ARAAudioModificationHostRef,
            properties_pointer: [*c]const raw.ARAAudioModificationProperties,
        ) callconv(.c) raw.ARAAudioModificationRef {
            const self = usable(controller_ref) catch return null;
            return self.createModification(
                source_ref,
                host_ref,
                properties_pointer,
            );
        }

        fn cloneAudioModification(
            controller_ref: raw.ARADocumentControllerRef,
            source_modification_ref: raw.ARAAudioModificationRef,
            host_ref: raw.ARAAudioModificationHostRef,
            properties_pointer: [*c]const raw.ARAAudioModificationProperties,
        ) callconv(.c) raw.ARAAudioModificationRef {
            const self = usable(controller_ref) catch return null;
            const source_id = decodeRef(
                Model.AudioModificationId,
                source_modification_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return null;
            };
            const source = self.document.audioModification(
                source_id,
            ) orelse {
                self.record(error.InvalidHandle);
                return null;
            };
            const properties = self.audioModificationProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            const id = self.document.createAudioModification(
                source.audio_source,
                eraseHostRef(host_ref),
                properties,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            return encodeRef(raw.ARAAudioModificationRef, id);
        }

        fn createModification(
            self: *Self,
            source_ref: raw.ARAAudioSourceRef,
            host_ref: raw.ARAAudioModificationHostRef,
            properties_pointer: [*c]const raw.ARAAudioModificationProperties,
        ) raw.ARAAudioModificationRef {
            const source_id = decodeRef(
                Model.AudioSourceId,
                source_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return null;
            };
            const properties = self.audioModificationProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            const id = self.document.createAudioModification(
                source_id,
                eraseHostRef(host_ref),
                properties,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            return encodeRef(raw.ARAAudioModificationRef, id);
        }

        fn updateAudioModificationProperties(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioModificationRef,
            properties_pointer: [*c]const raw.ARAAudioModificationProperties,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.AudioModificationId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            const properties = self.audioModificationProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return;
            };
            self.document.updateAudioModification(
                id,
                properties,
            ) catch |failure| self.record(failure);
        }

        fn deactivateAudioModificationForUndoHistory(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioModificationRef,
            deactivate: raw.ARABool,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.AudioModificationId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            ara.validateBoolean(deactivate) catch {
                self.record(error.InvalidProperties);
                return;
            };
            self.document.deactivateAudioModificationForUndoHistory(
                id,
                deactivate == raw.kARATrue,
            ) catch |failure| self.record(failure);
        }

        fn destroyAudioModification(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioModificationRef,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.AudioModificationId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            self.document.destroyAudioModification(id) catch |failure|
                self.record(failure);
        }

        fn createPlaybackRegion(
            controller_ref: raw.ARADocumentControllerRef,
            modification_ref: raw.ARAAudioModificationRef,
            host_ref: raw.ARAPlaybackRegionHostRef,
            properties_pointer: [*c]const raw.ARAPlaybackRegionProperties,
        ) callconv(.c) raw.ARAPlaybackRegionRef {
            const self = usable(controller_ref) catch return null;
            const modification_id = decodeRef(
                Model.AudioModificationId,
                modification_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return null;
            };
            const properties = self.playbackRegionProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            const id = self.document.createPlaybackRegion(
                modification_id,
                eraseHostRef(host_ref),
                properties,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            return encodeRef(raw.ARAPlaybackRegionRef, id);
        }

        fn updatePlaybackRegionProperties(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAPlaybackRegionRef,
            properties_pointer: [*c]const raw.ARAPlaybackRegionProperties,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.PlaybackRegionId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            const properties = self.playbackRegionProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return;
            };
            self.document.updatePlaybackRegion(
                id,
                properties,
            ) catch |failure| self.record(failure);
        }

        fn destroyPlaybackRegion(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAPlaybackRegionRef,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.PlaybackRegionId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            self.document.destroyPlaybackRegion(id) catch |failure|
                self.record(failure);
        }

        fn createRegionSequence(
            controller_ref: raw.ARADocumentControllerRef,
            host_ref: raw.ARARegionSequenceHostRef,
            properties_pointer: [*c]const raw.ARARegionSequenceProperties,
        ) callconv(.c) raw.ARARegionSequenceRef {
            const self = usable(controller_ref) catch return null;
            const properties = self.regionSequenceProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            const id = self.document.createRegionSequence(
                eraseHostRef(host_ref),
                properties,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            return encodeRef(raw.ARARegionSequenceRef, id);
        }

        fn updateRegionSequenceProperties(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARARegionSequenceRef,
            properties_pointer: [*c]const raw.ARARegionSequenceProperties,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.RegionSequenceId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            const properties = self.regionSequenceProperties(
                properties_pointer,
            ) catch |failure| {
                self.record(failure);
                return;
            };
            self.document.updateRegionSequence(
                id,
                properties,
            ) catch |failure| self.record(failure);
        }

        fn destroyRegionSequence(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARARegionSequenceRef,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                Model.RegionSequenceId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            self.document.destroyRegionSequence(id) catch |failure|
                self.record(failure);
        }

        fn isAudioSourceContentAvailable(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
            content_type: raw.ARAContentType,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            const object = self.audioSourceContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAFalse;
            };
            return self.contentAvailable(object, content_type);
        }

        fn isAudioSourceContentAnalysisIncomplete(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
            content_type: raw.ARAContentType,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            const object = self.audioSourceContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAFalse;
            };
            if (!ara.validContentType(content_type)) {
                self.record(error.InvalidProperties);
                return raw.kARAFalse;
            }
            const provider = self.content_provider orelse
                return raw.kARAFalse;
            const callback =
                provider.vtable.analysis_incomplete orelse
                return raw.kARAFalse;
            const source_id = switch (object) {
                .audio_source => |id| id,
                else => return raw.kARAFalse,
            };
            return if (callback(
                provider.context,
                source_id,
                content_type,
            ))
                raw.kARATrue
            else
                raw.kARAFalse;
        }

        fn requestAudioSourceContentAnalysis(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
            count: raw.ARASize,
            content_types: [*c]const raw.ARAContentType,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const object = self.audioSourceContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return;
            };
            if (count == 0 or
                count > self.factory.analyzeableContentTypesCount or
                content_types == null)
            {
                self.record(error.InvalidProperties);
                return;
            }
            const requested = content_types[0..count];
            ara.validateContentTypes(requested) catch {
                self.record(error.InvalidProperties);
                return;
            };
            for (requested) |content_type| {
                if (!self.factoryAnalyzes(content_type)) {
                    self.record(error.InvalidProperties);
                    return;
                }
            }
            const provider = self.content_provider orelse {
                self.record(error.ContentReaderUnavailable);
                return;
            };
            const callback =
                provider.vtable.request_analysis orelse {
                    self.record(error.ContentReaderUnavailable);
                    return;
                };
            const source_id = switch (object) {
                .audio_source => |id| id,
                else => return,
            };
            if (!callback(
                provider.context,
                source_id,
                requested,
            ))
                self.record(error.ContentReaderUnavailable);
        }

        fn getAudioSourceContentGrade(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
            content_type: raw.ARAContentType,
        ) callconv(.c) raw.ARAContentGrade {
            const self = usable(controller_ref) catch
                return raw.kARAContentGradeInitial;
            const object = self.audioSourceContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAContentGradeInitial;
            };
            return self.contentGrade(object, content_type);
        }

        fn createAudioSourceContentReader(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
            content_type: raw.ARAContentType,
            range: [*c]const raw.ARAContentTimeRange,
        ) callconv(.c) raw.ARAContentReaderRef {
            const self = usable(controller_ref) catch return null;
            const object = self.audioSourceContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            return self.openContentReader(
                object,
                content_type,
                range,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
        }

        fn isAudioModificationContentAvailable(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioModificationRef,
            content_type: raw.ARAContentType,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            const object = self.audioModificationContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAFalse;
            };
            return self.contentAvailable(object, content_type);
        }

        fn getAudioModificationContentGrade(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioModificationRef,
            content_type: raw.ARAContentType,
        ) callconv(.c) raw.ARAContentGrade {
            const self = usable(controller_ref) catch
                return raw.kARAContentGradeInitial;
            const object = self.audioModificationContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAContentGradeInitial;
            };
            return self.contentGrade(object, content_type);
        }

        fn createAudioModificationContentReader(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioModificationRef,
            content_type: raw.ARAContentType,
            range: [*c]const raw.ARAContentTimeRange,
        ) callconv(.c) raw.ARAContentReaderRef {
            const self = usable(controller_ref) catch return null;
            const object = self.audioModificationContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            return self.openContentReader(
                object,
                content_type,
                range,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
        }

        fn isPlaybackRegionContentAvailable(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAPlaybackRegionRef,
            content_type: raw.ARAContentType,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            const object = self.playbackRegionContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAFalse;
            };
            return self.contentAvailable(object, content_type);
        }

        fn getPlaybackRegionContentGrade(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAPlaybackRegionRef,
            content_type: raw.ARAContentType,
        ) callconv(.c) raw.ARAContentGrade {
            const self = usable(controller_ref) catch
                return raw.kARAContentGradeInitial;
            const object = self.playbackRegionContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAContentGradeInitial;
            };
            return self.contentGrade(object, content_type);
        }

        fn createPlaybackRegionContentReader(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAPlaybackRegionRef,
            content_type: raw.ARAContentType,
            range: [*c]const raw.ARAContentTimeRange,
        ) callconv(.c) raw.ARAContentReaderRef {
            const self = usable(controller_ref) catch return null;
            const object = self.playbackRegionContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
            return self.openContentReader(
                object,
                content_type,
                range,
            ) catch |failure| {
                self.record(failure);
                return null;
            };
        }

        fn getContentReaderEventCount(
            controller_ref: raw.ARADocumentControllerRef,
            reader_ref: raw.ARAContentReaderRef,
        ) callconv(.c) raw.ARAInt32 {
            const self = usable(controller_ref) catch return 0;
            const reader = self.contentReader(reader_ref) orelse {
                self.record(error.ContentReaderUnavailable);
                return 0;
            };
            return @intCast(reader.event_count);
        }

        fn getContentReaderDataForEvent(
            controller_ref: raw.ARADocumentControllerRef,
            reader_ref: raw.ARAContentReaderRef,
            event_index: raw.ARAInt32,
        ) callconv(.c) ?*const anyopaque {
            const self = usable(controller_ref) catch return null;
            const reader = self.contentReader(reader_ref) orelse {
                self.record(error.ContentReaderUnavailable);
                return null;
            };
            if (event_index < 0 or
                @as(usize, @intCast(event_index)) >= reader.event_count)
            {
                self.record(error.InvalidReference);
                return null;
            }
            const provider = self.content_provider orelse {
                self.record(error.ContentReaderUnavailable);
                return null;
            };
            return provider.vtable.event_data(
                provider.context,
                &reader.object,
                reader.content_type,
                if (reader.range) |*range| range else null,
                @intCast(event_index),
            );
        }

        fn destroyContentReader(
            controller_ref: raw.ARADocumentControllerRef,
            reader_ref: raw.ARAContentReaderRef,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            const id = decodeRef(
                ContentReaderId,
                reader_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return;
            };
            if (id.index >= self.content_readers.len) {
                self.record(error.InvalidReference);
                return;
            }
            const slot = &self.content_readers[id.index];
            if (slot.generation != id.generation or
                slot.value == null)
            {
                self.record(error.ContentReaderUnavailable);
                return;
            }
            slot.value = null;
            slot.generation +%= 1;
            if (slot.generation == 0) slot.generation = 1;
        }

        fn getPlaybackRegionHeadAndTailTime(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAPlaybackRegionRef,
            head_time: [*c]raw.ARATimeDuration,
            tail_time: [*c]raw.ARATimeDuration,
        ) callconv(.c) void {
            _ = controller_ref;
            _ = object_ref;
            if (head_time == null or tail_time == null) return;
            head_time[0] = 0.0;
            tail_time[0] = 0.0;
        }

        fn restoreObjectsFromArchive(
            controller_ref: raw.ARADocumentControllerRef,
            archive_reader: raw.ARAArchiveReaderHostRef,
            filter: [*c]const raw.ARARestoreObjectsFilter,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            if (!self.document.isEditing()) {
                self.record(error.NotEditing);
                return raw.kARAFalse;
            }
            const size = self.readArchive(archive_reader) catch |failure| {
                self.record(failure);
                return raw.kARAFalse;
            };
            self.decodeArchive(
                self.archive_buffer[0..size],
                filter,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAFalse;
            };
            return raw.kARATrue;
        }

        fn storeObjectsToArchive(
            controller_ref: raw.ARADocumentControllerRef,
            archive_writer: raw.ARAArchiveWriterHostRef,
            filter: [*c]const raw.ARAStoreObjectsFilter,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            self.storeArchive(
                archive_writer,
                filter,
            ) catch |failure| {
                self.record(failure);
                return raw.kARAFalse;
            };
            return raw.kARATrue;
        }

        fn storeArchive(
            self: *Self,
            archive_writer: raw.ARAArchiveWriterHostRef,
            filter_pointer: [*c]const raw.ARAStoreObjectsFilter,
        ) Error!void {
            if (self.document.isEditing()) return error.AlreadyEditing;
            var encoder = ArchiveEncoder.init(&self.archive_buffer);
            try encoder.bytes(&archive_magic_prefix);
            try encoder.byte(archive_version);

            var document_data = true;
            var source_count: usize = 0;
            var modification_count: usize = 0;
            var source_ids: [Model.audio_source_capacity]Model.AudioSourceId =
                undefined;
            var written_source_count: usize = 0;
            var filter: ?*const raw.ARAStoreObjectsFilter = null;
            if (filter_pointer != null) {
                const value: *const raw.ARAStoreObjectsFilter =
                    @ptrCast(filter_pointer);
                if (value.structSize < raw.kARAStoreObjectsFilterMinSize)
                    return error.InvalidStructSize;
                try validateCountedPointer(
                    value.audioSourceRefsCount,
                    value.audioSourceRefs,
                );
                try validateCountedPointer(
                    value.audioModificationRefsCount,
                    value.audioModificationRefs,
                );
                if (value.documentData != raw.kARAFalse and
                    value.documentData != raw.kARATrue)
                    return error.InvalidFilter;
                document_data = value.documentData == raw.kARATrue;
                source_count = value.audioSourceRefsCount;
                modification_count =
                    value.audioModificationRefsCount;
                filter = value;
            } else {
                for (0..Model.audio_source_capacity) |slot_index| {
                    if (self.document.audioSourceIdAt(slot_index) != null)
                        source_count += 1;
                }
                for (
                    0..Model.audio_modification_capacity,
                ) |slot_index| {
                    if (self.document.audioModificationIdAt(
                        slot_index,
                    ) != null)
                        modification_count += 1;
                }
            }
            if (source_count > std.math.maxInt(u16) or
                modification_count > std.math.maxInt(u16))
                return error.ArchiveTooLarge;
            try encoder.byte(if (document_data) 1 else 0);
            try encoder.byte(0);
            try encoder.integer16(@intCast(source_count));
            try encoder.integer16(@intCast(modification_count));

            if (filter) |value| {
                for (0..source_count) |index| {
                    const id = decodeRef(
                        Model.AudioSourceId,
                        value.audioSourceRefs[index],
                    ) orelse return error.InvalidFilter;
                    const source = self.document.audioSource(id) orelse
                        return error.InvalidFilter;
                    source_ids[index] = id;
                    try encoder.text(source.persistent_id.slice());
                }
                for (0..modification_count) |index| {
                    const id = decodeRef(
                        Model.AudioModificationId,
                        value.audioModificationRefs[index],
                    ) orelse return error.InvalidFilter;
                    const modification =
                        self.document.audioModification(id) orelse
                        return error.InvalidFilter;
                    try encoder.text(
                        modification.persistent_id.slice(),
                    );
                }
            } else {
                for (0..Model.audio_source_capacity) |slot_index| {
                    const id = self.document.audioSourceIdAt(
                        slot_index,
                    ) orelse continue;
                    const source = self.document.audioSource(id) orelse
                        return error.InvalidHandle;
                    source_ids[written_source_count] = id;
                    written_source_count += 1;
                    try encoder.text(source.persistent_id.slice());
                }
                for (
                    0..Model.audio_modification_capacity,
                ) |slot_index| {
                    const id = self.document.audioModificationIdAt(
                        slot_index,
                    ) orelse continue;
                    const modification =
                        self.document.audioModification(id) orelse
                        return error.InvalidHandle;
                    try encoder.text(
                        modification.persistent_id.slice(),
                    );
                }
            }
            const selected_sources = source_ids[0..source_count];
            const extension_size =
                if (self.content_provider) |provider|
                    if (provider.vtable.archive_size) |callback|
                        callback(
                            provider.context,
                            selected_sources,
                        )
                    else
                        0
                else
                    0;
            if (extension_size > limits.archive_extension_bytes or
                extension_size > std.math.maxInt(u32))
                return error.ArchiveTooLarge;
            try encoder.integer32(@intCast(extension_size));
            if (extension_size != 0) {
                const provider = self.content_provider orelse
                    return error.InvalidArchive;
                const callback = provider.vtable.store_archive orelse
                    return error.InvalidArchive;
                const destination = try encoder.reserve(
                    extension_size,
                );
                if (!callback(
                    provider.context,
                    selected_sources,
                    destination,
                ))
                    return error.InvalidArchive;
            }
            try self.writeArchive(
                archive_writer,
                encoder.written(),
            );
        }

        fn readArchive(
            self: *Self,
            archive_reader: raw.ARAArchiveReaderHostRef,
        ) Error!usize {
            if (archive_reader == null) return error.ArchiveAccessFailed;
            const host_interface_pointer =
                self.host.archivingControllerInterface;
            if (host_interface_pointer == null)
                return error.MissingHostInterface;
            const host_interface: *const raw.ARAArchivingControllerInterface =
                @ptrCast(host_interface_pointer);
            const get_size = host_interface.getArchiveSize orelse
                return error.MissingHostInterface;
            const read = host_interface.readBytesFromArchive orelse
                return error.MissingHostInterface;
            const size = get_size(
                self.host.archivingControllerHostRef,
                archive_reader,
            );
            if (size == 0) return error.InvalidArchive;
            if (size > self.archive_buffer.len)
                return error.ArchiveTooLarge;
            const succeeded = read(
                self.host.archivingControllerHostRef,
                archive_reader,
                0,
                size,
                &self.archive_buffer,
            );
            if (succeeded != raw.kARATrue)
                return error.ArchiveAccessFailed;
            self.notifyArchiveProgress(false, 1.0);
            return size;
        }

        fn writeArchive(
            self: *Self,
            archive_writer: raw.ARAArchiveWriterHostRef,
            bytes: []const u8,
        ) Error!void {
            if (archive_writer == null) return error.ArchiveAccessFailed;
            const host_interface_pointer =
                self.host.archivingControllerInterface;
            if (host_interface_pointer == null)
                return error.MissingHostInterface;
            const host_interface: *const raw.ARAArchivingControllerInterface =
                @ptrCast(host_interface_pointer);
            const write = host_interface.writeBytesToArchive orelse
                return error.MissingHostInterface;
            const succeeded = write(
                self.host.archivingControllerHostRef,
                archive_writer,
                0,
                bytes.len,
                bytes.ptr,
            );
            if (succeeded != raw.kARATrue)
                return error.ArchiveAccessFailed;
            self.notifyArchiveProgress(true, 1.0);
        }

        fn notifyArchiveProgress(
            self: *Self,
            storing: bool,
            progress: f32,
        ) void {
            const pointer = self.host.archivingControllerInterface;
            if (pointer == null) return;
            const host_interface: *const raw.ARAArchivingControllerInterface =
                @ptrCast(pointer);
            if (storing) {
                const callback =
                    host_interface.notifyDocumentArchivingProgress orelse
                    return;
                callback(
                    self.host.archivingControllerHostRef,
                    progress,
                );
            } else {
                const callback =
                    host_interface.notifyDocumentUnarchivingProgress orelse
                    return;
                callback(
                    self.host.archivingControllerHostRef,
                    progress,
                );
            }
        }

        fn decodeArchive(
            self: *Self,
            bytes: []const u8,
            filter_pointer: [*c]const raw.ARARestoreObjectsFilter,
        ) Error!void {
            var decoder = ArchiveDecoder.init(bytes);
            const magic =
                try decoder.bytes(archive_magic_prefix.len);
            if (!std.mem.eql(u8, magic, &archive_magic_prefix))
                return error.InvalidArchive;
            const version = try decoder.byte();
            if (version != 1 and version != archive_version)
                return error.InvalidArchive;
            const document_data = try decoder.byte();
            if (document_data > 1) return error.InvalidArchive;
            if (try decoder.byte() != 0) return error.InvalidArchive;
            const source_count = try decoder.integer16();
            const modification_count = try decoder.integer16();
            if (source_count > Model.audio_source_capacity or
                modification_count >
                    Model.audio_modification_capacity)
                return error.InvalidArchive;
            var archive_source_ids: [Model.audio_source_capacity][]const u8 =
                undefined;
            for (0..source_count) |index| {
                const id = try decoder.text(
                    limits.persistent_id_bytes,
                );
                if (id.len == 0) return error.InvalidArchive;
                archive_source_ids[index] = id;
            }
            for (0..modification_count) |_| {
                const id = try decoder.text(
                    limits.persistent_id_bytes,
                );
                if (id.len == 0) return error.InvalidArchive;
            }
            const extension_bytes = if (version == archive_version)
                try decoder.bytes(@intCast(
                    try decoder.integer32(),
                ))
            else
                &.{};
            if (!decoder.finished()) return error.InvalidArchive;
            if (filter_pointer != null)
                try self.validateRestoreFilter(
                    @ptrCast(filter_pointer),
                );
            if (extension_bytes.len != 0) {
                if (extension_bytes.len >
                    limits.archive_extension_bytes)
                    return error.ArchiveTooLarge;
                const provider = self.content_provider orelse
                    return error.InvalidArchive;
                const callback =
                    provider.vtable.restore_archive orelse
                    return error.InvalidArchive;
                var mappings: [Model.audio_source_capacity]ArchiveSourceMapping =
                    undefined;
                for (
                    archive_source_ids[0..source_count],
                    0..,
                ) |archive_id, index| {
                    mappings[index] = .{
                        .archive_id = archive_id,
                        .current_id = try self.resolveArchiveSource(
                            archive_id,
                            filter_pointer,
                        ),
                    };
                }
                if (!callback(
                    provider.context,
                    mappings[0..source_count],
                    extension_bytes,
                ))
                    return error.InvalidArchive;
            }
        }

        fn resolveArchiveSource(
            self: *Self,
            archive_id: []const u8,
            filter_pointer: [*c]const raw.ARARestoreObjectsFilter,
        ) Error!?Model.AudioSourceId {
            if (filter_pointer == null)
                return self.document.findAudioSourceByPersistentId(
                    archive_id,
                );
            const filter: *const raw.ARARestoreObjectsFilter =
                @ptrCast(filter_pointer);
            for (0..filter.audioSourceIDsCount) |index| {
                const candidate = try cString(
                    filter.audioSourceArchiveIDs[index],
                    limits.persistent_id_bytes,
                );
                if (!std.mem.eql(u8, archive_id, candidate))
                    continue;
                const current_pointer =
                    if (filter.audioSourceCurrentIDs == null)
                        filter.audioSourceArchiveIDs[index]
                    else
                        filter.audioSourceCurrentIDs[index];
                const current = try cString(
                    current_pointer,
                    limits.persistent_id_bytes,
                );
                return self.document.findAudioSourceByPersistentId(
                    current,
                ) orelse error.InvalidFilter;
            }
            return null;
        }

        fn validateRestoreFilter(
            self: *Self,
            filter: *const raw.ARARestoreObjectsFilter,
        ) Error!void {
            if (filter.structSize < raw.kARARestoreObjectsFilterMinSize)
                return error.InvalidStructSize;
            if (filter.documentData != raw.kARAFalse and
                filter.documentData != raw.kARATrue)
                return error.InvalidFilter;
            try validateCountedPointer(
                filter.audioSourceIDsCount,
                filter.audioSourceArchiveIDs,
            );
            try validateOptionalMapping(
                filter.audioSourceIDsCount,
                filter.audioSourceCurrentIDs,
            );
            try validateCountedPointer(
                filter.audioModificationIDsCount,
                filter.audioModificationArchiveIDs,
            );
            try validateOptionalMapping(
                filter.audioModificationIDsCount,
                filter.audioModificationCurrentIDs,
            );
            for (0..filter.audioSourceIDsCount) |index| {
                _ = try cString(
                    filter.audioSourceArchiveIDs[index],
                    limits.persistent_id_bytes,
                );
                const current_pointer =
                    if (filter.audioSourceCurrentIDs == null)
                        filter.audioSourceArchiveIDs[index]
                    else
                        filter.audioSourceCurrentIDs[index];
                const current = try cString(
                    current_pointer,
                    limits.persistent_id_bytes,
                );
                if (self.document.findAudioSourceByPersistentId(
                    current,
                ) == null)
                    return error.InvalidFilter;
            }
            for (0..filter.audioModificationIDsCount) |index| {
                _ = try cString(
                    filter.audioModificationArchiveIDs[index],
                    limits.persistent_id_bytes,
                );
                const current_pointer =
                    if (filter.audioModificationCurrentIDs == null)
                        filter.audioModificationArchiveIDs[index]
                    else
                        filter.audioModificationCurrentIDs[index];
                const current = try cString(
                    current_pointer,
                    limits.persistent_id_bytes,
                );
                if (self.document.findAudioModificationByPersistentId(
                    current,
                ) == null)
                    return error.InvalidFilter;
            }
        }

        fn getProcessingAlgorithmsCount(
            controller_ref: raw.ARADocumentControllerRef,
        ) callconv(.c) raw.ARAInt32 {
            const self = usable(controller_ref) catch return 0;
            const count = self.processingAlgorithmsCount() orelse return 0;
            if (count > std.math.maxInt(raw.ARAInt32)) {
                self.record(error.InvalidProcessingAlgorithm);
                return 0;
            }
            return @intCast(count);
        }

        fn getProcessingAlgorithmProperties(
            controller_ref: raw.ARADocumentControllerRef,
            algorithm_index: raw.ARAInt32,
        ) callconv(.c) [*c]const raw.ARAProcessingAlgorithmProperties {
            const self = usable(controller_ref) catch return null;
            const index = nonnegativeAlgorithmIndex(
                algorithm_index,
            ) orelse {
                self.record(error.InvalidProcessingAlgorithm);
                return null;
            };
            const provider = self.content_provider orelse {
                self.record(error.InvalidProcessingAlgorithm);
                return null;
            };
            const count = self.processingAlgorithmsCount() orelse {
                self.record(error.InvalidProcessingAlgorithm);
                return null;
            };
            const callback =
                provider.vtable.processing_algorithm_properties orelse {
                    self.record(error.InvalidProcessingAlgorithm);
                    return null;
                };
            if (index >= count) {
                self.record(error.InvalidProcessingAlgorithm);
                return null;
            }
            const properties = callback(
                provider.context,
                index,
            ) orelse {
                self.record(error.InvalidProcessingAlgorithm);
                return null;
            };
            if (properties.structSize <
                raw.kARAProcessingAlgorithmPropertiesMinSize or
                properties.persistentID == null or
                properties.name == null)
            {
                self.record(error.InvalidProcessingAlgorithm);
                return null;
            }
            return properties;
        }

        fn getProcessingAlgorithmForAudioSource(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
        ) callconv(.c) raw.ARAInt32 {
            const self = usable(controller_ref) catch return 0;
            const object = self.audioSourceContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return 0;
            };
            const source_id = switch (object) {
                .audio_source => |id| id,
                else => return 0,
            };
            const provider = self.content_provider orelse {
                self.record(error.InvalidProcessingAlgorithm);
                return 0;
            };
            const count = self.processingAlgorithmsCount() orelse {
                self.record(error.InvalidProcessingAlgorithm);
                return 0;
            };
            const callback =
                provider.vtable.processing_algorithm_for_source orelse {
                    self.record(error.InvalidProcessingAlgorithm);
                    return 0;
                };
            const index = callback(
                provider.context,
                source_id,
            ) orelse {
                self.record(error.InvalidProcessingAlgorithm);
                return 0;
            };
            if (index >= count or index > std.math.maxInt(raw.ARAInt32)) {
                self.record(error.InvalidProcessingAlgorithm);
                return 0;
            }
            return @intCast(index);
        }

        fn requestProcessingAlgorithmForAudioSource(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioSourceRef,
            algorithm_index: raw.ARAInt32,
        ) callconv(.c) void {
            const self = usable(controller_ref) catch return;
            if (!self.document.isEditing()) {
                self.record(error.NotEditing);
                return;
            }
            const object = self.audioSourceContentObject(
                object_ref,
            ) catch |failure| {
                self.record(failure);
                return;
            };
            const source_id = switch (object) {
                .audio_source => |id| id,
                else => return,
            };
            const index = nonnegativeAlgorithmIndex(
                algorithm_index,
            ) orelse {
                self.record(error.InvalidProcessingAlgorithm);
                return;
            };
            const provider = self.content_provider orelse {
                self.record(error.InvalidProcessingAlgorithm);
                return;
            };
            const count = self.processingAlgorithmsCount() orelse {
                self.record(error.InvalidProcessingAlgorithm);
                return;
            };
            const callback =
                provider.vtable.request_processing_algorithm orelse {
                    self.record(error.InvalidProcessingAlgorithm);
                    return;
                };
            if (index >= count or
                !callback(provider.context, source_id, index))
            {
                self.record(error.InvalidProcessingAlgorithm);
            }
        }

        fn isLicensedForCapabilities(
            controller_ref: raw.ARADocumentControllerRef,
            run_dialog: raw.ARABool,
            content_types_count: raw.ARASize,
            content_types: [*c]const raw.ARAContentType,
            transformation_flags: raw.ARAPlaybackTransformationFlags,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            ara.validateBoolean(run_dialog) catch {
                self.record(error.InvalidProperties);
                return raw.kARAFalse;
            };
            if ((content_types_count == 0) != (content_types == null) or
                content_types_count >
                    self.factory.analyzeableContentTypesCount)
            {
                self.record(error.InvalidProperties);
                return raw.kARAFalse;
            }
            if (content_types_count != 0) {
                const requested = content_types[0..content_types_count];
                ara.validateContentTypes(requested) catch {
                    self.record(error.InvalidProperties);
                    return raw.kARAFalse;
                };
                for (requested) |content_type| {
                    if (!self.factoryAnalyzes(content_type)) {
                        self.record(error.InvalidProperties);
                        return raw.kARAFalse;
                    }
                }
            }
            if (transformation_flags &
                ~self.factory.supportedPlaybackTransformationFlags != 0)
            {
                self.record(error.UnsupportedTransformation);
                return raw.kARAFalse;
            }
            return raw.kARATrue;
        }

        fn isAudioModificationPreservingAudioSourceSignal(
            controller_ref: raw.ARADocumentControllerRef,
            object_ref: raw.ARAAudioModificationRef,
        ) callconv(.c) raw.ARABool {
            const self = usable(controller_ref) catch return raw.kARAFalse;
            const id = decodeRef(
                Model.AudioModificationId,
                object_ref,
            ) orelse {
                self.record(error.InvalidReference);
                return raw.kARAFalse;
            };
            if (self.document.audioModification(id) == null) {
                self.record(error.InvalidHandle);
                return raw.kARAFalse;
            }
            return raw.kARATrue;
        }

        fn validAudioSourceRef(
            self: *Self,
            object_ref: raw.ARAAudioSourceRef,
        ) bool {
            const id = decodeRef(
                Model.AudioSourceId,
                object_ref,
            ) orelse return false;
            return self.document.audioSource(id) != null;
        }

        fn factoryAnalyzes(
            self: *const Self,
            content_type: raw.ARAContentType,
        ) bool {
            if (self.factory.analyzeableContentTypesCount == 0 or
                self.factory.analyzeableContentTypes == null)
                return false;
            const content_types =
                self.factory.analyzeableContentTypes[0..self.factory.analyzeableContentTypesCount];
            for (content_types) |candidate| {
                if (candidate == content_type) return true;
            }
            return false;
        }

        fn processingAlgorithmsCount(self: *const Self) ?usize {
            const provider = self.content_provider orelse return null;
            const count_callback =
                provider.vtable.processing_algorithms_count orelse
                return null;
            if (provider.vtable.processing_algorithm_properties == null or
                provider.vtable.processing_algorithm_for_source == null or
                provider.vtable.request_processing_algorithm == null)
                return null;
            const count = count_callback(provider.context);
            return if (count == 0) null else count;
        }

        fn audioSourceContentObject(
            self: *Self,
            object_ref: raw.ARAAudioSourceRef,
        ) Error!ContentObject {
            const id = decodeRef(
                Model.AudioSourceId,
                object_ref,
            ) orelse return error.InvalidReference;
            if (self.document.audioSource(id) == null)
                return error.InvalidHandle;
            return .{ .audio_source = id };
        }

        fn audioModificationContentObject(
            self: *Self,
            object_ref: raw.ARAAudioModificationRef,
        ) Error!ContentObject {
            const id = decodeRef(
                Model.AudioModificationId,
                object_ref,
            ) orelse return error.InvalidReference;
            if (self.document.audioModification(id) == null)
                return error.InvalidHandle;
            return .{ .audio_modification = id };
        }

        fn playbackRegionContentObject(
            self: *Self,
            object_ref: raw.ARAPlaybackRegionRef,
        ) Error!ContentObject {
            const id = decodeRef(
                Model.PlaybackRegionId,
                object_ref,
            ) orelse return error.InvalidReference;
            if (self.document.playbackRegion(id) == null)
                return error.InvalidHandle;
            return .{ .playback_region = id };
        }

        fn contentAvailable(
            self: *Self,
            object: ContentObject,
            content_type: raw.ARAContentType,
        ) raw.ARABool {
            if (!ara.validContentType(content_type)) {
                self.record(error.InvalidProperties);
                return raw.kARAFalse;
            }
            const provider = self.content_provider orelse
                return raw.kARAFalse;
            return if (provider.vtable.is_available(
                provider.context,
                &object,
                content_type,
            ))
                raw.kARATrue
            else
                raw.kARAFalse;
        }

        fn contentGrade(
            self: *Self,
            object: ContentObject,
            content_type: raw.ARAContentType,
        ) raw.ARAContentGrade {
            if (self.contentAvailable(object, content_type) !=
                raw.kARATrue)
                return raw.kARAContentGradeInitial;
            const provider = self.content_provider orelse
                return raw.kARAContentGradeInitial;
            const grade = provider.vtable.grade(
                provider.context,
                &object,
                content_type,
            );
            if (grade < raw.kARAContentGradeInitial or
                grade > raw.kARAContentGradeApproved)
            {
                self.record(error.InvalidProperties);
                return raw.kARAContentGradeInitial;
            }
            return grade;
        }

        fn openContentReader(
            self: *Self,
            object: ContentObject,
            content_type: raw.ARAContentType,
            range_pointer: [*c]const raw.ARAContentTimeRange,
        ) Error!raw.ARAContentReaderRef {
            if (self.contentAvailable(object, content_type) !=
                raw.kARATrue)
                return error.ContentReaderUnavailable;
            const provider = self.content_provider orelse
                return error.ContentReaderUnavailable;
            const range: ?raw.ARAContentTimeRange =
                if (range_pointer == null)
                    null
                else blk: {
                    const value = range_pointer[0];
                    if (!std.math.isFinite(value.start) or
                        !std.math.isFinite(value.duration) or
                        value.duration < 0.0)
                        return error.InvalidProperties;
                    break :blk value;
                };
            var count: usize = 0;
            if (!provider.vtable.event_count(
                provider.context,
                &object,
                content_type,
                if (range) |*value| value else null,
                &count,
            )) return error.ContentReaderUnavailable;
            if (count > std.math.maxInt(i32))
                return error.ContentCountOverflow;
            for (&self.content_readers, 0..) |*slot, index| {
                if (slot.value != null) continue;
                slot.value = .{
                    .object = object,
                    .content_type = content_type,
                    .range = range,
                    .event_count = count,
                };
                return encodeRef(
                    raw.ARAContentReaderRef,
                    ContentReaderId{
                        .index = @intCast(index),
                        .generation = slot.generation,
                    },
                );
            }
            return error.CapacityExceeded;
        }

        fn contentReader(
            self: *Self,
            reader_ref: raw.ARAContentReaderRef,
        ) ?*ContentReader {
            const id = decodeRef(
                ContentReaderId,
                reader_ref,
            ) orelse return null;
            if (id.index >= self.content_readers.len) return null;
            const slot = &self.content_readers[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        fn closeAllContentReaders(self: *Self) void {
            for (&self.content_readers) |*slot| {
                if (slot.value == null) continue;
                slot.value = null;
                slot.generation +%= 1;
                if (slot.generation == 0) slot.generation = 1;
            }
        }

        fn audioAccessInterface(
            self: *const Self,
        ) ?*const raw.ARAAudioAccessControllerInterface {
            const pointer =
                self.host.audioAccessControllerInterface;
            if (pointer == null) return null;
            return @ptrCast(pointer);
        }

        fn contentAccessInterface(
            self: *const Self,
        ) ?*const raw.ARAContentAccessControllerInterface {
            const pointer =
                self.host.contentAccessControllerInterface;
            if (pointer == null) return null;
            return @ptrCast(pointer);
        }

        fn modelUpdateInterface(
            self: *const Self,
        ) ?*const raw.ARAModelUpdateControllerInterface {
            const pointer =
                self.host.modelUpdateControllerInterface;
            if (pointer == null) return null;
            return @ptrCast(pointer);
        }

        fn closeAudioReader(
            self: *Self,
            reader_id: AudioReaderId,
        ) void {
            self.closeAudioReaderAt(
                reader_id.index,
                reader_id.generation,
            );
        }

        fn acquireAudioReader(
            self: *Self,
            reader_id: AudioReaderId,
        ) ?AudioReadLease {
            if (reader_id.index >= self.audio_readers.len)
                return null;
            const slot = &self.audio_readers[reader_id.index];
            if (slot.closing.load(.acquire)) return null;
            var active_reads =
                slot.active_reads.load(.acquire);
            while (true) {
                if (active_reads == std.math.maxInt(u32))
                    return null;
                if (slot.active_reads.cmpxchgWeak(
                    active_reads,
                    active_reads + 1,
                    .acquire,
                    .acquire,
                )) |observed| {
                    active_reads = observed;
                    continue;
                }
                break;
            }
            if (slot.closing.load(.acquire) or
                slot.generation != reader_id.generation)
            {
                _ = slot.active_reads.fetchSub(1, .release);
                return null;
            }
            const state = if (slot.value) |*value|
                value
            else {
                _ = slot.active_reads.fetchSub(1, .release);
                return null;
            };
            return .{
                .slot = slot,
                .state = state,
            };
        }

        fn vacantAudioReaderIndex(self: *const Self) ?usize {
            for (&self.audio_readers, 0..) |*slot, index| {
                if (slot.value == null) return index;
            }
            return null;
        }

        fn closeAudioReaderAt(
            self: *Self,
            reader_index: usize,
            expected_generation: u32,
        ) void {
            if (reader_index >= self.audio_readers.len) return;
            const slot = &self.audio_readers[reader_index];
            if (slot.closing.cmpxchgStrong(
                false,
                true,
                .acq_rel,
                .acquire,
            ) != null)
                return;
            defer slot.closing.store(false, .release);
            if (slot.generation != expected_generation) return;
            while (slot.active_reads.load(.acquire) != 0)
                std.Thread.yield() catch {};
            const state = slot.value orelse return;
            const host_interface =
                self.audioAccessInterface();
            const callback =
                if (host_interface) |value|
                    value.destroyAudioReader
                else
                    null;
            if (callback) |destroy| {
                destroy(
                    self.host.audioAccessControllerHostRef,
                    state.host_reader,
                );
            }
            slot.value = null;
            slot.generation +%= 1;
            if (slot.generation == 0) slot.generation = 1;
        }

        fn closeAudioReadersForSource(
            self: *Self,
            source_id: Model.AudioSourceId,
        ) void {
            for (&self.audio_readers, 0..) |*slot, index| {
                const state = slot.value orelse continue;
                if (state.source_id.index == source_id.index and
                    state.source_id.generation ==
                        source_id.generation)
                    self.closeAudioReaderAt(
                        index,
                        slot.generation,
                    );
            }
        }

        fn closeAllAudioReaders(self: *Self) void {
            for (&self.audio_readers, 0..) |*slot, reader_index|
                self.closeAudioReaderAt(
                    reader_index,
                    slot.generation,
                );
        }

        fn musicalContextProperties(
            self: *Self,
            pointer: [*c]const raw.ARAMusicalContextProperties,
        ) Error!Model.MusicalContextProperties {
            _ = self;
            const properties = try requiredProperties(
                raw.ARAMusicalContextProperties,
                pointer,
                raw.kARAMusicalContextPropertiesMinSize,
            );
            const name = if (ara.implementsField(
                raw.ARAMusicalContextProperties,
                properties,
                "name",
            ))
                try cString(properties.name, limits.name_bytes)
            else
                "";
            const order_index = if (ara.implementsField(
                raw.ARAMusicalContextProperties,
                properties,
                "orderIndex",
            ))
                properties.orderIndex
            else
                0;
            const color = if (ara.implementsField(
                raw.ARAMusicalContextProperties,
                properties,
                "color",
            ))
                readColor(properties.color)
            else
                null;
            return .{
                .name = name,
                .order_index = order_index,
                .color = color,
            };
        }

        fn regionSequenceProperties(
            self: *Self,
            pointer: [*c]const raw.ARARegionSequenceProperties,
        ) Error!Model.RegionSequenceProperties {
            _ = self;
            const properties = try requiredProperties(
                raw.ARARegionSequenceProperties,
                pointer,
                raw.kARARegionSequencePropertiesMinSize,
            );
            const context = decodeRef(
                Model.MusicalContextId,
                properties.musicalContextRef,
            ) orelse return error.InvalidReference;
            return .{
                .name = try cString(
                    properties.name,
                    limits.name_bytes,
                ),
                .order_index = properties.orderIndex,
                .musical_context = context,
                .color = if (ara.implementsField(
                    raw.ARARegionSequenceProperties,
                    properties,
                    "color",
                ))
                    readColor(properties.color)
                else
                    null,
            };
        }

        fn audioSourceProperties(
            self: *Self,
            pointer: [*c]const raw.ARAAudioSourceProperties,
        ) Error!Model.AudioSourceProperties {
            _ = self;
            const properties = try requiredProperties(
                raw.ARAAudioSourceProperties,
                pointer,
                raw.kARAAudioSourcePropertiesMinSize,
            );
            if (ara.implementsField(
                raw.ARAAudioSourceProperties,
                properties,
                "channelArrangementDataType",
            ) and properties.channelArrangementDataType !=
                raw.kARAChannelArrangementUndefined)
                return error.UnsupportedChannelArrangement;
            if (properties.merits64BitSamples != raw.kARAFalse and
                properties.merits64BitSamples != raw.kARATrue)
                return error.InvalidProperties;
            return .{
                .name = try cString(
                    properties.name,
                    limits.name_bytes,
                ),
                .persistent_id = try cString(
                    properties.persistentID,
                    limits.persistent_id_bytes,
                ),
                .sample_count = properties.sampleCount,
                .sample_rate = properties.sampleRate,
                .channel_count = properties.channelCount,
                .merits_64_bit_samples = properties.merits64BitSamples == raw.kARATrue,
            };
        }

        fn audioModificationProperties(
            self: *Self,
            pointer: [*c]const raw.ARAAudioModificationProperties,
        ) Error!Model.AudioModificationProperties {
            _ = self;
            const properties = try requiredProperties(
                raw.ARAAudioModificationProperties,
                pointer,
                raw.kARAAudioModificationPropertiesMinSize,
            );
            return .{
                .name = try cString(
                    properties.name,
                    limits.name_bytes,
                ),
                .persistent_id = try cString(
                    properties.persistentID,
                    limits.persistent_id_bytes,
                ),
            };
        }

        fn playbackRegionProperties(
            self: *Self,
            pointer: [*c]const raw.ARAPlaybackRegionProperties,
        ) Error!Model.PlaybackRegionProperties {
            const properties = try requiredProperties(
                raw.ARAPlaybackRegionProperties,
                pointer,
                raw.kARAPlaybackRegionPropertiesMinSize,
            );
            if (!ara.implementsField(
                raw.ARAPlaybackRegionProperties,
                properties,
                "regionSequenceRef",
            ))
                return error.InvalidStructSize;
            const sequence = decodeRef(
                Model.RegionSequenceId,
                properties.regionSequenceRef,
            ) orelse return error.InvalidReference;
            const transformation = try readTransformation(
                properties.transformationFlags,
            );
            if (properties.transformationFlags &
                ~self.factory.supportedPlaybackTransformationFlags != 0)
                return error.UnsupportedTransformation;
            return .{
                .name = if (ara.implementsField(
                    raw.ARAPlaybackRegionProperties,
                    properties,
                    "name",
                ))
                    try cString(
                        properties.name,
                        limits.name_bytes,
                    )
                else
                    "",
                .region_sequence = sequence,
                .transformation = transformation,
                .start_in_modification_time = properties.startInModificationTime,
                .duration_in_modification_time = properties.durationInModificationTime,
                .start_in_playback_time = properties.startInPlaybackTime,
                .duration_in_playback_time = properties.durationInPlaybackTime,
                .color = if (ara.implementsField(
                    raw.ARAPlaybackRegionProperties,
                    properties,
                    "color",
                ))
                    readColor(properties.color)
                else
                    null,
            };
        }

        fn finishEditing(self: *Self) Error!void {
            const changed = try self.document.endEditing();
            if (!changed) return;
            self.publishModelObservers();
        }

        fn publishModelObservers(self: *Self) void {
            const PendingObserver = struct {
                id: ModelObserverId,
                sink: ModelPublicationSink,
            };
            var pending: [limits.model_observers]PendingObserver =
                undefined;
            var pending_count: usize = 0;
            for (&self.model_observers, 0..) |*slot, index| {
                const sink = slot.sink orelse continue;
                pending[pending_count] = .{
                    .id = .{
                        .index = @intCast(index),
                        .generation = slot.generation,
                    },
                    .sink = sink,
                };
                pending_count += 1;
            }
            const revision = self.document.currentRevision();
            for (pending[0..pending_count]) |observer| {
                const slot =
                    &self.model_observers[observer.id.index];
                if (slot.generation != observer.id.generation or
                    slot.sink == null)
                    continue;
                observer.sink.changed(
                    observer.sink.context,
                    self,
                    revision,
                );
            }
        }

        fn flushDocumentDataChanged(self: *Self) void {
            if (!self.document_data_changed_pending) return;
            const host_interface =
                self.host.modelUpdateControllerInterface;
            if (host_interface == null) return;
            const value: *const raw.ARAModelUpdateControllerInterface =
                @ptrCast(host_interface);
            if (!ara.implementsField(
                raw.ARAModelUpdateControllerInterface,
                value,
                "notifyDocumentDataChanged",
            ))
                return;
            const callback = value.notifyDocumentDataChanged orelse
                return;
            self.document_data_changed_pending = false;
            callback(self.host.modelUpdateControllerHostRef);
        }
    };
}

fn validateHost(
    host: *const raw.ARADocumentControllerHostInstance,
) Error!void {
    if (host.structSize < raw.kARADocumentControllerHostInstanceMinSize)
        return error.InvalidStructSize;
    try validateHostInterface(
        raw.ARAAudioAccessControllerInterface,
        host.audioAccessControllerInterface,
        raw.kARAAudioAccessControllerInterfaceMinSize,
    );
    try validateHostInterface(
        raw.ARAArchivingControllerInterface,
        host.archivingControllerInterface,
        raw.kARAArchivingControllerInterfaceMinSize,
    );
    try validateHostInterface(
        raw.ARAContentAccessControllerInterface,
        host.contentAccessControllerInterface,
        raw.kARAContentAccessControllerInterfaceMinSize,
    );
    try validateHostInterface(
        raw.ARAModelUpdateControllerInterface,
        host.modelUpdateControllerInterface,
        raw.kARAModelUpdateControllerInterfaceMinSize,
    );
    try validateHostInterface(
        raw.ARAPlaybackControllerInterface,
        host.playbackControllerInterface,
        raw.kARAPlaybackControllerInterfaceMinSize,
    );
}

const archive_magic_prefix = [_]u8{
    'Z', 'V', '3', 'A', 'R', 'A', 0,
};
const archive_version: u8 = 2;

const ArchiveEncoder = struct {
    buffer: []u8,
    position: usize = 0,

    fn init(buffer: []u8) ArchiveEncoder {
        return .{ .buffer = buffer };
    }

    fn byte(self: *ArchiveEncoder, value: u8) Error!void {
        if (self.position >= self.buffer.len)
            return error.ArchiveTooLarge;
        self.buffer[self.position] = value;
        self.position += 1;
    }

    fn bytes(
        self: *ArchiveEncoder,
        values: []const u8,
    ) Error!void {
        if (values.len > self.buffer.len - self.position)
            return error.ArchiveTooLarge;
        @memcpy(
            self.buffer[self.position..][0..values.len],
            values,
        );
        self.position += values.len;
    }

    fn integer16(
        self: *ArchiveEncoder,
        value: u16,
    ) Error!void {
        try self.byte(@truncate(value));
        try self.byte(@truncate(value >> 8));
    }

    fn integer32(
        self: *ArchiveEncoder,
        value: u32,
    ) Error!void {
        try self.integer16(@truncate(value));
        try self.integer16(@truncate(value >> 16));
    }

    fn text(
        self: *ArchiveEncoder,
        value: []const u8,
    ) Error!void {
        if (value.len == 0 or value.len > std.math.maxInt(u16))
            return error.InvalidArchive;
        try self.integer16(@intCast(value.len));
        try self.bytes(value);
    }

    fn written(self: *const ArchiveEncoder) []const u8 {
        return self.buffer[0..self.position];
    }

    fn reserve(
        self: *ArchiveEncoder,
        count: usize,
    ) Error![]u8 {
        if (count > self.buffer.len - self.position)
            return error.ArchiveTooLarge;
        const result =
            self.buffer[self.position..][0..count];
        self.position += count;
        return result;
    }
};

const ArchiveDecoder = struct {
    buffer: []const u8,
    position: usize = 0,

    fn init(buffer: []const u8) ArchiveDecoder {
        return .{ .buffer = buffer };
    }

    fn byte(self: *ArchiveDecoder) Error!u8 {
        if (self.position >= self.buffer.len)
            return error.InvalidArchive;
        const value = self.buffer[self.position];
        self.position += 1;
        return value;
    }

    fn bytes(
        self: *ArchiveDecoder,
        length: usize,
    ) Error![]const u8 {
        if (length > self.buffer.len - self.position)
            return error.InvalidArchive;
        const result =
            self.buffer[self.position..][0..length];
        self.position += length;
        return result;
    }

    fn integer16(self: *ArchiveDecoder) Error!u16 {
        const low = try self.byte();
        const high = try self.byte();
        return @as(u16, low) | (@as(u16, high) << 8);
    }

    fn integer32(self: *ArchiveDecoder) Error!u32 {
        const low = try self.integer16();
        const high = try self.integer16();
        return @as(u32, low) | (@as(u32, high) << 16);
    }

    fn text(
        self: *ArchiveDecoder,
        maximum_length: usize,
    ) Error![]const u8 {
        const length = try self.integer16();
        if (length == 0 or length > maximum_length)
            return error.InvalidArchive;
        return self.bytes(length);
    }

    fn finished(self: *const ArchiveDecoder) bool {
        return self.position == self.buffer.len;
    }
};

fn validateCountedPointer(
    count: raw.ARASize,
    pointer: anytype,
) Error!void {
    if ((count == 0) != (pointer == null))
        return error.InvalidFilter;
}

fn validateOptionalMapping(
    count: raw.ARASize,
    pointer: anytype,
) Error!void {
    if (count == 0 and pointer != null)
        return error.InvalidFilter;
}

fn validateHostInterface(
    comptime T: type,
    pointer: [*c]const T,
    minimum_size: usize,
) Error!void {
    if (pointer == null) return error.MissingHostInterface;
    if (pointer[0].structSize < minimum_size)
        return error.InvalidStructSize;
}

fn requiredProperties(
    comptime T: type,
    pointer: [*c]const T,
    minimum_size: usize,
) Error!*const T {
    const properties = try requiredPointer(T, pointer);
    if (properties.structSize < minimum_size)
        return error.InvalidStructSize;
    return properties;
}

fn requiredPointer(
    comptime T: type,
    pointer: [*c]const T,
) Error!*const T {
    if (pointer == null) return error.InvalidProperties;
    return @ptrCast(pointer);
}

fn cString(
    pointer: [*c]const u8,
    maximum_length: usize,
) Error![]const u8 {
    if (pointer == null) return "";
    var length: usize = 0;
    while (length <= maximum_length and pointer[length] != 0) : (length += 1) {}
    if (length > maximum_length) return error.NameTooLong;
    return pointer[0..length];
}

fn readColor(pointer: [*c]const raw.ARAColor) ?model_api.Color {
    if (pointer == null) return null;
    return .{
        .red = pointer[0].r,
        .green = pointer[0].g,
        .blue = pointer[0].b,
    };
}

fn readTransformation(
    flags: raw.ARAPlaybackTransformationFlags,
) Error!model_api.PlaybackTransformation {
    const supported =
        raw.kARAPlaybackTransformationTimestretch |
        raw.kARAPlaybackTransformationTimestretchReflectingTempo |
        raw.kARAPlaybackTransformationContentBasedFades;
    if (flags & ~supported != 0)
        return error.UnsupportedTransformation;
    return .{
        .time_stretch = flags & raw.kARAPlaybackTransformationTimestretch != 0,
        .reflect_tempo = flags &
            raw.kARAPlaybackTransformationTimestretchReflectingTempo !=
            0,
        .fade_tail = flags &
            raw.kARAPlaybackTransformationContentBasedFadeAtTail !=
            0,
        .fade_head = flags &
            raw.kARAPlaybackTransformationContentBasedFadeAtHead !=
            0,
    };
}

fn nonnegativeAlgorithmIndex(
    index: raw.ARAInt32,
) ?usize {
    if (index < 0) return null;
    return @intCast(index);
}

const content_update_flags_mask =
    raw.kARAContentUpdateSignalScopeRemainsUnchanged |
    raw.kARAContentUpdateNoteScopeRemainsUnchanged |
    raw.kARAContentUpdateTimingScopeRemainsUnchanged |
    raw.kARAContentUpdateTuningScopeRemainsUnchanged |
    raw.kARAContentUpdateHarmonicScopeRemainsUnchanged;

fn contentRange(
    pointer: [*c]const raw.ARAContentTimeRange,
) Error!?raw.ARAContentTimeRange {
    if (pointer == null) return null;
    const range = pointer[0];
    try validateContentRange(range);
    return range;
}

fn validateContentRange(
    range: ?raw.ARAContentTimeRange,
) Error!void {
    const value = range orelse return;
    if (!std.math.isFinite(value.start) or
        !std.math.isFinite(value.duration) or
        value.duration < 0.0)
        return error.InvalidProperties;
}

fn audioSourceHostRef(
    source: anytype,
) raw.ARAAudioSourceHostRef {
    const pointer = source.host_ref orelse return null;
    return @ptrCast(pointer);
}

fn musicalContextHostRef(
    context: anytype,
) raw.ARAMusicalContextHostRef {
    const pointer = context.host_ref orelse return null;
    return @ptrCast(pointer);
}

fn eraseHostRef(pointer: anytype) ?*anyopaque {
    const value = pointer orelse return null;
    return @ptrCast(value);
}

fn encodeRef(comptime Ref: type, id: anytype) Ref {
    const address =
        (@as(usize, id.generation) << 16) |
        (@as(usize, id.index) + 1);
    return @ptrFromInt(address);
}

fn decodeRef(comptime Id: type, pointer: anytype) ?Id {
    const value = pointer orelse return null;
    const address = @intFromPtr(value);
    const encoded_index = address & 0xffff;
    if (encoded_index == 0) return null;
    const generation = address >> 16;
    if (generation == 0 or generation > std.math.maxInt(u32))
        return null;
    return .{
        .index = @intCast(encoded_index - 1),
        .generation = @intCast(generation),
    };
}

test "ARA controller publishes complete playback render descriptions" {
    const limits = model_api.Limits{
        .musical_contexts = 1,
        .region_sequences = 1,
        .audio_sources = 1,
        .audio_modifications = 1,
        .playback_regions = 1,
        .content_readers = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    };
    const TestController = Controller(limits);
    var controller = TestController{
        .host = testHost(),
        .factory = @ptrFromInt(0x1000),
    };
    const Observer = struct {
        revision: u64 = 0,
        calls: usize = 0,

        fn changed(
            context: ?*anyopaque,
            _: *TestController,
            revision: u64,
        ) void {
            const self: *@This() =
                @ptrCast(@alignCast(context orelse return));
            self.revision = revision;
            self.calls += 1;
        }
    };
    var observer = Observer{};
    const observer_id =
        try controller.addModelPublicationSink(.{
            .context = &observer,
            .changed = Observer.changed,
        });

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
                .name = "Lead",
                .order_index = 0,
                .musical_context = musical_context,
            },
        );
    const source = try controller.document.createAudioSource(
        null,
        .{
            .name = "Take",
            .persistent_id = "source-1",
            .sample_count = 96_000,
            .sample_rate = 48_000.0,
            .channel_count = 2,
        },
    );
    const modification =
        try controller.document.createAudioModification(
            source,
            null,
            .{
                .name = "Tuned",
                .persistent_id = "modification-1",
            },
        );
    const region = try controller.document.createPlaybackRegion(
        modification,
        null,
        .{
            .name = "Verse",
            .region_sequence = sequence,
            .start_in_modification_time = 1.0,
            .duration_in_modification_time = 2.0,
            .start_in_playback_time = 4.0,
            .duration_in_playback_time = 3.0,
            .transformation = .{ .time_stretch = true },
        },
    );
    try controller.finishEditing();
    try controller.document.enableAudioSourceSamplesAccess(
        source,
        true,
    );
    try std.testing.expectEqual(@as(usize, 1), observer.calls);
    try std.testing.expectEqual(@as(u64, 1), observer.revision);

    const region_ref = encodeRef(raw.ARAPlaybackRegionRef, region);
    const description =
        try controller.playbackRegionRenderDescription(region_ref);
    try std.testing.expectEqual(source, description.audio_source);
    try std.testing.expectEqual(
        modification,
        description.audio_modification,
    );
    try std.testing.expectEqual(@as(f64, 48_000.0), description
        .source_sample_rate);
    try std.testing.expectEqual(@as(i32, 2), description
        .source_channel_count);
    try std.testing.expect(description.source_samples_access_enabled);
    try std.testing.expect(description.transformation.time_stretch);
    try std.testing.expectEqual(
        @as(f64, 3.0),
        description.duration_in_playback_time,
    );

    try controller.document.beginEditing();
    try controller.document.destroyPlaybackRegion(region);
    try controller.finishEditing();
    try std.testing.expectError(
        error.InvalidHandle,
        controller.playbackRegionRenderDescription(region_ref),
    );
    try std.testing.expectEqual(@as(usize, 2), observer.calls);
    controller.removeModelPublicationSink(observer_id);
}

test "ARA model publication contains reentrant observer changes" {
    const TestController = Controller(.{
        .audio_sources = 1,
        .model_observers = 3,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    });
    const ObserverState = struct {
        first_id: ?TestController.ModelObserverId = null,
        second_id: ?TestController.ModelObserverId = null,
        replacement_id: ?TestController.ModelObserverId = null,
        first_calls: usize = 0,
        second_calls: usize = 0,
        replacement_calls: usize = 0,
        failed: bool = false,

        fn first(
            context: ?*anyopaque,
            controller: *TestController,
            _: u64,
        ) void {
            const self: *@This() =
                @ptrCast(@alignCast(context orelse return));
            self.first_calls += 1;
            controller.removeModelPublicationSink(
                self.second_id orelse {
                    self.failed = true;
                    return;
                },
            );
            controller.removeModelPublicationSink(
                self.first_id orelse {
                    self.failed = true;
                    return;
                },
            );
            self.replacement_id =
                controller.addModelPublicationSink(.{
                    .context = self,
                    .changed = replacement,
                }) catch {
                    self.failed = true;
                    return;
                };
        }

        fn second(
            context: ?*anyopaque,
            _: *TestController,
            _: u64,
        ) void {
            const self: *@This() =
                @ptrCast(@alignCast(context orelse return));
            self.second_calls += 1;
        }

        fn replacement(
            context: ?*anyopaque,
            _: *TestController,
            _: u64,
        ) void {
            const self: *@This() =
                @ptrCast(@alignCast(context orelse return));
            self.replacement_calls += 1;
        }
    };

    var controller = TestController{
        .host = testHost(),
        .factory = @ptrFromInt(0x1000),
    };
    var observer = ObserverState{};
    observer.first_id = try controller.addModelPublicationSink(.{
        .context = &observer,
        .changed = ObserverState.first,
    });
    observer.second_id = try controller.addModelPublicationSink(.{
        .context = &observer,
        .changed = ObserverState.second,
    });

    try controller.document.beginEditing();
    const source = try controller.document.createAudioSource(
        null,
        .{
            .name = "Take",
            .persistent_id = "source-1",
            .sample_count = 8,
            .sample_rate = 48_000.0,
            .channel_count = 1,
        },
    );
    try controller.finishEditing();
    try std.testing.expect(!observer.failed);
    try std.testing.expectEqual(@as(usize, 1), observer.first_calls);
    try std.testing.expectEqual(@as(usize, 0), observer.second_calls);
    try std.testing.expectEqual(
        @as(usize, 0),
        observer.replacement_calls,
    );

    try controller.document.beginEditing();
    try controller.document.updateAudioSource(
        source,
        .{
            .name = "Retake",
            .persistent_id = "source-1",
            .sample_count = 16,
            .sample_rate = 48_000.0,
            .channel_count = 1,
        },
    );
    try controller.finishEditing();
    try std.testing.expectEqual(
        @as(usize, 1),
        observer.replacement_calls,
    );
}

test "ARA document-data notifications flush only on host request" {
    const TestController = Controller(.{});
    const Observer = struct {
        calls: usize = 0,

        fn notified(
            host_ref: raw.ARAModelUpdateControllerHostRef,
        ) callconv(.c) void {
            const pointer = host_ref orelse return;
            const self: *@This() =
                @ptrCast(@alignCast(pointer));
            self.calls += 1;
        }

        const interface = raw.ARAModelUpdateControllerInterface{
            .structSize = @sizeOf(raw.ARAModelUpdateControllerInterface),
            .notifyDocumentDataChanged = notified,
        };
    };
    var observer = Observer{};
    var host = testHost();
    host.modelUpdateControllerHostRef = @ptrCast(&observer);
    host.modelUpdateControllerInterface = &Observer.interface;
    var controller = TestController{
        .host = host,
        .factory = @ptrFromInt(0x1000),
    };
    try controller.markDocumentDataChanged();
    try std.testing.expectEqual(@as(usize, 0), observer.calls);
    TestController.interface.notifyModelUpdates.?(
        @ptrCast(&controller),
    );
    try std.testing.expectEqual(@as(usize, 1), observer.calls);
    TestController.interface.notifyModelUpdates.?(
        @ptrCast(&controller),
    );
    try std.testing.expectEqual(@as(usize, 1), observer.calls);
}

test "ARA controller publishes a complete valid interface" {
    const TestController = Controller(.{});
    var factory = std.mem.zeroes(raw.ARAFactory);
    var host = testHost();
    var properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Session",
    };
    var controller: TestController = undefined;
    try controller.init(&factory, &host, &properties);
    try ara.validateDocumentControllerInstance(
        controller.documentControllerInstance(),
    );
    try std.testing.expectEqualStrings(
        "Session",
        controller.documentName(),
    );
}

test "ARA controller validates licensed capability queries" {
    const TestController = Controller(.{
        .audio_sources = 1,
        .audio_modifications = 1,
        .playback_regions = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    });
    const analyzeable = [_]raw.ARAContentType{
        raw.kARAContentTypeStaticTuning,
    };
    var factory = std.mem.zeroes(raw.ARAFactory);
    factory.analyzeableContentTypesCount = analyzeable.len;
    factory.analyzeableContentTypes = &analyzeable;
    factory.supportedPlaybackTransformationFlags =
        raw.kARAPlaybackTransformationTimestretch;
    var host = testHost();
    var properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Session",
    };
    var controller: TestController = undefined;
    try controller.init(&factory, &host, &properties);
    const instance = controller.documentControllerInstance();
    const api: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    const query = api.isLicensedForCapabilities.?;

    try std.testing.expectEqual(
        raw.kARATrue,
        query(
            instance.documentControllerRef,
            raw.kARAFalse,
            analyzeable.len,
            &analyzeable,
            raw.kARAPlaybackTransformationTimestretch,
        ),
    );
    try std.testing.expect(controller.takeLastError() == null);

    try std.testing.expectEqual(
        raw.kARAFalse,
        query(
            instance.documentControllerRef,
            2,
            0,
            null,
            raw.kARAPlaybackTransformationNoChanges,
        ),
    );
    try std.testing.expectEqual(
        error.InvalidProperties,
        controller.takeLastError().?,
    );
    try std.testing.expectEqual(
        raw.kARAFalse,
        query(
            instance.documentControllerRef,
            raw.kARAFalse,
            0,
            &analyzeable,
            raw.kARAPlaybackTransformationNoChanges,
        ),
    );
    try std.testing.expectEqual(
        error.InvalidProperties,
        controller.takeLastError().?,
    );

    const duplicate = [_]raw.ARAContentType{
        raw.kARAContentTypeStaticTuning,
        raw.kARAContentTypeStaticTuning,
    };
    try std.testing.expectEqual(
        raw.kARAFalse,
        query(
            instance.documentControllerRef,
            raw.kARAFalse,
            duplicate.len,
            &duplicate,
            raw.kARAPlaybackTransformationNoChanges,
        ),
    );
    try std.testing.expectEqual(
        error.InvalidProperties,
        controller.takeLastError().?,
    );
    const unavailable = [_]raw.ARAContentType{
        raw.kARAContentTypeNotes,
    };
    try std.testing.expectEqual(
        raw.kARAFalse,
        query(
            instance.documentControllerRef,
            raw.kARAFalse,
            unavailable.len,
            &unavailable,
            raw.kARAPlaybackTransformationNoChanges,
        ),
    );
    try std.testing.expectEqual(
        error.InvalidProperties,
        controller.takeLastError().?,
    );
    try std.testing.expectEqual(
        raw.kARAFalse,
        query(
            instance.documentControllerRef,
            raw.kARAFalse,
            0,
            null,
            raw.kARAPlaybackTransformationContentBasedFades,
        ),
    );
    try std.testing.expectEqual(
        error.UnsupportedTransformation,
        controller.takeLastError().?,
    );
}

test "ARA controller routes graph lifecycle through C callbacks" {
    const TestController = Controller(.{
        .musical_contexts = 1,
        .region_sequences = 1,
        .audio_sources = 1,
        .audio_modifications = 1,
        .playback_regions = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    });
    var factory = std.mem.zeroes(raw.ARAFactory);
    var host = testHost();
    var document_properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Session",
    };
    var controller: TestController = undefined;
    try controller.init(&factory, &host, &document_properties);
    const instance = controller.documentControllerInstance();
    const api: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    const controller_ref = instance.documentControllerRef;
    api.beginEditing.?(controller_ref);

    var context_properties = raw.ARAMusicalContextProperties{
        .structSize = @sizeOf(raw.ARAMusicalContextProperties),
        .name = "Song",
        .orderIndex = 0,
    };
    const context = api.createMusicalContext.?(
        controller_ref,
        null,
        &context_properties,
    );
    try std.testing.expect(context != null);

    var sequence_properties = raw.ARARegionSequenceProperties{
        .structSize = @sizeOf(raw.ARARegionSequenceProperties),
        .name = "Lead",
        .orderIndex = 0,
        .musicalContextRef = context,
    };
    const sequence = api.createRegionSequence.?(
        controller_ref,
        null,
        &sequence_properties,
    );
    try std.testing.expect(sequence != null);

    var source_properties = raw.ARAAudioSourceProperties{
        .structSize = @sizeOf(raw.ARAAudioSourceProperties),
        .name = "Take",
        .persistentID = "source-1",
        .sampleCount = 48_000,
        .sampleRate = 48_000.0,
        .channelCount = 2,
        .merits64BitSamples = raw.kARAFalse,
    };
    const source = api.createAudioSource.?(
        controller_ref,
        null,
        &source_properties,
    );
    try std.testing.expect(source != null);

    var modification_properties =
        raw.ARAAudioModificationProperties{
            .structSize = @sizeOf(raw.ARAAudioModificationProperties),
            .name = "Edit",
            .persistentID = "modification-1",
        };
    const modification = api.createAudioModification.?(
        controller_ref,
        source,
        null,
        &modification_properties,
    );
    try std.testing.expect(modification != null);

    var region_properties = raw.ARAPlaybackRegionProperties{
        .structSize = @sizeOf(raw.ARAPlaybackRegionProperties),
        .startInModificationTime = 0.0,
        .durationInModificationTime = 1.0,
        .startInPlaybackTime = 2.0,
        .durationInPlaybackTime = 1.0,
        .regionSequenceRef = sequence,
        .name = "Verse",
    };
    const region = api.createPlaybackRegion.?(
        controller_ref,
        modification,
        null,
        &region_properties,
    );
    try std.testing.expect(region != null);
    api.endEditing.?(controller_ref);
    try std.testing.expectEqual(
        @as(u64, 1),
        controller.document.currentRevision(),
    );
    var head_time: raw.ARATimeDuration = -1.0;
    var tail_time: raw.ARATimeDuration = -1.0;
    api.getPlaybackRegionHeadAndTailTime.?(
        controller_ref,
        region,
        &head_time,
        &tail_time,
    );
    try std.testing.expectEqual(@as(raw.ARATimeDuration, 0.0), head_time);
    try std.testing.expectEqual(@as(raw.ARATimeDuration, 0.0), tail_time);
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 0),
        api.getProcessingAlgorithmsCount.?(controller_ref),
    );
    try std.testing.expect(api.getProcessingAlgorithmProperties != null);
    try std.testing.expect(
        api.getProcessingAlgorithmForAudioSource != null,
    );
    try std.testing.expect(
        api.requestProcessingAlgorithmForAudioSource != null,
    );
    try std.testing.expect(controller.takeLastError() == null);

    api.beginEditing.?(controller_ref);
    api.destroyAudioSource.?(controller_ref, source);
    try std.testing.expectEqual(
        error.ObjectInUse,
        controller.takeLastError().?,
    );
    api.destroyPlaybackRegion.?(controller_ref, region);
    api.destroyAudioModification.?(controller_ref, modification);
    api.destroyAudioSource.?(controller_ref, source);
    api.destroyRegionSequence.?(controller_ref, sequence);
    api.destroyMusicalContext.?(controller_ref, context);
    api.endEditing.?(controller_ref);
    try std.testing.expectEqual(
        @as(u64, 2),
        controller.document.currentRevision(),
    );
}

test "ARA controller round trips bounded versioned archives" {
    const TestController = Controller(.{
        .musical_contexts = 1,
        .region_sequences = 1,
        .audio_sources = 1,
        .audio_modifications = 1,
        .playback_regions = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    });
    var archive = TestArchive{};
    var factory = std.mem.zeroes(raw.ARAFactory);
    var host = testHostWithArchive(&archive);
    var document_properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Session",
    };
    var controller: TestController = undefined;
    try controller.init(&factory, &host, &document_properties);
    const instance = controller.documentControllerInstance();
    const api: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    const controller_ref = instance.documentControllerRef;

    api.beginEditing.?(controller_ref);
    var source_properties = raw.ARAAudioSourceProperties{
        .structSize = @sizeOf(raw.ARAAudioSourceProperties),
        .name = "Take",
        .persistentID = "source-1",
        .sampleCount = 48_000,
        .sampleRate = 48_000.0,
        .channelCount = 2,
        .merits64BitSamples = raw.kARAFalse,
    };
    const source = api.createAudioSource.?(
        controller_ref,
        null,
        &source_properties,
    );
    var modification_properties =
        raw.ARAAudioModificationProperties{
            .structSize = @sizeOf(raw.ARAAudioModificationProperties),
            .name = "Edit",
            .persistentID = "modification-1",
        };
    const modification = api.createAudioModification.?(
        controller_ref,
        source,
        null,
        &modification_properties,
    );
    api.endEditing.?(controller_ref);

    const writer_ref: raw.ARAArchiveWriterHostRef =
        @ptrCast(&archive);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.storeObjectsToArchive.?(
            controller_ref,
            writer_ref,
            null,
        ),
    );
    try std.testing.expect(
        archive.length > archive_magic_prefix.len + 1,
    );
    try std.testing.expectEqual(@as(f32, 1.0), archive.store_progress);
    const stored_length = archive.length;
    const stored_bytes = archive.bytes;
    const stored_revision = controller.document.currentRevision();
    const stored_source_id =
        controller.document.findAudioSourceByPersistentId(
            "source-1",
        ) orelse return error.MissingStoredSource;
    const stored_modification_id =
        controller.document.findAudioModificationByPersistentId(
            "modification-1",
        ) orelse return error.MissingStoredModification;
    try std.testing.expect(source != null);
    try std.testing.expect(modification != null);

    const reader_ref: raw.ARAArchiveReaderHostRef =
        @ptrCast(&archive);
    api.beginEditing.?(controller_ref);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.restoreObjectsFromArchive.?(
            controller_ref,
            reader_ref,
            null,
        ),
    );
    api.endEditing.?(controller_ref);
    try std.testing.expectEqual(
        @as(f32, 1.0),
        archive.restore_progress,
    );

    archive.bytes = stored_bytes;
    archive.length = stored_length;
    try std.testing.expectEqual(
        raw.kARATrue,
        api.beginRestoringDocumentFromArchive.?(
            controller_ref,
            reader_ref,
        ),
    );
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.beginRestoringDocumentFromArchive.?(
            controller_ref,
            reader_ref,
        ),
    );
    try std.testing.expectEqual(
        error.InvalidArchive,
        controller.takeLastError().?,
    );
    const wrong_reader: raw.ARAArchiveReaderHostRef =
        @ptrFromInt(0x1234);
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.endRestoringDocumentFromArchive.?(
            controller_ref,
            wrong_reader,
        ),
    );
    try std.testing.expectEqual(
        error.InvalidArchive,
        controller.takeLastError().?,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.endRestoringDocumentFromArchive.?(
            controller_ref,
            reader_ref,
        ),
    );

    archive.bytes[0] ^= 0xff;
    try std.testing.expectEqual(
        raw.kARATrue,
        api.beginRestoringDocumentFromArchive.?(
            controller_ref,
            reader_ref,
        ),
    );
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.endRestoringDocumentFromArchive.?(
            controller_ref,
            reader_ref,
        ),
    );
    try std.testing.expectEqual(
        error.InvalidArchive,
        controller.takeLastError().?,
    );
    archive.bytes = stored_bytes;
    try std.testing.expectEqual(
        raw.kARATrue,
        api.beginRestoringDocumentFromArchive.?(
            controller_ref,
            reader_ref,
        ),
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.endRestoringDocumentFromArchive.?(
            controller_ref,
            reader_ref,
        ),
    );

    archive.bytes = stored_bytes;
    archive.bytes[archive_magic_prefix.len] = 1;
    archive.length = stored_length - 4;
    api.beginEditing.?(controller_ref);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.restoreObjectsFromArchive.?(
            controller_ref,
            reader_ref,
            null,
        ),
    );
    api.endEditing.?(controller_ref);

    for (0..stored_length) |truncated_length| {
        archive.bytes = stored_bytes;
        archive.length = truncated_length;
        api.beginEditing.?(controller_ref);
        try std.testing.expectEqual(
            raw.kARAFalse,
            api.restoreObjectsFromArchive.?(
                controller_ref,
                reader_ref,
                null,
            ),
        );
        try std.testing.expect(controller.takeLastError() != null);
        api.endEditing.?(controller_ref);
    }

    archive.bytes = stored_bytes;
    archive.bytes[archive_magic_prefix.len] =
        archive_version + 1;
    archive.length = stored_length;
    api.beginEditing.?(controller_ref);
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.restoreObjectsFromArchive.?(
            controller_ref,
            reader_ref,
            null,
        ),
    );
    try std.testing.expectEqual(
        error.InvalidArchive,
        controller.takeLastError().?,
    );
    api.endEditing.?(controller_ref);

    archive.bytes = stored_bytes;
    archive.bytes[stored_length] = 0;
    archive.length = stored_length + 1;
    api.beginEditing.?(controller_ref);
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.restoreObjectsFromArchive.?(
            controller_ref,
            reader_ref,
            null,
        ),
    );
    try std.testing.expectEqual(
        error.InvalidArchive,
        controller.takeLastError().?,
    );
    api.endEditing.?(controller_ref);

    archive.bytes = stored_bytes;
    archive.bytes[0] ^= 0xff;
    archive.length = stored_length;
    api.beginEditing.?(controller_ref);
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.restoreObjectsFromArchive.?(
            controller_ref,
            reader_ref,
            null,
        ),
    );
    try std.testing.expectEqual(
        error.InvalidArchive,
        controller.takeLastError().?,
    );
    api.endEditing.?(controller_ref);

    try std.testing.expectEqual(
        stored_revision,
        controller.document.currentRevision(),
    );
    try std.testing.expect(
        controller.document.audioSource(stored_source_id) != null,
    );
    try std.testing.expect(
        controller.document.audioModification(
            stored_modification_id,
        ) != null,
    );
}

test "ARA controller reads host audio and closes readers safely" {
    const TestController = Controller(.{
        .musical_contexts = 1,
        .region_sequences = 1,
        .audio_sources = 1,
        .audio_modifications = 1,
        .playback_regions = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    });
    var audio = TestAudio{
        .samples = .{
            .{ 0, 1, 2, 3, 4, 5, 6, 7 },
            .{ 10, 11, 12, 13, 14, 15, 16, 17 },
        },
    };
    var factory = std.mem.zeroes(raw.ARAFactory);
    var host = testHostWithAudio(&audio);
    var document_properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Session",
    };
    var controller: TestController = undefined;
    try controller.init(&factory, &host, &document_properties);
    try controller.document.beginEditing();
    const source = try controller.document.createAudioSource(
        null,
        .{
            .name = "Take",
            .persistent_id = "source-1",
            .sample_count = 8,
            .sample_rate = 48_000.0,
            .channel_count = 2,
        },
    );
    _ = try controller.document.endEditing();
    try controller.setAudioSourceSamplesAccess(source, true);
    var reader = try controller.openAudioReader(source, false);
    var left: [3]f32 = @splat(0);
    var right: [3]f32 = @splat(0);
    const buffers = [_][]f32{ &left, &right };
    try reader.readF32(2, &buffers);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 2, 3, 4 },
        &left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 12, 13, 14 },
        &right,
    );
    var concurrent_reader =
        try controller.openAudioReader(source, false);
    try concurrent_reader.readF32(2, &buffers);
    reader.close();
    try std.testing.expectEqual(@as(usize, 1), audio.destroy_count);

    const ReadContext = struct {
        reader: *TestController.AudioReader,
        buffers: *const [2][]f32,
        failure: ?Error = null,

        fn run(context: *@This()) void {
            context.reader.readF32(
                2,
                context.buffers,
            ) catch |failure| {
                context.failure = failure;
            };
        }
    };
    const DisableContext = struct {
        controller: *TestController,
        source_id: @TypeOf(source),
        started: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        finished: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        failure: ?Error = null,

        fn run(context: *@This()) void {
            context.started.store(true, .release);
            context.controller.setAudioSourceSamplesAccess(
                context.source_id,
                false,
            ) catch |failure| {
                context.failure = failure;
            };
            context.finished.store(true, .release);
        }
    };
    audio.block_reads.store(true, .release);
    var read_context = ReadContext{
        .reader = &concurrent_reader,
        .buffers = &buffers,
    };
    const read_thread = try std.Thread.spawn(
        .{},
        ReadContext.run,
        .{&read_context},
    );
    while (!audio.read_started.load(.acquire))
        std.Thread.yield() catch {};
    var disable_context = DisableContext{
        .controller = &controller,
        .source_id = source,
    };
    const disable_thread = try std.Thread.spawn(
        .{},
        DisableContext.run,
        .{&disable_context},
    );
    while (!disable_context.started.load(.acquire))
        std.Thread.yield() catch {};
    for (0..100) |_| std.Thread.yield() catch {};
    try std.testing.expect(
        !disable_context.finished.load(.acquire),
    );
    audio.release_reads.store(true, .release);
    read_thread.join();
    disable_thread.join();
    try std.testing.expect(read_context.failure == null);
    try std.testing.expect(disable_context.failure == null);
    try std.testing.expect(
        disable_context.finished.load(.acquire),
    );
    try std.testing.expectEqual(@as(usize, 2), audio.destroy_count);
    try std.testing.expectError(
        error.AudioReaderUnavailable,
        concurrent_reader.readF32(0, &buffers),
    );
    concurrent_reader.close();

    try controller.setAudioSourceSamplesAccess(source, true);
    var second_reader = try controller.openAudioReader(source, false);
    const instance = controller.documentControllerInstance();
    const api: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    api.destroyDocumentController.?(
        instance.documentControllerRef,
    );
    try std.testing.expectEqual(@as(usize, 3), audio.destroy_count);
    try std.testing.expectError(
        error.AudioReaderUnavailable,
        second_reader.readF32(0, &buffers),
    );
}

test "ARA controller publishes typed provider content readers" {
    const TestController = Controller(.{
        .musical_contexts = 1,
        .region_sequences = 1,
        .audio_sources = 1,
        .audio_modifications = 1,
        .playback_regions = 1,
        .content_readers = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    });
    const ProviderState = struct {
        notes: [2]raw.ARAContentNote,
    };
    const Provider = struct {
        fn state(context: ?*anyopaque) *ProviderState {
            return @ptrCast(@alignCast(context.?));
        }

        fn available(
            context: ?*anyopaque,
            object: *const TestController.ContentObject,
            content_type: raw.ARAContentType,
        ) bool {
            _ = state(context);
            return object.* == .audio_source and
                content_type == raw.kARAContentTypeNotes;
        }

        fn grade(
            context: ?*anyopaque,
            object: *const TestController.ContentObject,
            content_type: raw.ARAContentType,
        ) raw.ARAContentGrade {
            _ = context;
            _ = object;
            _ = content_type;
            return raw.kARAContentGradeDetected;
        }

        fn count(
            context: ?*anyopaque,
            object: *const TestController.ContentObject,
            content_type: raw.ARAContentType,
            range: ?*const raw.ARAContentTimeRange,
            output: *usize,
        ) bool {
            _ = object;
            _ = content_type;
            _ = range;
            output.* = state(context).notes.len;
            return true;
        }

        fn data(
            context: ?*anyopaque,
            object: *const TestController.ContentObject,
            content_type: raw.ARAContentType,
            range: ?*const raw.ARAContentTimeRange,
            event_index: usize,
        ) ?*const anyopaque {
            _ = object;
            _ = content_type;
            _ = range;
            const provider = state(context);
            if (event_index >= provider.notes.len) return null;
            return &provider.notes[event_index];
        }

        const vtable = TestController.ContentProvider.VTable{
            .is_available = available,
            .grade = grade,
            .event_count = count,
            .event_data = data,
        };
    };

    var provider_state = ProviderState{
        .notes = .{
            .{
                .frequency = 440.0,
                .pitchNumber = 69,
                .volume = 0.8,
                .startPosition = 0.0,
                .noteDuration = 0.5,
                .signalDuration = 0.5,
            },
            .{
                .frequency = 523.251,
                .pitchNumber = 72,
                .volume = 0.7,
                .startPosition = 0.5,
                .noteDuration = 0.5,
                .signalDuration = 0.5,
            },
        },
    };
    var factory = std.mem.zeroes(raw.ARAFactory);
    var host = testHost();
    var document_properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Session",
    };
    var controller: TestController = undefined;
    try controller.init(&factory, &host, &document_properties);
    try controller.setContentProvider(.{
        .context = @ptrCast(&provider_state),
        .vtable = &Provider.vtable,
    });
    try controller.document.beginEditing();
    const source_id = try controller.document.createAudioSource(
        null,
        .{
            .name = "Take",
            .persistent_id = "source-1",
            .sample_count = 8,
            .sample_rate = 48_000.0,
            .channel_count = 1,
        },
    );
    _ = try controller.document.endEditing();
    const source_ref = encodeRef(raw.ARAAudioSourceRef, source_id);
    const instance = controller.documentControllerInstance();
    const api: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeNotes,
        ),
    );
    try std.testing.expectEqual(
        raw.kARAContentGradeDetected,
        api.getAudioSourceContentGrade.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeNotes,
        ),
    );
    const reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeNotes,
        null,
    );
    try std.testing.expect(reader != null);
    try std.testing.expectEqual(
        @as(i32, 2),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const event_pointer = api.getContentReaderDataForEvent.?(
        instance.documentControllerRef,
        reader,
        1,
    ) orelse return error.TestUnexpectedResult;
    const Note = TestController.EventType(
        raw.kARAContentTypeNotes,
    );
    const note: *const Note = @ptrCast(@alignCast(event_pointer));
    try std.testing.expectEqual(@as(i32, 72), note.pitchNumber);
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );
    try std.testing.expectEqual(
        @as(i32, 0),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    try std.testing.expectEqual(
        error.ContentReaderUnavailable,
        controller.takeLastError().?,
    );
}

test "ARA controller routes validated analysis requests and host notifications" {
    const TestController = Controller(.{
        .audio_sources = 1,
        .content_readers = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    });
    const SourceId = @FieldType(
        TestController.ContentObject,
        "audio_source",
    );
    const sameSource = struct {
        fn call(left: SourceId, right: SourceId) bool {
            return left.index == right.index and
                left.generation == right.generation;
        }
    }.call;
    const ProviderState = struct {
        source_id: ?SourceId = null,
        incomplete: bool = true,
        request_count: usize = 0,
        source_change_count: usize = 0,
        changed_range: ?raw.ARAContentTimeRange = null,
    };
    const Provider = struct {
        fn state(context: ?*anyopaque) *ProviderState {
            return @ptrCast(@alignCast(context.?));
        }

        fn incomplete(
            context: ?*anyopaque,
            source_id: SourceId,
            content_type: raw.ARAContentType,
        ) bool {
            const provider = state(context);
            return provider.incomplete and
                sameSource(provider.source_id.?, source_id) and
                content_type == raw.kARAContentTypeNotes;
        }

        fn request(
            context: ?*anyopaque,
            source_id: SourceId,
            content_types: []const raw.ARAContentType,
        ) bool {
            const provider = state(context);
            if (!sameSource(provider.source_id.?, source_id) or
                content_types.len != 1 or
                content_types[0] != raw.kARAContentTypeNotes)
                return false;
            provider.request_count += 1;
            provider.incomplete = false;
            return true;
        }

        fn changed(
            context: ?*anyopaque,
            source_id: SourceId,
            range: ?raw.ARAContentTimeRange,
            flags: raw.ARAContentUpdateFlags,
        ) void {
            _ = flags;
            const provider = state(context);
            if (!sameSource(provider.source_id.?, source_id)) return;
            provider.source_change_count += 1;
            provider.changed_range = range;
        }

        fn available(
            context: ?*anyopaque,
            object: *const TestController.ContentObject,
            content_type: raw.ARAContentType,
        ) bool {
            _ = context;
            _ = object;
            _ = content_type;
            return false;
        }

        fn grade(
            context: ?*anyopaque,
            object: *const TestController.ContentObject,
            content_type: raw.ARAContentType,
        ) raw.ARAContentGrade {
            _ = context;
            _ = object;
            _ = content_type;
            return raw.kARAContentGradeInitial;
        }

        fn count(
            context: ?*anyopaque,
            object: *const TestController.ContentObject,
            content_type: raw.ARAContentType,
            range: ?*const raw.ARAContentTimeRange,
            output: *usize,
        ) bool {
            _ = context;
            _ = object;
            _ = content_type;
            _ = range;
            _ = output;
            return false;
        }

        fn data(
            context: ?*anyopaque,
            object: *const TestController.ContentObject,
            content_type: raw.ARAContentType,
            range: ?*const raw.ARAContentTimeRange,
            event_index: usize,
        ) ?*const anyopaque {
            _ = context;
            _ = object;
            _ = content_type;
            _ = range;
            _ = event_index;
            return null;
        }

        const vtable = TestController.ContentProvider.VTable{
            .analysis_incomplete = incomplete,
            .request_analysis = request,
            .source_content_changed = changed,
            .is_available = available,
            .grade = grade,
            .event_count = count,
            .event_data = data,
        };
    };
    const HostState = struct {
        source_ref: raw.ARAAudioSourceHostRef = null,
        progress_state: raw.ARAAnalysisProgressState = -1,
        progress: f32 = -1,
        content_change_count: usize = 0,
        content_flags: raw.ARAContentUpdateFlags = 0,
        content_range: ?raw.ARAContentTimeRange = null,
    };
    const Host = struct {
        fn state(
            host_ref: raw.ARAModelUpdateControllerHostRef,
        ) *HostState {
            return @ptrCast(@alignCast(host_ref.?));
        }

        fn progress(
            host_ref: raw.ARAModelUpdateControllerHostRef,
            source_ref: raw.ARAAudioSourceHostRef,
            progress_state: raw.ARAAnalysisProgressState,
            value: f32,
        ) callconv(.c) void {
            const host = state(host_ref);
            host.source_ref = source_ref;
            host.progress_state = progress_state;
            host.progress = value;
        }

        fn changed(
            host_ref: raw.ARAModelUpdateControllerHostRef,
            source_ref: raw.ARAAudioSourceHostRef,
            range: [*c]const raw.ARAContentTimeRange,
            flags: raw.ARAContentUpdateFlags,
        ) callconv(.c) void {
            const host = state(host_ref);
            host.source_ref = source_ref;
            host.content_change_count += 1;
            host.content_flags = flags;
            host.content_range =
                if (range == null) null else range[0];
        }

        const interface = raw.ARAModelUpdateControllerInterface{
            .structSize = @sizeOf(raw.ARAModelUpdateControllerInterface),
            .notifyAudioSourceAnalysisProgress = progress,
            .notifyAudioSourceContentChanged = changed,
        };
    };

    const analyzeable = [_]raw.ARAContentType{
        raw.kARAContentTypeNotes,
    };
    var factory = std.mem.zeroes(raw.ARAFactory);
    factory.analyzeableContentTypesCount = analyzeable.len;
    factory.analyzeableContentTypes = &analyzeable;
    var host_state = HostState{};
    var host = testHost();
    host.modelUpdateControllerHostRef = @ptrCast(&host_state);
    host.modelUpdateControllerInterface = &Host.interface;
    var document_properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Session",
    };
    var controller: TestController = undefined;
    try controller.init(&factory, &host, &document_properties);
    var source_host_token: u8 = 0;
    try controller.document.beginEditing();
    const source_id = try controller.document.createAudioSource(
        @ptrCast(&source_host_token),
        .{
            .name = "Take",
            .persistent_id = "source-1",
            .sample_count = 8,
            .sample_rate = 48_000,
            .channel_count = 1,
        },
    );
    _ = try controller.document.endEditing();
    var provider_state = ProviderState{ .source_id = source_id };
    try controller.setContentProvider(.{
        .context = @ptrCast(&provider_state),
        .vtable = &Provider.vtable,
    });

    const source_ref = encodeRef(raw.ARAAudioSourceRef, source_id);
    const instance = controller.documentControllerInstance();
    const api: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAnalysisIncomplete.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeNotes,
        ),
    );
    api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        source_ref,
        analyzeable.len,
        &analyzeable,
    );
    try std.testing.expectEqual(@as(usize, 1), provider_state.request_count);
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.isAudioSourceContentAnalysisIncomplete.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeNotes,
        ),
    );

    const duplicate = [_]raw.ARAContentType{
        raw.kARAContentTypeNotes,
        raw.kARAContentTypeNotes,
    };
    api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        source_ref,
        duplicate.len,
        &duplicate,
    );
    try std.testing.expectEqual(
        error.InvalidProperties,
        controller.takeLastError().?,
    );
    const unavailable = [_]raw.ARAContentType{
        raw.kARAContentTypeTempoEntries,
    };
    api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        source_ref,
        unavailable.len,
        &unavailable,
    );
    try std.testing.expectEqual(
        error.InvalidProperties,
        controller.takeLastError().?,
    );

    const changed_range = raw.ARAContentTimeRange{
        .start = 0.25,
        .duration = 0.5,
    };
    api.updateAudioSourceContent.?(
        instance.documentControllerRef,
        source_ref,
        &changed_range,
        raw.kARAContentUpdateTimingScopeRemainsUnchanged,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        provider_state.source_change_count,
    );
    try std.testing.expectEqual(
        changed_range.start,
        provider_state.changed_range.?.start,
    );

    try controller.notifyAudioSourceAnalysisProgress(
        source_id,
        raw.kARAAnalysisProgressStarted,
        0.25,
    );
    try std.testing.expectEqual(
        raw.kARAAnalysisProgressStarted,
        host_state.progress_state,
    );
    try std.testing.expectEqual(@as(f32, 0.25), host_state.progress);
    try std.testing.expectEqual(
        @as(raw.ARAAudioSourceHostRef, @ptrCast(&source_host_token)),
        host_state.source_ref,
    );
    try controller.notifyAudioSourceContentChanged(
        source_id,
        changed_range,
        raw.kARAContentUpdateSignalScopeRemainsUnchanged,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        host_state.content_change_count,
    );
    try std.testing.expectEqual(
        raw.kARAContentUpdateSignalScopeRemainsUnchanged,
        host_state.content_flags,
    );
    try std.testing.expectEqual(
        changed_range.duration,
        host_state.content_range.?.duration,
    );
    try std.testing.expectError(
        error.InvalidProperties,
        controller.notifyAudioSourceAnalysisProgress(
            source_id,
            raw.kARAAnalysisProgressUpdated,
            std.math.nan(f32),
        ),
    );
}

const TestAudio = struct {
    samples: [2][8]f32,
    reader_open_count: usize = 0,
    next_reader_address: usize = 0x1000,
    destroy_count: usize = 0,
    block_reads: std.atomic.Value(bool) =
        std.atomic.Value(bool).init(false),
    read_started: std.atomic.Value(bool) =
        std.atomic.Value(bool).init(false),
    release_reads: std.atomic.Value(bool) =
        std.atomic.Value(bool).init(false),
};

fn testAudioFromHost(
    host_ref: raw.ARAAudioAccessControllerHostRef,
) *TestAudio {
    return @ptrCast(@alignCast(host_ref.?));
}

fn testCreateAudioReader(
    host_ref: raw.ARAAudioAccessControllerHostRef,
    source_ref: raw.ARAAudioSourceHostRef,
    use_64_bit_samples: raw.ARABool,
) callconv(.c) raw.ARAAudioReaderHostRef {
    _ = source_ref;
    const audio = testAudioFromHost(host_ref);
    if (use_64_bit_samples != raw.kARAFalse)
        return null;
    const address = audio.next_reader_address;
    audio.next_reader_address += 0x1000;
    audio.reader_open_count += 1;
    return @ptrFromInt(address);
}

fn testReadAudio(
    host_ref: raw.ARAAudioAccessControllerHostRef,
    reader_ref: raw.ARAAudioReaderHostRef,
    sample_position: raw.ARASamplePosition,
    samples_per_channel: raw.ARASampleCount,
    buffers: [*c]const ?*anyopaque,
) callconv(.c) raw.ARABool {
    _ = reader_ref;
    const audio = testAudioFromHost(host_ref);
    if (audio.reader_open_count == 0 or
        sample_position < 0 or
        samples_per_channel < 0 or
        buffers == null)
        return raw.kARAFalse;
    const start: usize = @intCast(sample_position);
    const count: usize = @intCast(samples_per_channel);
    if (start > audio.samples[0].len or
        count > audio.samples[0].len - start)
        return raw.kARAFalse;
    if (audio.block_reads.load(.acquire)) {
        audio.read_started.store(true, .release);
        while (!audio.release_reads.load(.acquire))
            std.Thread.yield() catch {};
    }
    for (0..audio.samples.len) |channel| {
        const destination: [*]f32 =
            @ptrCast(@alignCast(buffers[channel].?));
        @memcpy(
            destination[0..count],
            audio.samples[channel][start..][0..count],
        );
    }
    return raw.kARATrue;
}

fn testDestroyAudioReader(
    host_ref: raw.ARAAudioAccessControllerHostRef,
    reader_ref: raw.ARAAudioReaderHostRef,
) callconv(.c) void {
    _ = reader_ref;
    const audio = testAudioFromHost(host_ref);
    if (audio.reader_open_count == 0) return;
    audio.reader_open_count -= 1;
    audio.destroy_count += 1;
}

fn testHostWithAudio(
    audio: *TestAudio,
) raw.ARADocumentControllerHostInstance {
    const Host = struct {
        const audio_interface =
            raw.ARAAudioAccessControllerInterface{
                .structSize = @sizeOf(raw.ARAAudioAccessControllerInterface),
                .createAudioReaderForSource = testCreateAudioReader,
                .readAudioSamples = testReadAudio,
                .destroyAudioReader = testDestroyAudioReader,
            };
        const archive = raw.ARAArchivingControllerInterface{
            .structSize = @sizeOf(raw.ARAArchivingControllerInterface),
        };
        const content = raw.ARAContentAccessControllerInterface{
            .structSize = @sizeOf(raw.ARAContentAccessControllerInterface),
        };
        const model_update = raw.ARAModelUpdateControllerInterface{
            .structSize = @sizeOf(raw.ARAModelUpdateControllerInterface),
        };
        const playback = raw.ARAPlaybackControllerInterface{
            .structSize = @sizeOf(raw.ARAPlaybackControllerInterface),
        };
    };
    return .{
        .structSize = @sizeOf(raw.ARADocumentControllerHostInstance),
        .audioAccessControllerHostRef = @ptrCast(audio),
        .audioAccessControllerInterface = &Host.audio_interface,
        .archivingControllerInterface = &Host.archive,
        .contentAccessControllerInterface = &Host.content,
        .modelUpdateControllerInterface = &Host.model_update,
        .playbackControllerInterface = &Host.playback,
    };
}

const TestArchive = struct {
    bytes: [4096]u8 = @splat(0),
    length: usize = 0,
    store_progress: f32 = 0.0,
    restore_progress: f32 = 0.0,
};

fn testArchiveFromHost(
    host_ref: raw.ARAArchivingControllerHostRef,
) *TestArchive {
    return @ptrCast(@alignCast(host_ref.?));
}

fn testGetArchiveSize(
    host_ref: raw.ARAArchivingControllerHostRef,
    reader_ref: raw.ARAArchiveReaderHostRef,
) callconv(.c) raw.ARASize {
    _ = reader_ref;
    return testArchiveFromHost(host_ref).length;
}

fn testReadArchive(
    host_ref: raw.ARAArchivingControllerHostRef,
    reader_ref: raw.ARAArchiveReaderHostRef,
    position: raw.ARASize,
    length: raw.ARASize,
    buffer: [*c]raw.ARAByte,
) callconv(.c) raw.ARABool {
    _ = reader_ref;
    const archive = testArchiveFromHost(host_ref);
    if (buffer == null or
        position > archive.length or
        length > archive.length - position)
        return raw.kARAFalse;
    @memcpy(buffer[0..length], archive.bytes[position..][0..length]);
    return raw.kARATrue;
}

fn testWriteArchive(
    host_ref: raw.ARAArchivingControllerHostRef,
    writer_ref: raw.ARAArchiveWriterHostRef,
    position: raw.ARASize,
    length: raw.ARASize,
    buffer: [*c]const raw.ARAByte,
) callconv(.c) raw.ARABool {
    _ = writer_ref;
    const archive = testArchiveFromHost(host_ref);
    if (buffer == null or
        position > archive.bytes.len or
        length > archive.bytes.len - position)
        return raw.kARAFalse;
    @memcpy(archive.bytes[position..][0..length], buffer[0..length]);
    archive.length = @max(archive.length, position + length);
    return raw.kARATrue;
}

fn testStoreProgress(
    host_ref: raw.ARAArchivingControllerHostRef,
    value: f32,
) callconv(.c) void {
    testArchiveFromHost(host_ref).store_progress = value;
}

fn testRestoreProgress(
    host_ref: raw.ARAArchivingControllerHostRef,
    value: f32,
) callconv(.c) void {
    testArchiveFromHost(host_ref).restore_progress = value;
}

fn testHostWithArchive(
    archive: *TestArchive,
) raw.ARADocumentControllerHostInstance {
    const Host = struct {
        const audio = raw.ARAAudioAccessControllerInterface{
            .structSize = @sizeOf(raw.ARAAudioAccessControllerInterface),
        };
        const archive_interface =
            raw.ARAArchivingControllerInterface{
                .structSize = @sizeOf(raw.ARAArchivingControllerInterface),
                .getArchiveSize = testGetArchiveSize,
                .readBytesFromArchive = testReadArchive,
                .writeBytesToArchive = testWriteArchive,
                .notifyDocumentArchivingProgress = testStoreProgress,
                .notifyDocumentUnarchivingProgress = testRestoreProgress,
            };
        const content = raw.ARAContentAccessControllerInterface{
            .structSize = @sizeOf(raw.ARAContentAccessControllerInterface),
        };
        const model_update = raw.ARAModelUpdateControllerInterface{
            .structSize = @sizeOf(raw.ARAModelUpdateControllerInterface),
        };
        const playback = raw.ARAPlaybackControllerInterface{
            .structSize = @sizeOf(raw.ARAPlaybackControllerInterface),
        };
    };
    return .{
        .structSize = @sizeOf(raw.ARADocumentControllerHostInstance),
        .audioAccessControllerInterface = &Host.audio,
        .archivingControllerHostRef = @ptrCast(archive),
        .archivingControllerInterface = &Host.archive_interface,
        .contentAccessControllerInterface = &Host.content,
        .modelUpdateControllerInterface = &Host.model_update,
        .playbackControllerInterface = &Host.playback,
    };
}

fn testHost() raw.ARADocumentControllerHostInstance {
    const Host = struct {
        const audio = raw.ARAAudioAccessControllerInterface{
            .structSize = @sizeOf(raw.ARAAudioAccessControllerInterface),
        };
        const archive = raw.ARAArchivingControllerInterface{
            .structSize = @sizeOf(raw.ARAArchivingControllerInterface),
        };
        const content = raw.ARAContentAccessControllerInterface{
            .structSize = @sizeOf(raw.ARAContentAccessControllerInterface),
        };
        const model_update = raw.ARAModelUpdateControllerInterface{
            .structSize = @sizeOf(raw.ARAModelUpdateControllerInterface),
        };
        const playback = raw.ARAPlaybackControllerInterface{
            .structSize = @sizeOf(raw.ARAPlaybackControllerInterface),
        };
    };
    return .{
        .structSize = @sizeOf(raw.ARADocumentControllerHostInstance),
        .audioAccessControllerInterface = &Host.audio,
        .archivingControllerInterface = &Host.archive,
        .contentAccessControllerInterface = &Host.content,
        .modelUpdateControllerInterface = &Host.model_update,
        .playbackControllerInterface = &Host.playback,
    };
}

const TestHostTempoContent = struct {
    events: [3]raw.ARAContentTempoEntry = .{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 1.0, .quarterPosition = 2.0 },
        .{ .timePosition = 3.0, .quarterPosition = 5.0 },
    },
    create_calls: usize = 0,
    destroy_calls: usize = 0,
    requested_range: ?raw.ARAContentTimeRange = null,
};

fn testTempoContentState(
    host_ref: raw.ARAContentAccessControllerHostRef,
) *TestHostTempoContent {
    return @ptrCast(@alignCast(host_ref orelse
        unreachable));
}

fn testMusicalContentAvailable(
    _: raw.ARAContentAccessControllerHostRef,
    context_ref: raw.ARAMusicalContextHostRef,
    content_type: raw.ARAContentType,
) callconv(.c) raw.ARABool {
    if (context_ref == null or
        content_type != raw.kARAContentTypeTempoEntries)
        return raw.kARAFalse;
    return raw.kARATrue;
}

fn testMusicalContentGrade(
    _: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAMusicalContextHostRef,
    _: raw.ARAContentType,
) callconv(.c) raw.ARAContentGrade {
    return raw.kARAContentGradeApproved;
}

fn testCreateMusicalContentReader(
    host_ref: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAMusicalContextHostRef,
    _: raw.ARAContentType,
    range: [*c]const raw.ARAContentTimeRange,
) callconv(.c) raw.ARAContentReaderHostRef {
    const state = testTempoContentState(host_ref);
    state.create_calls += 1;
    state.requested_range =
        if (range == null) null else range[0];
    return @ptrFromInt(0x2000);
}

fn testHostContentEventCount(
    host_ref: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAContentReaderHostRef,
) callconv(.c) raw.ARAInt32 {
    return @intCast(
        testTempoContentState(host_ref).events.len,
    );
}

fn testHostContentEventData(
    host_ref: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAContentReaderHostRef,
    event_index: raw.ARAInt32,
) callconv(.c) ?*const anyopaque {
    if (event_index < 0) return null;
    const state = testTempoContentState(host_ref);
    const index: usize = @intCast(event_index);
    if (index >= state.events.len) return null;
    return &state.events[index];
}

fn testDestroyHostContentReader(
    host_ref: raw.ARAContentAccessControllerHostRef,
    _: raw.ARAContentReaderHostRef,
) callconv(.c) void {
    testTempoContentState(host_ref).destroy_calls += 1;
}

test "ARA controller copies bounded host musical-context content" {
    const limits = model_api.Limits{
        .musical_contexts = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    };
    const TestController = Controller(limits);
    const Host = struct {
        const audio = raw.ARAAudioAccessControllerInterface{
            .structSize = @sizeOf(raw.ARAAudioAccessControllerInterface),
        };
        const archive = raw.ARAArchivingControllerInterface{
            .structSize = @sizeOf(raw.ARAArchivingControllerInterface),
        };
        const content = raw.ARAContentAccessControllerInterface{
            .structSize = @sizeOf(raw.ARAContentAccessControllerInterface),
            .isMusicalContextContentAvailable = testMusicalContentAvailable,
            .getMusicalContextContentGrade = testMusicalContentGrade,
            .createMusicalContextContentReader = testCreateMusicalContentReader,
            .getContentReaderEventCount = testHostContentEventCount,
            .getContentReaderDataForEvent = testHostContentEventData,
            .destroyContentReader = testDestroyHostContentReader,
        };
        const model_update =
            raw.ARAModelUpdateControllerInterface{
                .structSize = @sizeOf(
                    raw.ARAModelUpdateControllerInterface,
                ),
            };
        const playback = raw.ARAPlaybackControllerInterface{
            .structSize = @sizeOf(raw.ARAPlaybackControllerInterface),
        };
    };
    var state = TestHostTempoContent{};
    var controller = TestController{
        .host = .{
            .structSize = @sizeOf(
                raw.ARADocumentControllerHostInstance,
            ),
            .audioAccessControllerInterface = &Host.audio,
            .archivingControllerInterface = &Host.archive,
            .contentAccessControllerHostRef = @ptrCast(&state),
            .contentAccessControllerInterface = &Host.content,
            .modelUpdateControllerInterface = &Host.model_update,
            .playbackControllerInterface = &Host.playback,
        },
        .factory = @ptrFromInt(0x1000),
    };
    try controller.document.beginEditing();
    const context =
        try controller.document.createMusicalContext(
            @ptrFromInt(0x3000),
            .{ .name = "Song", .order_index = 0 },
        );
    _ = try controller.document.endEditing();

    try std.testing.expect(
        try controller.hostMusicalContextContentAvailable(
            context,
            raw.kARAContentTypeTempoEntries,
        ),
    );
    try std.testing.expectEqual(
        raw.kARAContentGradeApproved,
        try controller.hostMusicalContextContentGrade(
            context,
            raw.kARAContentTypeTempoEntries,
        ),
    );
    var output: [3]raw.ARAContentTempoEntry = undefined;
    const range = raw.ARAContentTimeRange{
        .start = 0.5,
        .duration = 2.0,
    };
    try std.testing.expectEqual(
        @as(usize, 3),
        try controller.copyHostMusicalContextContent(
            context,
            raw.kARAContentTypeTempoEntries,
            range,
            &output,
        ),
    );
    try std.testing.expectEqualDeep(state.events, output);
    try std.testing.expectEqual(
        @as(usize, 1),
        state.create_calls,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        state.destroy_calls,
    );
    try std.testing.expectEqualDeep(
        range,
        state.requested_range orelse
            return error.TestUnexpectedResult,
    );

    var too_small: [2]raw.ARAContentTempoEntry = undefined;
    try std.testing.expectError(
        error.CapacityExceeded,
        controller.copyHostMusicalContextContent(
            context,
            raw.kARAContentTypeTempoEntries,
            null,
            &too_small,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        state.destroy_calls,
    );
}
