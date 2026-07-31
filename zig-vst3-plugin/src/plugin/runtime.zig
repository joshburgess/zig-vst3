const std = @import("std");
const common = @import("../common.zig");
const parameters = @import("../parameters.zig");
const process_api = @import("../process.zig");
const instance_mod = @import("instance.zig");

pub const RuntimeState = enum {
    initialized,
    prepared,
    active,
};

pub fn ProcessorRuntime(comptime Plugin: type) type {
    return struct {
        const Self = @This();

        pub const Instance = instance_mod.PluginInstance(Plugin);

        instance: Instance,
        state: RuntimeState = .initialized,
        prepare_config: ?instance_mod.PrepareConfig = null,

        pub fn initInto(
            self: *Self,
            allocator: std.mem.Allocator,
            params: Plugin.Params,
        ) !void {
            try self.instance.initInto(allocator, params);
            self.state = .initialized;
            self.prepare_config = null;
        }

        pub fn init(
            allocator: std.mem.Allocator,
            params: Plugin.Params,
        ) !Self {
            var self: Self = undefined;
            try self.initInto(allocator, params);
            return self;
        }

        pub fn runtimeState(self: *const Self) RuntimeState {
            return self.state;
        }

        pub fn prepare(
            self: *Self,
            config: instance_mod.PrepareConfig,
        ) !void {
            if (self.state == .active) return error.ProcessorActive;
            try config.validate();
            if (self.state == .prepared) {
                self.instance.releaseResources();
                self.prepare_config = null;
                self.state = .initialized;
            }
            try self.instance.prepareChecked(config);
            self.prepare_config = config;
            self.state = .prepared;
        }

        pub fn activate(self: *Self) !void {
            if (self.state == .active) return error.ProcessorAlreadyActive;
            if (self.state != .prepared) return error.ProcessorNotPrepared;
            self.instance.activate();
            self.state = .active;
        }

        pub fn deactivate(self: *Self) !void {
            if (self.state != .active) return error.ProcessorNotActive;
            self.instance.deactivate();
            self.instance.reset();
            self.state = .prepared;
        }

        pub fn reset(self: *Self) !void {
            if (self.state == .initialized)
                return error.ProcessorNotPrepared;
            self.instance.reset();
        }

        pub fn releaseResources(self: *Self) !void {
            if (self.state == .active) return error.ProcessorActive;
            if (self.state != .prepared)
                return error.ProcessorNotPrepared;
            self.instance.releaseResources();
            self.prepare_config = null;
            self.state = .initialized;
        }

        pub fn process(
            self: *Self,
            context: *process_api.BoundedProcessContext(
                f32,
                Instance.Spec.auxiliary_audio_bus_capacity,
            ),
        ) !void {
            if (!Instance.Spec.has_process32_hook)
                return error.UnsupportedSamplePrecision;
            try self.validateContext(f32, context);
            self.instance.process(context);
        }

        pub fn process64(
            self: *Self,
            context: *process_api.BoundedProcessContext(
                f64,
                Instance.Spec.auxiliary_audio_bus_capacity,
            ),
        ) !void {
            if (!Instance.Spec.has_process64_hook)
                return error.UnsupportedSamplePrecision;
            try self.validateContext(f64, context);
            self.instance.process64(context);
        }

        pub fn flushParameterChanges(
            self: *Self,
            changes: process_api.ParameterChanges,
            frame_count: usize,
        ) !usize {
            if (!changes.valid(frame_count))
                return error.InvalidParameterChanges;
            return self.instance.applyParameterChangesChangedCount(changes);
        }

        pub fn latencySamples(self: *const Self) u32 {
            return self.instance.latencySamples();
        }

        pub fn tailSamples(self: *const Self) u32 {
            return self.instance.tailSamples();
        }

        pub fn writeParameterState(
            self: *const Self,
            writer: anytype,
        ) !void {
            try self.instance.writeParameterState(writer);
        }

        pub fn readParameterState(
            self: *Self,
            reader: anytype,
        ) !void {
            if (self.state == .active) return error.ProcessorActive;
            try self.readParameterStateExclusive(reader);
        }

        /// Caller must exclude process and lifecycle calls while this runs.
        pub fn readParameterStateExclusive(
            self: *Self,
            reader: anytype,
        ) !void {
            try self.instance.readParameterState(reader);
            self.instance.afterStateRestore();
        }

        pub fn deinit(self: *Self) void {
            if (self.state == .active) {
                self.instance.deactivate();
                self.instance.reset();
            }
            if (self.state != .initialized)
                self.instance.releaseResources();
            self.state = .initialized;
            self.prepare_config = null;
            self.instance.deinit();
        }

        fn validateContext(
            self: *const Self,
            comptime Sample: type,
            context: *const process_api.BoundedProcessContext(
                Sample,
                Instance.Spec.auxiliary_audio_bus_capacity,
            ),
        ) !void {
            if (self.state != .active) return error.ProcessorNotActive;
            const config = self.prepare_config orelse
                return error.ProcessorNotPrepared;
            if (!common.isPositiveFinite(context.sampleRate()))
                return error.InvalidSampleRate;
            if (context.sampleRate() != config.sample_rate)
                return error.SampleRateMismatch;
            if (context.processMode() != config.process_mode and
                !Instance.Spec.allow_dynamic_process_mode)
                return error.ProcessModeMismatch;
            if (context.frameCount() > config.max_block_size)
                return error.BlockTooLarge;
            if (!context.inputs.valid() or
                !context.sidechain_inputs.valid() or
                !context.outputs.valid() or
                !context.auxiliary_outputs.valid())
                return error.InvalidAudioBuffers;
            const frame_count = context.frameCount();
            if (context.inputs.hasChannels() and
                context.outputs.hasChannels() and
                context.inputFrameCount() !=
                    context.outputFrameCount())
                return error.InvalidAudioBuffers;
            if (context.sidechain_inputs.hasChannels() and
                context.sidechainInputFrameCount() != frame_count)
                return error.InvalidAudioBuffers;
            if (context.auxiliary_outputs.hasChannels() and
                context.auxiliaryOutputFrameCount() != frame_count)
                return error.InvalidAudioBuffers;
            if (!context.auxiliary_input_ranges.valid(
                context.sidechain_inputs.channelCount(),
            ) or
                !context.auxiliary_output_ranges.valid(
                    context.auxiliary_outputs.channelCount(),
                ))
                return error.InvalidAudioBuffers;
            if (!context.parameter_changes.valid(frame_count))
                return error.InvalidParameterChanges;
            if (!context.events.valid(frame_count))
                return error.InvalidEvents;
            if (context.host_transport) |transport| {
                if (!transport.valid()) return error.InvalidTransport;
            }
            if (context.output_events) |writer| {
                if (!writer.valid() or
                    writer.frame_count != frame_count)
                    return error.InvalidOutputEvents;
            }
        }
    };
}

test "processor runtime enforces lifecycle and carries host-neutral process data" {
    const Gain = struct {
        prepare_count: usize = 0,
        activate_count: usize = 0,
        deactivate_count: usize = 0,
        reset_count: usize = 0,
        release_count: usize = 0,
        process_count: usize = 0,
        restored_count: usize = 0,
        observed_tempo: ?f64 = null,
        observed_pitch: ?i16 = null,

        pub const name = "Runtime Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam =
                parameters.FloatParam.init(
                    0,
                    "Gain",
                    0.0,
                    1.0,
                    0.5,
                ),
        };

        pub fn prepare(
            self: *@This(),
            _: instance_mod.PrepareConfig,
        ) void {
            self.prepare_count += 1;
        }

        pub fn activate(self: *@This()) void {
            self.activate_count += 1;
        }

        pub fn deactivate(self: *@This()) void {
            self.deactivate_count += 1;
        }

        pub fn reset(self: *@This()) void {
            self.reset_count += 1;
        }

        pub fn releaseResources(self: *@This()) void {
            self.release_count += 1;
        }

        pub fn afterStateRestore(self: *@This()) void {
            self.restored_count += 1;
        }

        pub fn processWithParameterView(
            self: *@This(),
            context: *process_api.ProcessContext(f32),
            parameter_view: parameters.ParameterView(Params),
        ) void {
            self.process_count += 1;
            self.observed_tempo = context.hostTempoBpm();
            if (context.firstEvent(.note_on)) |event|
                self.observed_pitch = event.pitch;
            const gain: f32 =
                @floatCast(parameter_view.load("gain"));
            for (0..context.outputChannelCount()) |channel_index| {
                const input =
                    context.inputChannel(channel_index) orelse continue;
                const output =
                    context.outputChannel(channel_index) orelse continue;
                for (input, output) |input_sample, *output_sample|
                    output_sample.* = input_sample * gain;
            }
        }
    };

    var runtime: ProcessorRuntime(Gain) = undefined;
    try runtime.initInto(std.testing.allocator, .{});
    defer runtime.deinit();

    try std.testing.expectError(
        error.ProcessorNotPrepared,
        runtime.activate(),
    );
    try runtime.prepare(.{
        .sample_rate = 48_000.0,
        .max_block_size = 4,
        .process_mode = .offline,
    });
    try runtime.activate();

    const input = [_]f32{ 1.0, 0.5, -0.5, -1.0 };
    var output = [_]f32{0.0} ** input.len;
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    const changes = [_]process_api.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.25 },
    };
    const events = [_]process_api.Event{
        process_api.Event.noteOn(2, 0, 64, 0.75),
    };
    var context =
        try process_api.ProcessContext(f32).initWithOptions(.{
            .sample_rate = 48_000.0,
            .process_mode = .offline,
            .input_channels = &inputs,
            .output_channels = &outputs,
            .attachments = .{
                .parameter_changes = &changes,
                .events = &events,
            },
            .transport = .{
                .project_time_samples = 512,
                .state_valid = true,
                .playing = true,
                .tempo_bpm = 123.0,
            },
        });
    try runtime.process(&context);

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.25, 0.125, -0.125, -0.25 },
        &output,
    );
    try std.testing.expectEqual(@as(?f64, 123.0), runtime.instance.plugin.observed_tempo);
    try std.testing.expectEqual(@as(?i16, 64), runtime.instance.plugin.observed_pitch);
    try std.testing.expectEqual(@as(usize, 1), runtime.instance.plugin.process_count);
    var context64 = try process_api.ProcessContext(f64).init(
        48_000.0,
        &.{},
        &.{},
    );
    try std.testing.expectError(
        error.UnsupportedSamplePrecision,
        runtime.process64(&context64),
    );

    try runtime.deactivate();
    try runtime.prepare(.{
        .sample_rate = 48_000.0,
        .max_block_size = 8,
        .process_mode = .offline,
    });
    try runtime.releaseResources();
    try std.testing.expectEqual(RuntimeState.initialized, runtime.runtimeState());
    try std.testing.expectEqual(@as(usize, 2), runtime.instance.plugin.prepare_count);
    try std.testing.expectEqual(@as(usize, 1), runtime.instance.plugin.activate_count);
    try std.testing.expectEqual(@as(usize, 1), runtime.instance.plugin.deactivate_count);
    try std.testing.expectEqual(@as(usize, 1), runtime.instance.plugin.reset_count);
    try std.testing.expectEqual(@as(usize, 2), runtime.instance.plugin.release_count);
}

test "processor runtime validates context and restores state only while inactive" {
    const Gain = struct {
        restored_count: usize = 0,

        pub const name = "Runtime State";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam =
                parameters.FloatParam.init(
                    0,
                    "Gain",
                    0.0,
                    1.0,
                    0.5,
                ),
        };

        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}

        pub fn afterStateRestore(self: *@This()) void {
            self.restored_count += 1;
        }
    };

    const Runtime = ProcessorRuntime(Gain);
    var source = try Runtime.init(std.testing.allocator, .{});
    defer source.deinit();
    _ = source.instance.storeParameterNormalized("gain", 0.75);
    var encoded: [Runtime.Instance.Spec.encoded_parameter_state_size]u8 =
        undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try source.writeParameterState(&writer);

    var restored = try Runtime.init(std.testing.allocator, .{});
    defer restored.deinit();
    try restored.prepare(.{
        .sample_rate = 48_000.0,
        .max_block_size = 2,
    });
    var reader: std.Io.Reader = .fixed(&encoded);
    try restored.readParameterState(&reader);
    try std.testing.expectEqual(
        @as(f64, 0.75),
        restored.instance.loadParameterNormalized("gain"),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        restored.instance.plugin.restored_count,
    );

    try restored.activate();
    var wrong_rate = try process_api.ProcessContext(f32).init(
        44_100.0,
        &.{},
        &.{},
    );
    try std.testing.expectError(
        error.SampleRateMismatch,
        restored.process(&wrong_rate),
    );
    var too_large_output = [_]f32{ 0.0, 0.0, 0.0 };
    const too_large_outputs = [_][]f32{&too_large_output};
    var too_large = try process_api.ProcessContext(f32).init(
        48_000.0,
        &.{},
        &too_large_outputs,
    );
    try std.testing.expectError(
        error.BlockTooLarge,
        restored.process(&too_large),
    );
    const mismatched_input = [_]f32{ 0.0, 0.0 };
    var mismatched_output = [_]f32{0.0};
    const mismatched_inputs = [_][]const f32{&mismatched_input};
    const mismatched_outputs = [_][]f32{&mismatched_output};
    var mismatched_context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .inputs = try process_api.AudioInputs(f32).init(
            &mismatched_inputs,
        ),
        .outputs = try process_api.AudioOutputs(f32).init(
            &mismatched_outputs,
        ),
    };
    try std.testing.expectError(
        error.InvalidAudioBuffers,
        restored.process(&mismatched_context),
    );
    var active_reader: std.Io.Reader = .fixed(&encoded);
    try std.testing.expectError(
        error.ProcessorActive,
        restored.readParameterState(&active_reader),
    );
}

test "processor runtime permits process mode changes only for opted-in plugins" {
    const Strict = struct {
        pub const name = "Strict Process Mode";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
        ) void {}
    };
    var strict = try ProcessorRuntime(Strict).init(
        std.testing.allocator,
        .{},
    );
    defer strict.deinit();
    try strict.prepare(.{
        .sample_rate = 48_000.0,
        .max_block_size = 1,
        .process_mode = .realtime,
    });
    try strict.activate();
    var strict_offline =
        try process_api.ProcessContext(f32).initWithOptions(.{
            .sample_rate = 48_000.0,
            .process_mode = .offline,
        });
    try std.testing.expectError(
        error.ProcessModeMismatch,
        strict.process(&strict_offline),
    );

    const Dynamic = struct {
        observed_modes: [2]process_api.ProcessMode = undefined,
        observed_count: usize = 0,

        pub const name = "Dynamic Process Mode";
        pub const vendor = "zig-vst3";
        pub const allow_dynamic_process_mode = true;
        pub const Params = struct {};

        pub fn process(
            self: *@This(),
            context: *process_api.ProcessContext(f32),
        ) void {
            if (self.observed_count >= self.observed_modes.len) return;
            self.observed_modes[self.observed_count] =
                context.processMode();
            self.observed_count += 1;
        }
    };
    var dynamic = try ProcessorRuntime(Dynamic).init(
        std.testing.allocator,
        .{},
    );
    defer dynamic.deinit();
    try dynamic.prepare(.{
        .sample_rate = 48_000.0,
        .max_block_size = 1,
        .process_mode = .realtime,
    });
    try dynamic.activate();
    var realtime =
        try process_api.ProcessContext(f32).initWithOptions(.{
            .sample_rate = 48_000.0,
            .process_mode = .realtime,
        });
    var offline =
        try process_api.ProcessContext(f32).initWithOptions(.{
            .sample_rate = 48_000.0,
            .process_mode = .offline,
        });
    try dynamic.process(&realtime);
    try dynamic.process(&offline);
    try std.testing.expectEqual(
        @as(usize, 2),
        dynamic.instance.plugin.observed_count,
    );
    try std.testing.expectEqualSlices(
        process_api.ProcessMode,
        &.{ .realtime, .offline },
        &dynamic.instance.plugin.observed_modes,
    );
}
