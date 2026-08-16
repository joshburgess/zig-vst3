const std = @import("std");
const ara = @import("zig-vst3-ara");
const plug_core = @import("zig-vst3-plugin-core");
const ara_document_controller =
    @import("ara_document_controller.zig");
const ara_extension = @import("ara_extension.zig");
const ara_source_cache = @import("ara_source_cache.zig");
const ara_vst3 = @import("ara_vst3.zig");

pub const raw = ara.raw;

pub const Interpolation = enum {
    linear,
    cubic_catmull_rom,
    windowed_sinc_8,
};

pub const FadeCurve = enum {
    linear,
    smoothstep,
    equal_power,
};

pub const FadeDescription = struct {
    head_duration: f64 = 0.0,
    tail_duration: f64 = 0.0,
    curve: FadeCurve = .smoothstep,

    pub fn valid(
        self: FadeDescription,
        region_duration: f64,
    ) bool {
        return std.math.isFinite(region_duration) and
            region_duration > 0.0 and
            std.math.isFinite(self.head_duration) and
            std.math.isFinite(self.tail_duration) and
            self.head_duration >= 0.0 and
            self.tail_duration >= 0.0 and
            self.head_duration <= region_duration and
            self.tail_duration <= region_duration and
            self.head_duration + self.tail_duration <=
                region_duration;
    }
};

pub const TempoWarpPoint = struct {
    playback_time: f64,
    modification_time: f64,
};

const windowed_sinc_taps: usize = 8;
const windowed_sinc_phase_count: usize = 1024;
const windowed_sinc_offsets =
    [_]i64{ -3, -2, -1, 0, 1, 2, 3, 4 };
const windowed_sinc_weights = makeWindowedSincWeights();

pub const Limits = struct {
    regions: usize = 64,
    channels: usize = 8,
    maximum_block_frames: usize = 2048,
    maximum_source_frames_per_region: usize = 4096,
    maximum_tempo_warp_points: usize = 64,
    interpolation: Interpolation = .linear,
};

pub const Error = error{
    NotInitialized,
    AlreadyBound,
    InvalidSampleType,
    InvalidSampleRate,
    InvalidOutputBuffers,
    InvalidSourceFormat,
    SourceUnavailable,
    FadeAnalysisUnavailable,
    TempoMapUnavailable,
    UnsupportedTransformation,
    SourceReadTooLarge,
    RenderPlanUnavailable,
};

pub fn Renderer(
    comptime ControllerType: type,
    comptime Sample: type,
    comptime limits: Limits,
) type {
    validateLimits(limits);
    if (Sample != f32 and Sample != f64)
        @compileError("ARA playback rendering supports f32 or f64");

    const ExtensionType = ara_extension.Extension(.{
        .playback_regions = limits.regions,
        .editor_regions = limits.regions,
        .selected_regions = limits.regions,
    });
    const ExtensionState = ara_extension.State(.{
        .playback_regions = limits.regions,
        .editor_regions = limits.regions,
        .selected_regions = limits.regions,
    });
    const Description =
        ControllerType.PlaybackRegionRenderDescription;
    const empty_description: Description = std.mem.zeroes(Description);
    const empty_tempo_warp_point = TempoWarpPoint{
        .playback_time = 0.0,
        .modification_time = 0.0,
    };

    return struct {
        const Self = @This();

        pub const SourceProvider = struct {
            context: ?*anyopaque = null,
            /// Runs on the ARA model thread before a plan is published.
            ready: *const fn (
                ?*anyopaque,
                *const Description,
            ) bool,
            /// Runs on the render thread and must not allocate, lock,
            /// perform I/O, or block.
            read: *const fn (
                ?*anyopaque,
                @FieldType(Description, "audio_source"),
                i64,
                []const []Sample,
            ) anyerror!void,
            /// Runs on the ARA model thread for regions that request
            /// content-based fades.
            fade_context: ?*anyopaque = null,
            fades: ?*const fn (
                ?*anyopaque,
                *const Description,
            ) ?FadeDescription = null,
            /// Runs on the ARA model thread before a plan is
            /// published. Returns the number of initialized points.
            tempo_warp_context: ?*anyopaque = null,
            tempo_warp: ?*const fn (
                ?*anyopaque,
                *const Description,
                []TempoWarpPoint,
            ) ?usize = null,
        };

        const Region = struct {
            description: Description = empty_description,
            fades: FadeDescription = .{},
            tempo_warp: [limits.maximum_tempo_warp_points]TempoWarpPoint =
                @splat(empty_tempo_warp_point),
            tempo_warp_count: usize = 0,
        };

        const Plan = struct {
            regions: [limits.regions]Region = @splat(.{}),
            region_count: usize = 0,
            model_revision: u64 = 0,
            assignment_revision: u64 = 0,
        };

        const PlanPublisher =
            plug_core.dsp.RealtimeSnapshotPublisher(Plan);

        pub const EntryPoint = ara_vst3.PlugInEntryPoint(
            BindConfig,
        );

        extension: ExtensionType = ExtensionType.init(.{}),
        controller: ?*ControllerType = null,
        observer_id: ?ControllerType.ModelObserverId = null,
        source_provider: SourceProvider,
        plan_publisher: PlanPublisher =
            PlanPublisher.init(.{}),
        scratch: [limits.channels][limits.maximum_source_frames_per_region]Sample =
            undefined,
        retained_error: ?anyerror = null,
        render_failures: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),
        initialized: bool = false,
        bound: bool = false,

        pub fn init(source_provider: SourceProvider) Self {
            return .{
                .source_provider = source_provider,
            };
        }

        pub fn initializeInPlace(self: *Self) void {
            self.extension.publication_sink = .{
                .context = self,
                .changed = assignmentsChanged,
            };
            self.initialized = true;
        }

        pub fn deinit(self: *Self) void {
            if (self.controller) |controller| {
                if (self.observer_id) |observer_id|
                    controller.removeModelPublicationSink(
                        observer_id,
                    );
            }
            self.observer_id = null;
            self.controller = null;
            self.bound = false;
        }

        pub fn takeError(self: *Self) ?anyerror {
            const retained = self.retained_error;
            self.retained_error = null;
            return retained;
        }

        pub fn renderFailureCount(self: *const Self) u64 {
            return self.render_failures.load(.acquire);
        }

        /// Republishes after the provider's cache readiness changes.
        pub fn refreshSourceState(self: *Self) void {
            self.rebuildOrSilence();
        }

        pub fn render(
            self: *Self,
            block_start_time: f64,
            sample_rate: f64,
            outputs: []const []Sample,
        ) anyerror!void {
            validateOutputs(sample_rate, outputs) catch |failure| {
                clearOutputs(outputs);
                _ = self.render_failures.fetchAdd(1, .monotonic);
                return failure;
            };
            self.renderPlan(
                block_start_time,
                sample_rate,
                outputs,
            ) catch |failure| {
                clearOutputs(outputs);
                _ = self.render_failures.fetchAdd(1, .monotonic);
                return failure;
            };
        }

        fn bind(
            self: *Self,
            document: *ara_vst3.DocumentController,
            known_roles: ara_vst3.RoleFlags,
            assigned_roles: ara_vst3.RoleFlags,
        ) anyerror!*const raw.ARAPlugInExtensionInstance {
            if (!self.initialized) return error.NotInitialized;
            if (self.bound) return error.AlreadyBound;
            const controller =
                try ControllerType.fromDocumentControllerRef(
                    @ptrCast(document),
                );
            const observer_id =
                try controller.addModelPublicationSink(.{
                    .context = self,
                    .changed = modelChanged,
                });
            errdefer controller.removeModelPublicationSink(observer_id);
            const instance = try self.extension.bind(
                @ptrCast(document),
                known_roles,
                assigned_roles,
            );
            self.controller = controller;
            self.observer_id = observer_id;
            self.bound = true;
            self.rebuildOrSilence();
            return instance;
        }

        fn rebuildOrSilence(self: *Self) void {
            self.rebuild() catch |failure| {
                self.retain(failure);
                _ = self.plan_publisher.publish(.{}) catch {};
            };
        }

        fn rebuild(self: *Self) anyerror!void {
            const controller = self.controller orelse
                return error.NotInitialized;
            const assignments = self.extension.snapshot();
            var plan = Plan{
                .model_revision = controller.document.currentRevision(),
                .assignment_revision = assignments.revision,
            };
            for (assignments.playback_regions[0..assignments.playback_region_count]) |region_ref| {
                if (plan.region_count == plan.regions.len)
                    return error.CapacityExceeded;
                const description =
                    try controller.playbackRegionRenderDescription(
                        region_ref,
                    );
                if (!renderDescriptionValid(
                    &description,
                    limits.channels,
                ))
                    return error.InvalidSourceFormat;
                if (!self.source_provider.ready(
                    self.source_provider.context,
                    &description,
                ))
                    return error.SourceUnavailable;
                const fades = try self.fadeDescription(
                    &description,
                );
                var planned_region = Region{
                    .description = description,
                    .fades = fades,
                };
                if (description.transformation.reflect_tempo)
                    planned_region.tempo_warp_count =
                        try self.tempoWarp(
                            &description,
                            &planned_region.tempo_warp,
                        );
                plan.regions[plan.region_count] =
                    planned_region;
                plan.region_count += 1;
            }
            _ = try self.plan_publisher.publish(plan);
        }

        fn fadeDescription(
            self: *const Self,
            description: *const Description,
        ) Error!FadeDescription {
            const needs_head =
                description.transformation.fade_head;
            const needs_tail =
                description.transformation.fade_tail;
            if (!needs_head and !needs_tail) return .{};
            const callback = self.source_provider.fades orelse
                return error.FadeAnalysisUnavailable;
            var fades = callback(
                self.source_provider.fade_context,
                description,
            ) orelse return error.FadeAnalysisUnavailable;
            if (!needs_head) fades.head_duration = 0.0;
            if (!needs_tail) fades.tail_duration = 0.0;
            if (!fades.valid(
                description.duration_in_playback_time,
            ) or
                (needs_head and fades.head_duration == 0.0) or
                (needs_tail and fades.tail_duration == 0.0))
                return error.FadeAnalysisUnavailable;
            return fades;
        }

        fn tempoWarp(
            self: *const Self,
            description: *const Description,
            output: []TempoWarpPoint,
        ) Error!usize {
            const callback =
                self.source_provider.tempo_warp orelse
                return error.TempoMapUnavailable;
            const count = callback(
                self.source_provider.tempo_warp_context,
                description,
                output,
            ) orelse return error.TempoMapUnavailable;
            if (count < 2 or count > output.len)
                return error.TempoMapUnavailable;
            const points = output[0..count];
            const playback_start =
                description.start_in_playback_time;
            const playback_end = playback_start +
                description.duration_in_playback_time;
            const modification_start =
                description.start_in_modification_time;
            const modification_end = modification_start +
                description.duration_in_modification_time;
            if (!approximatelyEqual(
                points[0].playback_time,
                playback_start,
            ) or
                !approximatelyEqual(
                    points[count - 1].playback_time,
                    playback_end,
                ))
                return error.TempoMapUnavailable;
            for (points, 0..) |point, index| {
                if (!std.math.isFinite(point.playback_time) or
                    !std.math.isFinite(
                        point.modification_time,
                    ) or
                    point.modification_time <
                        modification_start or
                    point.modification_time >
                        modification_end)
                    return error.TempoMapUnavailable;
                if (index == 0) continue;
                if (point.playback_time <=
                    points[index - 1].playback_time or
                    point.modification_time <=
                        points[index - 1].modification_time)
                    return error.TempoMapUnavailable;
            }
            return count;
        }

        fn renderPlan(
            self: *Self,
            block_start_time: f64,
            sample_rate: f64,
            outputs: []const []Sample,
        ) anyerror!void {
            if (!std.math.isFinite(block_start_time))
                return error.InvalidSampleRate;
            clearOutputs(outputs);
            const snapshot = self.plan_publisher.tryRead() orelse
                return error.RenderPlanUnavailable;
            for (snapshot.value.regions[0..snapshot.value.region_count]) |*region|
                try self.renderRegion(
                    region,
                    block_start_time,
                    sample_rate,
                    outputs,
                );
        }

        fn renderRegion(
            self: *Self,
            region: *const Region,
            block_start_time: f64,
            sample_rate: f64,
            outputs: []const []Sample,
        ) anyerror!void {
            const description = region.description;
            const block_frames = outputs[0].len;
            const block_end_time =
                block_start_time +
                @as(f64, @floatFromInt(block_frames)) /
                    sample_rate;
            const region_start =
                description.start_in_playback_time;
            const region_end =
                region_start +
                description.duration_in_playback_time;
            const overlap_start = @max(block_start_time, region_start);
            const overlap_end = @min(block_end_time, region_end);
            if (overlap_end <= overlap_start) return;

            const first_output = boundedSampleIndexAtOrAfter(
                overlap_start - block_start_time,
                sample_rate,
                block_frames,
            );
            const end_output = boundedSampleIndexAtOrAfter(
                overlap_end - block_start_time,
                sample_rate,
                block_frames,
            );
            if (end_output <= first_output) return;

            const time_ratio =
                description.duration_in_modification_time /
                description.duration_in_playback_time;
            if (region.tempo_warp_count == 0 and
                (!std.math.isFinite(time_ratio) or
                    time_ratio <= 0))
                return error.InvalidSourceFormat;
            const first_source_position = sourcePosition(
                region,
                block_start_time,
                sample_rate,
                first_output,
                time_ratio,
            );
            const last_source_position = sourcePosition(
                region,
                block_start_time,
                sample_rate,
                end_output - 1,
                time_ratio,
            );
            const maximum_source_position =
                @as(f64, @floatFromInt(
                    description.source_sample_count - 1,
                ));
            const bounded_first =
                std.math.clamp(
                    first_source_position,
                    0.0,
                    maximum_source_position,
                );
            const bounded_last =
                std.math.clamp(
                    last_source_position,
                    0.0,
                    maximum_source_position,
                );
            const first_floor: i64 =
                @intFromFloat(@floor(@min(
                    bounded_first,
                    bounded_last,
                )));
            const last_floor: i64 =
                @intFromFloat(@floor(@max(
                    bounded_first,
                    bounded_last,
                )));
            const read_start = switch (limits.interpolation) {
                .linear => first_floor,
                .cubic_catmull_rom => @max(0, first_floor - 1),
                .windowed_sinc_8 => @max(0, first_floor - 3),
            };
            const read_padding = switch (limits.interpolation) {
                .linear => @as(i64, 2),
                .cubic_catmull_rom => @as(i64, 3),
                .windowed_sinc_8 => @as(i64, 5),
            };
            const padded_read_end = std.math.add(
                i64,
                last_floor,
                read_padding,
            ) catch std.math.maxInt(i64);
            const read_end = @min(
                description.source_sample_count,
                padded_read_end,
            );
            const frame_count: usize =
                @intCast(read_end - read_start);
            if (frame_count == 0) return;
            if (frame_count >
                limits.maximum_source_frames_per_region)
                return error.SourceReadTooLarge;

            const source_channels: usize =
                @intCast(description.source_channel_count);
            var source_buffers: [limits.channels][]Sample =
                undefined;
            for (0..source_channels) |channel|
                source_buffers[channel] =
                    self.scratch[channel][0..frame_count];
            try self.source_provider.read(
                self.source_provider.context,
                description.audio_source,
                read_start,
                source_buffers[0..source_channels],
            );

            const mixed_channels = @min(
                outputs.len,
                source_channels,
            );
            for (first_output..end_output) |output_index| {
                const position = sourcePosition(
                    region,
                    block_start_time,
                    sample_rate,
                    output_index,
                    time_ratio,
                );
                if (position < 0.0 or
                    position > maximum_source_position)
                    continue;
                const local = position -
                    @as(f64, @floatFromInt(read_start));
                const first_index: usize =
                    @intFromFloat(@floor(local));
                const fraction: Sample =
                    @floatCast(local -
                        @as(f64, @floatFromInt(first_index)));
                const playback_time =
                    block_start_time +
                    @as(f64, @floatFromInt(output_index)) /
                        sample_rate;
                const fade_gain: Sample = @floatCast(
                    regionFadeGain(
                        region.fades,
                        playback_time - region_start,
                        description.duration_in_playback_time,
                    ),
                );
                for (0..mixed_channels) |channel|
                    outputs[channel][output_index] +=
                        fade_gain * interpolate(
                            Sample,
                            limits.interpolation,
                            source_buffers[channel],
                            first_index,
                            fraction,
                        );
            }
        }

        fn validateOutputs(
            sample_rate: f64,
            outputs: []const []Sample,
        ) Error!void {
            if (!std.math.isFinite(sample_rate) or sample_rate <= 0)
                return error.InvalidSampleRate;
            if (outputs.len == 0 or outputs.len > limits.channels)
                return error.InvalidOutputBuffers;
            const frames = outputs[0].len;
            if (frames > limits.maximum_block_frames)
                return error.InvalidOutputBuffers;
            for (outputs) |output| {
                if (output.len != frames)
                    return error.InvalidOutputBuffers;
            }
            for (outputs, 0..) |output, index| {
                for (outputs[index + 1 ..]) |other| {
                    if (slicesOverlap(output, other))
                        return error.InvalidOutputBuffers;
                }
            }
        }

        fn slicesOverlap(left: []Sample, right: []Sample) bool {
            const left_start = @intFromPtr(left.ptr);
            const right_start = @intFromPtr(right.ptr);
            const left_bytes = std.math.mul(
                usize,
                left.len,
                @sizeOf(Sample),
            ) catch return true;
            const right_bytes = std.math.mul(
                usize,
                right.len,
                @sizeOf(Sample),
            ) catch return true;
            const left_end = std.math.add(
                usize,
                left_start,
                left_bytes,
            ) catch return true;
            const right_end = std.math.add(
                usize,
                right_start,
                right_bytes,
            ) catch return true;
            return left_start < right_end and
                right_start < left_end;
        }

        fn sourcePosition(
            region: *const Region,
            block_start_time: f64,
            sample_rate: f64,
            output_index: usize,
            time_ratio: f64,
        ) f64 {
            const playback_time =
                block_start_time +
                @as(f64, @floatFromInt(output_index)) /
                    sample_rate;
            const description = region.description;
            const modification_time =
                if (region.tempo_warp_count == 0)
                    description.start_in_modification_time +
                        (playback_time -
                            description.start_in_playback_time) *
                            time_ratio
                else
                    warpedModificationTime(
                        region.tempo_warp[0..region.tempo_warp_count],
                        playback_time,
                    );
            return modification_time *
                description.source_sample_rate;
        }

        fn clearOutputs(outputs: []const []Sample) void {
            for (outputs) |output| @memset(output, 0);
        }

        fn retain(self: *Self, failure: anyerror) void {
            if (self.retained_error == null)
                self.retained_error = failure;
        }

        fn assignmentsChanged(
            context: ?*anyopaque,
            _: *const ExtensionState,
        ) void {
            const self: *Self =
                @ptrCast(@alignCast(context orelse return));
            self.rebuildOrSilence();
        }

        fn modelChanged(
            context: ?*anyopaque,
            _: *ControllerType,
            _: u64,
        ) void {
            const self: *Self =
                @ptrCast(@alignCast(context orelse return));
            self.rebuildOrSilence();
        }

        const BindConfig = struct {
            pub fn bind(
                entry: anytype,
                document: *ara_vst3.DocumentController,
                known_roles: ara_vst3.RoleFlags,
                assigned_roles: ara_vst3.RoleFlags,
            ) ?*const ara_vst3.PlugInExtensionInstance {
                const context = entry.context orelse return null;
                const self: *Self =
                    @ptrCast(@alignCast(context));
                const effective_known_roles =
                    if (known_roles == ara_vst3.no_roles and
                    assigned_roles == ara_vst3.all_roles)
                        ara_vst3.all_roles
                    else
                        known_roles;
                const instance = self.bind(
                    document,
                    effective_known_roles,
                    assigned_roles,
                ) catch |failure| {
                    self.retain(failure);
                    return null;
                };
                return @ptrCast(instance);
            }
        };
    };
}

fn renderDescriptionValid(
    description: anytype,
    maximum_channels: usize,
) bool {
    const source_channels = std.math.cast(
        usize,
        description.source_channel_count,
    ) orelse return false;
    const source_sample_rate: f64 = description.source_sample_rate;
    if (source_channels == 0 or
        source_channels > maximum_channels or
        description.source_sample_count <= 0 or
        !std.math.isFinite(source_sample_rate) or
        source_sample_rate <= 0)
        return false;
    const times = [_]f64{
        description.start_in_modification_time,
        description.duration_in_modification_time,
        description.start_in_playback_time,
        description.duration_in_playback_time,
    };
    for (times) |time| {
        if (!std.math.isFinite(time)) return false;
    }
    if (description.duration_in_modification_time < 0 or
        description.duration_in_playback_time < 0)
        return false;
    const modification_end =
        description.start_in_modification_time +
        description.duration_in_modification_time;
    const playback_end =
        description.start_in_playback_time +
        description.duration_in_playback_time;
    return std.math.isFinite(modification_end) and
        std.math.isFinite(playback_end) and
        std.math.isFinite(
            description.start_in_modification_time *
                description.source_sample_rate,
        ) and
        std.math.isFinite(
            modification_end * description.source_sample_rate,
        );
}

fn boundedSampleIndexAtOrAfter(
    relative_time: f64,
    sample_rate: f64,
    maximum: usize,
) usize {
    const exact = @ceil(relative_time * sample_rate);
    if (!std.math.isFinite(exact))
        return if (exact > 0.0) maximum else 0;
    if (exact <= 0.0) return 0;
    const maximum_float: f64 = @floatFromInt(maximum);
    if (exact >= maximum_float) return maximum;
    return @intFromFloat(exact);
}

test "ARA playback sample indices contain non-finite products" {
    try std.testing.expectEqual(
        @as(usize, 0),
        boundedSampleIndexAtOrAfter(std.math.nan(f64), 48_000.0, 64),
    );
    try std.testing.expectEqual(
        @as(usize, 64),
        boundedSampleIndexAtOrAfter(std.math.inf(f64), 48_000.0, 64),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        boundedSampleIndexAtOrAfter(-std.math.inf(f64), 48_000.0, 64),
    );
    try std.testing.expectEqual(
        @as(usize, 64),
        boundedSampleIndexAtOrAfter(std.math.floatMax(f64), 48_000.0, 64),
    );

    const overflowing_description = .{
        .source_channel_count = @as(i32, 2),
        .source_sample_count = @as(i64, 64),
        .source_sample_rate = 48_000.0,
        .start_in_modification_time = std.math.floatMax(f64),
        .duration_in_modification_time = std.math.floatMax(f64),
        .start_in_playback_time = std.math.floatMax(f64),
        .duration_in_playback_time = std.math.floatMax(f64),
    };
    try std.testing.expect(!renderDescriptionValid(
        &overflowing_description,
        2,
    ));
}

fn interpolate(
    comptime Sample: type,
    comptime mode: Interpolation,
    source: []const Sample,
    first_index: usize,
    fraction: Sample,
) Sample {
    const last_index = source.len - 1;
    const second_index = @min(first_index + 1, last_index);
    if (mode == .linear) {
        const first = source[first_index];
        const second = source[second_index];
        return first + (second - first) * fraction;
    }
    if (mode == .windowed_sinc_8) {
        var weighted_sum: f64 = 0.0;
        const fraction_f64 = std.math.clamp(
            @as(f64, @floatCast(fraction)),
            0.0,
            1.0,
        );
        const scaled_phase =
            fraction_f64 *
            @as(f64, @floatFromInt(windowed_sinc_phase_count));
        const phase_index: usize = @intFromFloat(
            @min(
                @floor(scaled_phase + 0.5),
                @as(
                    f64,
                    @floatFromInt(windowed_sinc_phase_count),
                ),
            ),
        );
        const first_signed: i64 = @intCast(first_index);
        const last_signed: i64 = @intCast(last_index);
        inline for (
            windowed_sinc_offsets,
            windowed_sinc_weights[phase_index],
        ) |offset, weight| {
            const source_index: usize = @intCast(
                std.math.clamp(
                    first_signed + offset,
                    0,
                    last_signed,
                ),
            );
            weighted_sum +=
                @as(f64, @floatCast(source[source_index])) *
                weight;
        }
        return @floatCast(weighted_sum);
    }

    const previous_index =
        if (first_index == 0) first_index else first_index - 1;
    const fourth_index = @min(first_index + 2, last_index);
    const previous = source[previous_index];
    const first = source[first_index];
    const second = source[second_index];
    const fourth = source[fourth_index];
    const squared = fraction * fraction;
    const cubed = squared * fraction;
    return @as(Sample, 0.5) *
        ((@as(Sample, 2) * first) +
            (-previous + second) * fraction +
            (@as(Sample, 2) * previous -
                @as(Sample, 5) * first +
                @as(Sample, 4) * second -
                fourth) *
                squared +
            (-previous +
                @as(Sample, 3) * first -
                @as(Sample, 3) * second +
                fourth) *
                cubed);
}

fn regionFadeGain(
    fades: FadeDescription,
    relative_time: f64,
    region_duration: f64,
) f64 {
    var gain: f64 = 1.0;
    if (fades.head_duration > 0.0) {
        gain *= fadeCurveGain(
            fades.curve,
            std.math.clamp(
                relative_time / fades.head_duration,
                0.0,
                1.0,
            ),
        );
    }
    if (fades.tail_duration > 0.0) {
        gain *= fadeCurveGain(
            fades.curve,
            std.math.clamp(
                (region_duration - relative_time) /
                    fades.tail_duration,
                0.0,
                1.0,
            ),
        );
    }
    return gain;
}

fn fadeCurveGain(curve: FadeCurve, progress: f64) f64 {
    return switch (curve) {
        .linear => progress,
        .smoothstep => progress * progress *
            (3.0 - 2.0 * progress),
        .equal_power => @sin(progress * std.math.pi * 0.5),
    };
}

fn warpedModificationTime(
    points: []const TempoWarpPoint,
    playback_time: f64,
) f64 {
    if (playback_time <= points[0].playback_time)
        return points[0].modification_time;
    if (playback_time >= points[points.len - 1].playback_time)
        return points[points.len - 1].modification_time;
    var left: usize = 0;
    var right = points.len - 1;
    while (right - left > 1) {
        const middle = left + (right - left) / 2;
        if (playback_time < points[middle].playback_time)
            right = middle
        else
            left = middle;
    }
    const first = points[left];
    const second = points[right];
    const progress =
        (playback_time - first.playback_time) /
        (second.playback_time - first.playback_time);
    return first.modification_time +
        progress *
            (second.modification_time -
                first.modification_time);
}

fn approximatelyEqual(first: f64, second: f64) bool {
    const scale = @max(
        @as(f64, 1.0),
        @max(@abs(first), @abs(second)),
    );
    return @abs(first - second) <=
        32.0 * std.math.floatEps(f64) * scale;
}

test "ARA fade descriptors validate bounds and curves reach exact endpoints" {
    try std.testing.expect(
        (FadeDescription{
            .head_duration = 0.25,
            .tail_duration = 0.5,
        }).valid(1.0),
    );
    try std.testing.expect(
        !(FadeDescription{
            .head_duration = 0.75,
            .tail_duration = 0.5,
        }).valid(1.0),
    );
    try std.testing.expect(
        !(FadeDescription{}).valid(std.math.inf(f64)),
    );
    inline for (std.meta.tags(FadeCurve)) |curve| {
        try std.testing.expectEqual(
            @as(f64, 0.0),
            fadeCurveGain(curve, 0.0),
        );
        try std.testing.expectEqual(
            @as(f64, 1.0),
            fadeCurveGain(curve, 1.0),
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        fadeCurveGain(.linear, 0.5),
        1.0e-15,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        fadeCurveGain(.smoothstep, 0.5),
        1.0e-15,
    );
    try std.testing.expectApproxEqAbs(
        @sqrt(@as(f64, 0.5)),
        fadeCurveGain(.equal_power, 0.5),
        1.0e-15,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        regionFadeGain(
            .{
                .head_duration = 0.5,
                .tail_duration = 0.5,
                .curve = .linear,
            },
            0.25,
            0.5,
        ),
        1.0e-15,
    );
}

test "ARA tempo warp lookup follows every piecewise segment" {
    const points = [_]TempoWarpPoint{
        .{
            .playback_time = 0.0,
            .modification_time = 0.0,
        },
        .{
            .playback_time = 1.0,
            .modification_time = 0.5,
        },
        .{
            .playback_time = 4.0 / 3.0,
            .modification_time = 1.0,
        },
        .{
            .playback_time = 2.0,
            .modification_time = 2.0,
        },
    };
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        warpedModificationTime(&points, 0.5),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.75),
        warpedModificationTime(&points, 7.0 / 6.0),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.5),
        warpedModificationTime(&points, 5.0 / 3.0),
        1.0e-12,
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        warpedModificationTime(&points, -1.0),
    );
    try std.testing.expectEqual(
        @as(f64, 2.0),
        warpedModificationTime(&points, 3.0),
    );
}

fn normalizedSinc(value: f64) f64 {
    const nearest_integer = @round(value);
    if (@abs(value - nearest_integer) <=
        8.0 * std.math.floatEps(f64))
    {
        return if (nearest_integer == 0.0) 1.0 else 0.0;
    }
    const angle = std.math.pi * value;
    return @sin(angle) / angle;
}

fn makeWindowedSincWeights() [windowed_sinc_phase_count + 1][windowed_sinc_taps]f64 {
    @setEvalBranchQuota(10_000_000);
    var table: [windowed_sinc_phase_count + 1][windowed_sinc_taps]f64 =
        undefined;
    for (&table, 0..) |*phase_weights, phase_index| {
        const fraction =
            @as(f64, @floatFromInt(phase_index)) /
            @as(f64, @floatFromInt(windowed_sinc_phase_count));
        var sum: f64 = 0.0;
        for (windowed_sinc_offsets, 0..) |offset, tap_index| {
            const distance =
                @as(f64, @floatFromInt(offset)) -
                fraction;
            const weight =
                normalizedSinc(distance) *
                normalizedSinc(distance / 4.0);
            phase_weights[tap_index] = weight;
            sum += weight;
        }
        for (phase_weights) |*weight| weight.* /= sum;
    }
    return table;
}

fn validateLimits(comptime limits: Limits) void {
    inline for (.{
        limits.regions,
        limits.channels,
        limits.maximum_block_frames,
        limits.maximum_source_frames_per_region,
        limits.maximum_tempo_warp_points,
    }) |capacity| {
        if (capacity == 0 or capacity > std.math.maxInt(u16))
            @compileError(
                "ARA playback renderer capacities must be between 1 and 65535",
            );
    }
}

test "ARA playback interpolation supports linear and cubic modes" {
    const samples = [_]f64{ 0, 1, 4, 9 };
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.5),
        interpolate(f64, .linear, &samples, 1, 0.5),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.25),
        interpolate(
            f64,
            .cubic_catmull_rom,
            &samples,
            1,
            0.5,
        ),
        1.0e-12,
    );
    try std.testing.expectEqual(
        @as(f64, 9),
        interpolate(
            f64,
            .cubic_catmull_rom,
            &samples,
            3,
            0,
        ),
    );
}

test "ARA playback windowed sinc is bounded and exact at samples" {
    const constant = [_]f64{1.0} ** 16;
    for (0..15) |index| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            interpolate(
                f64,
                .windowed_sinc_8,
                &constant,
                index,
                0.37,
            ),
            1.0e-12,
        );
    }

    const ramp = [_]f64{ 0, 1, 2, 3, 4, 5, 6, 7 };
    for (0..ramp.len) |index| {
        try std.testing.expectApproxEqAbs(
            ramp[index],
            interpolate(
                f64,
                .windowed_sinc_8,
                &ramp,
                index,
                0.0,
            ),
            1.0e-12,
        );
    }

    const sine = [_]f64{
        0.0,
        0.7071067811865475,
        1.0,
        0.7071067811865476,
        0.0,
        -0.7071067811865475,
        -1.0,
        -0.7071067811865477,
        0.0,
    };
    try std.testing.expectApproxEqAbs(
        @sin(7.0 * std.math.pi / 8.0),
        interpolate(
            f64,
            .windowed_sinc_8,
            &sine,
            3,
            0.5,
        ),
        1.5e-2,
    );
}

test "ARA playback windowed sinc improves fractional high frequency error" {
    var source: [256]f64 = undefined;
    const angular_frequency = 0.4 * std.math.pi;
    for (&source, 0..) |*sample, index| {
        sample.* = @sin(
            angular_frequency *
                @as(f64, @floatFromInt(index)),
        );
    }

    var linear_error_squared: f64 = 0.0;
    var sinc_error_squared: f64 = 0.0;
    var count: usize = 0;
    for (4..251) |index| {
        const fraction = 0.37;
        const expected = @sin(
            angular_frequency *
                (@as(f64, @floatFromInt(index)) + fraction),
        );
        const linear_error =
            interpolate(
                f64,
                .linear,
                &source,
                index,
                fraction,
            ) -
            expected;
        const sinc_error =
            interpolate(
                f64,
                .windowed_sinc_8,
                &source,
                index,
                fraction,
            ) -
            expected;
        linear_error_squared += linear_error * linear_error;
        sinc_error_squared += sinc_error * sinc_error;
        count += 1;
    }
    const count_f64: f64 = @floatFromInt(count);
    const linear_rms = @sqrt(linear_error_squared / count_f64);
    const sinc_rms = @sqrt(sinc_error_squared / count_f64);
    try std.testing.expect(sinc_rms < linear_rms * 0.1);
    try std.testing.expect(sinc_rms < 0.01);
}

const TestAudio = struct {
    samples_f32: [2][16]f32,
    samples_f64: [2][16]f64,
    use_64_bit_samples: bool,
    open_readers: usize = 0,
    destroyed_readers: usize = 0,
    next_reader_address: usize = 0x1000,
};

fn testAudio(
    host_ref: raw.ARAAudioAccessControllerHostRef,
) *TestAudio {
    return @ptrCast(@alignCast(host_ref.?));
}

fn testCreateReader(
    host_ref: raw.ARAAudioAccessControllerHostRef,
    _: raw.ARAAudioSourceHostRef,
    use_64_bit_samples: raw.ARABool,
) callconv(.c) raw.ARAAudioReaderHostRef {
    const audio = testAudio(host_ref);
    if ((use_64_bit_samples != raw.kARAFalse) !=
        audio.use_64_bit_samples)
        return null;
    const address = audio.next_reader_address;
    audio.next_reader_address += 0x1000;
    audio.open_readers += 1;
    return @ptrFromInt(address);
}

fn testReadSamples(
    host_ref: raw.ARAAudioAccessControllerHostRef,
    _: raw.ARAAudioReaderHostRef,
    sample_position: raw.ARASamplePosition,
    samples_per_channel: raw.ARASampleCount,
    buffers: [*c]const ?*anyopaque,
) callconv(.c) raw.ARABool {
    const audio = testAudio(host_ref);
    if (sample_position < 0 or
        samples_per_channel < 0 or
        buffers == null)
        return raw.kARAFalse;
    const start: usize = @intCast(sample_position);
    const count: usize = @intCast(samples_per_channel);
    const available = audio.samples_f32[0].len;
    if (start > available or count > available - start)
        return raw.kARAFalse;
    if (audio.use_64_bit_samples) {
        for (0..audio.samples_f64.len) |channel| {
            const destination: [*]f64 =
                @ptrCast(@alignCast(buffers[channel].?));
            @memcpy(
                destination[0..count],
                audio.samples_f64[channel][start..][0..count],
            );
        }
    } else {
        for (0..audio.samples_f32.len) |channel| {
            const destination: [*]f32 =
                @ptrCast(@alignCast(buffers[channel].?));
            @memcpy(
                destination[0..count],
                audio.samples_f32[channel][start..][0..count],
            );
        }
    }
    return raw.kARATrue;
}

fn testDestroyReader(
    host_ref: raw.ARAAudioAccessControllerHostRef,
    _: raw.ARAAudioReaderHostRef,
) callconv(.c) void {
    const audio = testAudio(host_ref);
    if (audio.open_readers == 0) return;
    audio.open_readers -= 1;
    audio.destroyed_readers += 1;
}

fn testHost(
    audio: *TestAudio,
) raw.ARADocumentControllerHostInstance {
    const Host = struct {
        const audio_interface =
            raw.ARAAudioAccessControllerInterface{
                .structSize = @sizeOf(raw.ARAAudioAccessControllerInterface),
                .createAudioReaderForSource = testCreateReader,
                .readAudioSamples = testReadSamples,
                .destroyAudioReader = testDestroyReader,
            };
        const archive = raw.ARAArchivingControllerInterface{
            .structSize = @sizeOf(raw.ARAArchivingControllerInterface),
        };
        const content = raw.ARAContentAccessControllerInterface{
            .structSize = @sizeOf(raw.ARAContentAccessControllerInterface),
        };
        const model_update =
            raw.ARAModelUpdateControllerInterface{
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

fn exercisePlaybackRenderer(
    comptime Sample: type,
    comptime interpolation: Interpolation,
) !void {
    const ControllerType = ara_document_controller.Controller(.{
        .musical_contexts = 1,
        .region_sequences = 1,
        .audio_sources = 1,
        .audio_modifications = 1,
        .playback_regions = 1,
        .audio_readers = 2,
        .model_observers = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    });
    const TestRenderer = Renderer(
        ControllerType,
        Sample,
        .{
            .regions = 1,
            .channels = 2,
            .maximum_block_frames = 16,
            .maximum_source_frames_per_region = 16,
            .interpolation = interpolation,
        },
    );
    const TestCache = ara_source_cache.Cache(
        ControllerType,
        Sample,
        .{
            .sources = 1,
            .channels = 2,
            .frames_per_source = 16,
            .publication_slots = 3,
        },
    );

    var audio = TestAudio{
        .samples_f32 = .{
            .{
                0, 1, 2,  3,  4,  5,  6,  7,
                8, 9, 10, 11, 12, 13, 14, 15,
            },
            .{
                16, 17, 18, 19, 20, 21, 22, 23,
                24, 25, 26, 27, 28, 29, 30, 31,
            },
        },
        .samples_f64 = .{
            .{
                0, 1, 2,  3,  4,  5,  6,  7,
                8, 9, 10, 11, 12, 13, 14, 15,
            },
            .{
                16, 17, 18, 19, 20, 21, 22, 23,
                24, 25, 26, 27, 28, 29, 30, 31,
            },
        },
        .use_64_bit_samples = Sample == f64,
    };
    var factory = std.mem.zeroes(raw.ARAFactory);
    var host = testHost(&audio);
    var document_properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Renderer test",
    };
    var controller: ControllerType = undefined;
    try controller.init(
        &factory,
        &host,
        &document_properties,
    );
    try controller.document.beginEditing();
    const context =
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
                .musical_context = context,
            },
        );
    const source =
        try controller.document.createAudioSource(
            null,
            .{
                .name = "Source",
                .persistent_id = "source",
                .sample_count = 16,
                .sample_rate = 8.0,
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
                .start_in_modification_time = 0.0,
                .duration_in_modification_time = 1.0,
                .start_in_playback_time = 0.25,
                .duration_in_playback_time = 1.0,
            },
        );
    _ = try controller.document.endEditing();
    try controller.setAudioSourceSamplesAccess(source, true);

    var source_cache = TestCache.init();
    _ = try source_cache.loadSource(&controller, source);
    var renderer = TestRenderer.init(
        source_cache.provider(TestRenderer),
    );
    for (renderer.plan_publisher.slots) |slot| {
        try std.testing.expectEqual(@as(usize, 0), slot.value.region_count);
        for (slot.value.regions) |planned_region| {
            try std.testing.expectEqualDeep(
                std.mem.zeroes(
                    ControllerType.PlaybackRegionRenderDescription,
                ),
                planned_region.description,
            );
            try std.testing.expectEqual(
                @as(usize, 0),
                planned_region.tempo_warp_count,
            );
            for (planned_region.tempo_warp) |point| {
                try std.testing.expectEqualDeep(
                    TempoWarpPoint{
                        .playback_time = 0.0,
                        .modification_time = 0.0,
                    },
                    point,
                );
            }
        }
    }
    renderer.initializeInPlace();
    defer renderer.deinit();
    var entry = TestRenderer.EntryPoint.init(
        &renderer,
        @ptrFromInt(0x1000),
    );
    const entry_interface = entry.asEntryPoint2();
    const opaque_instance =
        entry_interface.vtable
            .bindToDocumentControllerWithRoles(
            entry_interface,
            @ptrCast(&controller),
            ara_vst3.all_roles,
            ara_vst3.playback_renderer_role,
        ) orelse return error.TestUnexpectedResult;
    const instance: *const raw.ARAPlugInExtensionInstance =
        @ptrCast(@alignCast(opaque_instance));
    const playback_interface =
        instance.playbackRendererInterface orelse
        return error.TestUnexpectedResult;
    const region_ref = try controller.playbackRegionRef(region);
    playback_interface[0].addPlaybackRegion.?(
        instance.playbackRendererRef,
        region_ref,
    );

    var left: [10]Sample = @splat(-1);
    var right: [10]Sample = @splat(-1);
    const outputs = [_][]Sample{ &left, &right };
    try renderer.render(0.0, 8.0, &outputs);
    try std.testing.expectEqualSlices(
        Sample,
        &.{ 0, 0, 0, 1, 2, 3, 4, 5, 6, 7 },
        &left,
    );
    try std.testing.expectEqualSlices(
        Sample,
        &.{ 0, 0, 16, 17, 18, 19, 20, 21, 22, 23 },
        &right,
    );

    var aliased_output: [10]Sample = @splat(-1);
    const aliased_outputs = [_][]Sample{
        &aliased_output,
        &aliased_output,
    };
    try std.testing.expectError(
        error.InvalidOutputBuffers,
        renderer.render(0.0, 8.0, &aliased_outputs),
    );
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{0} ** 10),
        &aliased_output,
    );

    try controller.setAudioSourceSamplesAccess(source, false);
    try renderer.render(0.0, 8.0, &outputs);
    try std.testing.expectEqualSlices(
        Sample,
        &.{ 0, 0, 0, 1, 2, 3, 4, 5, 6, 7 },
        &left,
    );
    try controller.setAudioSourceSamplesAccess(source, true);
    try renderer.render(0.0, 8.0, &outputs);
    try std.testing.expectEqualSlices(
        Sample,
        &.{ 0, 0, 0, 1, 2, 3, 4, 5, 6, 7 },
        &left,
    );

    _ = try source_cache.invalidate(source);
    renderer.refreshSourceState();
    try std.testing.expectEqual(
        error.SourceUnavailable,
        renderer.takeError().?,
    );
    try renderer.render(0.0, 8.0, &outputs);
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{0} ** 10),
        &left,
    );
    _ = try source_cache.loadSource(&controller, source);
    renderer.refreshSourceState();

    ControllerType.interface.beginEditing.?(
        @ptrCast(&controller),
    );
    try controller.document.updatePlaybackRegion(
        region,
        .{
            .name = "Region",
            .region_sequence = sequence,
            .start_in_modification_time = 0.0,
            .duration_in_modification_time = 1.0,
            .start_in_playback_time = 0.5,
            .duration_in_playback_time = 1.0,
        },
    );
    ControllerType.interface.endEditing.?(
        @ptrCast(&controller),
    );
    try renderer.render(0.0, 8.0, &outputs);
    try std.testing.expectEqualSlices(
        Sample,
        &.{ 0, 0, 0, 0, 0, 1, 2, 3, 4, 5 },
        &left,
    );

    ControllerType.interface.beginEditing.?(
        @ptrCast(&controller),
    );
    try controller.document.destroyPlaybackRegion(region);
    ControllerType.interface.endEditing.?(
        @ptrCast(&controller),
    );
    try std.testing.expectEqual(
        error.InvalidHandle,
        renderer.takeError().?,
    );
    try renderer.render(0.0, 8.0, &outputs);
    try std.testing.expectEqualSlices(
        Sample,
        &([_]Sample{0} ** 10),
        &left,
    );
    try std.testing.expectEqual(@as(usize, 0), audio.open_readers);
    renderer.deinit();
    try std.testing.expectEqual(@as(usize, 0), audio.open_readers);
    try std.testing.expectEqual(
        @as(usize, 2),
        audio.destroyed_readers,
    );
}

test "ARA playback renderer follows assignments and model publications for f32" {
    try exercisePlaybackRenderer(f32, .linear);
}

test "ARA playback renderer follows assignments and model publications for f64" {
    try exercisePlaybackRenderer(f64, .linear);
}

test "ARA playback renderer supports cached cubic playback for f32" {
    try exercisePlaybackRenderer(f32, .cubic_catmull_rom);
}

test "ARA playback renderer supports cached cubic playback for f64" {
    try exercisePlaybackRenderer(f64, .cubic_catmull_rom);
}

test "ARA playback renderer supports cached windowed sinc playback for f32" {
    try exercisePlaybackRenderer(f32, .windowed_sinc_8);
}

test "ARA playback renderer supports cached windowed sinc playback for f64" {
    try exercisePlaybackRenderer(f64, .windowed_sinc_8);
}
