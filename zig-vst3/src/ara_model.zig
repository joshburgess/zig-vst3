const std = @import("std");

pub const Limits = struct {
    musical_contexts: usize = 16,
    region_sequences: usize = 32,
    audio_sources: usize = 32,
    audio_modifications: usize = 64,
    playback_regions: usize = 128,
    audio_readers: usize = 64,
    content_readers: usize = 32,
    model_observers: usize = 16,
    name_bytes: usize = 127,
    persistent_id_bytes: usize = 127,
    archive_extension_bytes: usize = 0,
};

pub const Color = struct {
    red: f32,
    green: f32,
    blue: f32,

    pub fn valid(self: Color) bool {
        return componentValid(self.red) and
            componentValid(self.green) and
            componentValid(self.blue);
    }

    fn componentValid(value: f32) bool {
        return std.math.isFinite(value) and
            value >= 0.0 and value <= 1.0;
    }
};

pub const PlaybackTransformation = packed struct(u8) {
    time_stretch: bool = false,
    reflect_tempo: bool = false,
    fade_tail: bool = false,
    fade_head: bool = false,
    _: u4 = 0,

    pub fn valid(self: PlaybackTransformation) bool {
        return !self.reflect_tempo or self.time_stretch;
    }
};

pub const Error = error{
    NotEditing,
    AlreadyEditing,
    CapacityExceeded,
    InvalidHandle,
    ObjectInUse,
    NameTooLong,
    PersistentIdTooLong,
    EmptyPersistentId,
    DuplicatePersistentId,
    InvalidOrder,
    InvalidColor,
    InvalidSampleCount,
    InvalidSampleRate,
    InvalidChannelCount,
    SamplesAccessEnabled,
    InvalidPlaybackRange,
    InvalidTransformation,
};

const ObjectKind = enum {
    musical_context,
    region_sequence,
    audio_source,
    audio_modification,
    playback_region,
};

fn Handle(comptime kind: ObjectKind) type {
    return struct {
        index: u16,
        generation: u32,

        pub const object_kind = kind;
    };
}

fn BoundedBytes(
    comptime capacity: usize,
    comptime too_long: Error,
) type {
    if (capacity == 0 or capacity > std.math.maxInt(u16))
        @compileError(
            "ARA text capacities must be between 1 and 65535 bytes",
        );
    return struct {
        bytes: [capacity]u8 = @splat(0),
        len: u16 = 0,

        pub fn init(value: []const u8) Error!@This() {
            if (value.len > capacity) return too_long;
            var result = @This(){};
            @memcpy(result.bytes[0..value.len], value);
            result.len = @intCast(value.len);
            return result;
        }

        pub fn slice(self: *const @This()) []const u8 {
            return self.bytes[0..self.len];
        }

        pub fn eql(self: *const @This(), value: []const u8) bool {
            return std.mem.eql(u8, self.slice(), value);
        }
    };
}

fn Slot(comptime T: type) type {
    return struct {
        generation: u32 = 1,
        value: ?T = null,
    };
}

pub fn Document(comptime limits: Limits) type {
    validateLimits(limits);
    const Name = BoundedBytes(limits.name_bytes, error.NameTooLong);
    const PersistentId = BoundedBytes(
        limits.persistent_id_bytes,
        error.PersistentIdTooLong,
    );

    return struct {
        const Self = @This();

        pub const MusicalContextId = Handle(.musical_context);
        pub const RegionSequenceId = Handle(.region_sequence);
        pub const AudioSourceId = Handle(.audio_source);
        pub const AudioModificationId = Handle(.audio_modification);
        pub const PlaybackRegionId = Handle(.playback_region);
        pub const audio_source_capacity = limits.audio_sources;
        pub const audio_modification_capacity =
            limits.audio_modifications;

        pub const MusicalContextProperties = struct {
            name: []const u8,
            order_index: i32,
            color: ?Color = null,
        };

        pub const RegionSequenceProperties = struct {
            name: []const u8,
            order_index: i32,
            musical_context: MusicalContextId,
            color: ?Color = null,
        };

        pub const AudioSourceProperties = struct {
            name: []const u8,
            persistent_id: []const u8,
            sample_count: i64,
            sample_rate: f64,
            channel_count: i32,
            merits_64_bit_samples: bool = false,
        };

        pub const AudioModificationProperties = struct {
            name: []const u8,
            persistent_id: []const u8,
        };

        pub const PlaybackRegionProperties = struct {
            name: []const u8,
            region_sequence: RegionSequenceId,
            transformation: PlaybackTransformation = .{},
            start_in_modification_time: f64,
            duration_in_modification_time: f64,
            start_in_playback_time: f64,
            duration_in_playback_time: f64,
            color: ?Color = null,
        };

        pub const MusicalContext = struct {
            host_ref: ?*anyopaque,
            name: Name,
            order_index: i32,
            color: ?Color,
        };

        pub const RegionSequence = struct {
            host_ref: ?*anyopaque,
            name: Name,
            order_index: i32,
            musical_context: MusicalContextId,
            color: ?Color,
        };

        pub const AudioSource = struct {
            host_ref: ?*anyopaque,
            name: Name,
            persistent_id: PersistentId,
            sample_count: i64,
            sample_rate: f64,
            channel_count: i32,
            merits_64_bit_samples: bool,
            samples_access_enabled: bool = false,
            inactive_for_undo: bool = false,
        };

        pub const AudioModification = struct {
            host_ref: ?*anyopaque,
            audio_source: AudioSourceId,
            name: Name,
            persistent_id: PersistentId,
            inactive_for_undo: bool = false,
        };

        pub const PlaybackRegion = struct {
            host_ref: ?*anyopaque,
            audio_modification: AudioModificationId,
            name: Name,
            region_sequence: RegionSequenceId,
            transformation: PlaybackTransformation,
            start_in_modification_time: f64,
            duration_in_modification_time: f64,
            start_in_playback_time: f64,
            duration_in_playback_time: f64,
            color: ?Color,
        };

        musical_contexts: [limits.musical_contexts]Slot(MusicalContext) =
            @splat(.{}),
        region_sequences: [limits.region_sequences]Slot(RegionSequence) =
            @splat(.{}),
        audio_sources: [limits.audio_sources]Slot(AudioSource) =
            @splat(.{}),
        audio_modifications: [limits.audio_modifications]Slot(AudioModification) =
            @splat(.{}),
        playback_regions: [limits.playback_regions]Slot(PlaybackRegion) =
            @splat(.{}),
        editing: bool = false,
        changed: bool = false,
        revision: u64 = 0,

        pub fn beginEditing(self: *Self) Error!void {
            if (self.editing) return error.AlreadyEditing;
            self.editing = true;
            self.changed = false;
        }

        pub fn endEditing(self: *Self) Error!bool {
            if (!self.editing) return error.NotEditing;
            self.editing = false;
            const did_change = self.changed;
            if (did_change) self.revision +|= 1;
            self.changed = false;
            return did_change;
        }

        pub fn currentRevision(self: *const Self) u64 {
            return self.revision;
        }

        pub fn isEditing(self: *const Self) bool {
            return self.editing;
        }

        pub fn audioSourceIdAt(
            self: *const Self,
            slot_index: usize,
        ) ?AudioSourceId {
            if (slot_index >= self.audio_sources.len) return null;
            const slot = &self.audio_sources[slot_index];
            if (slot.value == null) return null;
            return idFor(
                AudioSourceId,
                slot_index,
                slot.generation,
            );
        }

        pub fn audioModificationIdAt(
            self: *const Self,
            slot_index: usize,
        ) ?AudioModificationId {
            if (slot_index >= self.audio_modifications.len)
                return null;
            const slot = &self.audio_modifications[slot_index];
            if (slot.value == null) return null;
            return idFor(
                AudioModificationId,
                slot_index,
                slot.generation,
            );
        }

        pub fn findAudioSourceByPersistentId(
            self: *const Self,
            persistent_id: []const u8,
        ) ?AudioSourceId {
            for (&self.audio_sources, 0..) |*slot, slot_index| {
                const source = slot.value orelse continue;
                if (source.persistent_id.eql(persistent_id))
                    return idFor(
                        AudioSourceId,
                        slot_index,
                        slot.generation,
                    );
            }
            return null;
        }

        pub fn findAudioModificationByPersistentId(
            self: *const Self,
            persistent_id: []const u8,
        ) ?AudioModificationId {
            for (
                &self.audio_modifications,
                0..,
            ) |*slot, slot_index| {
                const modification = slot.value orelse continue;
                if (modification.persistent_id.eql(persistent_id))
                    return idFor(
                        AudioModificationId,
                        slot_index,
                        slot.generation,
                    );
            }
            return null;
        }

        pub fn createMusicalContext(
            self: *Self,
            host_ref: ?*anyopaque,
            properties: MusicalContextProperties,
        ) Error!MusicalContextId {
            try self.requireEditing();
            var value = try makeMusicalContext(properties);
            value.host_ref = host_ref;
            const index = vacantIndex(&self.musical_contexts) orelse
                return error.CapacityExceeded;
            self.musical_contexts[index].value = value;
            self.changed = true;
            return idFor(
                MusicalContextId,
                index,
                self.musical_contexts[index].generation,
            );
        }

        pub fn updateMusicalContext(
            self: *Self,
            id: MusicalContextId,
            properties: MusicalContextProperties,
        ) Error!void {
            try self.requireEditing();
            const current = self.musicalContextMut(id) orelse
                return error.InvalidHandle;
            var replacement = try makeMusicalContext(properties);
            replacement.host_ref = current.host_ref;
            if (musicalContextsEqual(current, &replacement)) return;
            current.* = replacement;
            self.changed = true;
        }

        pub fn destroyMusicalContext(
            self: *Self,
            id: MusicalContextId,
        ) Error!void {
            try self.requireEditing();
            _ = self.musicalContext(id) orelse
                return error.InvalidHandle;
            for (&self.region_sequences) |*slot| {
                if (slot.value) |sequence| {
                    if (sameId(sequence.musical_context, id))
                        return error.ObjectInUse;
                }
            }
            destroySlot(
                &self.musical_contexts[id.index],
            );
            self.changed = true;
        }

        pub fn createRegionSequence(
            self: *Self,
            host_ref: ?*anyopaque,
            properties: RegionSequenceProperties,
        ) Error!RegionSequenceId {
            try self.requireEditing();
            _ = self.musicalContext(properties.musical_context) orelse
                return error.InvalidHandle;
            var value = try makeRegionSequence(properties);
            value.host_ref = host_ref;
            const index = vacantIndex(&self.region_sequences) orelse
                return error.CapacityExceeded;
            self.region_sequences[index].value = value;
            self.changed = true;
            return idFor(
                RegionSequenceId,
                index,
                self.region_sequences[index].generation,
            );
        }

        pub fn updateRegionSequence(
            self: *Self,
            id: RegionSequenceId,
            properties: RegionSequenceProperties,
        ) Error!void {
            try self.requireEditing();
            _ = self.musicalContext(properties.musical_context) orelse
                return error.InvalidHandle;
            const current = self.regionSequenceMut(id) orelse
                return error.InvalidHandle;
            var replacement = try makeRegionSequence(properties);
            replacement.host_ref = current.host_ref;
            if (regionSequencesEqual(current, &replacement)) return;
            current.* = replacement;
            self.changed = true;
        }

        pub fn destroyRegionSequence(
            self: *Self,
            id: RegionSequenceId,
        ) Error!void {
            try self.requireEditing();
            _ = self.regionSequence(id) orelse
                return error.InvalidHandle;
            for (&self.playback_regions) |*slot| {
                if (slot.value) |region| {
                    if (sameId(region.region_sequence, id))
                        return error.ObjectInUse;
                }
            }
            destroySlot(&self.region_sequences[id.index]);
            self.changed = true;
        }

        pub fn createAudioSource(
            self: *Self,
            host_ref: ?*anyopaque,
            properties: AudioSourceProperties,
        ) Error!AudioSourceId {
            try self.requireEditing();
            try self.ensureUniqueSourceId(
                null,
                properties.persistent_id,
            );
            var value = try makeAudioSource(properties);
            value.host_ref = host_ref;
            const index = vacantIndex(&self.audio_sources) orelse
                return error.CapacityExceeded;
            self.audio_sources[index].value = value;
            self.changed = true;
            return idFor(
                AudioSourceId,
                index,
                self.audio_sources[index].generation,
            );
        }

        pub fn updateAudioSource(
            self: *Self,
            id: AudioSourceId,
            properties: AudioSourceProperties,
        ) Error!void {
            try self.requireEditing();
            const current = self.audioSourceMut(id) orelse
                return error.InvalidHandle;
            var replacement = try makeAudioSource(properties);
            const format_changed =
                replacement.sample_count != current.sample_count or
                replacement.sample_rate != current.sample_rate or
                replacement.channel_count != current.channel_count;
            if (format_changed and current.samples_access_enabled)
                return error.SamplesAccessEnabled;
            try self.ensureUniqueSourceId(
                id,
                properties.persistent_id,
            );
            replacement.host_ref = current.host_ref;
            replacement.samples_access_enabled =
                current.samples_access_enabled;
            replacement.inactive_for_undo =
                current.inactive_for_undo;
            if (audioSourcesEqual(current, &replacement)) return;
            current.* = replacement;
            self.changed = true;
        }

        pub fn enableAudioSourceSamplesAccess(
            self: *Self,
            id: AudioSourceId,
            enabled: bool,
        ) Error!void {
            const source = self.audioSourceMut(id) orelse
                return error.InvalidHandle;
            if (source.samples_access_enabled == enabled) return;
            source.samples_access_enabled = enabled;
        }

        pub fn deactivateAudioSourceForUndoHistory(
            self: *Self,
            id: AudioSourceId,
            inactive: bool,
        ) Error!void {
            try self.requireEditing();
            const source = self.audioSourceMut(id) orelse
                return error.InvalidHandle;
            if (source.inactive_for_undo == inactive) return;
            source.inactive_for_undo = inactive;
            self.changed = true;
        }

        pub fn destroyAudioSource(
            self: *Self,
            id: AudioSourceId,
        ) Error!void {
            try self.requireEditing();
            const source = self.audioSource(id) orelse
                return error.InvalidHandle;
            if (source.samples_access_enabled)
                return error.SamplesAccessEnabled;
            for (&self.audio_modifications) |*slot| {
                if (slot.value) |modification| {
                    if (sameId(modification.audio_source, id))
                        return error.ObjectInUse;
                }
            }
            destroySlot(&self.audio_sources[id.index]);
            self.changed = true;
        }

        pub fn createAudioModification(
            self: *Self,
            audio_source: AudioSourceId,
            host_ref: ?*anyopaque,
            properties: AudioModificationProperties,
        ) Error!AudioModificationId {
            try self.requireEditing();
            _ = self.audioSource(audio_source) orelse
                return error.InvalidHandle;
            try self.ensureUniqueModificationId(
                null,
                properties.persistent_id,
            );
            var value = try makeAudioModification(
                audio_source,
                properties,
            );
            value.host_ref = host_ref;
            const index =
                vacantIndex(&self.audio_modifications) orelse
                return error.CapacityExceeded;
            self.audio_modifications[index].value = value;
            self.changed = true;
            return idFor(
                AudioModificationId,
                index,
                self.audio_modifications[index].generation,
            );
        }

        pub fn updateAudioModification(
            self: *Self,
            id: AudioModificationId,
            properties: AudioModificationProperties,
        ) Error!void {
            try self.requireEditing();
            const current = self.audioModificationMut(id) orelse
                return error.InvalidHandle;
            try self.ensureUniqueModificationId(
                id,
                properties.persistent_id,
            );
            var replacement = try makeAudioModification(
                current.audio_source,
                properties,
            );
            replacement.host_ref = current.host_ref;
            replacement.inactive_for_undo =
                current.inactive_for_undo;
            if (audioModificationsEqual(current, &replacement))
                return;
            current.* = replacement;
            self.changed = true;
        }

        pub fn deactivateAudioModificationForUndoHistory(
            self: *Self,
            id: AudioModificationId,
            inactive: bool,
        ) Error!void {
            try self.requireEditing();
            const modification = self.audioModificationMut(id) orelse
                return error.InvalidHandle;
            if (modification.inactive_for_undo == inactive) return;
            modification.inactive_for_undo = inactive;
            self.changed = true;
        }

        pub fn destroyAudioModification(
            self: *Self,
            id: AudioModificationId,
        ) Error!void {
            try self.requireEditing();
            _ = self.audioModification(id) orelse
                return error.InvalidHandle;
            for (&self.playback_regions) |*slot| {
                if (slot.value) |region| {
                    if (sameId(region.audio_modification, id))
                        return error.ObjectInUse;
                }
            }
            destroySlot(&self.audio_modifications[id.index]);
            self.changed = true;
        }

        pub fn createPlaybackRegion(
            self: *Self,
            audio_modification: AudioModificationId,
            host_ref: ?*anyopaque,
            properties: PlaybackRegionProperties,
        ) Error!PlaybackRegionId {
            try self.requireEditing();
            _ = self.audioModification(audio_modification) orelse
                return error.InvalidHandle;
            _ = self.regionSequence(properties.region_sequence) orelse
                return error.InvalidHandle;
            var value = try makePlaybackRegion(
                audio_modification,
                properties,
            );
            value.host_ref = host_ref;
            const index = vacantIndex(&self.playback_regions) orelse
                return error.CapacityExceeded;
            self.playback_regions[index].value = value;
            self.changed = true;
            return idFor(
                PlaybackRegionId,
                index,
                self.playback_regions[index].generation,
            );
        }

        pub fn updatePlaybackRegion(
            self: *Self,
            id: PlaybackRegionId,
            properties: PlaybackRegionProperties,
        ) Error!void {
            try self.requireEditing();
            _ = self.regionSequence(properties.region_sequence) orelse
                return error.InvalidHandle;
            const current = self.playbackRegionMut(id) orelse
                return error.InvalidHandle;
            var replacement = try makePlaybackRegion(
                current.audio_modification,
                properties,
            );
            replacement.host_ref = current.host_ref;
            if (playbackRegionsEqual(current, &replacement)) return;
            current.* = replacement;
            self.changed = true;
        }

        pub fn destroyPlaybackRegion(
            self: *Self,
            id: PlaybackRegionId,
        ) Error!void {
            try self.requireEditing();
            _ = self.playbackRegion(id) orelse
                return error.InvalidHandle;
            destroySlot(&self.playback_regions[id.index]);
            self.changed = true;
        }

        pub fn musicalContext(
            self: *const Self,
            id: MusicalContextId,
        ) ?*const MusicalContext {
            if (id.index >= self.musical_contexts.len) return null;
            const slot = &self.musical_contexts[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        pub fn regionSequence(
            self: *const Self,
            id: RegionSequenceId,
        ) ?*const RegionSequence {
            if (id.index >= self.region_sequences.len) return null;
            const slot = &self.region_sequences[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        pub fn audioSource(
            self: *const Self,
            id: AudioSourceId,
        ) ?*const AudioSource {
            if (id.index >= self.audio_sources.len) return null;
            const slot = &self.audio_sources[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        pub fn audioModification(
            self: *const Self,
            id: AudioModificationId,
        ) ?*const AudioModification {
            if (id.index >= self.audio_modifications.len)
                return null;
            const slot = &self.audio_modifications[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        pub fn playbackRegion(
            self: *const Self,
            id: PlaybackRegionId,
        ) ?*const PlaybackRegion {
            if (id.index >= self.playback_regions.len) return null;
            const slot = &self.playback_regions[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        fn musicalContextMut(
            self: *Self,
            id: MusicalContextId,
        ) ?*MusicalContext {
            if (id.index >= self.musical_contexts.len) return null;
            const slot = &self.musical_contexts[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        fn regionSequenceMut(
            self: *Self,
            id: RegionSequenceId,
        ) ?*RegionSequence {
            if (id.index >= self.region_sequences.len) return null;
            const slot = &self.region_sequences[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        fn audioSourceMut(
            self: *Self,
            id: AudioSourceId,
        ) ?*AudioSource {
            if (id.index >= self.audio_sources.len) return null;
            const slot = &self.audio_sources[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        fn audioModificationMut(
            self: *Self,
            id: AudioModificationId,
        ) ?*AudioModification {
            if (id.index >= self.audio_modifications.len)
                return null;
            const slot = &self.audio_modifications[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        fn playbackRegionMut(
            self: *Self,
            id: PlaybackRegionId,
        ) ?*PlaybackRegion {
            if (id.index >= self.playback_regions.len) return null;
            const slot = &self.playback_regions[id.index];
            if (slot.generation != id.generation) return null;
            return if (slot.value) |*value| value else null;
        }

        fn requireEditing(self: *const Self) Error!void {
            if (!self.editing) return error.NotEditing;
        }

        fn ensureUniqueSourceId(
            self: *const Self,
            excluded: ?AudioSourceId,
            persistent_id: []const u8,
        ) Error!void {
            if (persistent_id.len == 0)
                return error.EmptyPersistentId;
            for (&self.audio_sources, 0..) |*slot, index| {
                if (slot.value) |source| {
                    if (excluded) |id| {
                        if (id.index == index and
                            id.generation == slot.generation)
                            continue;
                    }
                    if (source.persistent_id.eql(persistent_id))
                        return error.DuplicatePersistentId;
                }
            }
        }

        fn ensureUniqueModificationId(
            self: *const Self,
            excluded: ?AudioModificationId,
            persistent_id: []const u8,
        ) Error!void {
            if (persistent_id.len == 0)
                return error.EmptyPersistentId;
            for (
                &self.audio_modifications,
                0..,
            ) |*slot, index| {
                if (slot.value) |modification| {
                    if (excluded) |id| {
                        if (id.index == index and
                            id.generation == slot.generation)
                            continue;
                    }
                    if (modification.persistent_id.eql(persistent_id))
                        return error.DuplicatePersistentId;
                }
            }
        }

        fn makeMusicalContext(
            properties: MusicalContextProperties,
        ) Error!MusicalContext {
            try validateOrder(properties.order_index);
            try validateColor(properties.color);
            return .{
                .host_ref = null,
                .name = try Name.init(properties.name),
                .order_index = properties.order_index,
                .color = properties.color,
            };
        }

        fn makeRegionSequence(
            properties: RegionSequenceProperties,
        ) Error!RegionSequence {
            try validateOrder(properties.order_index);
            try validateColor(properties.color);
            return .{
                .host_ref = null,
                .name = try Name.init(properties.name),
                .order_index = properties.order_index,
                .musical_context = properties.musical_context,
                .color = properties.color,
            };
        }

        fn makeAudioSource(
            properties: AudioSourceProperties,
        ) Error!AudioSource {
            if (properties.sample_count < 0)
                return error.InvalidSampleCount;
            if (!std.math.isFinite(properties.sample_rate) or
                properties.sample_rate <= 0.0)
                return error.InvalidSampleRate;
            if (properties.channel_count <= 0)
                return error.InvalidChannelCount;
            return .{
                .host_ref = null,
                .name = try Name.init(properties.name),
                .persistent_id = try PersistentId.init(
                    properties.persistent_id,
                ),
                .sample_count = properties.sample_count,
                .sample_rate = properties.sample_rate,
                .channel_count = properties.channel_count,
                .merits_64_bit_samples = properties.merits_64_bit_samples,
            };
        }

        fn makeAudioModification(
            audio_source: AudioSourceId,
            properties: AudioModificationProperties,
        ) Error!AudioModification {
            return .{
                .host_ref = null,
                .audio_source = audio_source,
                .name = try Name.init(properties.name),
                .persistent_id = try PersistentId.init(
                    properties.persistent_id,
                ),
            };
        }

        fn makePlaybackRegion(
            audio_modification: AudioModificationId,
            properties: PlaybackRegionProperties,
        ) Error!PlaybackRegion {
            try validateColor(properties.color);
            if (!properties.transformation.valid())
                return error.InvalidTransformation;
            const values = [_]f64{
                properties.start_in_modification_time,
                properties.duration_in_modification_time,
                properties.start_in_playback_time,
                properties.duration_in_playback_time,
            };
            for (values) |value| {
                if (!std.math.isFinite(value))
                    return error.InvalidPlaybackRange;
            }
            if (properties.duration_in_modification_time < 0.0 or
                properties.duration_in_playback_time < 0.0)
                return error.InvalidPlaybackRange;
            if (!properties.transformation.time_stretch and
                properties.duration_in_modification_time !=
                    properties.duration_in_playback_time)
                return error.InvalidPlaybackRange;
            return .{
                .host_ref = null,
                .audio_modification = audio_modification,
                .name = try Name.init(properties.name),
                .region_sequence = properties.region_sequence,
                .transformation = properties.transformation,
                .start_in_modification_time = properties.start_in_modification_time,
                .duration_in_modification_time = properties.duration_in_modification_time,
                .start_in_playback_time = properties.start_in_playback_time,
                .duration_in_playback_time = properties.duration_in_playback_time,
                .color = properties.color,
            };
        }

        fn musicalContextsEqual(
            first: *const MusicalContext,
            second: *const MusicalContext,
        ) bool {
            return first.host_ref == second.host_ref and
                std.mem.eql(u8, first.name.slice(), second.name.slice()) and
                first.order_index == second.order_index and
                colorsEqual(first.color, second.color);
        }

        fn regionSequencesEqual(
            first: *const RegionSequence,
            second: *const RegionSequence,
        ) bool {
            return first.host_ref == second.host_ref and
                std.mem.eql(u8, first.name.slice(), second.name.slice()) and
                first.order_index == second.order_index and
                sameId(first.musical_context, second.musical_context) and
                colorsEqual(first.color, second.color);
        }

        fn audioSourcesEqual(
            first: *const AudioSource,
            second: *const AudioSource,
        ) bool {
            return first.host_ref == second.host_ref and
                std.mem.eql(u8, first.name.slice(), second.name.slice()) and
                std.mem.eql(
                    u8,
                    first.persistent_id.slice(),
                    second.persistent_id.slice(),
                ) and
                first.sample_count == second.sample_count and
                first.sample_rate == second.sample_rate and
                first.channel_count == second.channel_count and
                first.merits_64_bit_samples ==
                    second.merits_64_bit_samples and
                first.samples_access_enabled ==
                    second.samples_access_enabled and
                first.inactive_for_undo == second.inactive_for_undo;
        }

        fn audioModificationsEqual(
            first: *const AudioModification,
            second: *const AudioModification,
        ) bool {
            return first.host_ref == second.host_ref and
                sameId(first.audio_source, second.audio_source) and
                std.mem.eql(u8, first.name.slice(), second.name.slice()) and
                std.mem.eql(
                    u8,
                    first.persistent_id.slice(),
                    second.persistent_id.slice(),
                ) and
                first.inactive_for_undo == second.inactive_for_undo;
        }

        fn playbackRegionsEqual(
            first: *const PlaybackRegion,
            second: *const PlaybackRegion,
        ) bool {
            return first.host_ref == second.host_ref and
                sameId(
                    first.audio_modification,
                    second.audio_modification,
                ) and
                std.mem.eql(u8, first.name.slice(), second.name.slice()) and
                sameId(first.region_sequence, second.region_sequence) and
                @as(u8, @bitCast(first.transformation)) ==
                    @as(u8, @bitCast(second.transformation)) and
                first.start_in_modification_time ==
                    second.start_in_modification_time and
                first.duration_in_modification_time ==
                    second.duration_in_modification_time and
                first.start_in_playback_time ==
                    second.start_in_playback_time and
                first.duration_in_playback_time ==
                    second.duration_in_playback_time and
                colorsEqual(first.color, second.color);
        }
    };
}

fn validateLimits(comptime limits: Limits) void {
    inline for (.{
        limits.musical_contexts,
        limits.region_sequences,
        limits.audio_sources,
        limits.audio_modifications,
        limits.playback_regions,
        limits.audio_readers,
        limits.content_readers,
        limits.model_observers,
    }) |capacity| {
        if (capacity == 0 or capacity > std.math.maxInt(u16))
            @compileError(
                "ARA object capacities must be between 1 and 65535",
            );
    }
}

fn validateOrder(order_index: i32) Error!void {
    if (order_index < 0) return error.InvalidOrder;
}

fn validateColor(color: ?Color) Error!void {
    if (color) |value| {
        if (!value.valid()) return error.InvalidColor;
    }
}

fn colorsEqual(first: ?Color, second: ?Color) bool {
    const first_value = first orelse return second == null;
    const second_value = second orelse return false;
    return first_value.red == second_value.red and
        first_value.green == second_value.green and
        first_value.blue == second_value.blue;
}

fn vacantIndex(slots: anytype) ?usize {
    for (slots, 0..) |*slot, index| {
        if (slot.value == null) return index;
    }
    return null;
}

fn idFor(
    comptime Id: type,
    index: usize,
    generation: u32,
) Id {
    return .{
        .index = @intCast(index),
        .generation = generation,
    };
}

fn sameId(first: anytype, second: @TypeOf(first)) bool {
    return first.index == second.index and
        first.generation == second.generation;
}

fn destroySlot(slot: anytype) void {
    slot.value = null;
    slot.generation +%= 1;
    if (slot.generation == 0) slot.generation = 1;
}

test "ARA document enforces graph ownership and stale handles" {
    const Model = Document(.{
        .musical_contexts = 1,
        .region_sequences = 1,
        .audio_sources = 1,
        .audio_modifications = 1,
        .playback_regions = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    });
    var model = Model{};
    try std.testing.expectError(
        error.NotEditing,
        model.createMusicalContext(null, .{
            .name = "Song",
            .order_index = 0,
        }),
    );
    try model.beginEditing();
    const context = try model.createMusicalContext(
        @ptrFromInt(0x1000),
        .{ .name = "Song", .order_index = 0 },
    );
    const sequence = try model.createRegionSequence(
        @ptrFromInt(0x2000),
        .{
            .name = "Lead",
            .order_index = 0,
            .musical_context = context,
        },
    );
    const source = try model.createAudioSource(
        @ptrFromInt(0x3000),
        .{
            .name = "Take",
            .persistent_id = "source-1",
            .sample_count = 96_000,
            .sample_rate = 48_000.0,
            .channel_count = 2,
        },
    );
    const modification = try model.createAudioModification(
        source,
        @ptrFromInt(0x4000),
        .{
            .name = "Tuned",
            .persistent_id = "modification-1",
        },
    );
    const region = try model.createPlaybackRegion(
        modification,
        @ptrFromInt(0x5000),
        .{
            .name = "Verse",
            .region_sequence = sequence,
            .start_in_modification_time = 0.0,
            .duration_in_modification_time = 2.0,
            .start_in_playback_time = 4.0,
            .duration_in_playback_time = 2.0,
        },
    );
    try std.testing.expectError(
        error.ObjectInUse,
        model.destroyAudioSource(source),
    );
    try std.testing.expectError(
        error.ObjectInUse,
        model.destroyMusicalContext(context),
    );
    try model.destroyPlaybackRegion(region);
    try model.destroyAudioModification(modification);
    try model.destroyAudioSource(source);
    try model.destroyRegionSequence(sequence);
    try model.destroyMusicalContext(context);
    try std.testing.expect(try model.endEditing());
    try std.testing.expectEqual(@as(u64, 1), model.currentRevision());
    try std.testing.expect(model.audioSource(source) == null);

    try model.beginEditing();
    const replacement = try model.createAudioSource(null, .{
        .name = "Replacement",
        .persistent_id = "source-2",
        .sample_count = 1,
        .sample_rate = 44_100.0,
        .channel_count = 1,
    });
    try std.testing.expectEqual(source.index, replacement.index);
    try std.testing.expect(source.generation != replacement.generation);
    try std.testing.expect(try model.endEditing());
}

test "ARA document validates atomic source updates and capacity" {
    const Model = Document(.{
        .musical_contexts = 1,
        .region_sequences = 1,
        .audio_sources = 1,
        .audio_modifications = 1,
        .playback_regions = 1,
        .name_bytes = 8,
        .persistent_id_bytes = 8,
    });
    var model = Model{};
    try model.beginEditing();
    const source = try model.createAudioSource(null, .{
        .name = "Take",
        .persistent_id = "source",
        .sample_count = 8,
        .sample_rate = 48_000.0,
        .channel_count = 1,
    });
    try std.testing.expectError(
        error.CapacityExceeded,
        model.createAudioSource(null, .{
            .name = "Other",
            .persistent_id = "other",
            .sample_count = 8,
            .sample_rate = 48_000.0,
            .channel_count = 1,
        }),
    );
    try model.enableAudioSourceSamplesAccess(source, true);
    try std.testing.expectError(
        error.SamplesAccessEnabled,
        model.updateAudioSource(source, .{
            .name = "Take",
            .persistent_id = "source",
            .sample_count = 16,
            .sample_rate = 48_000.0,
            .channel_count = 1,
        }),
    );
    try std.testing.expectEqual(
        @as(i64, 8),
        model.audioSource(source).?.sample_count,
    );
    try std.testing.expectError(
        error.SamplesAccessEnabled,
        model.destroyAudioSource(source),
    );
    try model.enableAudioSourceSamplesAccess(source, false);
    try model.updateAudioSource(source, .{
        .name = "Retake",
        .persistent_id = "source",
        .sample_count = 16,
        .sample_rate = 48_000.0,
        .channel_count = 2,
    });
    try std.testing.expectEqual(
        @as(i32, 2),
        model.audioSource(source).?.channel_count,
    );
    try std.testing.expect(try model.endEditing());

    try model.beginEditing();
    try model.updateAudioSource(source, .{
        .name = "Retake",
        .persistent_id = "source",
        .sample_count = 16,
        .sample_rate = 48_000.0,
        .channel_count = 2,
    });
    try std.testing.expect(!(try model.endEditing()));
    try std.testing.expectEqual(@as(u64, 1), model.currentRevision());
}

test "ARA document rejects malformed playback and no-op revisions" {
    const Model = Document(.{});
    var model = Model{};
    try model.beginEditing();
    try std.testing.expect(!(try model.endEditing()));
    try std.testing.expectEqual(@as(u64, 0), model.currentRevision());

    try model.beginEditing();
    const context = try model.createMusicalContext(null, .{
        .name = "Song",
        .order_index = 0,
    });
    const sequence = try model.createRegionSequence(null, .{
        .name = "Track",
        .order_index = 0,
        .musical_context = context,
    });
    const source = try model.createAudioSource(null, .{
        .name = "Take",
        .persistent_id = "source",
        .sample_count = 1,
        .sample_rate = 48_000.0,
        .channel_count = 1,
    });
    const modification = try model.createAudioModification(
        source,
        null,
        .{
            .name = "Edit",
            .persistent_id = "modification",
        },
    );
    try std.testing.expectError(
        error.InvalidPlaybackRange,
        model.createPlaybackRegion(modification, null, .{
            .name = "Bad",
            .region_sequence = sequence,
            .start_in_modification_time = 0.0,
            .duration_in_modification_time = 1.0,
            .start_in_playback_time = 0.0,
            .duration_in_playback_time = 2.0,
        }),
    );
    try std.testing.expectError(
        error.InvalidTransformation,
        model.createPlaybackRegion(modification, null, .{
            .name = "Bad",
            .region_sequence = sequence,
            .transformation = .{ .reflect_tempo = true },
            .start_in_modification_time = 0.0,
            .duration_in_modification_time = 1.0,
            .start_in_playback_time = 0.0,
            .duration_in_playback_time = 1.0,
        }),
    );
    try std.testing.expect(try model.endEditing());
}
