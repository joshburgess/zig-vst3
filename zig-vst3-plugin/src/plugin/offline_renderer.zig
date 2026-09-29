const std = @import("std");
const process_api = @import("../process.zig");
const runtime_mod = @import("runtime.zig");

pub fn OfflineRenderer(
    comptime Plugin: type,
    comptime Sample: type,
    comptime max_block_size: usize,
    comptime max_parameter_changes_per_block: usize,
    comptime max_events_per_block: usize,
    comptime max_output_events_per_block: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("OfflineRenderer Sample must be f32 or f64");
    if (max_block_size == 0)
        @compileError("OfflineRenderer max_block_size must be nonzero");
    if (max_block_size > std.math.maxInt(u32))
        @compileError("OfflineRenderer max_block_size exceeds u32");

    const RuntimeType = runtime_mod.ProcessorRuntime(Plugin);
    const auxiliary_audio_bus_capacity =
        RuntimeType.Instance.Spec.auxiliary_audio_bus_capacity;

    return struct {
        const Self = @This();

        pub const Runtime = RuntimeType;
        pub const RenderOptions = struct {
            sample_rate: f64,
            input_channels: []const []const Sample = &.{},
            sidechain_input_channels: []const []const Sample = &.{},
            auxiliary_input_bus_channel_counts: []const usize = &.{},
            output_channels: []const []Sample = &.{},
            auxiliary_output_channels: []const []Sample = &.{},
            auxiliary_output_bus_channel_counts: []const usize = &.{},
            parameter_changes: []const process_api.ParameterChange = &.{},
            events: []const process_api.Event = &.{},
            output_events: ?*process_api.EventWriter = null,
            transport: ?process_api.Transport = null,
        };

        runtime: Runtime,

        pub fn init(
            allocator: std.mem.Allocator,
            params: Plugin.Params,
        ) !Self {
            return .{
                .runtime = try Runtime.init(allocator, params),
            };
        }

        pub fn render(
            self: *Self,
            options: RenderOptions,
        ) !void {
            const frame_count = try validateOptions(options);
            try validateBlockCapacities(
                options.parameter_changes,
                options.events,
                frame_count,
            );
            try self.runtime.prepare(.{
                .sample_rate = options.sample_rate,
                .max_block_size = max_block_size,
                .process_mode = .offline,
            });
            errdefer self.stopAfterFailure();
            try self.runtime.activate();
            defer {
                self.runtime.deactivate() catch {};
                self.runtime.releaseResources() catch {};
            }

            var input_headers: [process_api.max_audio_channels][]const Sample =
                [_][]const Sample{&.{}} **
                process_api.max_audio_channels;
            var sidechain_headers: [process_api.max_audio_channels][]const Sample =
                [_][]const Sample{&.{}} **
                process_api.max_audio_channels;
            var output_headers: [process_api.max_audio_channels][]Sample =
                [_][]Sample{&.{}} **
                process_api.max_audio_channels;
            var auxiliary_output_headers: [process_api.max_audio_channels][]Sample =
                [_][]Sample{&.{}} **
                process_api.max_audio_channels;
            var change_storage: [max_parameter_changes_per_block]process_api.ParameterChange = undefined;
            var event_storage: [max_events_per_block]process_api.Event = undefined;
            var output_event_storage: [max_output_events_per_block]process_api.Event = undefined;

            var start: usize = 0;
            while (start < frame_count) {
                const end = @min(start + max_block_size, frame_count);
                sliceConstChannels(
                    Sample,
                    options.input_channels,
                    start,
                    end,
                    &input_headers,
                );
                sliceConstChannels(
                    Sample,
                    options.sidechain_input_channels,
                    start,
                    end,
                    &sidechain_headers,
                );
                sliceChannels(
                    Sample,
                    options.output_channels,
                    start,
                    end,
                    &output_headers,
                );
                sliceChannels(
                    Sample,
                    options.auxiliary_output_channels,
                    start,
                    end,
                    &auxiliary_output_headers,
                );
                const block_changes = collectChanges(
                    options.parameter_changes,
                    start,
                    end,
                    &change_storage,
                );
                const block_events = collectEvents(
                    options.events,
                    start,
                    end,
                    &event_storage,
                );
                var block_output_events =
                    process_api.EventWriter.init(
                        &output_event_storage,
                        end - start,
                    );
                var context =
                    try process_api.BoundedProcessContext(
                        Sample,
                        auxiliary_audio_bus_capacity,
                    ).initWithOptions(.{
                        .sample_rate = options.sample_rate,
                        .process_mode = .offline,
                        .input_channels = input_headers[0..options.input_channels.len],
                        .sidechain_input_channels = sidechain_headers[0..options.sidechain_input_channels.len],
                        .auxiliary_input_bus_channel_counts = options.auxiliary_input_bus_channel_counts,
                        .output_channels = output_headers[0..options.output_channels.len],
                        .auxiliary_output_channels = auxiliary_output_headers[0..options.auxiliary_output_channels.len],
                        .auxiliary_output_bus_channel_counts = options.auxiliary_output_bus_channel_counts,
                        .attachments = .{
                            .parameter_changes = block_changes,
                            .events = block_events,
                            .output_events = if (options.output_events != null)
                                &block_output_events
                            else
                                null,
                        },
                        .transport = advanceTransport(
                            options.transport,
                            options.sample_rate,
                            start,
                        ),
                    });
                if (Sample == f32)
                    try self.runtime.process(&context)
                else
                    try self.runtime.process64(&context);
                if (options.output_events) |destination| {
                    try appendOutputEvents(
                        destination,
                        block_output_events.events(),
                        start,
                    );
                }
                start = end;
            }
        }

        pub fn deinit(self: *Self) void {
            self.runtime.deinit();
        }

        fn stopAfterFailure(self: *Self) void {
            if (self.runtime.runtimeState() == .active)
                self.runtime.deactivate() catch {};
            if (self.runtime.runtimeState() == .prepared)
                self.runtime.releaseResources() catch {};
        }

        fn validateOptions(options: RenderOptions) !usize {
            const context =
                try process_api.BoundedProcessContext(
                    Sample,
                    auxiliary_audio_bus_capacity,
                ).initWithOptions(.{
                    .sample_rate = options.sample_rate,
                    .process_mode = .offline,
                    .input_channels = options.input_channels,
                    .sidechain_input_channels = options.sidechain_input_channels,
                    .auxiliary_input_bus_channel_counts = options.auxiliary_input_bus_channel_counts,
                    .output_channels = options.output_channels,
                    .auxiliary_output_channels = options.auxiliary_output_channels,
                    .auxiliary_output_bus_channel_counts = options.auxiliary_output_bus_channel_counts,
                    .attachments = .{
                        .parameter_changes = options.parameter_changes,
                        .events = options.events,
                        .output_events = options.output_events,
                    },
                    .transport = options.transport,
                });
            return context.frameCount();
        }

        fn validateBlockCapacities(
            changes: []const process_api.ParameterChange,
            events: []const process_api.Event,
            frame_count: usize,
        ) !void {
            var start: usize = 0;
            while (start < frame_count) {
                const end = @min(start + max_block_size, frame_count);
                var change_count: usize = 0;
                for (changes) |change| {
                    if (change.sample_offset >= start and
                        change.sample_offset < end)
                        change_count += 1;
                }
                if (change_count > max_parameter_changes_per_block)
                    return error.TooManyParameterChanges;
                var event_count: usize = 0;
                for (events) |event| {
                    if (event.sample_offset >= start and
                        event.sample_offset < end)
                        event_count += 1;
                }
                if (event_count > max_events_per_block)
                    return error.TooManyEvents;
                start = end;
            }
        }

        fn collectChanges(
            source: []const process_api.ParameterChange,
            start: usize,
            end: usize,
            storage: *[max_parameter_changes_per_block]process_api.ParameterChange,
        ) []const process_api.ParameterChange {
            if (comptime max_parameter_changes_per_block == 0)
                return &.{};
            var count: usize = 0;
            for (source) |change| {
                if (change.sample_offset < start or
                    change.sample_offset >= end)
                    continue;
                storage[count] = change;
                storage[count].sample_offset -= start;
                count += 1;
            }
            return storage[0..count];
        }

        fn collectEvents(
            source: []const process_api.Event,
            start: usize,
            end: usize,
            storage: *[max_events_per_block]process_api.Event,
        ) []const process_api.Event {
            if (comptime max_events_per_block == 0)
                return &.{};
            var count: usize = 0;
            for (source) |event| {
                if (event.sample_offset < start or
                    event.sample_offset >= end)
                    continue;
                storage[count] =
                    event.withSampleOffset(event.sample_offset - start);
                count += 1;
            }
            return storage[0..count];
        }

        fn appendOutputEvents(
            destination: *process_api.EventWriter,
            source: process_api.Events,
            block_start: usize,
        ) !void {
            for (source.items) |event|
                try destination.append(
                    event.withSampleOffset(
                        event.sample_offset + block_start,
                    ),
                );
        }
    };
}

fn sliceConstChannels(
    comptime Sample: type,
    source: []const []const Sample,
    start: usize,
    end: usize,
    destination: *[process_api.max_audio_channels][]const Sample,
) void {
    for (source, 0..) |channel, index|
        destination[index] = channel[start..end];
}

fn sliceChannels(
    comptime Sample: type,
    source: []const []Sample,
    start: usize,
    end: usize,
    destination: *[process_api.max_audio_channels][]Sample,
) void {
    for (source, 0..) |channel, index|
        destination[index] = channel[start..end];
}

fn advanceTransport(
    source: ?process_api.Transport,
    sample_rate: f64,
    sample_offset: usize,
) ?process_api.Transport {
    var transport = source orelse return null;
    const offset =
        std.math.cast(i64, sample_offset) orelse std.math.maxInt(i64);
    transport.project_time_samples =
        std.math.add(
            i64,
            transport.project_time_samples,
            offset,
        ) catch std.math.maxInt(i64);
    if (transport.tempo_bpm) |tempo| {
        const quarter_note_offset =
            @as(f64, @floatFromInt(sample_offset)) /
            sample_rate *
            tempo /
            60.0;
        if (transport.project_quarter_notes) |position|
            transport.project_quarter_notes =
                position + quarter_note_offset;
        if (transport.bar_position_quarter_notes) |position|
            transport.bar_position_quarter_notes =
                position + quarter_note_offset;
    }
    return transport;
}

test "offline renderer partitions automation events transport and output events" {
    const Gain = struct {
        block_count: usize = 0,
        project_times: [3]i64 = @splat(0),
        quarter_note_positions: [3]f64 = @splat(0.0),

        pub const name = "Offline Runtime Gain";
        pub const vendor = "zig-vst3";
        pub const event_output = true;
        pub const Params = struct {
            gain: @import("../parameters.zig").FloatParam =
                @import("../parameters.zig").FloatParam.init(
                    0,
                    "Gain",
                    0.0,
                    1.0,
                    1.0,
                ),
        };

        pub fn processWithParameterView(
            self: *@This(),
            context: *process_api.ProcessContext(f32),
            view: @import("../parameters.zig").ParameterView(Params),
        ) void {
            self.project_times[self.block_count] =
                context.transport().?.project_time_samples;
            self.quarter_note_positions[self.block_count] =
                context.transport().?.project_quarter_notes.?;
            self.block_count += 1;
            const gain: f32 = @floatCast(view.load("gain"));
            for (0..context.outputChannelCount()) |channel_index| {
                const input =
                    context.inputChannel(channel_index) orelse continue;
                const output =
                    context.outputChannel(channel_index) orelse continue;
                for (input, output) |input_sample, *output_sample|
                    output_sample.* = input_sample * gain;
            }
            for (context.inputEvents().items) |event|
                context.appendOutputEvent(event) catch {};
        }
    };

    const Renderer = OfflineRenderer(Gain, f32, 3, 2, 2, 2);
    var renderer = try Renderer.init(std.testing.allocator, .{});
    defer renderer.deinit();
    const input = [_]f32{1.0} ** 7;
    var output = [_]f32{0.0} ** input.len;
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    const changes = [_]process_api.ParameterChange{
        .{ .id = 0, .sample_offset = 3, .normalized = 0.5 },
    };
    const events = [_]process_api.Event{
        process_api.Event.noteOn(2, 0, 60, 0.75),
        process_api.Event.noteOff(5, 0, 60, 0.0),
    };
    var output_event_storage: [2]process_api.Event = undefined;
    var output_events =
        process_api.EventWriter.init(
            &output_event_storage,
            input.len,
        );
    try renderer.render(.{
        .sample_rate = 48_000.0,
        .input_channels = &inputs,
        .output_channels = &outputs,
        .parameter_changes = &changes,
        .events = &events,
        .output_events = &output_events,
        .transport = .{
            .project_time_samples = 100,
            .state_valid = true,
            .playing = true,
            .tempo_bpm = 120.0,
            .project_quarter_notes = 2.0,
        },
    });

    try std.testing.expectEqualSlices(
        f32,
        &.{ 1.0, 1.0, 1.0, 0.5, 0.5, 0.5, 0.5 },
        &output,
    );
    try std.testing.expectEqualSlices(
        i64,
        &.{ 100, 103, 106 },
        &renderer.runtime.instance.plugin.project_times,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        renderer.runtime.instance.plugin.quarter_note_positions[0],
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.000125),
        renderer.runtime.instance.plugin.quarter_note_positions[1],
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.00025),
        renderer.runtime.instance.plugin.quarter_note_positions[2],
        1.0e-12,
    );
    try std.testing.expectEqual(@as(usize, 2), output_events.eventCount());
    try std.testing.expectEqual(
        @as(usize, 2),
        output_events.events().items[0].sample_offset,
    );
    try std.testing.expectEqual(
        @as(usize, 5),
        output_events.events().items[1].sample_offset,
    );
}

test "offline renderer dispatches f64 processors" {
    const DoubleGain = struct {
        pub const name = "Offline Double Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};

        pub fn process64(
            _: *@This(),
            context: *process_api.ProcessContext(f64),
        ) void {
            for (0..context.outputChannelCount()) |channel_index| {
                const input =
                    context.inputChannel(channel_index) orelse continue;
                const output =
                    context.outputChannel(channel_index) orelse continue;
                for (input, output) |input_sample, *output_sample|
                    output_sample.* = input_sample * 2.0;
            }
        }
    };

    const Renderer =
        OfflineRenderer(DoubleGain, f64, 2, 0, 0, 0);
    var renderer = try Renderer.init(std.testing.allocator, .{});
    defer renderer.deinit();
    const input = [_]f64{ 0.25, -0.5, 1.0 };
    var output = [_]f64{0.0} ** input.len;
    const inputs = [_][]const f64{&input};
    const outputs = [_][]f64{&output};
    try renderer.render(.{
        .sample_rate = 96_000.0,
        .input_channels = &inputs,
        .output_channels = &outputs,
    });
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.5, -1.0, 2.0 },
        &output,
    );
}

test "offline renderer carries selected auxiliary bus capacity" {
    const Probe = struct {
        pub const name = "Offline Large Bus Probe";
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
    const Renderer =
        OfflineRenderer(Probe, f32, 2, 0, 0, 0);
    var renderer = try Renderer.init(std.testing.allocator, .{});
    defer renderer.deinit();
    const main_input = [_]f32{ 1.0, 2.0 };
    const auxiliary_samples =
        [_][2]f32{.{ 3.0, 4.0 }} **
        Probe.maximum_auxiliary_audio_buses;
    var auxiliary_inputs: [Probe.maximum_auxiliary_audio_buses][]const f32 =
        undefined;
    for (&auxiliary_samples, &auxiliary_inputs) |*samples, *view|
        view.* = samples;
    const channel_counts =
        [_]usize{1} ** Probe.maximum_auxiliary_audio_buses;

    try renderer.render(.{
        .sample_rate = 48_000.0,
        .input_channels = &.{&main_input},
        .sidechain_input_channels = &auxiliary_inputs,
        .auxiliary_input_bus_channel_counts = &channel_counts,
    });
    try std.testing.expectEqual(
        @as(usize, 12),
        renderer.runtime.instance.plugin
            .auxiliary_input_count,
    );
}

test "offline renderer rejects per-block attachment overflow before processing" {
    const Monitor = struct {
        process_count: usize = 0,

        pub const name = "Offline Capacity";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};

        pub fn process(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {
            self.process_count += 1;
        }
    };

    const Renderer = OfflineRenderer(Monitor, f32, 4, 1, 1, 1);
    var renderer = try Renderer.init(std.testing.allocator, .{});
    defer renderer.deinit();
    var output = [_]f32{0.0} ** 4;
    const outputs = [_][]f32{&output};
    const events = [_]process_api.Event{
        process_api.Event.noteOn(0, 0, 60, 0.5),
        process_api.Event.noteOff(1, 0, 60, 0.0),
    };
    try std.testing.expectError(
        error.TooManyEvents,
        renderer.render(.{
            .sample_rate = 48_000.0,
            .output_channels = &outputs,
            .events = &events,
        }),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        renderer.runtime.instance.plugin.process_count,
    );
    try std.testing.expectEqual(
        runtime_mod.RuntimeState.initialized,
        renderer.runtime.runtimeState(),
    );
}
