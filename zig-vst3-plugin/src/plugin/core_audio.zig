const builtin = @import("builtin");
const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const device_catalog = core.plugin;
const process_api = core.process;
const standalone = core.plugin;

const ProcessChannels = *const fn (
    context: ?*anyopaque,
    frame_count: u32,
    input_channels: [*c]const ?*const anyopaque,
    output_channels: [*c]const ?*anyopaque,
) callconv(.c) i32;

const CaptureChannels = *const fn (
    context: ?*anyopaque,
    frame_count: u32,
    input_channels: [*c]const ?*const anyopaque,
) callconv(.c) i32;

const RenderChannels = *const fn (
    context: ?*anyopaque,
    frame_count: u32,
    output_channels: [*c]const ?*anyopaque,
) callconv(.c) i32;

const TopologyChanged = *const fn (
    context: ?*anyopaque,
) callconv(.c) void;

pub const CallbackStatistics = struct {
    processed: usize,
    rejected: usize,
    device_failures: u64,
};

pub const DirectionalDeviceFailures = struct {
    input: u64,
    output: u64,
};

pub const DeviceRuntimeInfo = struct {
    sample_rate: f64,
    buffer_frames: u32,
    input_channels: u32,
    output_channels: u32,

    pub fn valid(self: DeviceRuntimeInfo) bool {
        return std.math.isFinite(self.sample_rate) and
            self.sample_rate > 0.0 and
            self.buffer_frames != 0 and
            (self.input_channels != 0 or self.output_channels != 0);
    }
};

pub fn Backend(comptime Api: type, comptime Sample: type) type {
    return BoundedBackend(
        Api,
        Sample,
        core.plugin.max_auxiliary_audio_buses,
    );
}

pub fn BoundedBackend(
    comptime Api: type,
    comptime Sample: type,
    comptime maximum_auxiliary_buses: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("CoreAudio supports f32 and f64");
    if (maximum_auxiliary_buses >= std.math.maxInt(u8))
        @compileError(
            "CoreAudio supports at most 254 auxiliary buses",
        );

    return struct {
        const Self = @This();
        const Session = Api.Session;
        const Device = Api.Device;
        const Observer = Api.Observer;

        selected_device: ?Device = null,
        selected_input_device: ?Device = null,
        selected_output_device: ?Device = null,
        session: ?Session = null,
        observer: ?Observer = null,
        callback: ?standalone.AudioCallback(Sample) = null,
        split_callback: ?standalone.SplitAudioCallback(Sample) = null,
        maximum_frames: usize = 0,
        main_input_channel_count: usize = 0,
        main_output_channel_count: usize = 0,
        auxiliary_input_channel_counts: [maximum_auxiliary_buses]usize = @splat(0),
        auxiliary_input_bus_count: usize = 0,
        auxiliary_output_channel_counts: [maximum_auxiliary_buses]usize = @splat(0),
        auxiliary_output_bus_count: usize = 0,
        input_views: [standalone.maximum_routed_channels][]const Sample = undefined,
        output_views: [standalone.maximum_routed_channels][]Sample = undefined,
        topology_generation: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),
        topology_fingerprint: u64 = 0,
        processed_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        rejected_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        final_device_failures: u64 = 0,
        final_input_device_failures: u64 = 0,
        final_output_device_failures: u64 = 0,

        /// Keep the backend at a stable address while audio is running.
        pub fn audioDevice(
            self: *Self,
        ) standalone.AudioDevice(Sample) {
            return .{
                .context = self,
                .start_audio = startAudioDevice,
                .stop_audio = stopAudioDevice,
            };
        }

        pub fn refreshTopology(self: *Self) !u64 {
            if (!Api.supported) return error.UnsupportedPlatform;
            const fingerprint = try topologyFingerprint(Api);
            if (self.currentTopologyGeneration() == 0 or
                fingerprint != self.topology_fingerprint)
            {
                incrementGeneration(&self.topology_generation);
                self.topology_fingerprint = fingerprint;
            }
            return self.currentTopologyGeneration();
        }

        pub fn currentTopologyGeneration(
            self: *const Self,
        ) u64 {
            return self.topology_generation.load(.acquire);
        }

        pub fn startObservingTopology(self: *Self) !void {
            if (!Api.supported) return error.UnsupportedPlatform;
            if (self.observer != null)
                return error.CoreAudioTopologyObserverAlreadyRunning;
            self.observer = try Api.startObserver(
                self,
                topologyChanged,
            );
        }

        pub fn stopObservingTopology(self: *Self) void {
            if (self.observer) |observer|
                Api.stopObserver(observer);
            self.observer = null;
        }

        pub fn enumerate(
            self: *Self,
            output: []device_catalog.DeviceDescriptor,
        ) !usize {
            if (!Api.supported) return error.UnsupportedPlatform;
            const initial_generation =
                self.currentTopologyGeneration();
            const initial_fingerprint = try topologyFingerprint(Api);
            var count: usize = 0;
            var uid_storage: [device_catalog.maximum_device_identifier_bytes]u8 =
                undefined;
            var name_storage: [device_catalog.maximum_device_name_bytes]u8 =
                undefined;
            const default_input = Api.defaultInputDevice();
            const default_output = Api.defaultOutputDevice();
            for (0..Api.deviceCount()) |index| {
                const device = try Api.deviceAt(index);
                const channels = try Api.deviceChannels(device);
                if (channels.input == 0 and channels.output == 0)
                    continue;
                if (channels.input > std.math.maxInt(u8) or
                    channels.output > std.math.maxInt(u8))
                    return error.CoreAudioChannelCountTooLarge;
                if (count == output.len)
                    return error.CoreAudioDeviceStorageTooSmall;
                const identifier = try deviceIdentifier(
                    Api,
                    device,
                    &uid_storage,
                );
                const name = try Api.deviceName(
                    device,
                    &name_storage,
                );
                output[count] = try device_catalog.DeviceDescriptor.init(
                    .audio,
                    identifier.slice(),
                    name,
                    @intCast(channels.input),
                    @intCast(channels.output),
                    device == default_input or
                        device == default_output,
                );
                count += 1;
            }
            const final_fingerprint = try topologyFingerprint(Api);
            if (final_fingerprint != initial_fingerprint or
                self.currentTopologyGeneration() != initial_generation)
                return error.CoreAudioTopologyChanged;
            if (self.currentTopologyGeneration() == 0 or
                final_fingerprint != self.topology_fingerprint)
            {
                incrementGeneration(&self.topology_generation);
                self.topology_fingerprint = final_fingerprint;
            }
            return count;
        }

        pub fn select(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            if (!Api.supported) return error.UnsupportedPlatform;
            if (self.session != null)
                return error.CoreAudioBackendRunning;
            self.selected_device = try resolveDevice(
                Api,
                identifier,
            );
        }

        pub fn selectInput(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            if (!Api.supported) return error.UnsupportedPlatform;
            if (self.session != null)
                return error.CoreAudioBackendRunning;
            const device = try resolveDevice(Api, identifier);
            if ((try Api.deviceChannels(device)).input == 0)
                return error.CoreAudioDeviceHasNoInput;
            self.selected_input_device = device;
        }

        pub fn selectOutput(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            if (!Api.supported) return error.UnsupportedPlatform;
            if (self.session != null)
                return error.CoreAudioBackendRunning;
            const device = try resolveDevice(Api, identifier);
            if ((try Api.deviceChannels(device)).output == 0)
                return error.CoreAudioDeviceHasNoOutput;
            self.selected_output_device = device;
        }

        pub fn runtimeInfo(
            _: *const Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !DeviceRuntimeInfo {
            if (!Api.supported) return error.UnsupportedPlatform;
            if (!identifier.valid())
                return error.InvalidDeviceIdentifier;
            var uid_storage: [device_catalog.maximum_device_identifier_bytes]u8 =
                undefined;
            for (0..Api.deviceCount()) |index| {
                const device = try Api.deviceAt(index);
                const candidate = try deviceIdentifier(
                    Api,
                    device,
                    &uid_storage,
                );
                if (!candidate.eql(&identifier)) continue;
                const channels = try Api.deviceChannels(device);
                const info = DeviceRuntimeInfo{
                    .sample_rate = try Api.deviceSampleRate(device),
                    .buffer_frames = try Api.deviceBufferFrames(device),
                    .input_channels = channels.input,
                    .output_channels = channels.output,
                };
                if (!info.valid())
                    return error.InvalidCoreAudioDeviceRuntimeInfo;
                return info;
            }
            return error.CoreAudioDeviceNotFound;
        }

        pub fn clearSelection(self: *Self) !void {
            if (self.session != null)
                return error.CoreAudioBackendRunning;
            self.selected_device = null;
        }

        pub fn clearInputSelection(self: *Self) !void {
            if (self.session != null)
                return error.CoreAudioBackendRunning;
            self.selected_input_device = null;
        }

        pub fn clearOutputSelection(self: *Self) !void {
            if (self.session != null)
                return error.CoreAudioBackendRunning;
            self.selected_output_device = null;
        }

        pub fn isRunning(self: *const Self) bool {
            return self.session != null;
        }

        pub fn statistics(
            self: *const Self,
        ) CallbackStatistics {
            const device_failures = if (self.session) |session|
                Api.deviceFailures(session)
            else
                self.final_device_failures;
            return .{
                .processed = self.processed_count.load(.acquire),
                .rejected = self.rejected_count.load(.acquire),
                .device_failures = device_failures,
            };
        }

        pub fn directionalDeviceFailures(
            self: *const Self,
        ) DirectionalDeviceFailures {
            if (self.session) |session| {
                return .{
                    .input = Api.inputDeviceFailures(session),
                    .output = Api.outputDeviceFailures(session),
                };
            }
            return .{
                .input = self.final_input_device_failures,
                .output = self.final_output_device_failures,
            };
        }

        pub fn failureSource(
            self: *Self,
        ) device_catalog.DeviceFailureSource {
            return .{
                .context = self,
                .read_snapshot = readFailureSnapshot,
            };
        }

        fn readFailureSnapshot(
            context: *anyopaque,
        ) !device_catalog.DeviceFailureSnapshot {
            const self: *Self = @ptrCast(@alignCast(context));
            const configured =
                self.main_input_channel_count != 0 or
                self.auxiliary_input_bus_count != 0 or
                self.main_output_channel_count != 0 or
                self.auxiliary_output_bus_count != 0;
            if (self.split_callback != null) {
                const failures =
                    self.directionalDeviceFailures();
                return .{
                    .audio_input = failures.input,
                    .audio_output = failures.output,
                };
            }
            return .{
                .audio = if (configured)
                    self.statistics().device_failures
                else
                    0,
            };
        }

        pub fn resetStatistics(self: *Self) !void {
            if (self.session != null)
                return error.CoreAudioBackendRunning;
            self.processed_count.store(0, .release);
            self.rejected_count.store(0, .release);
            self.final_device_failures = 0;
            self.final_input_device_failures = 0;
            self.final_output_device_failures = 0;
        }

        pub fn start(
            self: *Self,
            configuration: standalone.DeviceConfiguration,
            callback: standalone.AudioCallback(Sample),
        ) !void {
            if (!Api.supported) return error.UnsupportedPlatform;
            if (self.session != null)
                return error.CoreAudioBackendRunning;
            try configuration.validate();
            if (configuration.auxiliary_input_bus_channel_counts.len >
                maximum_auxiliary_buses or
                configuration.auxiliary_output_bus_channel_counts.len >
                    maximum_auxiliary_buses)
                return error.TooManyAudioBuses;
            const total_input_channels = try totalChannels(
                configuration.input_channel_count,
                configuration.auxiliary_input_bus_channel_counts,
            );
            const total_output_channels = try totalChannels(
                configuration.output_channel_count,
                configuration.auxiliary_output_bus_channel_counts,
            );
            if (total_input_channels == 0 and
                total_output_channels == 0)
                return error.CoreAudioRequiresAudioChannels;

            const device = self.selected_device orelse
                defaultDevice(Api, total_input_channels, total_output_channels) orelse
                return error.CoreAudioDefaultDeviceUnavailable;
            const available = try Api.deviceChannels(device);
            if (total_input_channels > available.input)
                return error.CoreAudioInsufficientInputChannels;
            if (total_output_channels > available.output)
                return error.CoreAudioInsufficientOutputChannels;

            self.callback = callback;
            self.split_callback = null;
            self.maximum_frames = configuration.max_block_size;
            self.final_device_failures = 0;
            self.final_input_device_failures = 0;
            self.final_output_device_failures = 0;
            self.main_input_channel_count =
                configuration.input_channel_count;
            self.main_output_channel_count =
                configuration.output_channel_count;
            self.auxiliary_input_bus_count =
                configuration.auxiliary_input_bus_channel_counts.len;
            self.auxiliary_output_bus_count =
                configuration.auxiliary_output_bus_channel_counts.len;
            @memcpy(
                self.auxiliary_input_channel_counts[0..self.auxiliary_input_bus_count],
                configuration.auxiliary_input_bus_channel_counts,
            );
            @memcpy(
                self.auxiliary_output_channel_counts[0..self.auxiliary_output_bus_count],
                configuration.auxiliary_output_bus_channel_counts,
            );
            errdefer self.clearRuntimeState();
            self.session = try Api.start(
                device,
                @sizeOf(Sample),
                configuration.sample_rate,
                configuration.max_block_size,
                @intCast(total_input_channels),
                @intCast(total_output_channels),
                self,
                processChannels,
            );
        }

        pub fn startSplit(
            self: *Self,
            configuration: standalone.DeviceConfiguration,
            callback: standalone.SplitAudioCallback(Sample),
        ) !void {
            if (!Api.supported) return error.UnsupportedPlatform;
            if (self.session != null)
                return error.CoreAudioBackendRunning;
            try configuration.validate();
            if (configuration.auxiliary_input_bus_channel_counts.len >
                maximum_auxiliary_buses or
                configuration.auxiliary_output_bus_channel_counts.len >
                    maximum_auxiliary_buses)
                return error.TooManyAudioBuses;
            const total_input_channels = try totalChannels(
                configuration.input_channel_count,
                configuration.auxiliary_input_bus_channel_counts,
            );
            const total_output_channels = try totalChannels(
                configuration.output_channel_count,
                configuration.auxiliary_output_bus_channel_counts,
            );
            if (total_input_channels == 0 or
                total_output_channels == 0)
                return error.CoreAudioSplitRequiresDuplex;

            const input_device =
                self.selected_input_device orelse
                self.selected_device orelse
                Api.defaultInputDevice();
            if (input_device == Api.invalid_device)
                return error.CoreAudioDefaultInputDeviceUnavailable;
            const output_device =
                self.selected_output_device orelse
                self.selected_device orelse
                Api.defaultOutputDevice();
            if (output_device == Api.invalid_device)
                return error.CoreAudioDefaultOutputDeviceUnavailable;
            if (total_input_channels >
                (try Api.deviceChannels(input_device)).input)
                return error.CoreAudioInsufficientInputChannels;
            if (total_output_channels >
                (try Api.deviceChannels(output_device)).output)
                return error.CoreAudioInsufficientOutputChannels;

            self.callback = null;
            self.split_callback = callback;
            self.maximum_frames = configuration.max_block_size;
            self.final_device_failures = 0;
            self.final_input_device_failures = 0;
            self.final_output_device_failures = 0;
            self.main_input_channel_count =
                configuration.input_channel_count;
            self.main_output_channel_count =
                configuration.output_channel_count;
            self.auxiliary_input_bus_count =
                configuration.auxiliary_input_bus_channel_counts.len;
            self.auxiliary_output_bus_count =
                configuration.auxiliary_output_bus_channel_counts.len;
            @memcpy(
                self.auxiliary_input_channel_counts[0..self.auxiliary_input_bus_count],
                configuration.auxiliary_input_bus_channel_counts,
            );
            @memcpy(
                self.auxiliary_output_channel_counts[0..self.auxiliary_output_bus_count],
                configuration.auxiliary_output_bus_channel_counts,
            );
            errdefer self.clearRuntimeState();
            self.session = try Api.startSplit(
                input_device,
                output_device,
                @sizeOf(Sample),
                configuration.sample_rate,
                configuration.max_block_size,
                @intCast(total_input_channels),
                @intCast(total_output_channels),
                self,
                captureChannels,
                renderChannels,
            );
        }

        pub fn stop(self: *Self) void {
            if (self.session) |session| {
                self.final_device_failures =
                    Api.deviceFailures(session);
                self.final_input_device_failures =
                    Api.inputDeviceFailures(session);
                self.final_output_device_failures =
                    Api.outputDeviceFailures(session);
                Api.stop(session);
            }
            self.clearRuntimeState();
        }

        pub fn deinit(self: *Self) void {
            self.stop();
            self.stopObservingTopology();
        }

        fn clearRuntimeState(self: *Self) void {
            self.session = null;
            self.callback = null;
            self.split_callback = null;
            self.maximum_frames = 0;
            self.main_input_channel_count = 0;
            self.main_output_channel_count = 0;
            self.auxiliary_input_bus_count = 0;
            self.auxiliary_output_bus_count = 0;
        }

        fn startAudioDevice(
            context: *anyopaque,
            configuration: standalone.DeviceConfiguration,
            callback: standalone.AudioCallback(Sample),
        ) !void {
            const self: *Self = @ptrCast(@alignCast(context));
            try self.start(configuration, callback);
        }

        fn stopAudioDevice(context: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(context));
            self.stop();
        }

        fn topologyChanged(context: ?*anyopaque) callconv(.c) void {
            const self = callbackContext(context) orelse return;
            incrementGeneration(&self.topology_generation);
        }

        fn processChannels(
            context: ?*anyopaque,
            frame_count_u32: u32,
            input_channels: [*c]const ?*const anyopaque,
            output_channels: [*c]const ?*anyopaque,
        ) callconv(.c) i32 {
            const self = callbackContext(context) orelse return -1;
            const callback = self.callback orelse {
                incrementSaturating(&self.rejected_count);
                return -1;
            };
            const frame_count: usize = frame_count_u32;
            if (frame_count > self.maximum_frames) {
                incrementSaturating(&self.rejected_count);
                return -1;
            }
            const input_count = self.totalInputChannels() catch {
                incrementSaturating(&self.rejected_count);
                return -1;
            };
            const output_count = self.totalOutputChannels() catch {
                incrementSaturating(&self.rejected_count);
                return -1;
            };
            for (0..input_count) |index| {
                const pointer = input_channels[index] orelse {
                    incrementSaturating(&self.rejected_count);
                    return -1;
                };
                if (@intFromPtr(pointer) % @alignOf(Sample) != 0) {
                    incrementSaturating(&self.rejected_count);
                    return -1;
                }
                const samples: [*]const Sample = @ptrCast(@alignCast(pointer));
                self.input_views[index] = samples[0..frame_count];
            }
            for (0..output_count) |index| {
                const pointer = output_channels[index] orelse {
                    incrementSaturating(&self.rejected_count);
                    return -1;
                };
                if (@intFromPtr(pointer) % @alignOf(Sample) != 0) {
                    incrementSaturating(&self.rejected_count);
                    return -1;
                }
                const samples: [*]Sample = @ptrCast(@alignCast(pointer));
                self.output_views[index] = samples[0..frame_count];
            }
            callback.process_block(callback.context, .{
                .input_channels = self.input_views[0..self.main_input_channel_count],
                .auxiliary_input_channels = self.input_views[self.main_input_channel_count..input_count],
                .auxiliary_input_bus_channel_counts = self.auxiliary_input_channel_counts[0..self.auxiliary_input_bus_count],
                .output_channels = self.output_views[0..self.main_output_channel_count],
                .auxiliary_output_channels = self.output_views[self.main_output_channel_count..output_count],
                .auxiliary_output_bus_channel_counts = self.auxiliary_output_channel_counts[0..self.auxiliary_output_bus_count],
            });
            incrementSaturating(&self.processed_count);
            return 0;
        }

        fn captureChannels(
            context: ?*anyopaque,
            frame_count_u32: u32,
            input_channels: [*c]const ?*const anyopaque,
        ) callconv(.c) i32 {
            const self = callbackContext(context) orelse return -1;
            const callback = self.split_callback orelse {
                incrementSaturating(&self.rejected_count);
                return -1;
            };
            const frame_count: usize = frame_count_u32;
            if (frame_count > self.maximum_frames) {
                incrementSaturating(&self.rejected_count);
                return -1;
            }
            const input_count = self.totalInputChannels() catch {
                incrementSaturating(&self.rejected_count);
                return -1;
            };
            for (0..input_count) |index| {
                const pointer = input_channels[index] orelse {
                    incrementSaturating(&self.rejected_count);
                    return -1;
                };
                if (@intFromPtr(pointer) % @alignOf(Sample) != 0) {
                    incrementSaturating(&self.rejected_count);
                    return -1;
                }
                const samples: [*]const Sample =
                    @ptrCast(@alignCast(pointer));
                self.input_views[index] =
                    samples[0..frame_count];
            }
            callback.capture_block(
                callback.context,
                self.input_views[0..input_count],
            );
            return 0;
        }

        fn renderChannels(
            context: ?*anyopaque,
            frame_count_u32: u32,
            output_channels: [*c]const ?*anyopaque,
        ) callconv(.c) i32 {
            const self = callbackContext(context) orelse return -1;
            const callback = self.split_callback orelse {
                incrementSaturating(&self.rejected_count);
                return -1;
            };
            const frame_count: usize = frame_count_u32;
            if (frame_count > self.maximum_frames) {
                incrementSaturating(&self.rejected_count);
                return -1;
            }
            const output_count = self.totalOutputChannels() catch {
                incrementSaturating(&self.rejected_count);
                return -1;
            };
            for (0..output_count) |index| {
                const pointer = output_channels[index] orelse {
                    incrementSaturating(&self.rejected_count);
                    return -1;
                };
                if (@intFromPtr(pointer) % @alignOf(Sample) != 0) {
                    incrementSaturating(&self.rejected_count);
                    return -1;
                }
                const samples: [*]Sample =
                    @ptrCast(@alignCast(pointer));
                self.output_views[index] =
                    samples[0..frame_count];
            }
            callback.render_block(callback.context, .{
                .frame_count = frame_count,
                .output_channels = self.output_views[0..self.main_output_channel_count],
                .auxiliary_output_channels = self.output_views[self.main_output_channel_count..output_count],
                .auxiliary_output_bus_channel_counts = self.auxiliary_output_channel_counts[0..self.auxiliary_output_bus_count],
            });
            incrementSaturating(&self.processed_count);
            return 0;
        }

        fn callbackContext(context: ?*anyopaque) ?*Self {
            const value = context orelse return null;
            if (@intFromPtr(value) % @alignOf(Self) != 0)
                return null;
            return @ptrCast(@alignCast(value));
        }

        fn totalInputChannels(self: *const Self) !usize {
            return totalChannels(
                self.main_input_channel_count,
                self.auxiliary_input_channel_counts[0..self.auxiliary_input_bus_count],
            );
        }

        fn totalOutputChannels(self: *const Self) !usize {
            return totalChannels(
                self.main_output_channel_count,
                self.auxiliary_output_channel_counts[0..self.auxiliary_output_bus_count],
            );
        }
    };
}

pub fn CoreAudioBackend(comptime Sample: type) type {
    return Backend(CoreAudioSystemApi, Sample);
}

pub fn BoundedCoreAudioBackend(
    comptime Sample: type,
    comptime maximum_auxiliary_buses: usize,
) type {
    return BoundedBackend(
        CoreAudioSystemApi,
        Sample,
        maximum_auxiliary_buses,
    );
}

fn totalChannels(main: usize, auxiliary: []const usize) !usize {
    var total = main;
    for (auxiliary) |count| {
        total = std.math.add(usize, total, count) catch
            return error.CoreAudioChannelCountOverflow;
    }
    if (total > standalone.maximum_routed_channels)
        return error.CoreAudioChannelCountTooLarge;
    return total;
}

fn defaultDevice(
    comptime Api: type,
    input_channels: usize,
    output_channels: usize,
) ?Api.Device {
    if (output_channels != 0) {
        const output = Api.defaultOutputDevice();
        if (output != Api.invalid_device) return output;
    }
    if (input_channels != 0) {
        const input = Api.defaultInputDevice();
        if (input != Api.invalid_device) return input;
    }
    return null;
}

fn resolveDevice(
    comptime Api: type,
    identifier: device_catalog.DeviceIdentifier,
) !Api.Device {
    if (!identifier.valid())
        return error.InvalidDeviceIdentifier;
    var uid_storage: [device_catalog.maximum_device_identifier_bytes]u8 =
        undefined;
    for (0..Api.deviceCount()) |index| {
        const device = try Api.deviceAt(index);
        const candidate = try deviceIdentifier(
            Api,
            device,
            &uid_storage,
        );
        if (candidate.eql(&identifier))
            return device;
    }
    return error.CoreAudioDeviceNotFound;
}

fn deviceIdentifier(
    comptime Api: type,
    device: Api.Device,
    storage: []u8,
) !device_catalog.DeviceIdentifier {
    const prefix = "coreaudio:";
    if (storage.len < prefix.len)
        return error.CoreAudioIdentifierTooLong;
    const uid = try Api.deviceUid(device, storage[prefix.len..]);
    const length = std.math.add(
        usize,
        prefix.len,
        uid.len,
    ) catch return error.CoreAudioIdentifierTooLong;
    if (length > storage.len)
        return error.CoreAudioIdentifierTooLong;
    @memcpy(storage[0..prefix.len], prefix);
    return device_catalog.DeviceIdentifier.init(storage[0..length]);
}

fn topologyFingerprint(comptime Api: type) !u64 {
    var hasher = std.hash.Wyhash.init(0);
    const count = Api.deviceCount();
    hasher.update(std.mem.asBytes(&count));
    const default_input = Api.defaultInputDevice();
    const default_output = Api.defaultOutputDevice();
    hasher.update(std.mem.asBytes(&default_input));
    hasher.update(std.mem.asBytes(&default_output));
    var uid_storage: [device_catalog.maximum_device_identifier_bytes]u8 = undefined;
    for (0..count) |index| {
        const device = try Api.deviceAt(index);
        hasher.update(std.mem.asBytes(&device));
        const uid = try Api.deviceUid(device, &uid_storage);
        hasher.update(uid);
        const channels = try Api.deviceChannels(device);
        hasher.update(std.mem.asBytes(&channels));
    }
    return hasher.final();
}

fn incrementSaturating(value: *std.atomic.Value(usize)) void {
    var current = value.load(.monotonic);
    while (current != std.math.maxInt(usize)) {
        if (value.cmpxchgWeak(
            current,
            current + 1,
            .monotonic,
            .monotonic,
        )) |observed| {
            current = observed;
        } else return;
    }
}

fn incrementGeneration(value: *std.atomic.Value(u64)) void {
    var current = value.load(.monotonic);
    while (true) {
        var next = current +% 1;
        if (next == 0) next = 1;
        if (value.cmpxchgWeak(
            current,
            next,
            .release,
            .monotonic,
        )) |observed| {
            current = observed;
        } else return;
    }
}

const CoreAudioSystemApi = if (builtin.os.tag == .macos)
    MacOsCoreAudioApi
else
    UnsupportedCoreAudioApi;

const UnsupportedCoreAudioApi = struct {
    const supported = false;
    const Device = u32;
    const Session = u32;
    const Observer = u32;
    const invalid_device: Device = 0;

    fn deviceCount() usize {
        return 0;
    }
    fn deviceAt(_: usize) !Device {
        return error.UnsupportedPlatform;
    }
    fn defaultInputDevice() Device {
        return invalid_device;
    }
    fn defaultOutputDevice() Device {
        return invalid_device;
    }
    fn deviceUid(_: Device, _: []u8) ![]const u8 {
        return error.UnsupportedPlatform;
    }
    fn deviceName(_: Device, _: []u8) ![]const u8 {
        return error.UnsupportedPlatform;
    }
    fn deviceChannels(_: Device) !ChannelCounts {
        return error.UnsupportedPlatform;
    }
    fn deviceSampleRate(_: Device) !f64 {
        return error.UnsupportedPlatform;
    }
    fn deviceBufferFrames(_: Device) !u32 {
        return error.UnsupportedPlatform;
    }
    fn startObserver(
        _: *anyopaque,
        _: TopologyChanged,
    ) !Observer {
        return error.UnsupportedPlatform;
    }
    fn stopObserver(_: Observer) void {}
    fn start(
        _: Device,
        _: usize,
        _: f64,
        _: u32,
        _: u32,
        _: u32,
        _: *anyopaque,
        _: ProcessChannels,
    ) !Session {
        return error.UnsupportedPlatform;
    }
    fn startSplit(
        _: Device,
        _: Device,
        _: usize,
        _: f64,
        _: u32,
        _: u32,
        _: u32,
        _: *anyopaque,
        _: CaptureChannels,
        _: RenderChannels,
    ) !Session {
        return error.UnsupportedPlatform;
    }
    fn deviceFailures(_: Session) u64 {
        return 0;
    }
    fn inputDeviceFailures(_: Session) u64 {
        return 0;
    }
    fn outputDeviceFailures(_: Session) u64 {
        return 0;
    }
    fn stop(_: Session) void {}
};

const ChannelCounts = extern struct {
    input: u32,
    output: u32,
};

const MacOsCoreAudioApi = if (builtin.os.tag == .macos) struct {
    const supported = true;
    const c = @cImport({
        @cInclude("core_audio_shim.h");
    });
    const Device = u32;
    const Session = *c.zv3_core_audio_session;
    const Observer = *c.zv3_core_audio_observer;
    const invalid_device: Device = 0;

    fn deviceCount() usize {
        return c.zv3_core_audio_device_count();
    }

    fn deviceAt(index: usize) !Device {
        var device: Device = 0;
        if (c.zv3_core_audio_device_at(index, &device) != 0)
            return error.CoreAudioDeviceNotFound;
        return device;
    }

    fn defaultInputDevice() Device {
        return c.zv3_core_audio_default_input_device();
    }

    fn defaultOutputDevice() Device {
        return c.zv3_core_audio_default_output_device();
    }

    fn deviceUid(device: Device, storage: []u8) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_core_audio_device_uid(
            device,
            storage.ptr,
            storage.len,
            &length,
        ) != 0)
            return error.CoreAudioDeviceHasNoUid;
        if (length == 0 or length > storage.len)
            return error.CoreAudioIdentifierTooLong;
        return storage[0..length];
    }

    fn deviceName(device: Device, storage: []u8) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_core_audio_device_name(
            device,
            storage.ptr,
            storage.len,
            &length,
        ) != 0)
            return error.CoreAudioDeviceHasNoName;
        if (length == 0 or length > storage.len)
            return error.CoreAudioDeviceNameTooLong;
        return storage[0..length];
    }

    fn deviceChannels(device: Device) !ChannelCounts {
        var result = ChannelCounts{ .input = 0, .output = 0 };
        if (c.zv3_core_audio_device_channels(
            device,
            &result.input,
            &result.output,
        ) != 0)
            return error.CoreAudioDeviceQueryFailed;
        return result;
    }

    fn deviceSampleRate(device: Device) !f64 {
        var result: f64 = 0.0;
        if (c.zv3_core_audio_device_sample_rate(
            device,
            &result,
        ) != 0)
            return error.CoreAudioDeviceQueryFailed;
        return result;
    }

    fn deviceBufferFrames(device: Device) !u32 {
        var result: u32 = 0;
        if (c.zv3_core_audio_device_buffer_frames(
            device,
            &result,
        ) != 0)
            return error.CoreAudioDeviceQueryFailed;
        return result;
    }

    fn startObserver(
        context: *anyopaque,
        callback: TopologyChanged,
    ) !Observer {
        var observer: ?Observer = null;
        if (c.zv3_core_audio_observe_topology(
            context,
            callback,
            &observer,
        ) != 0)
            return error.CoreAudioTopologyObserverStartFailed;
        return observer orelse
            error.CoreAudioTopologyObserverStartFailed;
    }

    fn stopObserver(observer: Observer) void {
        c.zv3_core_audio_stop_observing(observer);
    }

    fn start(
        device: Device,
        sample_bytes: usize,
        sample_rate: f64,
        maximum_frames: u32,
        input_channels: u32,
        output_channels: u32,
        context: *anyopaque,
        process: ProcessChannels,
    ) !Session {
        var session: ?Session = null;
        if (c.zv3_core_audio_start(
            device,
            @intCast(sample_bytes),
            sample_rate,
            maximum_frames,
            input_channels,
            output_channels,
            context,
            process,
            &session,
        ) != 0)
            return error.CoreAudioStartFailed;
        return session orelse error.CoreAudioStartFailed;
    }

    fn startSplit(
        input_device: Device,
        output_device: Device,
        sample_bytes: usize,
        sample_rate: f64,
        maximum_frames: u32,
        input_channels: u32,
        output_channels: u32,
        context: *anyopaque,
        capture: CaptureChannels,
        render: RenderChannels,
    ) !Session {
        var session: ?Session = null;
        if (c.zv3_core_audio_start_split(
            input_device,
            output_device,
            @intCast(sample_bytes),
            sample_rate,
            maximum_frames,
            input_channels,
            output_channels,
            context,
            capture,
            render,
            &session,
        ) != 0)
            return error.CoreAudioStartFailed;
        return session orelse error.CoreAudioStartFailed;
    }

    fn deviceFailures(session: Session) u64 {
        return c.zv3_core_audio_device_failures(session);
    }

    fn inputDeviceFailures(session: Session) u64 {
        return c.zv3_core_audio_input_device_failures(session);
    }

    fn outputDeviceFailures(session: Session) u64 {
        return c.zv3_core_audio_output_device_failures(session);
    }

    fn stop(session: Session) void {
        c.zv3_core_audio_stop(session);
    }
} else struct {};

test "unsupported backend reports no devices and rejects start" {
    if (builtin.os.tag == .macos) return error.SkipZigTest;
    var backend = CoreAudioBackend(f32){};
    var descriptors: [1]device_catalog.DeviceDescriptor = undefined;
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.enumerate(&descriptors),
    );
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.refreshTopology(),
    );
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.startObservingTopology(),
    );
    var context: u8 = 0;
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.start(.{
            .sample_rate = 48_000.0,
            .max_block_size = 64,
            .input_channel_count = 0,
            .output_channel_count = 2,
        }, .{
            .context = &context,
            .process_block = struct {
                fn process(
                    _: *anyopaque,
                    _: standalone.CallbackBlock(f32),
                ) void {}
            }.process,
        }),
    );
}

const MockApi = struct {
    const supported = true;
    const Device = u32;
    const Session = u32;
    const Observer = u32;
    const invalid_device: Device = 0;
    const devices = [_]Device{ 11, 22, 33 };
    var callback_context: ?*anyopaque = null;
    var callback_function: ?ProcessChannels = null;
    var capture_function: ?CaptureChannels = null;
    var render_function: ?RenderChannels = null;
    var split_input_device: ?Device = null;
    var split_output_device: ?Device = null;
    var stop_count: usize = 0;
    var observer_context: ?*anyopaque = null;
    var observer_callback: ?TopologyChanged = null;
    var fail_start = false;
    var fail_observer = false;
    var notify_during_enumeration = false;
    var device_failures: u64 = 0;
    var input_device_failures: u64 = 0;
    var output_device_failures: u64 = 0;
    var large_channel_count = false;

    fn reset() void {
        callback_context = null;
        callback_function = null;
        capture_function = null;
        render_function = null;
        split_input_device = null;
        split_output_device = null;
        stop_count = 0;
        observer_context = null;
        observer_callback = null;
        fail_start = false;
        fail_observer = false;
        notify_during_enumeration = false;
        device_failures = 0;
        input_device_failures = 0;
        output_device_failures = 0;
        large_channel_count = false;
    }
    fn deviceCount() usize {
        return devices.len;
    }
    fn deviceAt(index: usize) !Device {
        if (index >= devices.len) return error.DeviceNotFound;
        if (index == 1 and notify_during_enumeration) {
            notify_during_enumeration = false;
            notifyTopologyChanged();
        }
        return devices[index];
    }
    fn defaultInputDevice() Device {
        return 11;
    }
    fn defaultOutputDevice() Device {
        return 22;
    }
    fn deviceUid(device: Device, storage: []u8) ![]const u8 {
        const value = switch (device) {
            11 => "input",
            22 => "duplex",
            33 => "empty",
            else => return error.DeviceNotFound,
        };
        if (storage.len < value.len) return error.StorageTooSmall;
        @memcpy(storage[0..value.len], value);
        return storage[0..value.len];
    }
    fn deviceName(device: Device, storage: []u8) ![]const u8 {
        const value = switch (device) {
            11 => "Input Device",
            22 => "Duplex Device",
            33 => "Empty Device",
            else => return error.DeviceNotFound,
        };
        if (storage.len < value.len) return error.StorageTooSmall;
        @memcpy(storage[0..value.len], value);
        return storage[0..value.len];
    }
    fn deviceChannels(device: Device) !ChannelCounts {
        if (large_channel_count and device == 22)
            return .{ .input = 64, .output = 64 };
        return switch (device) {
            11 => .{ .input = 2, .output = 0 },
            22 => .{ .input = 4, .output = 4 },
            33 => .{ .input = 0, .output = 0 },
            else => error.DeviceNotFound,
        };
    }
    fn deviceSampleRate(device: Device) !f64 {
        _ = try deviceChannels(device);
        return 48_000.0;
    }
    fn deviceBufferFrames(device: Device) !u32 {
        _ = try deviceChannels(device);
        return 128;
    }
    fn startObserver(
        context: *anyopaque,
        callback: TopologyChanged,
    ) !Observer {
        if (fail_observer) return error.MockObserverFailed;
        observer_context = context;
        observer_callback = callback;
        return 9;
    }
    fn stopObserver(_: Observer) void {
        observer_context = null;
        observer_callback = null;
    }
    fn notifyTopologyChanged() void {
        const callback = observer_callback orelse return;
        callback(observer_context);
    }
    fn start(
        _: Device,
        _: usize,
        _: f64,
        _: u32,
        _: u32,
        _: u32,
        context: *anyopaque,
        process: ProcessChannels,
    ) !Session {
        if (fail_start) return error.MockStartFailed;
        callback_context = context;
        callback_function = process;
        return 7;
    }
    fn startSplit(
        input_device: Device,
        output_device: Device,
        _: usize,
        _: f64,
        _: u32,
        _: u32,
        _: u32,
        context: *anyopaque,
        capture: CaptureChannels,
        render: RenderChannels,
    ) !Session {
        if (fail_start) return error.MockStartFailed;
        callback_context = context;
        capture_function = capture;
        render_function = render;
        split_input_device = input_device;
        split_output_device = output_device;
        return 7;
    }
    fn deviceFailures(_: Session) u64 {
        return device_failures;
    }
    fn inputDeviceFailures(_: Session) u64 {
        return input_device_failures;
    }
    fn outputDeviceFailures(_: Session) u64 {
        return output_device_failures;
    }
    fn stop(_: Session) void {
        stop_count += 1;
        callback_context = null;
        callback_function = null;
        capture_function = null;
        render_function = null;
        split_input_device = null;
        split_output_device = null;
    }
};

test "backend enumerates selects and publishes topology generations" {
    MockApi.reset();
    const TestBackend = Backend(MockApi, f32);
    var backend = TestBackend{};
    var descriptors: [2]device_catalog.DeviceDescriptor = undefined;
    try std.testing.expectEqual(
        @as(usize, 2),
        try backend.enumerate(&descriptors),
    );
    try std.testing.expectEqualStrings(
        "coreaudio:input",
        descriptors[0].identifier.slice(),
    );
    try std.testing.expectEqualStrings(
        "Duplex Device",
        descriptors[1].name(),
    );
    try std.testing.expect(descriptors[0].is_default);
    try std.testing.expect(descriptors[1].is_default);
    try std.testing.expectEqual(@as(u64, 1), backend.currentTopologyGeneration());
    try std.testing.expectEqual(
        @as(u64, 1),
        try backend.refreshTopology(),
    );
    try backend.startObservingTopology();
    try std.testing.expectError(
        error.CoreAudioTopologyObserverAlreadyRunning,
        backend.startObservingTopology(),
    );
    MockApi.notifyTopologyChanged();
    try std.testing.expectEqual(
        @as(u64, 2),
        backend.currentTopologyGeneration(),
    );
    MockApi.notify_during_enumeration = true;
    try std.testing.expectError(
        error.CoreAudioTopologyChanged,
        backend.enumerate(&descriptors),
    );
    backend.stopObservingTopology();
    MockApi.fail_observer = true;
    try std.testing.expectError(
        error.MockObserverFailed,
        backend.startObservingTopology(),
    );
    try std.testing.expect(backend.observer == null);
    try backend.select(descriptors[1].identifier);
    try std.testing.expectEqual(@as(?u32, 22), backend.selected_device);
    try std.testing.expectEqual(
        DeviceRuntimeInfo{
            .sample_rate = 48_000.0,
            .buffer_frames = 128,
            .input_channels = 4,
            .output_channels = 4,
        },
        try backend.runtimeInfo(descriptors[1].identifier),
    );
    try backend.clearSelection();
    try std.testing.expectEqual(@as(?u32, null), backend.selected_device);
    var too_small: [1]device_catalog.DeviceDescriptor = undefined;
    try std.testing.expectError(
        error.CoreAudioDeviceStorageTooSmall,
        backend.enumerate(&too_small),
    );
}

test "backend adapts planar callbacks and preserves auxiliary bus boundaries" {
    MockApi.reset();
    const TestBackend = Backend(MockApi, f64);
    const Probe = struct {
        calls: usize = 0,
        fn process(
            context: *anyopaque,
            block: standalone.CallbackBlock(f64),
        ) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.calls += 1;
            std.debug.assert(block.input_channels.len == 1);
            std.debug.assert(block.auxiliary_input_channels.len == 1);
            std.debug.assert(block.output_channels.len == 1);
            std.debug.assert(block.auxiliary_output_channels.len == 1);
            @memcpy(block.output_channels[0], block.input_channels[0]);
            @memcpy(
                block.auxiliary_output_channels[0],
                block.auxiliary_input_channels[0],
            );
        }
    };
    var probe = Probe{};
    var backend = TestBackend{};
    var device = backend.audioDevice();
    try device.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 2,
        .input_channel_count = 1,
        .auxiliary_input_bus_channel_counts = &.{1},
        .output_channel_count = 1,
        .auxiliary_output_bus_channel_counts = &.{1},
    }, .{
        .context = &probe,
        .process_block = Probe.process,
    });
    const input_a = [_]f64{ 0.25, -0.5 };
    const input_b = [_]f64{ 0.75, 1.0 };
    var output_a = [_]f64{ 0.0, 0.0 };
    var output_b = [_]f64{ 0.0, 0.0 };
    const input_pointers = [_]?*const anyopaque{
        &input_a,
        &input_b,
    };
    const output_pointers = [_]?*anyopaque{
        &output_a,
        &output_b,
    };
    const process = MockApi.callback_function orelse
        return error.MissingCallback;
    try std.testing.expectEqual(
        @as(i32, 0),
        process(
            MockApi.callback_context,
            2,
            &input_pointers,
            &output_pointers,
        ),
    );
    try std.testing.expectEqualSlices(f64, &input_a, &output_a);
    try std.testing.expectEqualSlices(f64, &input_b, &output_b);
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expectEqual(
        CallbackStatistics{
            .processed = 1,
            .rejected = 0,
            .device_failures = 0,
        },
        backend.statistics(),
    );
    const missing_output_pointers = [_]?*anyopaque{
        &output_a,
        null,
    };
    try std.testing.expectEqual(
        @as(i32, -1),
        process(
            MockApi.callback_context,
            2,
            &input_pointers,
            &missing_output_pointers,
        ),
    );
    try std.testing.expectEqual(
        CallbackStatistics{
            .processed = 1,
            .rejected = 1,
            .device_failures = 0,
        },
        backend.statistics(),
    );
    MockApi.device_failures = 3;
    try std.testing.expectEqual(
        @as(u64, 3),
        (try backend.failureSource().snapshot()).audio,
    );
    try std.testing.expectError(
        error.CoreAudioBackendRunning,
        backend.resetStatistics(),
    );
    device.stop();
    try std.testing.expectEqual(@as(usize, 1), MockApi.stop_count);
    try std.testing.expectEqual(
        @as(u64, 3),
        backend.statistics().device_failures,
    );
    try backend.resetStatistics();
    try std.testing.expectEqual(
        @as(u64, 0),
        backend.statistics().device_failures,
    );
}

test "CoreAudio split devices feed the bounded capture-rate adapter" {
    MockApi.reset();
    const TestBackend = Backend(MockApi, f64);
    const Adapter = standalone.BoundedCaptureRateCallbackAdapter(
        f64,
        2,
        32,
        4,
        8,
        1,
    );
    const Probe = struct {
        calls: usize = 0,

        fn process(
            context: *anyopaque,
            block: standalone.CallbackBlock(f64),
        ) void {
            const self: *@This() =
                @ptrCast(@alignCast(context));
            self.calls += 1;
            std.debug.assert(block.input_channels.len == 1);
            std.debug.assert(
                block.auxiliary_input_channels.len == 1,
            );
            std.debug.assert(block.output_channels.len == 1);
            std.debug.assert(
                block.auxiliary_output_channels.len == 1,
            );
            @memcpy(
                block.output_channels[0],
                block.input_channels[0],
            );
            @memcpy(
                block.auxiliary_output_channels[0],
                block.auxiliary_input_channels[0],
            );
        }
    };

    var descriptors: [2]device_catalog.DeviceDescriptor = undefined;
    var backend = TestBackend{};
    _ = try backend.enumerate(&descriptors);
    try backend.selectInput(descriptors[0].identifier);
    try std.testing.expectError(
        error.CoreAudioDeviceHasNoOutput,
        backend.selectOutput(descriptors[0].identifier),
    );
    try backend.selectOutput(descriptors[1].identifier);

    var probe = Probe{};
    var adapter = try Adapter.init(
        .{
            .main_input_channel_count = 1,
            .auxiliary_input_bus_channel_counts = &.{1},
            .capture_sample_rate = 48_000.0,
            .render_sample_rate = 48_000.0,
            .drift = .{
                .target_buffer_frames = 8,
            },
        },
        .{
            .context = &probe,
            .process_block = Probe.process,
        },
    );
    try backend.startSplit(.{
        .sample_rate = 48_000.0,
        .max_block_size = 8,
        .input_channel_count = 1,
        .auxiliary_input_bus_channel_counts = &.{1},
        .output_channel_count = 1,
        .auxiliary_output_bus_channel_counts = &.{1},
    }, adapter.splitCallback());
    try std.testing.expectEqual(@as(?u32, 11), MockApi.split_input_device);
    try std.testing.expectEqual(@as(?u32, 22), MockApi.split_output_device);
    try std.testing.expect(backend.callback == null);
    try std.testing.expect(backend.split_callback != null);
    try std.testing.expect(MockApi.callback_function == null);

    const input_a: [8]f64 = @splat(0.25);
    const input_b: [8]f64 = @splat(0.5);
    const inputs = [_]?*const anyopaque{ &input_a, &input_b };
    const capture_callback = MockApi.capture_function orelse
        return error.MissingCoreAudioCaptureCallback;
    try std.testing.expectEqual(
        @as(i32, 0),
        capture_callback(MockApi.callback_context, 8, &inputs),
    );

    var output_a: [4]f64 = @splat(-1);
    var output_b: [4]f64 = @splat(-1);
    const outputs = [_]?*anyopaque{ &output_a, &output_b };
    const render_callback = MockApi.render_function orelse
        return error.MissingCoreAudioRenderCallback;
    var context_storage: [@sizeOf(TestBackend) + 1]u8 align(@alignOf(TestBackend)) = undefined;
    const misaligned_context: *anyopaque =
        @ptrCast(&context_storage[1]);
    try std.testing.expectEqual(
        @as(i32, -1),
        capture_callback(misaligned_context, 8, &inputs),
    );
    try std.testing.expectEqual(
        @as(i32, -1),
        render_callback(misaligned_context, 4, &outputs),
    );
    TestBackend.topologyChanged(misaligned_context);
    try std.testing.expectEqual(
        @as(i32, 0),
        render_callback(MockApi.callback_context, 4, &outputs),
    );
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    for (output_a, output_b) |main, auxiliary| {
        try std.testing.expectApproxEqAbs(
            main * 2.0,
            auxiliary,
            1.0e-12,
        );
    }
    try std.testing.expectEqual(
        @as(usize, 8),
        (try adapter.statistics()).fifo.written_frames,
    );

    try std.testing.expectEqual(
        @as(i32, -1),
        capture_callback(MockApi.callback_context, 9, &inputs),
    );
    const missing_input = [_]?*const anyopaque{ null, &input_b };
    try std.testing.expectEqual(
        @as(i32, -1),
        capture_callback(MockApi.callback_context, 8, &missing_input),
    );
    var misaligned_input_storage: [65]u8 align(@alignOf(f64)) =
        undefined;
    const misaligned_input: *const anyopaque = @ptrFromInt(
        @intFromPtr(&misaligned_input_storage) + 1,
    );
    const misaligned_inputs = [_]?*const anyopaque{
        misaligned_input,
        &input_b,
    };
    try std.testing.expectEqual(
        @as(i32, -1),
        capture_callback(
            MockApi.callback_context,
            8,
            &misaligned_inputs,
        ),
    );
    const missing_output = [_]?*anyopaque{ &output_a, null };
    try std.testing.expectEqual(
        @as(i32, -1),
        render_callback(
            MockApi.callback_context,
            4,
            &missing_output,
        ),
    );
    var misaligned_output_storage: [33]u8 align(@alignOf(f64)) =
        undefined;
    const misaligned_output: *anyopaque = @ptrFromInt(
        @intFromPtr(&misaligned_output_storage) + 1,
    );
    const misaligned_outputs = [_]?*anyopaque{
        misaligned_output,
        &output_b,
    };
    try std.testing.expectEqual(
        @as(i32, -1),
        render_callback(
            MockApi.callback_context,
            4,
            &misaligned_outputs,
        ),
    );
    try std.testing.expectEqual(
        @as(i32, -1),
        render_callback(MockApi.callback_context, 9, &outputs),
    );

    MockApi.device_failures = 5;
    MockApi.input_device_failures = 2;
    MockApi.output_device_failures = 3;
    const failure_snapshot = try backend.failureSource().snapshot();
    try std.testing.expectEqual(
        @as(u64, 2),
        failure_snapshot.audio_input,
    );
    try std.testing.expectEqual(
        @as(u64, 3),
        failure_snapshot.audio_output,
    );
    try std.testing.expectEqual(
        DirectionalDeviceFailures{
            .input = 2,
            .output = 3,
        },
        backend.directionalDeviceFailures(),
    );
    backend.stop();
    try std.testing.expectEqual(@as(usize, 1), MockApi.stop_count);
    try std.testing.expect(backend.split_callback == null);
    try std.testing.expectEqual(@as(usize, 0), backend.maximum_frames);
    try std.testing.expectEqual(
        DirectionalDeviceFailures{
            .input = 2,
            .output = 3,
        },
        backend.directionalDeviceFailures(),
    );

    var context: u8 = 0;
    const no_op = standalone.SplitAudioCallback(f64){
        .context = &context,
        .capture_block = struct {
            fn capture(
                _: *anyopaque,
                _: []const []const f64,
            ) void {}
        }.capture,
        .render_block = struct {
            fn render(
                _: *anyopaque,
                _: standalone.CaptureRenderBlock(f64),
            ) void {}
        }.render,
    };
    try std.testing.expectError(
        error.CoreAudioSplitRequiresDuplex,
        backend.startSplit(.{
            .sample_rate = 48_000.0,
            .max_block_size = 8,
            .input_channel_count = 2,
            .output_channel_count = 0,
        }, no_op),
    );
    MockApi.fail_start = true;
    try std.testing.expectError(
        error.MockStartFailed,
        backend.startSplit(.{
            .sample_rate = 48_000.0,
            .max_block_size = 8,
            .input_channel_count = 1,
            .output_channel_count = 1,
        }, no_op),
    );
    try std.testing.expect(!backend.isRunning());
    try std.testing.expect(backend.split_callback == null);
    try std.testing.expectEqual(@as(usize, 0), backend.maximum_frames);
}

test "backend start is transactional and validates device capacity" {
    MockApi.reset();
    const TestBackend = Backend(MockApi, f32);
    var backend = TestBackend{};
    const input_identifier = try device_catalog.DeviceIdentifier.init(
        "coreaudio:input",
    );
    try backend.select(input_identifier);
    var context: u8 = 0;
    const callback = standalone.AudioCallback(f32){
        .context = &context,
        .process_block = struct {
            fn process(
                _: *anyopaque,
                _: standalone.CallbackBlock(f32),
            ) void {}
        }.process,
    };
    try std.testing.expectError(
        error.CoreAudioInsufficientOutputChannels,
        backend.start(.{
            .sample_rate = 48_000.0,
            .max_block_size = 64,
            .input_channel_count = 0,
            .output_channel_count = 1,
        }, callback),
    );
    try std.testing.expect(!backend.isRunning());
    try backend.clearSelection();
    MockApi.fail_start = true;
    try std.testing.expectError(
        error.MockStartFailed,
        backend.start(.{
            .sample_rate = 48_000.0,
            .max_block_size = 64,
            .input_channel_count = 0,
            .output_channel_count = 1,
        }, callback),
    );
    try std.testing.expect(!backend.isRunning());
    try std.testing.expect(backend.callback == null);
}

test "CoreAudio backend selects auxiliary bus storage capacity" {
    MockApi.reset();
    const TestBackend = BoundedBackend(MockApi, f32, 12);
    std.testing.refAllDecls(TestBackend);
    const Probe = struct {
        calls: usize = 0,

        fn process(
            context: *anyopaque,
            block: standalone.CallbackBlock(f32),
        ) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.calls += 1;
            std.debug.assert(block.input_channels.len == 0);
            std.debug.assert(block.auxiliary_input_channels.len == 12);
            std.debug.assert(block.auxiliary_input_bus_channel_counts.len == 12);
            std.debug.assert(block.output_channels.len == 0);
            std.debug.assert(block.auxiliary_output_channels.len == 12);
            std.debug.assert(block.auxiliary_output_bus_channel_counts.len == 12);
            for (
                block.auxiliary_input_channels,
                block.auxiliary_output_channels,
            ) |input, output| {
                @memcpy(output, input);
            }
        }
    };
    var backend = TestBackend{};

    try std.testing.expectEqual(
        @as(usize, 12),
        backend.auxiliary_input_channel_counts.len,
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        backend.auxiliary_output_channel_counts.len,
    );

    const bus_channels = [_]usize{1} ** 12;
    var probe = Probe{};
    MockApi.large_channel_count = true;
    try backend.start(.{
        .sample_rate = 48_000,
        .max_block_size = 1,
        .input_channel_count = 0,
        .auxiliary_input_bus_channel_counts = &bus_channels,
        .output_channel_count = 0,
        .auxiliary_output_bus_channel_counts = &bus_channels,
    }, .{
        .context = &probe,
        .process_block = Probe.process,
    });

    const input_samples = [_]f32{
        0, 1, 2, 3, 4,  5,
        6, 7, 8, 9, 10, 11,
    };
    var output_samples: [12]f32 = @splat(0);
    var input_pointers: [12]?*const anyopaque = undefined;
    var output_pointers: [12]?*anyopaque = undefined;
    for (0..12) |index| {
        input_pointers[index] = &input_samples[index];
        output_pointers[index] = &output_samples[index];
    }
    const process = MockApi.callback_function orelse
        return error.MissingCallback;
    try std.testing.expectEqual(
        @as(i32, 0),
        process(
            MockApi.callback_context,
            1,
            &input_pointers,
            &output_pointers,
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &input_samples,
        &output_samples,
    );
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    backend.stop();

    const too_many_bus_channels = [_]usize{1} ** 13;
    try std.testing.expectError(
        error.TooManyAudioBuses,
        backend.start(.{
            .sample_rate = 48_000,
            .max_block_size = 1,
            .input_channel_count = 0,
            .auxiliary_input_bus_channel_counts = &too_many_bus_channels,
            .output_channel_count = 0,
        }, .{
            .context = &probe,
            .process_block = Probe.process,
        }),
    );
}

test "native CoreAudio discovery exposes valid device records" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    var backend = CoreAudioBackend(f32){};
    defer backend.deinit();
    try backend.startObservingTopology();
    var descriptors: [process_api.max_audio_channels]device_catalog.DeviceDescriptor =
        undefined;
    const count = backend.enumerate(&descriptors) catch |err| switch (err) {
        error.CoreAudioDeviceStorageTooSmall => return error.SkipZigTest,
        else => return err,
    };
    if (count == 0) return error.SkipZigTest;
    for (descriptors[0..count]) |*descriptor| {
        try std.testing.expect(descriptor.valid());
        try std.testing.expectEqual(
            device_catalog.DeviceKind.audio,
            descriptor.kind,
        );
        const info = try backend.runtimeInfo(descriptor.identifier);
        try std.testing.expect(info.valid());
    }
}
