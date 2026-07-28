const std = @import("std");
const ara_document_controller =
    @import("ara_document_controller.zig");
const ara_playback_renderer =
    @import("ara_playback_renderer.zig");

pub const raw = ara_document_controller.raw;

pub const Error = error{
    InvalidConfiguration,
    InvalidTempoMap,
    IncompatibleTempoRanges,
    CapacityExceeded,
    TempoMapUnavailable,
} || ara_document_controller.Error;

pub const Limits = struct {
    regions: usize,
    tempo_points: usize,
    warp_points: usize,
};

pub const Config = struct {
    endpoint_tolerance_seconds: f64 = 1.0e-6,

    pub fn valid(self: Config) bool {
        return std.math.isFinite(
            self.endpoint_tolerance_seconds,
        ) and self.endpoint_tolerance_seconds >= 0.0;
    }
};

pub fn Builder(
    comptime ControllerType: type,
    comptime limits: Limits,
) type {
    if (limits.regions == 0 or
        limits.tempo_points < 2 or
        limits.warp_points < 2)
        @compileError("ARA tempo-warp limits are too small");

    const Description =
        ControllerType.PlaybackRegionRenderDescription;
    const SourceId = @FieldType(Description, "audio_source");

    return struct {
        const Self = @This();

        const Entry = struct {
            occupied: bool = false,
            description: Description = undefined,
            points: [limits.warp_points]ara_playback_renderer.TempoWarpPoint =
                undefined,
            point_count: usize = 0,
        };

        entries: [limits.regions]Entry = @splat(.{}),
        source_scratch: [limits.tempo_points]raw.ARAContentTempoEntry =
            undefined,
        context_scratch: [limits.tempo_points]raw.ARAContentTempoEntry =
            undefined,
        warp_scratch: [limits.warp_points]ara_playback_renderer.TempoWarpPoint =
            undefined,
        config: Config = .{},

        pub fn init(config: Config) Error!Self {
            if (!config.valid()) return error.InvalidConfiguration;
            return .{ .config = config };
        }

        pub fn prepareRegionFromHostSource(
            self: *Self,
            controller: *ControllerType,
            description: *const Description,
        ) Error!usize {
            const region = controller.document.playbackRegion(
                description.playback_region,
            ) orelse return error.InvalidHandle;
            const sequence = controller.document.regionSequence(
                region.region_sequence,
            ) orelse return error.InvalidHandle;
            const source_count =
                try controller.copyHostAudioSourceContent(
                    description.audio_source,
                    raw.kARAContentTypeTempoEntries,
                    null,
                    &self.source_scratch,
                );
            const context_count =
                try controller.copyHostMusicalContextContent(
                    sequence.musical_context,
                    raw.kARAContentTypeTempoEntries,
                    null,
                    &self.context_scratch,
                );
            return self.prepareRegionFromMaps(
                description,
                self.source_scratch[0..source_count],
                self.context_scratch[0..context_count],
            );
        }

        pub fn prepareRegionFromMaps(
            self: *Self,
            description: *const Description,
            modification_tempo: []const raw.ARAContentTempoEntry,
            context_tempo: []const raw.ARAContentTempoEntry,
        ) Error!usize {
            if (!description.transformation.time_stretch or
                !description.transformation.reflect_tempo)
                return error.TempoMapUnavailable;
            try validateTempoMap(modification_tempo);
            try validateTempoMap(context_tempo);
            const playback_start =
                description.start_in_playback_time;
            const playback_end = playback_start +
                description.duration_in_playback_time;
            const modification_start =
                description.start_in_modification_time;
            const modification_end = modification_start +
                description.duration_in_modification_time;
            if (!finiteIncreasingRange(
                playback_start,
                playback_end,
            ) or
                !finiteIncreasingRange(
                    modification_start,
                    modification_end,
                ))
                return error.IncompatibleTempoRanges;

            const modification_anchor = quarterAtTime(
                modification_tempo,
                modification_start,
            );
            const context_anchor = quarterAtTime(
                context_tempo,
                playback_start,
            );
            var point_count: usize = 0;
            try appendPlaybackPoint(
                &self.warp_scratch,
                &point_count,
                playback_start,
            );
            for (context_tempo) |point| {
                if (point.timePosition > playback_start and
                    point.timePosition < playback_end)
                    try appendPlaybackPoint(
                        &self.warp_scratch,
                        &point_count,
                        point.timePosition,
                    );
            }
            const context_end_quarter =
                quarterAtTime(context_tempo, playback_end);
            const modification_quarter_end =
                modification_anchor +
                (context_end_quarter - context_anchor);
            const quarter_min = @min(
                modification_anchor,
                modification_quarter_end,
            );
            const quarter_max = @max(
                modification_anchor,
                modification_quarter_end,
            );
            for (modification_tempo) |point| {
                if (point.quarterPosition <= quarter_min or
                    point.quarterPosition >= quarter_max)
                    continue;
                const context_quarter =
                    context_anchor +
                    (point.quarterPosition -
                        modification_anchor);
                const playback_time =
                    timeAtQuarter(
                        context_tempo,
                        context_quarter,
                    );
                if (playback_time > playback_start and
                    playback_time < playback_end)
                    try appendPlaybackPoint(
                        &self.warp_scratch,
                        &point_count,
                        playback_time,
                    );
            }
            try appendPlaybackPoint(
                &self.warp_scratch,
                &point_count,
                playback_end,
            );
            sortAndDeduplicate(
                self.warp_scratch[0..point_count],
                &point_count,
            );
            for (self.warp_scratch[0..point_count]) |*point| {
                const context_quarter = quarterAtTime(
                    context_tempo,
                    point.playback_time,
                );
                const modification_quarter =
                    modification_anchor +
                    (context_quarter - context_anchor);
                point.modification_time = timeAtQuarter(
                    modification_tempo,
                    modification_quarter,
                );
            }
            if (@abs(
                self.warp_scratch[0].modification_time -
                    modification_start,
            ) > self.config.endpoint_tolerance_seconds or
                @abs(
                    self.warp_scratch[point_count - 1]
                        .modification_time -
                        modification_end,
                ) > self.config.endpoint_tolerance_seconds)
                return error.IncompatibleTempoRanges;
            self.warp_scratch[0].modification_time =
                modification_start;
            self.warp_scratch[point_count - 1]
                .modification_time = modification_end;
            for (self.warp_scratch[1..point_count], 1..) |point, index| {
                if (point.modification_time <=
                    self.warp_scratch[index - 1]
                        .modification_time)
                    return error.IncompatibleTempoRanges;
            }

            const entry = try self.entryFor(
                description.playback_region,
            );
            entry.occupied = true;
            entry.description = description.*;
            entry.point_count = point_count;
            @memcpy(
                entry.points[0..point_count],
                self.warp_scratch[0..point_count],
            );
            return point_count;
        }

        pub fn invalidateSource(
            self: *Self,
            source_id: SourceId,
        ) void {
            for (&self.entries) |*entry| {
                if (!entry.occupied) continue;
                if (sameHandle(
                    entry.description.audio_source,
                    source_id,
                ))
                    entry.* = .{};
            }
        }

        pub fn invalidateAll(self: *Self) void {
            for (&self.entries) |*entry| entry.* = .{};
        }

        pub fn configureProvider(
            self: *Self,
            comptime RendererType: type,
            provider: *RendererType.SourceProvider,
        ) void {
            provider.tempo_warp_context = @ptrCast(self);
            provider.tempo_warp = provide;
        }

        fn entryFor(
            self: *Self,
            region_id: @FieldType(Description, "playback_region"),
        ) Error!*Entry {
            for (&self.entries) |*entry| {
                if (!entry.occupied) continue;
                if (sameHandle(
                    entry.description.playback_region,
                    region_id,
                ))
                    return entry;
            }
            for (&self.entries) |*entry| {
                if (!entry.occupied) return entry;
            }
            return error.CapacityExceeded;
        }

        fn provide(
            context: ?*anyopaque,
            description: *const Description,
            output: []ara_playback_renderer.TempoWarpPoint,
        ) ?usize {
            const pointer = context orelse return null;
            const self: *Self =
                @ptrCast(@alignCast(pointer));
            for (&self.entries) |*entry| {
                if (!entry.occupied or
                    !sameDescription(
                        &entry.description,
                        description,
                    ))
                    continue;
                if (entry.point_count > output.len) return null;
                @memcpy(
                    output[0..entry.point_count],
                    entry.points[0..entry.point_count],
                );
                return entry.point_count;
            }
            return null;
        }

        fn sameDescription(
            left: *const Description,
            right: *const Description,
        ) bool {
            return left.model_revision == right.model_revision and
                sameHandle(
                    left.playback_region,
                    right.playback_region,
                ) and
                sameHandle(
                    left.audio_modification,
                    right.audio_modification,
                ) and
                sameHandle(
                    left.audio_source,
                    right.audio_source,
                ) and
                left.source_sample_count ==
                    right.source_sample_count and
                left.source_sample_rate ==
                    right.source_sample_rate and
                left.source_channel_count ==
                    right.source_channel_count and
                @as(u8, @bitCast(left.transformation)) ==
                    @as(u8, @bitCast(right.transformation)) and
                left.start_in_modification_time ==
                    right.start_in_modification_time and
                left.duration_in_modification_time ==
                    right.duration_in_modification_time and
                left.start_in_playback_time ==
                    right.start_in_playback_time and
                left.duration_in_playback_time ==
                    right.duration_in_playback_time;
        }

        fn sameHandle(left: anytype, right: @TypeOf(left)) bool {
            return left.index == right.index and
                left.generation == right.generation;
        }
    };
}

pub fn validateTempoMap(
    points: []const raw.ARAContentTempoEntry,
) Error!void {
    if (points.len < 2) return error.InvalidTempoMap;
    var has_zero_quarter = false;
    for (points, 0..) |point, index| {
        if (!std.math.isFinite(point.timePosition) or
            !std.math.isFinite(point.quarterPosition))
            return error.InvalidTempoMap;
        if (point.quarterPosition == 0.0)
            has_zero_quarter = true;
        if (index == 0) continue;
        if (point.timePosition <=
            points[index - 1].timePosition or
            point.quarterPosition <=
                points[index - 1].quarterPosition)
            return error.InvalidTempoMap;
    }
    if (!has_zero_quarter) return error.InvalidTempoMap;
}

pub fn quarterAtTime(
    points: []const raw.ARAContentTempoEntry,
    time: f64,
) f64 {
    const segment = segmentForTime(points, time);
    const first = points[segment];
    const second = points[segment + 1];
    const progress = (time - first.timePosition) /
        (second.timePosition - first.timePosition);
    return first.quarterPosition +
        progress *
            (second.quarterPosition -
                first.quarterPosition);
}

pub fn timeAtQuarter(
    points: []const raw.ARAContentTempoEntry,
    quarter: f64,
) f64 {
    const segment = segmentForQuarter(points, quarter);
    const first = points[segment];
    const second = points[segment + 1];
    const progress = (quarter - first.quarterPosition) /
        (second.quarterPosition - first.quarterPosition);
    return first.timePosition +
        progress *
            (second.timePosition - first.timePosition);
}

fn segmentForTime(
    points: []const raw.ARAContentTempoEntry,
    time: f64,
) usize {
    if (time <= points[0].timePosition) return 0;
    if (time >= points[points.len - 1].timePosition)
        return points.len - 2;
    var left: usize = 0;
    var right = points.len - 1;
    while (right - left > 1) {
        const middle = left + (right - left) / 2;
        if (time < points[middle].timePosition)
            right = middle
        else
            left = middle;
    }
    return left;
}

fn segmentForQuarter(
    points: []const raw.ARAContentTempoEntry,
    quarter: f64,
) usize {
    if (quarter <= points[0].quarterPosition) return 0;
    if (quarter >= points[points.len - 1].quarterPosition)
        return points.len - 2;
    var left: usize = 0;
    var right = points.len - 1;
    while (right - left > 1) {
        const middle = left + (right - left) / 2;
        if (quarter < points[middle].quarterPosition)
            right = middle
        else
            left = middle;
    }
    return left;
}

fn appendPlaybackPoint(
    points: []ara_playback_renderer.TempoWarpPoint,
    count: *usize,
    playback_time: f64,
) Error!void {
    if (count.* == points.len) return error.CapacityExceeded;
    points[count.*] = .{
        .playback_time = playback_time,
        .modification_time = 0.0,
    };
    count.* += 1;
}

fn sortAndDeduplicate(
    points: []ara_playback_renderer.TempoWarpPoint,
    count: *usize,
) void {
    std.mem.sort(
        ara_playback_renderer.TempoWarpPoint,
        points,
        {},
        struct {
            fn lessThan(
                _: void,
                left: ara_playback_renderer.TempoWarpPoint,
                right: ara_playback_renderer.TempoWarpPoint,
            ) bool {
                return left.playback_time <
                    right.playback_time;
            }
        }.lessThan,
    );
    var write: usize = 1;
    for (points[1..]) |point| {
        if (point.playback_time ==
            points[write - 1].playback_time)
            continue;
        points[write] = point;
        write += 1;
    }
    count.* = write;
}

fn finiteIncreasingRange(start: f64, end: f64) bool {
    return std.math.isFinite(start) and
        std.math.isFinite(end) and end > start;
}

test "ARA tempo maps interpolate and extrapolate exact sync points" {
    const map = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = -1.0, .quarterPosition = -2.0 },
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 2.0, .quarterPosition = 3.0 },
    };
    try validateTempoMap(&map);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.5),
        quarterAtTime(&map, 1.0),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        timeAtQuarter(&map, 1.5),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        quarterAtTime(&map, 2.0),
        1.0e-12,
    );
}

const TestHandle = struct {
    index: u16,
    generation: u32,
};

const TestTransformation = packed struct(u8) {
    time_stretch: bool = false,
    reflect_tempo: bool = false,
    fade_tail: bool = false,
    fade_head: bool = false,
    _: u4 = 0,
};

const TestDescription = struct {
    model_revision: u64,
    playback_region: TestHandle,
    audio_modification: TestHandle,
    audio_source: TestHandle,
    source_sample_count: i64,
    source_sample_rate: f64,
    source_channel_count: i32,
    transformation: TestTransformation,
    start_in_modification_time: f64,
    duration_in_modification_time: f64,
    start_in_playback_time: f64,
    duration_in_playback_time: f64,
};

const TestController = struct {
    pub const PlaybackRegionRenderDescription =
        TestDescription;
};

const TestRenderer = struct {
    pub const SourceProvider = struct {
        tempo_warp_context: ?*anyopaque = null,
        tempo_warp: ?*const fn (
            ?*anyopaque,
            *const TestDescription,
            []ara_playback_renderer.TempoWarpPoint,
        ) ?usize = null,
    };
};

fn testDescription() TestDescription {
    return .{
        .model_revision = 1,
        .playback_region = .{ .index = 0, .generation = 1 },
        .audio_modification = .{
            .index = 0,
            .generation = 1,
        },
        .audio_source = .{ .index = 0, .generation = 1 },
        .source_sample_count = 96_000,
        .source_sample_rate = 48_000.0,
        .source_channel_count = 2,
        .transformation = .{
            .time_stretch = true,
            .reflect_tempo = true,
        },
        .start_in_modification_time = 0.0,
        .duration_in_modification_time = 2.0,
        .start_in_playback_time = 0.0,
        .duration_in_playback_time = 2.0,
    };
}

test "ARA tempo warp builder publishes exact bounded nonlinear plans" {
    const TempoBuilder = Builder(
        TestController,
        .{
            .regions = 1,
            .tempo_points = 4,
            .warp_points = 8,
        },
    );
    const modification = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 1.0, .quarterPosition = 2.0 },
        .{ .timePosition = 2.0, .quarterPosition = 4.0 },
    };
    const context = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 1.0, .quarterPosition = 1.0 },
        .{ .timePosition = 2.0, .quarterPosition = 4.0 },
    };
    var builder = try TempoBuilder.init(.{});
    const description = testDescription();
    try std.testing.expectEqual(
        @as(usize, 4),
        try builder.prepareRegionFromMaps(
            &description,
            &modification,
            &context,
        ),
    );

    var provider = TestRenderer.SourceProvider{};
    builder.configureProvider(TestRenderer, &provider);
    const provide = provider.tempo_warp orelse
        return error.TestUnexpectedResult;
    var output: [8]ara_playback_renderer.TempoWarpPoint =
        undefined;
    const count = provide(
        provider.tempo_warp_context,
        &description,
        &output,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 4), count);
    try std.testing.expectEqualDeep(
        ara_playback_renderer.TempoWarpPoint{
            .playback_time = 0.0,
            .modification_time = 0.0,
        },
        output[0],
    );
    try std.testing.expectEqualDeep(
        ara_playback_renderer.TempoWarpPoint{
            .playback_time = 1.0,
            .modification_time = 0.5,
        },
        output[1],
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 4.0 / 3.0),
        output[2].playback_time,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        output[2].modification_time,
        1.0e-12,
    );
    try std.testing.expectEqualDeep(
        ara_playback_renderer.TempoWarpPoint{
            .playback_time = 2.0,
            .modification_time = 2.0,
        },
        output[3],
    );

    var stale = description;
    stale.model_revision += 1;
    try std.testing.expectEqual(
        null,
        provide(
            provider.tempo_warp_context,
            &stale,
            &output,
        ),
    );
    builder.invalidateSource(description.audio_source);
    try std.testing.expectEqual(
        null,
        provide(
            provider.tempo_warp_context,
            &description,
            &output,
        ),
    );
}

test "ARA tempo warp builder rejects malformed and incompatible maps" {
    const TempoBuilder = Builder(
        TestController,
        .{
            .regions = 1,
            .tempo_points = 4,
            .warp_points = 8,
        },
    );
    var builder = try TempoBuilder.init(.{});
    const description = testDescription();
    const modification = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 2.0, .quarterPosition = 4.0 },
    };
    const incompatible_context =
        [_]raw.ARAContentTempoEntry{
            .{
                .timePosition = 0.0,
                .quarterPosition = 0.0,
            },
            .{
                .timePosition = 2.0,
                .quarterPosition = 2.0,
            },
        };
    try std.testing.expectError(
        error.IncompatibleTempoRanges,
        builder.prepareRegionFromMaps(
            &description,
            &modification,
            &incompatible_context,
        ),
    );
    const malformed = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 0.0, .quarterPosition = 1.0 },
    };
    try std.testing.expectError(
        error.InvalidTempoMap,
        builder.prepareRegionFromMaps(
            &description,
            &modification,
            &malformed,
        ),
    );
}
