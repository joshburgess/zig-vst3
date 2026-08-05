const std = @import("std");
const plug_core = @import("zig-vst3-plugin-core");

pub const Limits = struct {
    sources: usize = 4,
    channels: usize = 2,
    frames_per_source: usize = 48_000,
    publication_slots: usize = 3,
};

pub const PagedLimits = struct {
    sources: usize = 4,
    channels: usize = 2,
    page_slots: usize = 16,
    frames_per_page: usize = 4096,
    publication_slots: usize = 3,
};

pub const Error = error{
    SourceCapacityExceeded,
    ChannelCapacityExceeded,
    FrameCapacityExceeded,
    InvalidSourceFormat,
    SourceUnavailable,
    InvalidAudioBuffer,
    EmptySourceRange,
    SourceRangeOverflow,
    PageCapacityExceeded,
};

/// Owns fixed-capacity source audio filled from ARA on a non-realtime thread.
pub fn Cache(
    comptime ControllerType: type,
    comptime Sample: type,
    comptime limits: Limits,
) type {
    validateLimits(limits);
    if (Sample != f32 and Sample != f64)
        @compileError("ARA source caches support f32 or f64");

    const Description =
        ControllerType.PlaybackRegionRenderDescription;
    const SourceId = @FieldType(Description, "audio_source");

    const SourceState = struct {
        valid: bool = false,
        source_index: u16 = 0,
        source_generation: u32 = 0,
        sample_count: usize = 0,
        sample_rate: f64 = 0,
        channel_count: usize = 0,
        samples: [limits.channels][limits.frames_per_source]Sample =
            @splat(@splat(0)),
    };
    const SourcePublisher = plug_core.dsp.RealtimeReferencePublisher(
        SourceState,
        limits.publication_slots,
    );

    return struct {
        const Self = @This();

        publishers: [limits.sources]SourcePublisher,

        pub fn init() Self {
            var publishers: [limits.sources]SourcePublisher = undefined;
            for (&publishers) |*publisher|
                publisher.* = SourcePublisher.init(.{});
            return .{ .publishers = publishers };
        }

        pub fn storageBytes() usize {
            return @sizeOf(Self);
        }

        /// Loads one complete source through the ARA non-realtime reader API.
        ///
        /// Call this only from a host-authorized model or control callback.
        /// A failed load leaves the previously published generation active.
        pub fn loadSource(
            self: *Self,
            controller: *ControllerType,
            source_id: SourceId,
        ) !u64 {
            const slot_index = try sourceSlotIndex(source_id);
            const source = controller.document.audioSource(source_id) orelse
                return error.SourceUnavailable;
            if (!std.math.isFinite(source.sample_rate) or
                source.sample_rate <= 0 or
                source.sample_count <= 0 or
                source.channel_count <= 0)
                return error.InvalidSourceFormat;
            if (source.channel_count > limits.channels)
                return error.ChannelCapacityExceeded;
            if (source.sample_count > limits.frames_per_source)
                return error.FrameCapacityExceeded;

            var reader = try controller.openAudioReader(
                source_id,
                Sample == f64,
            );
            defer reader.close();

            var writer =
                try self.publishers[slot_index].beginPublish();
            defer writer.cancel();
            const state = writer.value() orelse
                return error.SourceUnavailable;
            state.* = .{};
            state.source_index = source_id.index;
            state.source_generation = source_id.generation;
            state.sample_count = @intCast(source.sample_count);
            state.sample_rate = source.sample_rate;
            state.channel_count = @intCast(source.channel_count);

            var buffers: [limits.channels][]Sample = undefined;
            for (0..state.channel_count) |channel|
                buffers[channel] =
                    state.samples[channel][0..state.sample_count];
            if (comptime Sample == f32) {
                try reader.readF32(
                    0,
                    buffers[0..state.channel_count],
                );
            } else {
                try reader.readF64(
                    0,
                    buffers[0..state.channel_count],
                );
            }
            state.valid = true;
            return writer.commit();
        }

        /// Publishes an unavailable generation for one source slot.
        pub fn invalidate(
            self: *Self,
            source_id: SourceId,
        ) !u64 {
            const slot_index = try sourceSlotIndex(source_id);
            return self.publishers[slot_index].publish(.{
                .source_index = source_id.index,
                .source_generation = source_id.generation,
            });
        }

        /// Returns callbacks that borrow this cache at its current address.
        ///
        /// Keep the cache at that address until every renderer using the
        /// provider has been detached.
        pub fn provider(
            self: *Self,
            comptime RendererType: type,
        ) RendererType.SourceProvider {
            return .{
                .context = self,
                .ready = providerReady,
                .read = providerRead,
            };
        }

        fn providerReady(
            context: ?*anyopaque,
            description: *const Description,
        ) bool {
            const self: *Self =
                @ptrCast(@alignCast(context orelse return false));
            const slot_index =
                sourceSlotIndex(description.audio_source) catch
                    return false;
            var handle =
                self.publishers[slot_index].tryAcquire() orelse
                return false;
            defer handle.release();
            const state = handle.value() orelse return false;
            const source_sample_count = std.math.cast(
                usize,
                description.source_sample_count,
            ) orelse return false;
            const source_channel_count = std.math.cast(
                usize,
                description.source_channel_count,
            ) orelse return false;
            return stateValid(
                state,
                description.audio_source,
            ) and
                description.source_sample_count > 0 and
                state.sample_count == source_sample_count and
                state.sample_rate ==
                    description.source_sample_rate and
                description.source_channel_count > 0 and
                state.channel_count == source_channel_count;
        }

        fn providerRead(
            context: ?*anyopaque,
            source_id: SourceId,
            sample_position: i64,
            buffers: []const []Sample,
        ) anyerror!void {
            const self: *Self =
                @ptrCast(@alignCast(context orelse
                    return error.SourceUnavailable));
            if (sample_position < 0)
                return error.InvalidAudioBuffer;
            const slot_index = try sourceSlotIndex(source_id);
            var handle =
                self.publishers[slot_index].tryAcquire() orelse
                return error.SourceUnavailable;
            defer handle.release();
            const state = handle.value() orelse
                return error.SourceUnavailable;
            if (!stateValid(state, source_id))
                return error.SourceUnavailable;
            if (buffers.len != state.channel_count)
                return error.InvalidAudioBuffer;
            const start = std.math.cast(
                usize,
                sample_position,
            ) orelse return error.InvalidAudioBuffer;
            const count = if (buffers.len == 0)
                0
            else
                buffers[0].len;
            for (buffers) |buffer| {
                if (buffer.len != count)
                    return error.InvalidAudioBuffer;
            }
            if (sampleBuffersOverlap(Sample, buffers))
                return error.InvalidAudioBuffer;
            if (start > state.sample_count or
                count > state.sample_count - start)
                return error.InvalidAudioBuffer;
            for (buffers, 0..) |destination, channel|
                @memcpy(
                    destination,
                    state.samples[channel][start..][0..count],
                );
        }

        fn sourceSlotIndex(source_id: SourceId) Error!usize {
            if (source_id.index >= limits.sources)
                return error.SourceCapacityExceeded;
            return source_id.index;
        }

        fn stateMatches(
            state: *const SourceState,
            source_id: SourceId,
        ) bool {
            return state.valid and
                state.source_index == source_id.index and
                state.source_generation == source_id.generation;
        }

        fn stateValid(
            state: *const SourceState,
            source_id: SourceId,
        ) bool {
            return stateMatches(state, source_id) and
                state.sample_count > 0 and
                state.sample_count <= limits.frames_per_source and
                std.math.isFinite(state.sample_rate) and
                state.sample_rate > 0.0 and
                state.channel_count > 0 and
                state.channel_count <= limits.channels;
        }
    };
}

/// Owns a bounded working set of immutable source pages.
///
/// Page fills use ARA readers only on the model or control thread. A directory
/// generation becomes visible after every required page generation commits.
/// Realtime reads either observe one complete directory generation or fail,
/// allowing the renderer to replace the complete block with silence.
pub fn PagedCache(
    comptime ControllerType: type,
    comptime Sample: type,
    comptime limits: PagedLimits,
) type {
    validatePagedLimits(limits);
    if (Sample != f32 and Sample != f64)
        @compileError("ARA paged source caches support f32 or f64");

    const Description =
        ControllerType.PlaybackRegionRenderDescription;
    const SourceId = @FieldType(Description, "audio_source");

    const PageState = struct {
        valid: bool = false,
        source_index: u16 = 0,
        source_generation: u32 = 0,
        logical_page: usize = 0,
        source_sample_count: usize = 0,
        sample_rate: f64 = 0,
        channel_count: usize = 0,
        frame_count: usize = 0,
        samples: [limits.channels][limits.frames_per_page]Sample =
            @splat(@splat(0)),
    };
    const PagePublisher = plug_core.dsp.RealtimeReferencePublisher(
        PageState,
        limits.publication_slots,
    );

    const DirectoryEntry = struct {
        valid: bool = false,
        source_index: u16 = 0,
        source_generation: u32 = 0,
        logical_page: usize = 0,
        page_generation: u64 = 0,
        last_used: u64 = 0,
    };
    const Directory = struct {
        entries: [limits.page_slots]DirectoryEntry =
            @splat(.{}),
        clock: u64 = 0,
    };
    const DirectoryPublisher =
        plug_core.dsp.RealtimeReferencePublisher(
            Directory,
            limits.publication_slots,
        );

    const FrameRange = struct {
        start: usize,
        count: usize,
    };

    return struct {
        const Self = @This();

        pages: [limits.page_slots]PagePublisher,
        directory: DirectoryPublisher,

        pub fn init() Self {
            var pages: [limits.page_slots]PagePublisher = undefined;
            for (&pages) |*page|
                page.* = PagePublisher.init(.{});
            return .{
                .pages = pages,
                .directory = DirectoryPublisher.init(.{}),
            };
        }

        pub fn storageBytes() usize {
            return @sizeOf(Self);
        }

        /// Loads every page needed by one render description.
        pub fn loadRegion(
            self: *Self,
            controller: *ControllerType,
            description: *const Description,
        ) !u64 {
            const range = try requiredFrameRange(description);
            return self.loadRangeInternal(
                controller,
                description.audio_source,
                range.start,
                range.count,
                false,
            );
        }

        /// Replaces every required page while keeping the current directory
        /// active until all new page generations have been filled.
        pub fn refreshRegion(
            self: *Self,
            controller: *ControllerType,
            description: *const Description,
        ) !u64 {
            const range = try requiredFrameRange(description);
            return self.loadRangeInternal(
                controller,
                description.audio_source,
                range.start,
                range.count,
                true,
            );
        }

        /// Loads one source-frame range and merges it into the current working
        /// set. Least-recently-used pages outside the requested range are
        /// replaced when no unused slots remain.
        pub fn loadRange(
            self: *Self,
            controller: *ControllerType,
            source_id: SourceId,
            start_frame: usize,
            frame_count: usize,
        ) !u64 {
            return self.loadRangeInternal(
                controller,
                source_id,
                start_frame,
                frame_count,
                false,
            );
        }

        /// Replaces a source-frame range even when every logical page is
        /// already cached.
        pub fn refreshRange(
            self: *Self,
            controller: *ControllerType,
            source_id: SourceId,
            start_frame: usize,
            frame_count: usize,
        ) !u64 {
            return self.loadRangeInternal(
                controller,
                source_id,
                start_frame,
                frame_count,
                true,
            );
        }

        fn loadRangeInternal(
            self: *Self,
            controller: *ControllerType,
            source_id: SourceId,
            start_frame: usize,
            frame_count: usize,
            refresh: bool,
        ) !u64 {
            _ = try sourceSlotIndex(source_id);
            if (frame_count == 0) return error.EmptySourceRange;
            const end_frame = std.math.add(
                usize,
                start_frame,
                frame_count,
            ) catch return error.SourceRangeOverflow;
            const source = controller.document.audioSource(source_id) orelse
                return error.SourceUnavailable;
            if (!std.math.isFinite(source.sample_rate) or
                source.sample_rate <= 0 or
                source.sample_count <= 0 or
                source.channel_count <= 0)
                return error.InvalidSourceFormat;
            if (source.channel_count > limits.channels)
                return error.ChannelCapacityExceeded;
            const source_sample_count = std.math.cast(
                usize,
                source.sample_count,
            ) orelse return error.InvalidSourceFormat;
            if (start_frame >= source_sample_count or
                end_frame > source_sample_count)
                return error.InvalidAudioBuffer;

            const first_page = start_frame / limits.frames_per_page;
            const last_page =
                (end_frame - 1) / limits.frames_per_page;
            const needed_page_count =
                last_page - first_page + 1;
            if (needed_page_count > limits.page_slots)
                return error.PageCapacityExceeded;

            var current =
                self.directory.tryAcquire() orelse
                return error.SourceUnavailable;
            defer current.release();
            const current_directory = current.value() orelse
                return error.SourceUnavailable;
            var directory_writer =
                try self.directory.beginPublish();
            defer directory_writer.cancel();
            const next = directory_writer.value() orelse
                return error.SourceUnavailable;
            next.* = current_directory.*;
            next.clock +|= 1;

            var protected: [limits.page_slots]bool =
                @splat(false);
            var missing_pages: [limits.page_slots]usize =
                undefined;
            var selected_slots: [limits.page_slots]?usize =
                @splat(null);
            var missing_count: usize = 0;
            for (first_page..last_page + 1) |logical_page| {
                const existing = findDirectoryEntry(
                    next,
                    source_id,
                    logical_page,
                );
                if (existing) |slot| {
                    if (!refresh) {
                        protected[slot] = true;
                        next.entries[slot].last_used = next.clock;
                        continue;
                    }
                    selected_slots[missing_count] = slot;
                    protected[slot] = true;
                }
                missing_pages[missing_count] = logical_page;
                missing_count += 1;
            }

            for (missing_pages[0..missing_count], 0..) |
                _,
                missing_index,
            | {
                if (selected_slots[missing_index] != null)
                    continue;
                const slot = selectVictim(
                    next,
                    &protected,
                ) orelse return error.PageCapacityExceeded;
                selected_slots[missing_index] = slot;
                protected[slot] = true;
            }

            var page_writers: [limits.page_slots]PagePublisher.Writer =
                undefined;
            var reserved_count: usize = 0;
            defer {
                for (page_writers[0..reserved_count]) |*writer|
                    writer.cancel();
            }
            var concrete_slots: [limits.page_slots]usize = undefined;
            for (selected_slots[0..missing_count], 0..) |
                maybe_slot,
                index,
            | {
                const slot = maybe_slot orelse
                    return error.PageCapacityExceeded;
                concrete_slots[index] = slot;
                page_writers[reserved_count] =
                    try self.pages[slot].beginPublish();
                reserved_count += 1;
            }
            if (missing_count == 0)
                return directory_writer.commit();

            var reader = try controller.openAudioReader(
                source_id,
                Sample == f64,
            );
            defer reader.close();
            const channel_count: usize =
                @intCast(source.channel_count);
            for (
                missing_pages[0..missing_count],
                page_writers[0..missing_count],
            ) |logical_page, *writer| {
                const state = writer.value() orelse
                    return error.SourceUnavailable;
                state.* = .{
                    .valid = true,
                    .source_index = source_id.index,
                    .source_generation = source_id.generation,
                    .logical_page = logical_page,
                    .source_sample_count = source_sample_count,
                    .sample_rate = source.sample_rate,
                    .channel_count = channel_count,
                    .frame_count = @min(
                        limits.frames_per_page,
                        source_sample_count -
                            logical_page *
                                limits.frames_per_page,
                    ),
                };
                var buffers: [limits.channels][]Sample =
                    undefined;
                for (0..channel_count) |channel|
                    buffers[channel] =
                        state.samples[channel][0..state.frame_count];
                const page_start =
                    logical_page * limits.frames_per_page;
                if (comptime Sample == f32) {
                    try reader.readF32(
                        @intCast(page_start),
                        buffers[0..channel_count],
                    );
                } else {
                    try reader.readF64(
                        @intCast(page_start),
                        buffers[0..channel_count],
                    );
                }
            }

            for (
                missing_pages[0..missing_count],
                concrete_slots[0..missing_count],
                page_writers[0..missing_count],
            ) |logical_page, slot, *writer| {
                const page_generation = try writer.commit();
                next.entries[slot] = .{
                    .valid = true,
                    .source_index = source_id.index,
                    .source_generation = source_id.generation,
                    .logical_page = logical_page,
                    .page_generation = page_generation,
                    .last_used = next.clock,
                };
            }
            return directory_writer.commit();
        }

        pub fn invalidate(
            self: *Self,
            source_id: SourceId,
        ) !u64 {
            _ = try sourceSlotIndex(source_id);
            var current =
                self.directory.tryAcquire() orelse
                return error.SourceUnavailable;
            defer current.release();
            var writer = try self.directory.beginPublish();
            defer writer.cancel();
            const next = writer.value() orelse
                return error.SourceUnavailable;
            next.* = (current.value() orelse
                return error.SourceUnavailable).*;
            next.clock +|= 1;
            for (&next.entries) |*entry| {
                if (entry.valid and
                    entry.source_index == source_id.index and
                    entry.source_generation == source_id.generation)
                {
                    entry.valid = false;
                }
            }
            return writer.commit();
        }

        pub fn provider(
            self: *Self,
            comptime RendererType: type,
        ) RendererType.SourceProvider {
            return .{
                .context = self,
                .ready = providerReady,
                .read = providerRead,
            };
        }

        fn providerReady(
            context: ?*anyopaque,
            description: *const Description,
        ) bool {
            const self: *Self =
                @ptrCast(@alignCast(context orelse return false));
            const range = requiredFrameRange(description) catch
                return false;
            var directory_handle =
                self.directory.tryAcquire() orelse return false;
            defer directory_handle.release();
            const directory = directory_handle.value() orelse
                return false;
            return self.directoryHasRange(
                directory,
                description.audio_source,
                range,
                description,
            );
        }

        fn providerRead(
            context: ?*anyopaque,
            source_id: SourceId,
            sample_position: i64,
            buffers: []const []Sample,
        ) anyerror!void {
            const self: *Self =
                @ptrCast(@alignCast(context orelse
                    return error.SourceUnavailable));
            _ = try sourceSlotIndex(source_id);
            if (sample_position < 0 or buffers.len == 0)
                return error.InvalidAudioBuffer;
            const count = buffers[0].len;
            for (buffers) |buffer| {
                if (buffer.len != count)
                    return error.InvalidAudioBuffer;
            }
            if (sampleBuffersOverlap(Sample, buffers))
                return error.InvalidAudioBuffer;
            const start = std.math.cast(
                usize,
                sample_position,
            ) orelse return error.InvalidAudioBuffer;
            const end = std.math.add(
                usize,
                start,
                count,
            ) catch return error.InvalidAudioBuffer;

            var directory_handle =
                self.directory.tryAcquire() orelse
                return error.SourceUnavailable;
            defer directory_handle.release();
            const directory = directory_handle.value() orelse
                return error.SourceUnavailable;
            const source_slot = findSourceEntry(
                directory,
                source_id,
            ) orelse return error.SourceUnavailable;
            const source_entry = directory.entries[source_slot];
            var source_page_handle =
                self.pages[source_slot].tryAcquire() orelse
                return error.SourceUnavailable;
            defer source_page_handle.release();
            if (source_page_handle.generation() !=
                @as(?u64, source_entry.page_generation))
                return error.SourceUnavailable;
            const source_page = source_page_handle.value() orelse
                return error.SourceUnavailable;
            if (!pageStateValid(
                source_page,
                source_id,
                source_entry.logical_page,
            )) return error.SourceUnavailable;
            if (buffers.len != source_page.channel_count or
                end > source_page.source_sample_count)
                return error.InvalidAudioBuffer;
            if (count == 0) {
                return;
            }
            const first_page = start / limits.frames_per_page;
            const last_page = (end - 1) / limits.frames_per_page;
            const page_count = last_page - first_page + 1;
            if (page_count > limits.page_slots)
                return error.SourceUnavailable;
            var page_handles: [limits.page_slots]?PagePublisher.Handle =
                @splat(null);
            var page_values: [limits.page_slots]*const PageState = undefined;
            var acquired_count: usize = 0;
            defer {
                for (page_handles[0..acquired_count]) |*maybe_handle| {
                    if (maybe_handle.*) |*handle| handle.release();
                }
            }
            for (first_page..last_page + 1) |logical_page| {
                const slot = findDirectoryEntry(
                    directory,
                    source_id,
                    logical_page,
                ) orelse return error.SourceUnavailable;
                const entry = directory.entries[slot];
                var page_handle =
                    self.pages[slot].tryAcquire() orelse
                    return error.SourceUnavailable;
                if (page_handle.generation() !=
                    @as(?u64, entry.page_generation))
                {
                    page_handle.release();
                    return error.SourceUnavailable;
                }
                const page = page_handle.value() orelse
                    {
                        page_handle.release();
                        return error.SourceUnavailable;
                    };
                const page_start = logical_page * limits.frames_per_page;
                const page_capacity_end = std.math.add(
                    usize,
                    page_start,
                    limits.frames_per_page,
                ) catch {
                    page_handle.release();
                    return error.InvalidAudioBuffer;
                };
                const requested_page_end = @min(end, page_capacity_end);
                const page_offset = @max(start, page_start) - page_start;
                if (!pageStateValid(page, source_id, logical_page) or
                    page.channel_count != source_page.channel_count or
                    page.source_sample_count !=
                        source_page.source_sample_count or
                    page.sample_rate != source_page.sample_rate or
                    page_offset >= page.frame_count or
                    requested_page_end - page_start > page.frame_count)
                {
                    page_handle.release();
                    return error.SourceUnavailable;
                }
                page_values[acquired_count] = page;
                page_handles[acquired_count] = page_handle;
                acquired_count += 1;
            }

            var copied: usize = 0;
            for (page_values[0..acquired_count]) |page| {
                const page_offset =
                    (start + copied) % limits.frames_per_page;
                const chunk = @min(
                    count - copied,
                    page.frame_count - page_offset,
                );
                for (buffers, 0..) |destination, channel|
                    @memcpy(
                        destination[copied..][0..chunk],
                        page.samples[channel][page_offset..][0..chunk],
                    );
                copied += chunk;
            }
        }

        fn directoryHasRange(
            self: *Self,
            directory: *const Directory,
            source_id: SourceId,
            range: FrameRange,
            description: *const Description,
        ) bool {
            _ = sourceSlotIndex(source_id) catch return false;
            const end = std.math.add(
                usize,
                range.start,
                range.count,
            ) catch return false;
            const first_page =
                range.start / limits.frames_per_page;
            const last_page =
                (end - 1) / limits.frames_per_page;
            for (first_page..last_page + 1) |logical_page| {
                const slot = findDirectoryEntry(
                    directory,
                    source_id,
                    logical_page,
                ) orelse return false;
                const entry = directory.entries[slot];
                var page_handle =
                    self.pages[slot].tryAcquire() orelse
                    return false;
                defer page_handle.release();
                if (page_handle.generation() !=
                    @as(?u64, entry.page_generation))
                    return false;
                const page = page_handle.value() orelse
                    return false;
                const described_sample_count = std.math.cast(
                    usize,
                    description.source_sample_count,
                ) orelse return false;
                if (!pageStateValid(page, source_id, logical_page) or
                    description.source_sample_count <= 0 or
                    page.source_sample_count !=
                        described_sample_count or
                    page.sample_rate !=
                        description.source_sample_rate or
                    description.source_channel_count <= 0 or
                    page.channel_count !=
                        @as(
                            usize,
                            @intCast(
                                description.source_channel_count,
                            ),
                        ))
                {
                    return false;
                }
            }
            return true;
        }

        fn requiredFrameRange(
            description: *const Description,
        ) Error!FrameRange {
            if (description.source_sample_count <= 0 or
                !std.math.isFinite(
                    description.source_sample_rate,
                ) or
                description.source_sample_rate <= 0 or
                !std.math.isFinite(
                    description.start_in_modification_time,
                ) or
                !std.math.isFinite(
                    description.duration_in_modification_time,
                ) or
                description.duration_in_modification_time <= 0)
                return error.InvalidSourceFormat;
            const source_count = std.math.cast(
                usize,
                description.source_sample_count,
            ) orelse return error.InvalidSourceFormat;
            const exact_start =
                description.start_in_modification_time *
                description.source_sample_rate;
            const exact_end =
                (description.start_in_modification_time +
                    description.duration_in_modification_time) *
                description.source_sample_rate;
            if (!std.math.isFinite(exact_start) or
                !std.math.isFinite(exact_end) or
                exact_end <= exact_start)
                return error.InvalidSourceFormat;
            const padded_start = @max(0.0, @floor(exact_start) - 4.0);
            const padded_end = @min(
                @as(f64, @floatFromInt(source_count)),
                @ceil(exact_end) + 5.0,
            );
            if (padded_start >= padded_end)
                return error.InvalidSourceFormat;
            const start: usize = @intFromFloat(padded_start);
            const end: usize = @intFromFloat(padded_end);
            return .{ .start = start, .count = end - start };
        }

        fn findDirectoryEntry(
            directory: *const Directory,
            source_id: SourceId,
            logical_page: usize,
        ) ?usize {
            for (directory.entries, 0..) |entry, slot| {
                if (entry.valid and
                    entry.source_index == source_id.index and
                    entry.source_generation == source_id.generation and
                    entry.logical_page == logical_page)
                {
                    return slot;
                }
            }
            return null;
        }

        fn findSourceEntry(
            directory: *const Directory,
            source_id: SourceId,
        ) ?usize {
            for (directory.entries, 0..) |entry, slot| {
                if (entry.valid and
                    entry.source_index == source_id.index and
                    entry.source_generation == source_id.generation)
                {
                    return slot;
                }
            }
            return null;
        }

        fn selectVictim(
            directory: *const Directory,
            protected: *const [limits.page_slots]bool,
        ) ?usize {
            var selected: ?usize = null;
            for (directory.entries, 0..) |entry, slot| {
                if (protected[slot]) continue;
                if (!entry.valid) return slot;
                const replace = if (selected) |current|
                    entry.last_used <
                        directory.entries[current].last_used
                else
                    true;
                if (replace) {
                    selected = slot;
                }
            }
            return selected;
        }

        fn pageMatches(
            page: *const PageState,
            source_id: SourceId,
            logical_page: usize,
        ) bool {
            return page.valid and
                page.source_index == source_id.index and
                page.source_generation == source_id.generation and
                page.logical_page == logical_page;
        }

        fn pageStateValid(
            page: *const PageState,
            source_id: SourceId,
            logical_page: usize,
        ) bool {
            if (!pageMatches(page, source_id, logical_page) or
                page.source_sample_count == 0 or
                !std.math.isFinite(page.sample_rate) or
                page.sample_rate <= 0.0 or
                page.channel_count == 0 or
                page.channel_count > limits.channels or
                page.frame_count == 0 or
                page.frame_count > limits.frames_per_page)
                return false;
            const page_start = std.math.mul(
                usize,
                logical_page,
                limits.frames_per_page,
            ) catch return false;
            if (page_start >= page.source_sample_count)
                return false;
            return page.frame_count == @min(
                limits.frames_per_page,
                page.source_sample_count - page_start,
            );
        }

        fn sourceSlotIndex(source_id: SourceId) Error!usize {
            if (source_id.index >= limits.sources)
                return error.SourceCapacityExceeded;
            return source_id.index;
        }
    };
}

fn sampleBuffersOverlap(
    comptime Sample: type,
    buffers: []const []Sample,
) bool {
    for (buffers, 0..) |buffer, index| {
        const buffer_start = @intFromPtr(buffer.ptr);
        const buffer_bytes = std.math.mul(
            usize,
            buffer.len,
            @sizeOf(Sample),
        ) catch return true;
        const buffer_end = std.math.add(
            usize,
            buffer_start,
            buffer_bytes,
        ) catch return true;
        for (buffers[index + 1 ..]) |other| {
            const other_start = @intFromPtr(other.ptr);
            const other_bytes = std.math.mul(
                usize,
                other.len,
                @sizeOf(Sample),
            ) catch return true;
            const other_end = std.math.add(
                usize,
                other_start,
                other_bytes,
            ) catch return true;
            if (buffer_start < other_end and
                other_start < buffer_end)
                return true;
        }
    }
    return false;
}

fn validatePagedLimits(comptime limits: PagedLimits) void {
    if (limits.sources == 0 or
        limits.sources > std.math.maxInt(u16))
        @compileError(
            "ARA paged cache source capacity must be between 1 and 65535",
        );
    if (limits.channels == 0 or limits.channels > 64)
        @compileError(
            "ARA paged cache channel capacity must be between 1 and 64",
        );
    if (limits.page_slots == 0 or
        limits.page_slots > std.math.maxInt(u16))
        @compileError(
            "ARA paged cache page capacity must be between 1 and 65535",
        );
    if (limits.frames_per_page == 0 or
        limits.frames_per_page > std.math.maxInt(i64))
        @compileError(
            "ARA paged cache page size must be positive and fit i64",
        );
    if (limits.publication_slots < 3 or
        limits.publication_slots > 64)
        @compileError(
            "ARA paged cache publication slots must be between 3 and 64",
        );
    const samples_per_page = std.math.mul(
        usize,
        limits.channels,
        limits.frames_per_page,
    ) catch @compileError("ARA paged cache size overflows usize");
    const samples_per_generation = std.math.mul(
        usize,
        samples_per_page,
        limits.publication_slots,
    ) catch @compileError("ARA paged cache size overflows usize");
    _ = std.math.mul(
        usize,
        samples_per_generation,
        limits.page_slots,
    ) catch @compileError("ARA paged cache size overflows usize");
}

fn validateLimits(comptime limits: Limits) void {
    if (limits.sources == 0 or
        limits.sources > std.math.maxInt(u16))
        @compileError(
            "ARA source cache capacity must be between 1 and 65535",
        );
    if (limits.channels == 0 or limits.channels > 64)
        @compileError(
            "ARA source cache channel capacity must be between 1 and 64",
        );
    if (limits.frames_per_source == 0 or
        limits.frames_per_source > std.math.maxInt(i64))
        @compileError(
            "ARA source cache frame capacity must be positive and fit i64",
        );
    if (limits.publication_slots < 3 or
        limits.publication_slots > 64)
        @compileError(
            "ARA source cache publication slots must be between 3 and 64",
        );
    const samples_per_generation = std.math.mul(
        usize,
        limits.channels,
        limits.frames_per_source,
    ) catch @compileError("ARA source cache size overflows usize");
    _ = std.math.mul(
        usize,
        samples_per_generation,
        limits.publication_slots,
    ) catch @compileError("ARA source cache size overflows usize");
}

test "ARA source cache publishes and invalidates complete f32 sources" {
    try exerciseCache(f32);
}

test "ARA source cache publishes and invalidates complete f64 sources" {
    try exerciseCache(f64);
}

fn exerciseCache(comptime Sample: type) !void {
    const TestController = CacheTestController(Sample);
    const SourceId = TestController.SourceId;
    const TestRenderer = struct {
        pub const SourceProvider = struct {
            context: ?*anyopaque,
            ready: *const fn (
                ?*anyopaque,
                *const TestController.PlaybackRegionRenderDescription,
            ) bool,
            read: *const fn (
                ?*anyopaque,
                SourceId,
                i64,
                []const []Sample,
            ) anyerror!void,
        };
    };
    const TestCache = Cache(
        TestController,
        Sample,
        .{
            .sources = 1,
            .channels = 2,
            .frames_per_source = 4,
            .publication_slots = 3,
        },
    );

    var controller: TestController = undefined;
    controller = .{ .document = undefined };
    controller.init();
    var cache = TestCache.init();
    const source_id = SourceId{ .index = 0, .generation = 1 };
    const description =
        TestController.PlaybackRegionRenderDescription{
            .audio_source = source_id,
            .source_sample_count = 4,
            .source_sample_rate = 48_000,
            .source_channel_count = 2,
        };
    const provider = cache.provider(TestRenderer);
    try std.testing.expect(!provider.ready(
        provider.context,
        &description,
    ));
    try std.testing.expectEqual(
        @as(u64, 1),
        try cache.loadSource(&controller, source_id),
    );
    try std.testing.expect(provider.ready(
        provider.context,
        &description,
    ));
    var left: [2]Sample = @splat(0);
    var right: [2]Sample = @splat(0);
    const buffers = [_][]Sample{ &left, &right };
    try provider.read(provider.context, source_id, 1, &buffers);
    try std.testing.expectEqualSlices(
        Sample,
        &.{ 2, 3 },
        &left,
    );
    try std.testing.expectEqualSlices(
        Sample,
        &.{ 6, 7 },
        &right,
    );
    left = @splat(-5.0);
    const aliased_buffers = [_][]Sample{ &left, &left };
    try std.testing.expectError(
        error.InvalidAudioBuffer,
        provider.read(
            provider.context,
            source_id,
            1,
            &aliased_buffers,
        ),
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-5.0} ** 2),
        &left,
    );
    try std.testing.expectError(
        error.InvalidAudioBuffer,
        provider.read(
            provider.context,
            source_id,
            std.math.maxInt(i64),
            &buffers,
        ),
    );
    var oversized_description = description;
    oversized_description.source_sample_count =
        std.math.maxInt(i64);
    try std.testing.expect(!provider.ready(
        provider.context,
        &oversized_description,
    ));

    controller.source.sample_count = 5;
    try std.testing.expectError(
        error.FrameCapacityExceeded,
        cache.loadSource(&controller, source_id),
    );
    controller.source.sample_count = 4;
    controller.source.channel_count = 3;
    try std.testing.expectError(
        error.ChannelCapacityExceeded,
        cache.loadSource(&controller, source_id),
    );
    controller.source.channel_count = 2;
    controller.source.sample_rate = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidSourceFormat,
        cache.loadSource(&controller, source_id),
    );
    controller.source.sample_rate = 48_000;
    try std.testing.expect(provider.ready(
        provider.context,
        &description,
    ));

    controller.fail_reads = true;
    try std.testing.expectError(
        error.ReadFailed,
        cache.loadSource(&controller, source_id),
    );
    try std.testing.expect(provider.ready(
        provider.context,
        &description,
    ));
    try std.testing.expectEqual(
        @as(u64, 2),
        try cache.invalidate(source_id),
    );
    try std.testing.expect(!provider.ready(
        provider.context,
        &description,
    ));
    var reused_description = description;
    reused_description.audio_source.generation = 2;
    try std.testing.expect(!provider.ready(
        provider.context,
        &reused_description,
    ));

    controller.fail_reads = false;
    var hostile_cache = TestCache.init();
    _ = try hostile_cache.loadSource(&controller, source_id);
    const hostile_provider = hostile_cache.provider(TestRenderer);
    var invalid_channels =
        try hostile_cache.publishers[0].beginUpdate();
    defer invalid_channels.cancel();
    const invalid_channel_state = invalid_channels.value() orelse
        return error.MissingSourceCacheState;
    invalid_channel_state.channel_count = 3;
    _ = try invalid_channels.commit();
    var hostile_left = [_]Sample{-11.0} ** 2;
    var hostile_right = [_]Sample{-13.0} ** 2;
    var hostile_extra = [_]Sample{-17.0} ** 2;
    const hostile_channels = [_][]Sample{
        &hostile_left,
        &hostile_right,
        &hostile_extra,
    };
    try std.testing.expectError(
        error.SourceUnavailable,
        hostile_provider.read(
            hostile_provider.context,
            source_id,
            0,
            &hostile_channels,
        ),
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-11.0} ** 2),
        &hostile_left,
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-13.0} ** 2),
        &hostile_right,
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-17.0} ** 2),
        &hostile_extra,
    );

    _ = try hostile_cache.loadSource(&controller, source_id);
    var invalid_frames =
        try hostile_cache.publishers[0].beginUpdate();
    defer invalid_frames.cancel();
    const invalid_frame_state = invalid_frames.value() orelse
        return error.MissingSourceCacheState;
    invalid_frame_state.sample_count = 5;
    _ = try invalid_frames.commit();
    hostile_left = @splat(-19.0);
    hostile_right = @splat(-23.0);
    const hostile_frames = [_][]Sample{
        &hostile_left,
        &hostile_right,
    };
    try std.testing.expectError(
        error.SourceUnavailable,
        hostile_provider.read(
            hostile_provider.context,
            source_id,
            3,
            &hostile_frames,
        ),
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-19.0} ** 2),
        &hostile_left,
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-23.0} ** 2),
        &hostile_right,
    );
    try std.testing.expectEqual(
        controller.opened_readers,
        controller.closed_readers,
    );
}

test "ARA source cache readers never observe torn generations" {
    const Sample = f32;
    const TestController = CacheTestController(Sample);
    const SourceId = TestController.SourceId;
    const TestRenderer = struct {
        pub const SourceProvider = struct {
            context: ?*anyopaque,
            ready: *const fn (
                ?*anyopaque,
                *const TestController.PlaybackRegionRenderDescription,
            ) bool,
            read: *const fn (
                ?*anyopaque,
                SourceId,
                i64,
                []const []Sample,
            ) anyerror!void,
        };
    };
    const TestCache = Cache(
        TestController,
        Sample,
        .{
            .sources = 1,
            .channels = 2,
            .frames_per_source = 4,
            .publication_slots = 8,
        },
    );
    const Shared = struct {
        provider: TestRenderer.SourceProvider,
        source_id: SourceId,
        done: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        successful_reads: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),
        invalid_reads: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),

        fn read(shared: *@This()) void {
            while (!shared.done.load(.acquire)) {
                var left: [4]Sample = undefined;
                var right: [4]Sample = undefined;
                const buffers = [_][]Sample{ &left, &right };
                shared.provider.read(
                    shared.provider.context,
                    shared.source_id,
                    0,
                    &buffers,
                ) catch continue;
                const first = left[0];
                var valid = true;
                for (left) |value|
                    valid = valid and value == first;
                for (right) |value|
                    valid = valid and value == first + 100;
                if (!valid)
                    _ = shared.invalid_reads.fetchAdd(
                        1,
                        .monotonic,
                    );
                _ = shared.successful_reads.fetchAdd(
                    1,
                    .monotonic,
                );
            }
        }
    };

    var controller: TestController = .{ .document = undefined };
    controller.init();
    var cache = TestCache.init();
    const source_id = SourceId{ .index = 0, .generation = 1 };
    controller.samples = .{
        @splat(0),
        @splat(100),
    };
    _ = try cache.loadSource(&controller, source_id);
    var shared = Shared{
        .provider = cache.provider(TestRenderer),
        .source_id = source_id,
    };
    var readers: [4]std.Thread = undefined;
    for (&readers) |*reader|
        reader.* = try std.Thread.spawn(.{}, Shared.read, .{&shared});
    while (shared.successful_reads.load(.acquire) == 0)
        std.Thread.yield() catch {};
    for (1..10_001) |generation| {
        const value: Sample = @floatFromInt(generation % 97);
        controller.samples = .{
            @splat(value),
            @splat(value + 100),
        };
        _ = cache.loadSource(&controller, source_id) catch continue;
    }
    shared.done.store(true, .release);
    for (readers) |reader| reader.join();
    try std.testing.expectEqual(
        @as(u64, 0),
        shared.invalid_reads.load(.acquire),
    );
    try std.testing.expect(
        shared.successful_reads.load(.acquire) > 0,
    );
    try std.testing.expectEqual(
        controller.opened_readers,
        controller.closed_readers,
    );
}

test "ARA paged source cache loads regions evicts and rolls back" {
    const Sample = f32;
    const TestController = PagedCacheTestController(Sample);
    const SourceId = TestController.SourceId;
    const TestRenderer = struct {
        pub const SourceProvider = struct {
            context: ?*anyopaque,
            ready: *const fn (
                ?*anyopaque,
                *const TestController.PlaybackRegionRenderDescription,
            ) bool,
            read: *const fn (
                ?*anyopaque,
                SourceId,
                i64,
                []const []Sample,
            ) anyerror!void,
        };
    };
    const TestCache = PagedCache(
        TestController,
        Sample,
        .{
            .sources = 1,
            .channels = 2,
            .page_slots = 3,
            .frames_per_page = 8,
            .publication_slots = 4,
        },
    );

    var controller: TestController = .{ .document = undefined };
    controller.init();
    controller.fill(0);
    const source_id = SourceId{ .index = 0, .generation = 1 };
    const description =
        TestController.PlaybackRegionRenderDescription{
            .audio_source = source_id,
            .source_sample_count = 64,
            .source_sample_rate = 8,
            .source_channel_count = 2,
            .start_in_modification_time = 2,
            .duration_in_modification_time = 1,
        };
    var cache = TestCache.init();
    const provider = cache.provider(TestRenderer);
    try std.testing.expect(!provider.ready(
        provider.context,
        &description,
    ));
    try std.testing.expectEqual(
        @as(u64, 1),
        try cache.loadRegion(&controller, &description),
    );
    try std.testing.expect(provider.ready(
        provider.context,
        &description,
    ));
    const opened_after_fill = controller.opened_readers;
    _ = try cache.loadRegion(&controller, &description);
    try std.testing.expectEqual(
        opened_after_fill,
        controller.opened_readers,
    );

    var left: [12]Sample = undefined;
    var right: [12]Sample = undefined;
    const buffers = [_][]Sample{ &left, &right };
    try provider.read(
        provider.context,
        source_id,
        15,
        &buffers,
    );
    for (0..left.len) |index| {
        try std.testing.expectEqual(
            @as(Sample, @floatFromInt(15 + index)),
            left[index],
        );
        try std.testing.expectEqual(
            @as(Sample, @floatFromInt(115 + index)),
            right[index],
        );
    }
    var aliased_page_output = [_]Sample{-7.0} ** 12;
    const aliased_page_buffers = [_][]Sample{
        &aliased_page_output,
        &aliased_page_output,
    };
    try std.testing.expectError(
        error.InvalidAudioBuffer,
        provider.read(
            provider.context,
            source_id,
            15,
            &aliased_page_buffers,
        ),
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-7.0} ** 12),
        &aliased_page_output,
    );
    try std.testing.expectError(
        error.InvalidAudioBuffer,
        provider.read(
            provider.context,
            source_id,
            std.math.maxInt(i64),
            &buffers,
        ),
    );
    const empty = [_][]Sample{ left[0..0], right[0..0] };
    try provider.read(provider.context, source_id, 15, &empty);
    const missing_channel = [_][]Sample{left[0..0]};
    try std.testing.expectError(
        error.InvalidAudioBuffer,
        provider.read(
            provider.context,
            source_id,
            15,
            &missing_channel,
        ),
    );

    _ = try cache.loadRange(&controller, source_id, 40, 8);
    try std.testing.expect(!provider.ready(
        provider.context,
        &description,
    ));
    var incomplete_left = [_]Sample{-31.0} ** 17;
    var incomplete_right = [_]Sample{-47.0} ** 17;
    const incomplete = [_][]Sample{
        &incomplete_left,
        &incomplete_right,
    };
    try std.testing.expectError(
        error.SourceUnavailable,
        provider.read(
            provider.context,
            source_id,
            16,
            &incomplete,
        ),
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-31.0} ** 17),
        &incomplete_left,
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-47.0} ** 17),
        &incomplete_right,
    );
    var later_left: [8]Sample = undefined;
    var later_right: [8]Sample = undefined;
    const later = [_][]Sample{ &later_left, &later_right };
    try provider.read(
        provider.context,
        source_id,
        40,
        &later,
    );
    try std.testing.expectEqual(@as(Sample, 40), later_left[0]);
    try std.testing.expectEqual(@as(Sample, 147), later_right[7]);

    controller.fail_reads = true;
    try std.testing.expectError(
        error.ReadFailed,
        cache.refreshRange(&controller, source_id, 40, 8),
    );
    try provider.read(
        provider.context,
        source_id,
        40,
        &later,
    );
    try std.testing.expectEqual(@as(Sample, 40), later_left[0]);
    controller.fail_reads = false;
    controller.fill(1000);
    _ = try cache.refreshRange(&controller, source_id, 40, 8);
    try provider.read(
        provider.context,
        source_id,
        40,
        &later,
    );
    try std.testing.expectEqual(@as(Sample, 1040), later_left[0]);
    try std.testing.expectEqual(@as(Sample, 1147), later_right[7]);
    var refreshed_directory =
        cache.directory.tryAcquire() orelse
        return error.MissingSourceCacheDirectory;
    defer refreshed_directory.release();
    const refreshed_entries = refreshed_directory.value() orelse
        return error.MissingSourceCacheDirectory;
    var refreshed_page_count: usize = 0;
    for (refreshed_entries.entries) |entry| {
        if (entry.valid and
            entry.source_index == source_id.index and
            entry.source_generation == source_id.generation and
            entry.logical_page == 5)
            refreshed_page_count += 1;
    }
    try std.testing.expectEqual(
        @as(usize, 1),
        refreshed_page_count,
    );

    _ = try cache.loadRange(&controller, source_id, 16, 8);
    controller.fill(2000);
    _ = try cache.refreshRange(&controller, source_id, 16, 16);
    var refreshed_left: [16]Sample = undefined;
    var refreshed_right: [16]Sample = undefined;
    const refreshed_buffers = [_][]Sample{
        &refreshed_left,
        &refreshed_right,
    };
    try provider.read(
        provider.context,
        source_id,
        16,
        &refreshed_buffers,
    );
    for (0..refreshed_left.len) |index| {
        try std.testing.expectEqual(
            @as(Sample, @floatFromInt(2016 + index)),
            refreshed_left[index],
        );
        try std.testing.expectEqual(
            refreshed_left[index] + 100,
            refreshed_right[index],
        );
    }
    var multi_refresh_directory =
        cache.directory.tryAcquire() orelse
        return error.MissingSourceCacheDirectory;
    defer multi_refresh_directory.release();
    const multi_refresh_entries =
        multi_refresh_directory.value() orelse
        return error.MissingSourceCacheDirectory;
    var page_two_count: usize = 0;
    var page_three_count: usize = 0;
    for (multi_refresh_entries.entries) |entry| {
        if (!entry.valid or
            entry.source_index != source_id.index or
            entry.source_generation != source_id.generation)
            continue;
        if (entry.logical_page == 2)
            page_two_count += 1;
        if (entry.logical_page == 3)
            page_three_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), page_two_count);
    try std.testing.expectEqual(@as(usize, 1), page_three_count);
    try std.testing.expectError(
        error.PageCapacityExceeded,
        cache.loadRange(&controller, source_id, 0, 32),
    );

    var hostile_cache = TestCache.init();
    _ = try hostile_cache.loadRegion(&controller, &description);
    const hostile_provider = hostile_cache.provider(TestRenderer);
    var active_directory =
        hostile_cache.directory.tryAcquire() orelse
        return error.MissingSourceCacheDirectory;
    const directory = active_directory.value() orelse {
        active_directory.release();
        return error.MissingSourceCacheDirectory;
    };
    var hostile_slot: ?usize = null;
    for (directory.entries, 0..) |entry, slot| {
        if (entry.valid and
            entry.source_index == source_id.index and
            entry.source_generation == source_id.generation and
            entry.logical_page == 1)
        {
            hostile_slot = slot;
            break;
        }
    }
    active_directory.release();
    const slot = hostile_slot orelse
        return error.MissingSourceCachePage;

    var invalid_channels =
        try hostile_cache.pages[slot].beginUpdate();
    defer invalid_channels.cancel();
    const invalid_channel_page = invalid_channels.value() orelse
        return error.MissingSourceCachePage;
    invalid_channel_page.channel_count = 3;
    const invalid_channel_generation =
        try invalid_channels.commit();
    var channel_directory =
        try hostile_cache.directory.beginUpdate();
    defer channel_directory.cancel();
    const channel_entries = channel_directory.value() orelse
        return error.MissingSourceCacheDirectory;
    channel_entries.entries[slot].page_generation =
        invalid_channel_generation;
    _ = try channel_directory.commit();
    try std.testing.expect(!hostile_provider.ready(
        hostile_provider.context,
        &description,
    ));
    var hostile_left = [_]Sample{-53.0} ** 2;
    var hostile_right = [_]Sample{-59.0} ** 2;
    var hostile_extra = [_]Sample{-61.0} ** 2;
    const hostile_channels = [_][]Sample{
        &hostile_left,
        &hostile_right,
        &hostile_extra,
    };
    try std.testing.expectError(
        error.SourceUnavailable,
        hostile_provider.read(
            hostile_provider.context,
            source_id,
            15,
            &hostile_channels,
        ),
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-53.0} ** 2),
        &hostile_left,
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-59.0} ** 2),
        &hostile_right,
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-61.0} ** 2),
        &hostile_extra,
    );

    _ = try hostile_cache.refreshRegion(&controller, &description);
    var invalid_frames =
        try hostile_cache.pages[slot].beginUpdate();
    defer invalid_frames.cancel();
    const invalid_frame_page = invalid_frames.value() orelse
        return error.MissingSourceCachePage;
    invalid_frame_page.frame_count = 9;
    const invalid_frame_generation = try invalid_frames.commit();
    var frame_directory =
        try hostile_cache.directory.beginUpdate();
    defer frame_directory.cancel();
    const frame_entries = frame_directory.value() orelse
        return error.MissingSourceCacheDirectory;
    frame_entries.entries[slot].page_generation =
        invalid_frame_generation;
    _ = try frame_directory.commit();
    try std.testing.expect(!hostile_provider.ready(
        hostile_provider.context,
        &description,
    ));
    hostile_left = @splat(-67.0);
    hostile_right = @splat(-71.0);
    const hostile_frames = [_][]Sample{
        &hostile_left,
        &hostile_right,
    };
    try std.testing.expectError(
        error.SourceUnavailable,
        hostile_provider.read(
            hostile_provider.context,
            source_id,
            15,
            &hostile_frames,
        ),
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-67.0} ** 2),
        &hostile_left,
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{-71.0} ** 2),
        &hostile_right,
    );

    _ = try cache.invalidate(source_id);
    try std.testing.expectError(
        error.SourceUnavailable,
        provider.read(
            provider.context,
            source_id,
            40,
            &later,
        ),
    );
    try std.testing.expectEqual(
        controller.opened_readers,
        controller.closed_readers,
    );
}

test "ARA paged source cache readers never observe mixed pages" {
    const Sample = f32;
    const TestController = PagedCacheTestController(Sample);
    const SourceId = TestController.SourceId;
    const TestRenderer = struct {
        pub const SourceProvider = struct {
            context: ?*anyopaque,
            ready: *const fn (
                ?*anyopaque,
                *const TestController.PlaybackRegionRenderDescription,
            ) bool,
            read: *const fn (
                ?*anyopaque,
                SourceId,
                i64,
                []const []Sample,
            ) anyerror!void,
        };
    };
    const TestCache = PagedCache(
        TestController,
        Sample,
        .{
            .sources = 1,
            .channels = 2,
            .page_slots = 3,
            .frames_per_page = 8,
            .publication_slots = 8,
        },
    );
    const Shared = struct {
        provider: TestRenderer.SourceProvider,
        source_id: SourceId,
        done: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        successful_reads: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),
        mixed_reads: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),

        fn read(shared: *@This()) void {
            while (!shared.done.load(.acquire)) {
                var left: [12]Sample = undefined;
                var right: [12]Sample = undefined;
                const buffers = [_][]Sample{ &left, &right };
                shared.provider.read(
                    shared.provider.context,
                    shared.source_id,
                    15,
                    &buffers,
                ) catch continue;
                const base = left[0] - 15;
                var valid = true;
                for (0..left.len) |index| {
                    valid = valid and
                        left[index] ==
                            base +
                                @as(
                                    Sample,
                                    @floatFromInt(15 + index),
                                ) and
                        right[index] == left[index] + 100;
                }
                if (!valid)
                    _ = shared.mixed_reads.fetchAdd(
                        1,
                        .monotonic,
                    );
                _ = shared.successful_reads.fetchAdd(
                    1,
                    .monotonic,
                );
            }
        }
    };

    var controller: TestController = .{ .document = undefined };
    controller.init();
    controller.fill(0);
    const source_id = SourceId{ .index = 0, .generation = 1 };
    const description =
        TestController.PlaybackRegionRenderDescription{
            .audio_source = source_id,
            .source_sample_count = 64,
            .source_sample_rate = 8,
            .source_channel_count = 2,
            .start_in_modification_time = 2,
            .duration_in_modification_time = 1,
        };
    var cache = TestCache.init();
    _ = try cache.loadRegion(&controller, &description);
    var shared = Shared{
        .provider = cache.provider(TestRenderer),
        .source_id = source_id,
    };
    var readers: [4]std.Thread = undefined;
    for (&readers) |*reader|
        reader.* = try std.Thread.spawn(.{}, Shared.read, .{&shared});
    while (shared.successful_reads.load(.acquire) == 0)
        std.Thread.yield() catch {};
    for (1..2001) |generation| {
        controller.fill(@floatFromInt(generation * 1000));
        _ = cache.refreshRegion(
            &controller,
            &description,
        ) catch continue;
    }
    shared.done.store(true, .release);
    for (readers) |reader| reader.join();
    try std.testing.expectEqual(
        @as(u64, 0),
        shared.mixed_reads.load(.acquire),
    );
    try std.testing.expect(
        shared.successful_reads.load(.acquire) > 0,
    );
    try std.testing.expectEqual(
        controller.opened_readers,
        controller.closed_readers,
    );
}

fn PagedCacheTestController(comptime Sample: type) type {
    return struct {
        const Self = @This();

        pub const SourceId = struct {
            index: u16,
            generation: u32,
        };
        const Source = struct {
            sample_count: i64 = 64,
            sample_rate: f64 = 8,
            channel_count: i32 = 2,
        };
        pub const PlaybackRegionRenderDescription = struct {
            audio_source: SourceId,
            source_sample_count: i64,
            source_sample_rate: f64,
            source_channel_count: i32,
            start_in_modification_time: f64,
            duration_in_modification_time: f64,
        };
        const AudioReader = struct {
            owner: *Self,
            closed: bool = false,

            fn readF32(
                self: *@This(),
                position: i64,
                buffers: []const []f32,
            ) !void {
                if (Sample != f32) return error.InvalidAudioBuffer;
                try self.owner.read(f32, position, buffers);
            }

            fn readF64(
                self: *@This(),
                position: i64,
                buffers: []const []f64,
            ) !void {
                if (Sample != f64) return error.InvalidAudioBuffer;
                try self.owner.read(f64, position, buffers);
            }

            fn close(self: *@This()) void {
                if (self.closed) return;
                self.closed = true;
                self.owner.closed_readers += 1;
            }
        };
        const Document = struct {
            owner: *Self,

            fn audioSource(
                self: *const @This(),
                source_id: SourceId,
            ) ?*const Source {
                if (source_id.index != 0 or
                    source_id.generation != 1)
                    return null;
                return &self.owner.source;
            }
        };

        document: Document,
        source: Source = .{},
        samples: [2][64]Sample = @splat(@splat(0)),
        fail_reads: bool = false,
        opened_readers: usize = 0,
        closed_readers: usize = 0,

        fn init(self: *Self) void {
            self.document = .{ .owner = self };
        }

        fn fill(self: *Self, base: Sample) void {
            for (0..self.samples[0].len) |index| {
                self.samples[0][index] =
                    base + @as(Sample, @floatFromInt(index));
                self.samples[1][index] =
                    self.samples[0][index] + 100;
            }
        }

        fn openAudioReader(
            self: *Self,
            _: SourceId,
            use_64_bit_samples: bool,
        ) !AudioReader {
            if (use_64_bit_samples != (Sample == f64))
                return error.InvalidAudioBuffer;
            self.opened_readers += 1;
            return .{ .owner = self };
        }

        fn read(
            self: *Self,
            comptime ReadSample: type,
            position: i64,
            buffers: []const []ReadSample,
        ) !void {
            if (self.fail_reads) return error.ReadFailed;
            if (position < 0 or buffers.len != 2)
                return error.InvalidAudioBuffer;
            const start: usize = @intCast(position);
            const count = buffers[0].len;
            if (start > self.samples[0].len or
                count > self.samples[0].len - start or
                buffers[1].len != count)
                return error.InvalidAudioBuffer;
            for (buffers, 0..) |destination, channel|
                @memcpy(
                    destination,
                    self.samples[channel][start..][0..count],
                );
        }
    };
}

fn CacheTestController(comptime Sample: type) type {
    return struct {
        const Self = @This();

        pub const SourceId = struct {
            index: u16,
            generation: u32,
        };
        const Source = struct {
            sample_count: i64,
            sample_rate: f64,
            channel_count: i32,
        };
        pub const PlaybackRegionRenderDescription = struct {
            audio_source: SourceId,
            source_sample_count: i64,
            source_sample_rate: f64,
            source_channel_count: i32,
        };
        const AudioReader = struct {
            owner: *Self,
            closed: bool = false,

            fn readF32(
                self: *@This(),
                position: i64,
                buffers: []const []f32,
            ) !void {
                if (Sample != f32) return error.InvalidAudioBuffer;
                try self.owner.read(f32, position, buffers);
            }

            fn readF64(
                self: *@This(),
                position: i64,
                buffers: []const []f64,
            ) !void {
                if (Sample != f64) return error.InvalidAudioBuffer;
                try self.owner.read(f64, position, buffers);
            }

            fn close(self: *@This()) void {
                if (self.closed) return;
                self.closed = true;
                self.owner.closed_readers += 1;
            }
        };
        const Document = struct {
            owner: *Self,

            fn audioSource(
                self: *const @This(),
                source_id: SourceId,
            ) ?*const Source {
                if (source_id.index != 0 or
                    source_id.generation != 1)
                    return null;
                return &self.owner.source;
            }
        };

        document: Document,
        source: Source = .{
            .sample_count = 4,
            .sample_rate = 48_000,
            .channel_count = 2,
        },
        samples: [2][4]Sample = .{
            .{ 1, 2, 3, 4 },
            .{ 5, 6, 7, 8 },
        },
        fail_reads: bool = false,
        opened_readers: usize = 0,
        closed_readers: usize = 0,

        fn init(self: *Self) void {
            self.document = .{ .owner = self };
        }

        fn openAudioReader(
            self: *Self,
            _: SourceId,
            use_64_bit_samples: bool,
        ) !AudioReader {
            if (use_64_bit_samples != (Sample == f64))
                return error.InvalidAudioBuffer;
            self.opened_readers += 1;
            return .{ .owner = self };
        }

        fn read(
            self: *Self,
            comptime ReadSample: type,
            position: i64,
            buffers: []const []ReadSample,
        ) !void {
            if (self.fail_reads) return error.ReadFailed;
            if (position != 0 or buffers.len != 2)
                return error.InvalidAudioBuffer;
            for (buffers, 0..) |destination, channel|
                @memcpy(destination, &self.samples[channel]);
        }
    };
}
