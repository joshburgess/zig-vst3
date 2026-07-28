const std = @import("std");
const common = @import("common.zig");
const plugin_api = @import("plugin.zig");
const process_api = @import("process.zig");
const state_api = @import("state.zig");

pub const RenderStatistics = struct {
    rendered_blocks: u64 = 0,
    rendered_frames: u64 = 0,
    rejected_blocks: u64 = 0,
};

pub fn RenderOptions(comptime Sample: type) type {
    return struct {
        input_channels: []const []const Sample = &.{},
        auxiliary_input_channels: []const []const Sample = &.{},
        output_channels: []const []Sample = &.{},
        auxiliary_output_channels: []const []Sample = &.{},
        attachments: process_api.ProcessAttachments = .{},
        transport: ?process_api.Transport = null,
    };
}

pub fn RenderAdapter(
    comptime Plugin: type,
    comptime maximum_block_size: usize,
) type {
    if (maximum_block_size == 0 or
        maximum_block_size > std.math.maxInt(u32))
        @compileError("Audio Unit maximum block size must fit UInt32");

    const Runtime = plugin_api.ProcessorRuntime(Plugin);
    const Spec = plugin_api.PluginSpec(Plugin);
    if (Spec.dynamic_audio_bus_topology != null)
        @compileError(
            "Audio Unit render core requires static audio buses",
        );
    const auxiliary_input_bus_channel_counts =
        layoutChannelCounts(Spec.audio_auxiliary_input_layouts);
    const auxiliary_output_bus_channel_counts =
        layoutChannelCounts(Spec.audio_auxiliary_output_layouts);

    return struct {
        const Self = @This();

        pub const maximum_frames = maximum_block_size;
        pub const input_channel_count =
            Spec.audio_input_layout.channelCount();
        pub const output_channel_count =
            Spec.audio_output_layout.channelCount();
        pub const auxiliary_input_channel_count =
            totalLayoutChannels(Spec.audio_auxiliary_input_layouts);
        pub const auxiliary_output_channel_count =
            totalLayoutChannels(Spec.audio_auxiliary_output_layouts);
        pub const input_bus_count =
            1 + Spec.audio_auxiliary_input_layouts.len;
        pub const output_bus_count =
            1 + Spec.audio_auxiliary_output_layouts.len;
        pub const maximum_state_bytes =
            state_api.encodedSize(Plugin.Params);

        pub fn inputBusChannelCount(bus: usize) ?u32 {
            if (bus == 0)
                return input_channel_count;
            const auxiliary_index = bus - 1;
            if (auxiliary_index >= auxiliary_input_bus_channel_counts.len)
                return null;
            return @intCast(
                auxiliary_input_bus_channel_counts[auxiliary_index],
            );
        }

        pub fn outputBusChannelCount(bus: usize) ?u32 {
            if (bus == 0)
                return output_channel_count;
            const auxiliary_index = bus - 1;
            if (auxiliary_index >= auxiliary_output_bus_channel_counts.len)
                return null;
            return @intCast(
                auxiliary_output_bus_channel_counts[auxiliary_index],
            );
        }

        runtime: Runtime,
        sample_rate: f64,
        configured_maximum_frames: usize,
        process_mode: process_api.ProcessMode,
        initialized: bool = false,
        statistics: RenderStatistics = .{},

        pub fn init(
            allocator: std.mem.Allocator,
            parameters: Plugin.Params,
            sample_rate: f64,
            configured_maximum_frames: usize,
        ) !Self {
            try validateFormat(sample_rate, configured_maximum_frames);
            var runtime = try Runtime.init(allocator, parameters);
            errdefer runtime.deinit();
            try runtime.prepare(.{
                .sample_rate = sample_rate,
                .max_block_size = @intCast(configured_maximum_frames),
                .process_mode = .realtime,
            });
            return .{
                .runtime = runtime,
                .sample_rate = sample_rate,
                .configured_maximum_frames = configured_maximum_frames,
                .process_mode = .realtime,
            };
        }

        pub fn configure(
            self: *Self,
            sample_rate: f64,
            configured_maximum_frames: usize,
            process_mode: process_api.ProcessMode,
        ) !void {
            if (self.initialized)
                return error.AudioUnitInitialized;
            try validateFormat(sample_rate, configured_maximum_frames);
            try self.runtime.prepare(.{
                .sample_rate = sample_rate,
                .max_block_size = @intCast(configured_maximum_frames),
                .process_mode = process_mode,
            });
            self.sample_rate = sample_rate;
            self.configured_maximum_frames =
                configured_maximum_frames;
            self.process_mode = process_mode;
        }

        pub fn initialize(self: *Self) !void {
            if (self.initialized) return;
            try self.runtime.activate();
            self.initialized = true;
        }

        pub fn uninitialize(self: *Self) !void {
            if (!self.initialized) return;
            try self.runtime.deactivate();
            self.initialized = false;
        }

        pub fn reset(self: *Self) !void {
            if (!self.initialized)
                return error.AudioUnitUninitialized;
            try self.runtime.reset();
        }

        pub fn render(
            self: *Self,
            options: RenderOptions(f32),
        ) !void {
            try self.renderTyped(f32, options);
        }

        pub fn render64(
            self: *Self,
            options: RenderOptions(f64),
        ) !void {
            try self.renderTyped(f64, options);
        }

        pub fn latencySamples(self: *const Self) u32 {
            return self.runtime.latencySamples();
        }

        pub fn tailSamples(self: *const Self) u32 {
            return self.runtime.tailSamples();
        }

        pub fn renderStatistics(self: *const Self) RenderStatistics {
            return self.statistics;
        }

        pub fn parameterCount(self: *const Self) usize {
            return self.runtime.instance.parameterCount();
        }

        pub fn parameterId(
            self: *const Self,
            index: usize,
        ) ?u32 {
            return self.runtime.instance.parameterId(index);
        }

        pub fn parameterNameById(
            self: *const Self,
            parameter_id: u32,
        ) ?[]const u8 {
            return self.runtime.instance.parameterNameById(parameter_id);
        }

        pub fn parameterUnitsById(
            self: *const Self,
            parameter_id: u32,
        ) ?[]const u8 {
            return self.runtime.instance.parameterUnitsById(parameter_id);
        }

        pub fn parameterDefaultPlainById(
            self: *const Self,
            parameter_id: u32,
        ) ?f64 {
            return self.runtime.instance.parameterDefaultPlainById(
                parameter_id,
            );
        }

        pub fn parameterPlainMinimumById(
            self: *const Self,
            parameter_id: u32,
        ) ?f64 {
            return self.runtime.instance.parameterPlainMinimumById(
                parameter_id,
            );
        }

        pub fn parameterPlainMaximumById(
            self: *const Self,
            parameter_id: u32,
        ) ?f64 {
            return self.runtime.instance.parameterPlainMaximumById(
                parameter_id,
            );
        }

        pub fn parameterCanAutomateById(
            self: *const Self,
            parameter_id: u32,
        ) ?bool {
            return self.runtime.instance.parameterCanAutomateById(
                parameter_id,
            );
        }

        pub fn parameterIsReadOnlyById(
            self: *const Self,
            parameter_id: u32,
        ) ?bool {
            return self.runtime.instance.parameterIsReadOnlyById(
                parameter_id,
            );
        }

        pub fn parameterStepCountById(
            self: *const Self,
            parameter_id: u32,
        ) ?i32 {
            return self.runtime.instance.parameterStepCountById(
                parameter_id,
            );
        }

        pub fn parameterIsListById(
            self: *const Self,
            parameter_id: u32,
        ) ?bool {
            return self.runtime.instance.parameterIsListById(
                parameter_id,
            );
        }

        pub fn parameterNormalizedFromPlainById(
            self: *const Self,
            parameter_id: u32,
            value: f64,
        ) ?f64 {
            return self.runtime.instance.parameterNormalizedFromPlainById(
                parameter_id,
                value,
            );
        }

        pub fn loadParameterPlainById(
            self: *const Self,
            parameter_id: u32,
        ) ?f64 {
            return self.runtime.instance.loadParameterPlainById(
                parameter_id,
            );
        }

        pub fn storeParameterPlainById(
            self: *Self,
            parameter_id: u32,
            value: f64,
        ) bool {
            return self.runtime.instance.storeParameterPlainById(
                parameter_id,
                value,
            );
        }

        pub fn writeState(self: *const Self, destination: []u8) ![]const u8 {
            if (destination.len < maximum_state_bytes)
                return error.AudioUnitStateBufferTooSmall;
            var writer = std.Io.Writer.fixed(
                destination[0..maximum_state_bytes],
            );
            try self.runtime.instance.writeParameterState(&writer);
            return writer.buffered();
        }

        pub fn readState(self: *Self, source: []const u8) !void {
            var reader = std.Io.Reader.fixed(source);
            try self.runtime.instance.readParameterState(&reader);
            if (reader.seek != reader.end)
                return error.InvalidAudioUnitState;
        }

        pub fn deinit(self: *Self) void {
            self.runtime.deinit();
            self.initialized = false;
        }

        fn renderTyped(
            self: *Self,
            comptime Sample: type,
            options: RenderOptions(Sample),
        ) !void {
            self.renderTypedChecked(Sample, options) catch |err| {
                clearOutputs(Sample, options.output_channels);
                clearOutputs(
                    Sample,
                    options.auxiliary_output_channels,
                );
                self.statistics.rejected_blocks +|= 1;
                return err;
            };
        }

        fn renderTypedChecked(
            self: *Self,
            comptime Sample: type,
            options: RenderOptions(Sample),
        ) !void {
            if (!self.initialized)
                return error.AudioUnitUninitialized;
            const frame_count = try renderFrameCount(
                Sample,
                options,
            );
            if (frame_count > self.configured_maximum_frames)
                return error.AudioUnitBlockTooLarge;
            if (options.input_channels.len != input_channel_count or
                options.auxiliary_input_channels.len !=
                    auxiliary_input_channel_count or
                options.output_channels.len != output_channel_count or
                options.auxiliary_output_channels.len !=
                    auxiliary_output_channel_count)
                return error.AudioUnitChannelCountMismatch;

            var context =
                try process_api.BoundedProcessContext(
                    Sample,
                    Spec.auxiliary_audio_bus_capacity,
                ).initWithOptions(.{
                    .sample_rate = self.sample_rate,
                    .process_mode = self.process_mode,
                    .input_channels = options.input_channels,
                    .sidechain_input_channels = options.auxiliary_input_channels,
                    .auxiliary_input_bus_channel_counts = &auxiliary_input_bus_channel_counts,
                    .output_channels = options.output_channels,
                    .auxiliary_output_channels = options.auxiliary_output_channels,
                    .auxiliary_output_bus_channel_counts = &auxiliary_output_bus_channel_counts,
                    .attachments = options.attachments,
                    .transport = options.transport,
                });
            if (Sample == f32) {
                try self.runtime.process(&context);
            } else if (Sample == f64) {
                try self.runtime.process64(&context);
            } else {
                @compileError("Audio Unit samples must be f32 or f64");
            }
            self.statistics.rendered_blocks +|= 1;
            self.statistics.rendered_frames +|= frame_count;
        }

        fn validateFormat(
            sample_rate: f64,
            configured_maximum_frames: usize,
        ) !void {
            if (!common.isPositiveFinite(sample_rate))
                return error.InvalidSampleRate;
            if (configured_maximum_frames == 0 or
                configured_maximum_frames > maximum_block_size)
                return error.InvalidAudioUnitMaximumFrames;
        }
    };
}

fn layoutChannelCounts(
    comptime layouts: []const process_api.AudioBusLayout,
) [layouts.len]usize {
    var counts: [layouts.len]usize = undefined;
    for (layouts, 0..) |layout, index|
        counts[index] = layout.channelCount();
    return counts;
}

fn totalLayoutChannels(
    comptime layouts: []const process_api.AudioBusLayout,
) usize {
    var total: usize = 0;
    for (layouts) |layout|
        total += layout.channelCount();
    return total;
}

fn renderFrameCount(
    comptime Sample: type,
    options: RenderOptions(Sample),
) !usize {
    var frame_count: ?usize = null;
    inline for (.{
        options.input_channels,
        options.auxiliary_input_channels,
        options.output_channels,
        options.auxiliary_output_channels,
    }) |channels| {
        for (channels) |channel| {
            if (frame_count) |expected| {
                if (channel.len != expected)
                    return error.AudioUnitFrameCountMismatch;
            } else {
                frame_count = channel.len;
            }
        }
    }
    return frame_count orelse 0;
}

fn clearOutputs(
    comptime Sample: type,
    channels: []const []Sample,
) void {
    for (channels) |channel| @memset(channel, 0);
}

const TestProcessor = struct {
    pub const name = "Audio Unit Test";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: process_api.AudioBusLayout = .mono;
    pub const audio_output_layout: process_api.AudioBusLayout = .mono;
    pub const audio_auxiliary_input_layouts: []const process_api.AudioBusLayout = &.{.mono};
    pub const audio_auxiliary_output_layouts: []const process_api.AudioBusLayout = &.{.mono};
    pub const Params = struct {
        gain: @import("parameters.zig").FloatParam = .{
            .id = 7,
            .name = "Gain",
            .min = 0.0,
            .max = 2.0,
            .default = 1.0,
        },
    };

    resets: usize = 0,

    pub fn process(
        self: *@This(),
        context: *process_api.ProcessContext(f32),
    ) void {
        _ = self;
        processSamples(f32, context);
    }

    pub fn process64(
        self: *@This(),
        context: *process_api.ProcessContext(f64),
    ) void {
        _ = self;
        processSamples(f64, context);
    }

    pub fn reset(self: *@This()) void {
        self.resets += 1;
    }

    fn processSamples(
        comptime Sample: type,
        context: *process_api.ProcessContext(Sample),
    ) void {
        const input = context.inputChannel(0) orelse return;
        const sidechain = context.sidechainInputChannel(0) orelse
            return;
        const output = context.outputChannel(0) orelse return;
        const auxiliary = context.auxiliaryOutputChannel(0) orelse
            return;
        for (input, sidechain, output, auxiliary, 0..) |
            sample,
            sidechain_sample,
            *destination,
            *auxiliary_destination,
            frame,
        | {
            const normalized =
                context.parameterNormalizedAtOrBeforeOr(
                    7,
                    frame,
                    0.5,
                );
            const gain: Sample = @floatCast(normalized * 2.0);
            destination.* = (sample + sidechain_sample) * gain;
            auxiliary_destination.* = sample - sidechain_sample;
        }
    }
};

test "Audio Unit render core covers lifecycle buses precision and automation" {
    const Adapter = RenderAdapter(TestProcessor, 16);
    var adapter = try Adapter.init(
        std.testing.allocator,
        .{},
        48_000.0,
        8,
    );
    defer adapter.deinit();

    var input = [_]f32{ 1, 2, 3, 4 };
    var sidechain = [_]f32{ 0.5, 0.5, 0.5, 0.5 };
    var output = [_]f32{0} ** 4;
    var auxiliary = [_]f32{0} ** 4;
    const changes = [_]process_api.ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 0.5 },
        .{ .id = 7, .sample_offset = 2, .normalized = 1.0 },
    };

    try std.testing.expectError(
        error.AudioUnitUninitialized,
        adapter.render(.{
            .input_channels = &.{&input},
            .auxiliary_input_channels = &.{&sidechain},
            .output_channels = &.{&output},
            .auxiliary_output_channels = &.{&auxiliary},
        }),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 0, 0, 0 },
        &output,
    );

    try adapter.initialize();
    try adapter.initialize();
    try adapter.render(.{
        .input_channels = &.{&input},
        .auxiliary_input_channels = &.{&sidechain},
        .output_channels = &.{&output},
        .auxiliary_output_channels = &.{&auxiliary},
        .attachments = .{ .parameter_changes = &changes },
    });
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1.5, 2.5, 7.0, 9.0 },
        &output,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, 1.5, 2.5, 3.5 },
        &auxiliary,
    );
    try std.testing.expectEqual(
        RenderStatistics{
            .rendered_blocks = 1,
            .rendered_frames = 4,
            .rejected_blocks = 1,
        },
        adapter.renderStatistics(),
    );

    try adapter.reset();
    try std.testing.expectEqual(
        @as(usize, 1),
        adapter.runtime.instance.plugin.resets,
    );
    try adapter.uninitialize();
    try adapter.uninitialize();
    try adapter.configure(96_000.0, 16, .offline);
    try adapter.initialize();

    var input64 = [_]f64{ 2, 4 };
    var sidechain64 = [_]f64{ 1, 1 };
    var output64 = [_]f64{ 0, 0 };
    var auxiliary64 = [_]f64{ 0, 0 };
    const changes64 = [_]process_api.ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 1.0 },
    };
    try adapter.render64(.{
        .input_channels = &.{&input64},
        .auxiliary_input_channels = &.{&sidechain64},
        .output_channels = &.{&output64},
        .auxiliary_output_channels = &.{&auxiliary64},
        .attachments = .{ .parameter_changes = &changes64 },
    });
    try std.testing.expectEqualSlices(
        f64,
        &.{ 6, 10 },
        &output64,
    );
}

test "Audio Unit render core carries selected auxiliary bus capacity" {
    const Probe = struct {
        pub const name = "Audio Unit Large Bus Probe";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const maximum_auxiliary_audio_buses = 12;
        pub const audio_input_layout: process_api.AudioBusLayout = .mono;
        pub const audio_output_layout: process_api.AudioBusLayout = .none;
        pub const auxiliary_layouts =
            [_]process_api.AudioBusLayout{.mono} ** 12;
        pub const audio_auxiliary_input_layouts: []const process_api.AudioBusLayout =
            &auxiliary_layouts;

        auxiliary_input_count: usize = 0,

        pub fn process(
            self: *@This(),
            context: *process_api.BoundedProcessContext(
                f32,
                maximum_auxiliary_audio_buses,
            ),
        ) void {
            self.auxiliary_input_count =
                context.auxiliaryInputBusCount();
        }
    };
    const Adapter = RenderAdapter(Probe, 1);
    var adapter = try Adapter.init(
        std.testing.allocator,
        .{},
        48_000.0,
        1,
    );
    defer adapter.deinit();
    try adapter.initialize();
    const main_input = [_]f32{1.0};
    const auxiliary_samples =
        [_][1]f32{.{2.0}} **
        Probe.maximum_auxiliary_audio_buses;
    var auxiliary_inputs: [Probe.maximum_auxiliary_audio_buses][]const f32 =
        undefined;
    for (&auxiliary_samples, &auxiliary_inputs) |*samples, *view|
        view.* = samples;

    try adapter.render(.{
        .input_channels = &.{&main_input},
        .auxiliary_input_channels = &auxiliary_inputs,
    });
    try std.testing.expectEqual(
        @as(usize, 13),
        Adapter.input_bus_count,
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        adapter.runtime.instance.plugin
            .auxiliary_input_count,
    );
}

test "Audio Unit render core rejects malformed blocks with silence" {
    const Adapter = RenderAdapter(TestProcessor, 4);
    var adapter = try Adapter.init(
        std.testing.allocator,
        .{},
        48_000.0,
        4,
    );
    defer adapter.deinit();
    try adapter.initialize();

    var input = [_]f32{ 1, 2, 3, 4, 5 };
    var sidechain = [_]f32{ 1, 2, 3, 4, 5 };
    var output = [_]f32{1} ** 5;
    var auxiliary = [_]f32{1} ** 5;
    try std.testing.expectError(
        error.AudioUnitBlockTooLarge,
        adapter.render(.{
            .input_channels = &.{&input},
            .auxiliary_input_channels = &.{&sidechain},
            .output_channels = &.{&output},
            .auxiliary_output_channels = &.{&auxiliary},
        }),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 0, 0, 0, 0 },
        &output,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 0, 0, 0, 0 },
        &auxiliary,
    );

    var short_output = [_]f32{ 1, 1, 1 };
    try std.testing.expectError(
        error.AudioUnitFrameCountMismatch,
        adapter.render(.{
            .input_channels = &.{input[0..4]},
            .auxiliary_input_channels = &.{sidechain[0..4]},
            .output_channels = &.{&short_output},
            .auxiliary_output_channels = &.{auxiliary[0..4]},
        }),
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 0, 0 },
        &short_output,
    );
}

test "Audio Unit render core validates negotiated format" {
    const Adapter = RenderAdapter(TestProcessor, 32);
    try std.testing.expectError(
        error.InvalidSampleRate,
        Adapter.init(std.testing.allocator, .{}, 0.0, 16),
    );
    try std.testing.expectError(
        error.InvalidAudioUnitMaximumFrames,
        Adapter.init(std.testing.allocator, .{}, 48_000.0, 0),
    );
    try std.testing.expectError(
        error.InvalidAudioUnitMaximumFrames,
        Adapter.init(std.testing.allocator, .{}, 48_000.0, 33),
    );
}
