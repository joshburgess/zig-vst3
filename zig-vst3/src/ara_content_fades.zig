const std = @import("std");
const ara_model = @import("ara_model.zig");
const ara_playback_renderer =
    @import("ara_playback_renderer.zig");

pub const Error = error{
    InvalidConfiguration,
    InvalidHandle,
    InvalidSourceFormat,
    InvalidRegionRange,
    InvalidChannelCount,
    CapacityExceeded,
    AnalysisUnavailable,
} || @import("ara_document_controller.zig").Error;

pub const Limits = struct {
    regions: usize,
    channels: usize,
    analysis_frames: usize,
};

pub const Config = struct {
    minimum_fade_seconds: f64 = 0.002,
    fallback_fade_seconds: f64 = 0.010,
    curve: ara_playback_renderer.FadeCurve = .smoothstep,

    pub fn valid(self: Config) bool {
        return std.math.isFinite(self.minimum_fade_seconds) and
            std.math.isFinite(self.fallback_fade_seconds) and
            self.minimum_fade_seconds > 0.0 and
            self.fallback_fade_seconds >=
                self.minimum_fade_seconds;
    }
};

pub fn Analyzer(
    comptime ControllerType: type,
    comptime Sample: type,
    comptime limits: Limits,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("ARA fade analysis supports f32 or f64");
    if (limits.regions == 0 or
        limits.channels == 0 or
        limits.analysis_frames < 2)
        @compileError("ARA fade analysis limits must be nonzero");

    const Description =
        ControllerType.PlaybackRegionRenderDescription;
    const empty_description: Description = std.mem.zeroes(Description);
    const SourceId = @FieldType(Description, "audio_source");
    const RegionId = @FieldType(Description, "playback_region");

    return struct {
        const Self = @This();

        const Entry = struct {
            occupied: bool = false,
            description: Description = empty_description,
            fades: ara_playback_renderer.FadeDescription = .{},
        };

        entries: [limits.regions]Entry = @splat(.{}),
        scratch: [limits.channels][limits.analysis_frames]Sample =
            undefined,
        config: Config = .{},

        pub fn init(config: Config) Error!Self {
            if (!config.valid()) return error.InvalidConfiguration;
            return .{ .config = config };
        }

        pub fn analyzeRegion(
            self: *Self,
            controller: *ControllerType,
            description: *const Description,
        ) Error!ara_playback_renderer.FadeDescription {
            const source =
                controller.document.audioSource(
                    description.audio_source,
                ) orelse return error.InvalidHandle;
            if (!source.samples_access_enabled)
                return error.AudioAccessDisabled;
            if (source.channel_count <= 0 or
                source.channel_count > limits.channels)
                return error.InvalidChannelCount;
            if (source.sample_count <= 0 or
                !std.math.isFinite(source.sample_rate) or
                source.sample_rate <= 0.0 or
                !std.math.isFinite(
                    description.duration_in_modification_time,
                ) or
                !std.math.isFinite(
                    description.duration_in_playback_time,
                ) or
                !std.math.isFinite(
                    description.start_in_modification_time,
                ) or
                description.duration_in_modification_time <= 0.0 or
                description.duration_in_playback_time <= 0.0)
                return error.InvalidSourceFormat;

            const time_ratio =
                description.duration_in_modification_time /
                description.duration_in_playback_time;
            if (!std.math.isFinite(time_ratio) or
                time_ratio <= 0.0)
                return error.InvalidSourceFormat;
            const source_start = std.math.clamp(
                description.start_in_modification_time *
                    source.sample_rate,
                0.0,
                @as(f64, @floatFromInt(source.sample_count)),
            );
            const source_end = std.math.clamp(
                (description.start_in_modification_time +
                    description.duration_in_modification_time) *
                    source.sample_rate,
                0.0,
                @as(f64, @floatFromInt(source.sample_count)),
            );
            if (source_end <= source_start)
                return error.InvalidRegionRange;
            const maximum_i64_float: f64 =
                @floatFromInt(std.math.maxInt(i64));
            if (source_start >= maximum_i64_float or
                source_end >= maximum_i64_float)
                return error.InvalidRegionRange;

            var reader = try controller.openAudioReader(
                description.audio_source,
                Sample == f64,
            );
            defer reader.close();

            var fades = ara_playback_renderer.FadeDescription{
                .curve = self.config.curve,
            };
            if (description.transformation.fade_head) {
                fades.head_duration = try self.analyzeBorder(
                    &reader,
                    source.channel_count,
                    source.sample_rate,
                    time_ratio,
                    source_start,
                    source_end,
                    true,
                );
            }
            if (description.transformation.fade_tail) {
                fades.tail_duration = try self.analyzeBorder(
                    &reader,
                    source.channel_count,
                    source.sample_rate,
                    time_ratio,
                    source_start,
                    source_end,
                    false,
                );
            }
            const requested_total =
                fades.head_duration + fades.tail_duration;
            if (requested_total >
                description.duration_in_playback_time)
            {
                const scale =
                    description.duration_in_playback_time /
                    requested_total;
                fades.head_duration *= scale;
                fades.tail_duration *= scale;
            }
            if (!fades.valid(
                description.duration_in_playback_time,
            ))
                return error.AnalysisUnavailable;

            const entry = try self.entryFor(
                description.playback_region,
            );
            entry.* = .{
                .occupied = true,
                .description = description.*,
                .fades = fades,
            };
            return fades;
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

        pub fn configureProvider(
            self: *Self,
            comptime RendererType: type,
            provider: *RendererType.SourceProvider,
        ) void {
            provider.fade_context = @ptrCast(self);
            provider.fades = provide;
        }

        fn analyzeBorder(
            self: *Self,
            reader: *ControllerType.AudioReader,
            channel_count_value: i32,
            sample_rate: f64,
            time_ratio: f64,
            source_start: f64,
            source_end: f64,
            head: bool,
        ) Error!f64 {
            const region_first: i64 =
                @intFromFloat(@floor(source_start));
            const region_end: i64 =
                @intFromFloat(@ceil(source_end));
            const available: usize = @intCast(
                region_end - region_first,
            );
            const frame_count =
                @min(limits.analysis_frames, available);
            if (frame_count < 2)
                return error.AnalysisUnavailable;
            const read_start = if (head)
                region_first
            else
                region_end - @as(i64, @intCast(frame_count));
            const channel_count: usize =
                @intCast(channel_count_value);
            var buffers: [limits.channels][]Sample = undefined;
            for (0..channel_count) |channel| {
                buffers[channel] =
                    self.scratch[channel][0..frame_count];
            }
            if (Sample == f64)
                try reader.readF64(
                    read_start,
                    buffers[0..channel_count],
                )
            else
                try reader.readF32(
                    read_start,
                    buffers[0..channel_count],
                );

            const selected = try energeticChannel(
                Sample,
                buffers[0..channel_count],
            );
            const minimum_frames = boundedFrameCount(
                self.config.minimum_fade_seconds,
                sample_rate,
                time_ratio,
                frame_count - 1,
            );
            const fallback_frames = @max(
                minimum_frames,
                boundedFrameCount(
                    self.config.fallback_fade_seconds,
                    sample_rate,
                    time_ratio,
                    frame_count,
                ),
            );
            const fade_frames = crossingDistance(
                Sample,
                selected,
                minimum_frames,
                fallback_frames,
                head,
            );
            return @as(f64, @floatFromInt(fade_frames)) /
                (sample_rate * time_ratio);
        }

        fn entryFor(
            self: *Self,
            region_id: RegionId,
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
        ) ?ara_playback_renderer.FadeDescription {
            const pointer = context orelse return null;
            const self: *Self =
                @ptrCast(@alignCast(pointer));
            for (&self.entries) |*entry| {
                if (!entry.occupied) continue;
                if (sameDescription(
                    &entry.description,
                    description,
                ))
                    return entry.fades;
            }
            return null;
        }

        fn sameDescription(
            left: *const Description,
            right: *const Description,
        ) bool {
            return sameHandle(
                left.playback_region,
                right.playback_region,
            ) and
                left.model_revision ==
                    right.model_revision and
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

fn boundedFrameCount(
    seconds: f64,
    sample_rate: f64,
    time_ratio: f64,
    maximum: usize,
) usize {
    if (maximum == 0) return 0;
    const exact = @ceil(seconds * sample_rate * time_ratio);
    if (!std.math.isFinite(exact) or
        exact >= @as(f64, @floatFromInt(maximum)))
        return maximum;
    if (exact <= 1.0) return 1;
    return @intFromFloat(exact);
}

fn energeticChannel(
    comptime Sample: type,
    channels: []const []const Sample,
) Error![]const Sample {
    if (channels.len == 0) return error.InvalidChannelCount;
    var selected: usize = 0;
    var maximum_energy: f64 = -1.0;
    for (channels, 0..) |channel, index| {
        var mean: f64 = 0.0;
        for (channel) |sample| {
            const value: f64 = @floatCast(sample);
            if (!std.math.isFinite(value))
                return error.AnalysisUnavailable;
            mean += value;
        }
        mean /= @floatFromInt(channel.len);
        var energy: f64 = 0.0;
        for (channel) |sample| {
            const centered =
                @as(f64, @floatCast(sample)) - mean;
            energy += centered * centered;
        }
        if (energy > maximum_energy) {
            maximum_energy = energy;
            selected = index;
        }
    }
    return channels[selected];
}

fn crossingDistance(
    comptime Sample: type,
    samples: []const Sample,
    minimum_frames: usize,
    fallback_frames: usize,
    head: bool,
) usize {
    if (head) {
        var index = minimum_frames;
        while (index < samples.len) : (index += 1) {
            if (crossesZero(
                Sample,
                samples[index - 1],
                samples[index],
            ))
                return index;
        }
        return fallback_frames;
    }
    var distance = minimum_frames;
    while (distance < samples.len) : (distance += 1) {
        const index = samples.len - distance;
        if (crossesZero(
            Sample,
            samples[index - 1],
            samples[index],
        ))
            return distance;
    }
    return fallback_frames;
}

fn crossesZero(
    comptime Sample: type,
    first: Sample,
    second: Sample,
) bool {
    return first == 0 or second == 0 or
        (first < 0) != (second < 0);
}

test "ARA content fade helpers select energy and bounded crossings" {
    const quiet = [_]f64{ 0, 0, 0, 0, 0, 0 };
    const signal = [_]f64{ 1, 1, 1, -1, -1, 1 };
    const channels = [_][]const f64{ &quiet, &signal };
    const selected = try energeticChannel(f64, &channels);
    try std.testing.expectEqualSlices(f64, &signal, selected);
    try std.testing.expectEqual(
        @as(usize, 3),
        crossingDistance(f64, selected, 2, 4, true),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        crossingDistance(f64, selected, 1, 4, false),
    );
}

const TestHandle = struct {
    index: u16,
    generation: u32,
};

const TestSource = struct {
    samples_access_enabled: bool = true,
    sample_count: i64 = 16,
    sample_rate: f64 = 16.0,
    channel_count: i32 = 2,
};

const TestDescription = struct {
    model_revision: u64,
    playback_region: TestHandle,
    audio_modification: TestHandle,
    audio_source: TestHandle,
    source_sample_count: i64,
    source_sample_rate: f64,
    source_channel_count: i32,
    source_samples_access_enabled: bool,
    transformation: ara_model.PlaybackTransformation,
    start_in_modification_time: f64,
    duration_in_modification_time: f64,
    start_in_playback_time: f64,
    duration_in_playback_time: f64,
};

const TestController = struct {
    const Self = @This();

    pub const PlaybackRegionRenderDescription =
        TestDescription;

    const Document = struct {
        source: TestSource = .{},

        pub fn audioSource(
            self: *Document,
            source_id: TestHandle,
        ) ?*TestSource {
            if (source_id.index != 0 or
                source_id.generation != 1)
                return null;
            return &self.source;
        }
    };

    pub const AudioReader = struct {
        controller: *Self,
        use_f64: bool,
        closed: bool = false,

        pub fn readF32(
            self: *AudioReader,
            sample_position: i64,
            buffers: []const []f32,
        ) Error!void {
            if (self.use_f64)
                return error.InvalidSourceFormat;
            try self.read(f32, sample_position, buffers);
        }

        pub fn readF64(
            self: *AudioReader,
            sample_position: i64,
            buffers: []const []f64,
        ) Error!void {
            if (!self.use_f64)
                return error.InvalidSourceFormat;
            try self.read(f64, sample_position, buffers);
        }

        pub fn close(self: *AudioReader) void {
            if (self.closed) return;
            self.closed = true;
            self.controller.open_readers -= 1;
            self.controller.closed_readers += 1;
        }

        fn read(
            self: *AudioReader,
            comptime Sample: type,
            sample_position: i64,
            buffers: []const []Sample,
        ) Error!void {
            if (sample_position < 0)
                return error.InvalidRegionRange;
            const start: usize = @intCast(sample_position);
            if (buffers.len > self.controller.samples.len)
                return error.InvalidChannelCount;
            for (buffers, 0..) |buffer, channel| {
                if (start > self.controller.samples[channel].len or
                    buffer.len >
                        self.controller.samples[channel].len -
                            start)
                    return error.InvalidRegionRange;
                for (buffer, 0..) |*destination, frame| {
                    destination.* = @floatCast(
                        self.controller.samples[channel][start + frame],
                    );
                }
            }
        }
    };

    document: Document = .{},
    samples: [2][16]f64,
    open_readers: usize = 0,
    closed_readers: usize = 0,

    pub fn openAudioReader(
        self: *Self,
        source_id: TestHandle,
        use_f64: bool,
    ) Error!AudioReader {
        if (self.document.audioSource(source_id) == null)
            return error.InvalidHandle;
        self.open_readers += 1;
        return .{
            .controller = self,
            .use_f64 = use_f64,
        };
    }
};

const TestProviderTarget = struct {
    pub const SourceProvider = struct {
        fade_context: ?*anyopaque = null,
        fades: ?*const fn (
            ?*anyopaque,
            *const TestDescription,
        ) ?ara_playback_renderer.FadeDescription = null,
    };
};

fn testDescription(
    playback_region_index: u16,
) TestDescription {
    return .{
        .model_revision = 1,
        .playback_region = .{
            .index = playback_region_index,
            .generation = 1,
        },
        .audio_modification = .{
            .index = 0,
            .generation = 1,
        },
        .audio_source = .{
            .index = 0,
            .generation = 1,
        },
        .source_sample_count = 16,
        .source_sample_rate = 16.0,
        .source_channel_count = 2,
        .source_samples_access_enabled = true,
        .transformation = .{
            .fade_head = true,
            .fade_tail = true,
        },
        .start_in_modification_time = 0.0,
        .duration_in_modification_time = 1.0,
        .start_in_playback_time = 0.0,
        .duration_in_playback_time = 1.0,
    };
}

fn exerciseAnalyzer(comptime Sample: type) !void {
    const FadeAnalyzer = Analyzer(
        TestController,
        Sample,
        .{
            .regions = 1,
            .channels = 2,
            .analysis_frames = 16,
        },
    );
    var controller = TestController{
        .samples = .{
            @splat(0.0),
            .{
                1,  1,  1,  -1,
                -1, -1, 1,  1,
                1,  -1, -1, -1,
                1,  1,  -1, -1,
            },
        },
    };
    var analyzer = try FadeAnalyzer.init(.{
        .minimum_fade_seconds = 0.125,
        .fallback_fade_seconds = 0.25,
        .curve = .equal_power,
    });
    for (analyzer.entries) |entry| {
        try std.testing.expect(!entry.occupied);
        try std.testing.expectEqualDeep(
            std.mem.zeroes(TestDescription),
            entry.description,
        );
        try std.testing.expectEqualDeep(
            ara_playback_renderer.FadeDescription{},
            entry.fades,
        );
    }
    const description = testDescription(0);
    const fades = try analyzer.analyzeRegion(
        &controller,
        &description,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.1875),
        fades.head_duration,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.125),
        fades.tail_duration,
        1.0e-12,
    );
    try std.testing.expectEqual(
        ara_playback_renderer.FadeCurve.equal_power,
        fades.curve,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        controller.open_readers,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        controller.closed_readers,
    );

    var provider = TestProviderTarget.SourceProvider{};
    analyzer.configureProvider(
        TestProviderTarget,
        &provider,
    );
    const provide = provider.fades orelse
        return error.TestUnexpectedResult;
    const provided = provide(
        provider.fade_context,
        &description,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualDeep(fades, provided);

    var stale = description;
    stale.duration_in_playback_time = 0.5;
    try std.testing.expectEqual(
        null,
        provide(provider.fade_context, &stale),
    );

    var second = description;
    second.playback_region.index = 1;
    try std.testing.expectError(
        error.CapacityExceeded,
        analyzer.analyzeRegion(&controller, &second),
    );
    analyzer.invalidateSource(description.audio_source);
    try std.testing.expectEqual(
        null,
        provide(provider.fade_context, &description),
    );
    try std.testing.expectEqualDeep(
        std.mem.zeroes(TestDescription),
        analyzer.entries[0].description,
    );
    try std.testing.expectEqualDeep(
        ara_playback_renderer.FadeDescription{},
        analyzer.entries[0].fades,
    );
}

test "ARA content fade analyzer publishes exact f32 descriptors" {
    try exerciseAnalyzer(f32);
}

test "ARA content fade analyzer publishes exact f64 descriptors" {
    try exerciseAnalyzer(f64);
}

test "ARA content fade analyzer rejects invalid input transactionally" {
    const FadeAnalyzer = Analyzer(
        TestController,
        f64,
        .{
            .regions = 1,
            .channels = 2,
            .analysis_frames = 16,
        },
    );
    try std.testing.expectError(
        error.InvalidConfiguration,
        FadeAnalyzer.init(.{
            .minimum_fade_seconds = 0.02,
            .fallback_fade_seconds = 0.01,
        }),
    );
    var controller = TestController{
        .samples = .{
            @splat(0.0),
            @splat(1.0),
        },
    };
    var analyzer = try FadeAnalyzer.init(.{});
    const description = testDescription(0);
    _ = try analyzer.analyzeRegion(
        &controller,
        &description,
    );
    controller.samples[1][0] = std.math.nan(f64);
    try std.testing.expectError(
        error.AnalysisUnavailable,
        analyzer.analyzeRegion(&controller, &description),
    );

    var provider = TestProviderTarget.SourceProvider{};
    analyzer.configureProvider(
        TestProviderTarget,
        &provider,
    );
    const provide = provider.fades orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(
        provide(
            provider.fade_context,
            &description,
        ) != null,
    );
}
