const builtin = @import("builtin");
const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const device_catalog = core.plugin;
const standalone = core.plugin;

const maximum_native_channels = 64;
const maximum_native_identifier_bytes = 512;
const maximum_native_name_bytes = 512;
const input_identifier_text = "pipewire:default-input";
const output_identifier_text = "pipewire:default-output";

const Direction = enum(u8) {
    capture,
    playback,
};

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

pub const Statistics = struct {
    processed: u64,
    callback_failures: u64,
    capture_underflows: u64,
    capture_overflows: u64,
    recoveries: u64,
    device_failures: u64,
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
        @compileError("PipeWire supports f32 and f64");
    if (maximum_auxiliary_buses >= std.math.maxInt(u8))
        @compileError("PipeWire supports at most 254 auxiliary buses");

    return struct {
        const Self = @This();

        selected_input: ?device_catalog.DeviceIdentifier = null,
        selected_output: ?device_catalog.DeviceIdentifier = null,
        session: ?Api.Session = null,
        final_statistics: Statistics = emptyStatistics(),
        callback: ?standalone.AudioCallback(Sample) = null,
        split_callback: ?standalone.SplitAudioCallback(Sample) = null,
        maximum_frames: usize = 0,
        main_input_channel_count: usize = 0,
        main_output_channel_count: usize = 0,
        auxiliary_input_channel_counts: [maximum_auxiliary_buses]usize =
            @splat(0),
        auxiliary_input_bus_count: usize = 0,
        auxiliary_output_channel_counts: [maximum_auxiliary_buses]usize =
            @splat(0),
        auxiliary_output_bus_count: usize = 0,
        input_views: [standalone.maximum_routed_channels][]const Sample =
            undefined,
        output_views: [standalone.maximum_routed_channels][]Sample =
            undefined,
        topology_generation: u64 = 0,
        topology_fingerprint: u64 = 0,

        /// Keep the backend at a stable address while audio is running.
        pub fn audioDevice(self: *Self) standalone.AudioDevice(Sample) {
            return .{
                .context = self,
                .start_audio = startAudioDevice,
                .stop_audio = stopAudioDevice,
            };
        }

        pub fn available(self: *const Self) bool {
            _ = self;
            return Api.supported and Api.available();
        }

        pub fn currentTopologyGeneration(self: *const Self) u64 {
            return self.topology_generation;
        }

        pub fn refreshTopology(self: *Self) !u64 {
            try requireAvailable(Api);
            const fingerprint = try topologyFingerprint(Api);
            if (self.topology_generation == 0 or
                fingerprint != self.topology_fingerprint)
            {
                self.topology_generation +%= 1;
                if (self.topology_generation == 0)
                    self.topology_generation = 1;
                self.topology_fingerprint = fingerprint;
            }
            return self.topology_generation;
        }

        pub fn pollTopology(self: *Self) !bool {
            const previous = self.currentTopologyGeneration();
            return try self.refreshTopology() != previous;
        }

        pub fn enumerate(
            self: *Self,
            output: []device_catalog.DeviceDescriptor,
        ) !usize {
            try requireAvailable(Api);
            const snapshot = try Api.snapshot();
            defer Api.closeSnapshot(snapshot);
            const initial_fingerprint = try snapshotFingerprint(
                Api,
                snapshot,
            );
            var count: usize = 0;
            if (output.len < 2)
                return error.PipeWireDeviceStorageTooSmall;
            output[0] = try device_catalog.DeviceDescriptor.init(
                .audio_input,
                input_identifier_text,
                "PipeWire default input",
                maximum_native_channels,
                0,
                true,
            );
            output[1] = try device_catalog.DeviceDescriptor.init(
                .audio_output,
                output_identifier_text,
                "PipeWire default output",
                0,
                maximum_native_channels,
                true,
            );
            count = 2;
            inline for (.{ Direction.capture, Direction.playback }) |direction| {
                for (0..Api.deviceCount(snapshot, direction)) |index| {
                    if (count == output.len)
                        return error.PipeWireDeviceStorageTooSmall;
                    var identifier_storage: [maximum_native_identifier_bytes]u8 = undefined;
                    var name_storage: [maximum_native_name_bytes]u8 = undefined;
                    var bounded_name_storage: [device_catalog.maximum_device_name_bytes]u8 =
                        undefined;
                    const raw_identifier = try Api.deviceId(
                        snapshot,
                        direction,
                        index,
                        &identifier_storage,
                    );
                    const channels = try Api.deviceChannels(
                        snapshot,
                        direction,
                        index,
                    );
                    if (channels == 0 or
                        channels > maximum_native_channels)
                        continue;
                    const identifier = try endpointIdentifier(
                        direction,
                        raw_identifier,
                    );
                    const raw_name = try Api.deviceName(
                        snapshot,
                        direction,
                        index,
                        &name_storage,
                    );
                    const name = try boundedDeviceName(
                        raw_name,
                        &bounded_name_storage,
                    );
                    output[count] = try device_catalog.DeviceDescriptor.init(
                        if (direction == .capture)
                            .audio_input
                        else
                            .audio_output,
                        identifier.slice(),
                        name,
                        if (direction == .capture)
                            @intCast(channels)
                        else
                            0,
                        if (direction == .playback)
                            @intCast(channels)
                        else
                            0,
                        false,
                    );
                    count += 1;
                }
            }
            const final_snapshot = try Api.snapshot();
            defer Api.closeSnapshot(final_snapshot);
            const final_fingerprint = try snapshotFingerprint(
                Api,
                final_snapshot,
            );
            if (final_fingerprint != initial_fingerprint)
                return error.PipeWireTopologyChanged;
            self.updateTopology(final_fingerprint);
            return count;
        }

        pub fn selectInput(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            try requireAvailable(Api);
            if (self.session != null)
                return error.PipeWireBackendRunning;
            try validateSelection(Api, .capture, identifier);
            self.selected_input = identifier;
        }

        pub fn selectOutput(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            try requireAvailable(Api);
            if (self.session != null)
                return error.PipeWireBackendRunning;
            try validateSelection(Api, .playback, identifier);
            self.selected_output = identifier;
        }

        pub fn clearInputSelection(self: *Self) !void {
            if (self.session != null)
                return error.PipeWireBackendRunning;
            self.selected_input = null;
        }

        pub fn clearOutputSelection(self: *Self) !void {
            if (self.session != null)
                return error.PipeWireBackendRunning;
            self.selected_output = null;
        }

        pub fn isRunning(self: *const Self) bool {
            return self.session != null;
        }

        pub fn statistics(self: *const Self) Statistics {
            const session = self.session orelse
                return self.final_statistics;
            return Api.statistics(session);
        }

        pub fn failureSource(
            self: *Self,
        ) device_catalog.DeviceFailureSource {
            return .{
                .context = self,
                .read_snapshot = readFailureSnapshot,
            };
        }

        pub fn start(
            self: *Self,
            configuration: standalone.DeviceConfiguration,
            callback: standalone.AudioCallback(Sample),
        ) !void {
            try self.startInternal(configuration, callback, null);
        }

        pub fn startSplit(
            self: *Self,
            configuration: standalone.DeviceConfiguration,
            callback: standalone.SplitAudioCallback(Sample),
        ) !void {
            try self.startInternal(configuration, null, callback);
        }

        pub fn stop(self: *Self) void {
            if (self.session) |session|
                self.final_statistics = Api.stop(session);
            self.clearRuntimeState();
        }

        pub fn deinit(self: *Self) void {
            self.stop();
        }

        fn readFailureSnapshot(
            context: *anyopaque,
        ) !device_catalog.DeviceFailureSnapshot {
            const self: *Self = @ptrCast(@alignCast(context));
            const failures = self.statistics().device_failures;
            return .{
                .audio_input = if (self.totalInputChannels() catch 0 != 0)
                    failures
                else
                    0,
                .audio_output = if (self.totalOutputChannels() catch 0 != 0)
                    failures
                else
                    0,
            };
        }

        fn startInternal(
            self: *Self,
            configuration: standalone.DeviceConfiguration,
            callback: ?standalone.AudioCallback(Sample),
            split_callback: ?standalone.SplitAudioCallback(Sample),
        ) !void {
            try requireAvailable(Api);
            if (self.session != null)
                return error.PipeWireBackendRunning;
            if ((callback == null) == (split_callback == null))
                return error.InvalidPipeWireCallbackMode;
            try configuration.validate();
            if (configuration.auxiliary_input_bus_channel_counts.len >
                maximum_auxiliary_buses or
                configuration.auxiliary_output_bus_channel_counts.len >
                    maximum_auxiliary_buses)
                return error.TooManyAudioBuses;
            if (@floor(configuration.sample_rate) !=
                configuration.sample_rate or
                configuration.sample_rate > std.math.maxInt(u32))
                return error.InvalidPipeWireSampleRate;
            const input_count = try totalChannels(
                configuration.input_channel_count,
                configuration.auxiliary_input_bus_channel_counts,
            );
            const output_count = try totalChannels(
                configuration.output_channel_count,
                configuration.auxiliary_output_bus_channel_counts,
            );
            if (input_count == 0 and output_count == 0)
                return error.PipeWireRequiresAudioChannels;
            if (input_count > maximum_native_channels)
                return error.PipeWireInsufficientInputChannels;
            if (output_count > maximum_native_channels)
                return error.PipeWireInsufficientOutputChannels;
            if (split_callback != null and
                (input_count == 0 or output_count == 0))
                return error.PipeWireSplitRequiresDuplex;

            var input_target_storage: [maximum_native_identifier_bytes]u8 = undefined;
            var output_target_storage: [maximum_native_identifier_bytes]u8 = undefined;
            const input_target = if (input_count == 0)
                null
            else
                try resolveSelectedTarget(
                    Api,
                    .capture,
                    self.selected_input,
                    &input_target_storage,
                );
            const output_target = if (output_count == 0)
                null
            else
                try resolveSelectedTarget(
                    Api,
                    .playback,
                    self.selected_output,
                    &output_target_storage,
                );
            self.callback = callback;
            self.split_callback = split_callback;
            self.maximum_frames = configuration.max_block_size;
            self.final_statistics = emptyStatistics();
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
            self.session = if (split_callback != null)
                try Api.startSplit(
                    input_target,
                    output_target,
                    @sizeOf(Sample),
                    @intFromFloat(configuration.sample_rate),
                    configuration.max_block_size,
                    @intCast(input_count),
                    @intCast(output_count),
                    self,
                    captureChannels,
                    renderChannels,
                )
            else
                try Api.start(
                    input_target,
                    output_target,
                    @sizeOf(Sample),
                    @intFromFloat(configuration.sample_rate),
                    configuration.max_block_size,
                    @intCast(input_count),
                    @intCast(output_count),
                    self,
                    processChannels,
                );
        }

        fn updateTopology(self: *Self, fingerprint: u64) void {
            if (self.topology_generation == 0 or
                fingerprint != self.topology_fingerprint)
            {
                self.topology_generation +%= 1;
                if (self.topology_generation == 0)
                    self.topology_generation = 1;
                self.topology_fingerprint = fingerprint;
            }
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

        fn processChannels(
            context: ?*anyopaque,
            frame_count_u32: u32,
            input_channels: [*c]const ?*const anyopaque,
            output_channels: [*c]const ?*anyopaque,
        ) callconv(.c) i32 {
            const self = callbackContext(context) orelse return -1;
            const callback = self.callback orelse return -1;
            const input_count = self.totalInputChannels() catch return -1;
            const output_count = self.totalOutputChannels() catch return -1;
            const frame_count: usize = frame_count_u32;
            if (frame_count > self.maximum_frames)
                return -1;
            if (!self.setInputViews(
                input_channels,
                input_count,
                frame_count,
            ))
                return -1;
            if (!self.setOutputViews(
                output_channels,
                output_count,
                frame_count,
            ))
                return -1;
            callback.process_block(callback.context, .{
                .input_channels = self.input_views[0..self.main_input_channel_count],
                .auxiliary_input_channels = self.input_views[self.main_input_channel_count..input_count],
                .auxiliary_input_bus_channel_counts = self.auxiliary_input_channel_counts[0..self.auxiliary_input_bus_count],
                .output_channels = self.output_views[0..self.main_output_channel_count],
                .auxiliary_output_channels = self.output_views[self.main_output_channel_count..output_count],
                .auxiliary_output_bus_channel_counts = self.auxiliary_output_channel_counts[0..self.auxiliary_output_bus_count],
            });
            return 0;
        }

        fn captureChannels(
            context: ?*anyopaque,
            frame_count_u32: u32,
            input_channels: [*c]const ?*const anyopaque,
        ) callconv(.c) i32 {
            const self = callbackContext(context) orelse return -1;
            const callback = self.split_callback orelse return -1;
            const input_count = self.totalInputChannels() catch return -1;
            const frame_count: usize = frame_count_u32;
            if (frame_count > self.maximum_frames)
                return -1;
            if (!self.setInputViews(
                input_channels,
                input_count,
                frame_count,
            ))
                return -1;
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
            const callback = self.split_callback orelse return -1;
            const output_count = self.totalOutputChannels() catch return -1;
            const frame_count: usize = frame_count_u32;
            if (frame_count > self.maximum_frames)
                return -1;
            if (!self.setOutputViews(
                output_channels,
                output_count,
                frame_count,
            ))
                return -1;
            callback.render_block(callback.context, .{
                .frame_count = frame_count,
                .output_channels = self.output_views[0..self.main_output_channel_count],
                .auxiliary_output_channels = self.output_views[self.main_output_channel_count..output_count],
                .auxiliary_output_bus_channel_counts = self.auxiliary_output_channel_counts[0..self.auxiliary_output_bus_count],
            });
            return 0;
        }

        fn setInputViews(
            self: *Self,
            channels: [*c]const ?*const anyopaque,
            channel_count: usize,
            frame_count: usize,
        ) bool {
            if (channel_count != 0 and channels == null)
                return false;
            for (0..channel_count) |index| {
                const pointer = channels[index] orelse return false;
                if (@intFromPtr(pointer) % @alignOf(Sample) != 0)
                    return false;
                const samples: [*]const Sample =
                    @ptrCast(@alignCast(pointer));
                self.input_views[index] = samples[0..frame_count];
            }
            return true;
        }

        fn setOutputViews(
            self: *Self,
            channels: [*c]const ?*anyopaque,
            channel_count: usize,
            frame_count: usize,
        ) bool {
            if (channel_count != 0 and channels == null)
                return false;
            for (0..channel_count) |index| {
                const pointer = channels[index] orelse return false;
                if (@intFromPtr(pointer) % @alignOf(Sample) != 0)
                    return false;
                const samples: [*]Sample =
                    @ptrCast(@alignCast(pointer));
                self.output_views[index] = samples[0..frame_count];
            }
            return true;
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

pub fn PipeWireBackend(comptime Sample: type) type {
    return Backend(PipeWireSystemApi, Sample);
}

pub fn BoundedPipeWireBackend(
    comptime Sample: type,
    comptime maximum_auxiliary_buses: usize,
) type {
    return BoundedBackend(
        PipeWireSystemApi,
        Sample,
        maximum_auxiliary_buses,
    );
}

fn defaultIdentifierText(direction: Direction) []const u8 {
    return if (direction == .capture)
        input_identifier_text
    else
        output_identifier_text;
}

fn identifierMatches(
    identifier: device_catalog.DeviceIdentifier,
    expected: []const u8,
) bool {
    return identifier.valid() and
        std.mem.eql(u8, identifier.slice(), expected);
}

fn boundedDeviceName(raw: []const u8, storage: []u8) ![]const u8 {
    if (raw.len == 0 or !std.unicode.utf8ValidateSlice(raw) or
        std.mem.indexOfScalar(u8, raw, 0) != null)
        return error.InvalidPipeWireDeviceName;
    var source_length = @min(raw.len, storage.len);
    while (source_length != 0 and
        !std.unicode.utf8ValidateSlice(raw[0..source_length]))
        source_length -= 1;
    if (source_length == 0)
        return error.PipeWireDeviceNameTooLong;
    for (raw[0..source_length], 0..) |byte, index| {
        storage[index] = if (byte == '\n' or byte == '\r')
            ' '
        else
            byte;
    }
    return std.mem.trim(u8, storage[0..source_length], " ");
}

fn endpointIdentifier(
    direction: Direction,
    raw_identifier: []const u8,
) !device_catalog.DeviceIdentifier {
    if (raw_identifier.len == 0 or
        !std.unicode.utf8ValidateSlice(raw_identifier) or
        std.mem.indexOfScalar(u8, raw_identifier, 0) != null)
        return error.InvalidPipeWireEndpointIdentifier;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(
        raw_identifier,
        &digest,
        .{},
    );
    const prefix = if (direction == .capture)
        "pipewire-input:"
    else
        "pipewire-output:";
    var storage: [device_catalog.maximum_device_identifier_bytes]u8 = undefined;
    const encoded = std.fmt.bytesToHex(digest, .lower);
    @memcpy(storage[0..prefix.len], prefix);
    @memcpy(
        storage[prefix.len .. prefix.len + encoded.len],
        &encoded,
    );
    return device_catalog.DeviceIdentifier.init(
        storage[0 .. prefix.len + encoded.len],
    );
}

fn validateSelection(
    comptime Api: type,
    direction: Direction,
    identifier: device_catalog.DeviceIdentifier,
) !void {
    if (identifierMatches(identifier, defaultIdentifierText(direction)))
        return;
    var storage: [maximum_native_identifier_bytes]u8 = undefined;
    _ = try resolveIdentifier(
        Api,
        direction,
        identifier,
        &storage,
    );
}

fn resolveSelectedTarget(
    comptime Api: type,
    direction: Direction,
    selected: ?device_catalog.DeviceIdentifier,
    storage: []u8,
) !?[]const u8 {
    const identifier = selected orelse return null;
    if (identifierMatches(identifier, defaultIdentifierText(direction)))
        return null;
    const length = try resolveIdentifier(
        Api,
        direction,
        identifier,
        storage,
    );
    return storage[0..length];
}

fn resolveIdentifier(
    comptime Api: type,
    direction: Direction,
    identifier: device_catalog.DeviceIdentifier,
    output: []u8,
) !usize {
    if (!identifier.valid())
        return error.InvalidDeviceIdentifier;
    const snapshot = try Api.snapshot();
    defer Api.closeSnapshot(snapshot);
    var storage: [maximum_native_identifier_bytes]u8 = undefined;
    for (0..Api.deviceCount(snapshot, direction)) |index| {
        const raw = try Api.deviceId(
            snapshot,
            direction,
            index,
            &storage,
        );
        const candidate = try endpointIdentifier(direction, raw);
        if (!candidate.eql(&identifier))
            continue;
        if (output.len < raw.len)
            return error.PipeWireEndpointStorageTooSmall;
        @memcpy(output[0..raw.len], raw);
        return raw.len;
    }
    return error.PipeWireDeviceNotFound;
}

fn snapshotFingerprint(
    comptime Api: type,
    snapshot: Api.Snapshot,
) !u64 {
    var hasher = std.hash.Wyhash.init(0);
    inline for (.{ Direction.capture, Direction.playback }) |direction| {
        const count = Api.deviceCount(snapshot, direction);
        hasher.update(std.mem.asBytes(&count));
        var storage: [maximum_native_identifier_bytes]u8 = undefined;
        for (0..count) |index| {
            hasher.update(try Api.deviceId(
                snapshot,
                direction,
                index,
                &storage,
            ));
            const channels = try Api.deviceChannels(
                snapshot,
                direction,
                index,
            );
            hasher.update(std.mem.asBytes(&channels));
        }
    }
    return hasher.final();
}

fn topologyFingerprint(comptime Api: type) !u64 {
    const snapshot = try Api.snapshot();
    defer Api.closeSnapshot(snapshot);
    return snapshotFingerprint(Api, snapshot);
}

fn requireAvailable(comptime Api: type) !void {
    if (!Api.supported) return error.UnsupportedPlatform;
    if (!Api.available()) return error.PipeWireLibraryUnavailable;
}

fn totalChannels(main: usize, auxiliary: []const usize) !usize {
    var total = main;
    for (auxiliary) |count| {
        total = std.math.add(usize, total, count) catch
            return error.PipeWireChannelCountOverflow;
    }
    if (total > standalone.maximum_routed_channels)
        return error.PipeWireChannelCountTooLarge;
    return total;
}

fn emptyStatistics() Statistics {
    return .{
        .processed = 0,
        .callback_failures = 0,
        .capture_underflows = 0,
        .capture_overflows = 0,
        .recoveries = 0,
        .device_failures = 0,
    };
}

const PipeWireSystemApi = if (builtin.os.tag == .linux)
    LinuxPipeWireApi
else
    UnsupportedPipeWireApi;

const UnsupportedPipeWireApi = struct {
    const supported = false;
    const Session = u32;
    const Snapshot = u32;

    fn available() bool {
        return false;
    }

    fn snapshot() !Snapshot {
        return error.UnsupportedPlatform;
    }

    fn closeSnapshot(_: Snapshot) void {}

    fn deviceCount(_: Snapshot, _: Direction) usize {
        return 0;
    }

    fn deviceId(
        _: Snapshot,
        _: Direction,
        _: usize,
        _: []u8,
    ) ![]const u8 {
        return error.UnsupportedPlatform;
    }

    fn deviceName(
        _: Snapshot,
        _: Direction,
        _: usize,
        _: []u8,
    ) ![]const u8 {
        return error.UnsupportedPlatform;
    }

    fn deviceChannels(
        _: Snapshot,
        _: Direction,
        _: usize,
    ) !u32 {
        return error.UnsupportedPlatform;
    }

    fn start(
        _: ?[]const u8,
        _: ?[]const u8,
        _: usize,
        _: u32,
        _: u32,
        _: u32,
        _: u32,
        _: *anyopaque,
        _: ProcessChannels,
    ) !Session {
        return error.UnsupportedPlatform;
    }

    fn startSplit(
        _: ?[]const u8,
        _: ?[]const u8,
        _: usize,
        _: u32,
        _: u32,
        _: u32,
        _: u32,
        _: *anyopaque,
        _: CaptureChannels,
        _: RenderChannels,
    ) !Session {
        return error.UnsupportedPlatform;
    }

    fn statistics(_: Session) Statistics {
        return emptyStatistics();
    }

    fn stop(_: Session) Statistics {
        return emptyStatistics();
    }
};

const LinuxPipeWireApi = if (builtin.os.tag == .linux) struct {
    const c = @cImport({
        @cInclude("pipewire_shim.h");
    });
    const supported = true;
    const Session = *c.zv3_pipewire_session;
    const Snapshot = *c.zv3_pipewire_snapshot;

    fn available() bool {
        return c.zv3_pipewire_available() != 0;
    }

    fn snapshot() !Snapshot {
        var result: ?Snapshot = null;
        if (c.zv3_pipewire_snapshot_create(&result) != 0)
            return error.PipeWireDeviceQueryFailed;
        return result orelse error.PipeWireDeviceQueryFailed;
    }

    fn closeSnapshot(value: Snapshot) void {
        c.zv3_pipewire_snapshot_destroy(value);
    }

    fn deviceCount(value: Snapshot, direction: Direction) usize {
        return c.zv3_pipewire_snapshot_count(
            value,
            @intFromEnum(direction),
        );
    }

    fn deviceId(
        value: Snapshot,
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_pipewire_snapshot_identifier(
            value,
            @intFromEnum(direction),
            index,
            storage.ptr,
            storage.len,
            &length,
        ) != 0 or
            length == 0 or
            length > storage.len)
            return error.PipeWireDeviceQueryFailed;
        return storage[0..length];
    }

    fn deviceName(
        value: Snapshot,
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_pipewire_snapshot_name(
            value,
            @intFromEnum(direction),
            index,
            storage.ptr,
            storage.len,
            &length,
        ) != 0 or
            length == 0 or
            length > storage.len)
            return error.PipeWireDeviceQueryFailed;
        return storage[0..length];
    }

    fn deviceChannels(
        value: Snapshot,
        direction: Direction,
        index: usize,
    ) !u32 {
        var result: u32 = 0;
        if (c.zv3_pipewire_snapshot_channels(
            value,
            @intFromEnum(direction),
            index,
            &result,
        ) != 0)
            return error.PipeWireDeviceQueryFailed;
        return result;
    }

    fn start(
        input_target: ?[]const u8,
        output_target: ?[]const u8,
        sample_bytes: usize,
        sample_rate: u32,
        maximum_frames: u32,
        input_channels: u32,
        output_channels: u32,
        context: *anyopaque,
        process: ProcessChannels,
    ) !Session {
        var session: ?Session = null;
        if (c.zv3_pipewire_start(
            if (input_target) |value| value.ptr else null,
            if (input_target) |value| value.len else 0,
            if (output_target) |value| value.ptr else null,
            if (output_target) |value| value.len else 0,
            @intCast(sample_bytes),
            sample_rate,
            maximum_frames,
            input_channels,
            output_channels,
            context,
            process,
            &session,
        ) != 0)
            return error.PipeWireStartFailed;
        return session orelse error.PipeWireStartFailed;
    }

    fn startSplit(
        input_target: ?[]const u8,
        output_target: ?[]const u8,
        sample_bytes: usize,
        sample_rate: u32,
        maximum_frames: u32,
        input_channels: u32,
        output_channels: u32,
        context: *anyopaque,
        capture: CaptureChannels,
        render: RenderChannels,
    ) !Session {
        var session: ?Session = null;
        if (c.zv3_pipewire_start_split(
            if (input_target) |value| value.ptr else null,
            if (input_target) |value| value.len else 0,
            if (output_target) |value| value.ptr else null,
            if (output_target) |value| value.len else 0,
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
            return error.PipeWireStartFailed;
        return session orelse error.PipeWireStartFailed;
    }

    fn statistics(session: Session) Statistics {
        var result: c.zv3_pipewire_statistics = undefined;
        c.zv3_pipewire_get_statistics(session, &result);
        return fromCStatistics(result);
    }

    fn stop(session: Session) Statistics {
        var result: c.zv3_pipewire_statistics = undefined;
        c.zv3_pipewire_stop(session, &result);
        return fromCStatistics(result);
    }

    fn fromCStatistics(value: c.zv3_pipewire_statistics) Statistics {
        return .{
            .processed = value.processed,
            .callback_failures = value.callback_failures,
            .capture_underflows = value.capture_underflows,
            .capture_overflows = value.capture_overflows,
            .recoveries = value.recoveries,
            .device_failures = value.device_failures,
        };
    }
} else struct {};

test "unsupported PipeWire backend fails explicitly" {
    if (builtin.os.tag == .linux) return error.SkipZigTest;
    var backend = PipeWireBackend(f32){};
    var descriptors: [2]device_catalog.DeviceDescriptor = undefined;
    try std.testing.expect(!backend.available());
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.enumerate(&descriptors),
    );
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.refreshTopology(),
    );
}

test "native PipeWire availability query is stable" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var backend = PipeWireBackend(f32){};
    try std.testing.expectEqual(
        backend.available(),
        backend.available(),
    );
}

const MockApi = struct {
    const supported = true;
    const Session = u32;
    const Snapshot = u32;
    var is_available = true;
    var fail_start = false;
    var expect_named_targets = false;
    var topology_revision: u32 = 1;
    var final_statistics = Statistics{
        .processed = 3,
        .callback_failures = 1,
        .capture_underflows = 2,
        .capture_overflows = 4,
        .recoveries = 5,
        .device_failures = 6,
    };

    fn reset() void {
        is_available = true;
        fail_start = false;
        expect_named_targets = false;
        topology_revision = 1;
    }

    fn available() bool {
        return is_available;
    }

    fn snapshot() !Snapshot {
        if (!is_available)
            return error.MockUnavailable;
        return topology_revision;
    }

    fn closeSnapshot(_: Snapshot) void {}

    fn deviceCount(_: Snapshot, _: Direction) usize {
        return 1;
    }

    fn deviceId(
        snapshot_revision: Snapshot,
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        if (index != 0)
            return error.MockDeviceNotFound;
        const value = if (snapshot_revision == 1)
            if (direction == .capture)
                "mock-source"
            else
                "mock-sink"
        else if (direction == .capture)
            "mock-source-new"
        else
            "mock-sink-new";
        if (storage.len < value.len)
            return error.MockStorageTooSmall;
        @memcpy(storage[0..value.len], value);
        return storage[0..value.len];
    }

    fn deviceName(
        _: Snapshot,
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        if (index != 0)
            return error.MockDeviceNotFound;
        const value = if (direction == .capture)
            "Mock source"
        else
            "Mock sink";
        if (storage.len < value.len)
            return error.MockStorageTooSmall;
        @memcpy(storage[0..value.len], value);
        return storage[0..value.len];
    }

    fn deviceChannels(
        _: Snapshot,
        _: Direction,
        index: usize,
    ) !u32 {
        if (index != 0)
            return error.MockDeviceNotFound;
        return 8;
    }

    fn start(
        input_target: ?[]const u8,
        output_target: ?[]const u8,
        sample_bytes: usize,
        sample_rate: u32,
        maximum_frames: u32,
        input_channels: u32,
        output_channels: u32,
        context: *anyopaque,
        process: ProcessChannels,
    ) !Session {
        if (fail_start) return error.MockStartFailed;
        if (sample_bytes != @sizeOf(f32) or
            sample_rate != 48_000 or
            maximum_frames != 4 or
            input_channels != 1 or
            output_channels != 1)
            return error.InvalidMockConfiguration;
        if (expect_named_targets) {
            const actual_input =
                input_target orelse return error.InvalidMockTarget;
            const actual_output =
                output_target orelse return error.InvalidMockTarget;
            if (!std.mem.eql(u8, actual_input, "mock-source") or
                !std.mem.eql(u8, actual_output, "mock-sink"))
                return error.InvalidMockTarget;
        } else if (input_target != null or output_target != null) {
            return error.InvalidMockTarget;
        }
        var input = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
        var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
        var inputs = [_]?*const anyopaque{&input};
        var outputs = [_]?*anyopaque{&output};
        if (process(context, 4, null, &outputs) != -1 or
            process(context, 4, &inputs, null) != -1)
            return error.MockMalformedCallbackAccepted;
        if (process(
            context,
            4,
            &inputs,
            &outputs,
        ) != 0)
            return error.MockCallbackFailed;
        if (!std.mem.eql(f32, &input, &output))
            return error.MockOutputMismatch;
        return 1;
    }

    fn startSplit(
        input_target: ?[]const u8,
        output_target: ?[]const u8,
        _: usize,
        _: u32,
        _: u32,
        _: u32,
        _: u32,
        context: *anyopaque,
        capture: CaptureChannels,
        render: RenderChannels,
    ) !Session {
        if (fail_start) return error.MockStartFailed;
        if (expect_named_targets) {
            const actual_input =
                input_target orelse return error.InvalidMockTarget;
            const actual_output =
                output_target orelse return error.InvalidMockTarget;
            if (!std.mem.eql(u8, actual_input, "mock-source") or
                !std.mem.eql(u8, actual_output, "mock-sink"))
                return error.InvalidMockTarget;
        } else if (input_target != null or output_target != null) {
            return error.InvalidMockTarget;
        }
        var input = [_]f32{ 1.0, 2.0 };
        var output = [_]f32{ 9.0, 9.0 };
        var inputs = [_]?*const anyopaque{&input};
        var outputs = [_]?*anyopaque{&output};
        if (capture(context, 2, null) != -1 or
            render(context, 2, null) != -1)
            return error.MockMalformedCallbackAccepted;
        if (capture(context, 2, &inputs) != 0 or
            render(context, 2, &outputs) != 0)
            return error.MockCallbackFailed;
        return 2;
    }

    fn statistics(_: Session) Statistics {
        return final_statistics;
    }

    fn stop(_: Session) Statistics {
        return final_statistics;
    }
};

const CallbackProbe = struct {
    process_calls: usize = 0,
    capture_calls: usize = 0,
    render_calls: usize = 0,

    fn process(
        context: *anyopaque,
        block: standalone.CallbackBlock(f32),
    ) void {
        const self: *CallbackProbe = @ptrCast(@alignCast(context));
        self.process_calls += 1;
        if (block.input_channels.len == 1 and
            block.output_channels.len == 1)
            @memcpy(
                block.output_channels[0],
                block.input_channels[0],
            );
    }

    fn capture(
        context: *anyopaque,
        channels: []const []const f32,
    ) void {
        const self: *CallbackProbe = @ptrCast(@alignCast(context));
        if (channels.len == 1)
            self.capture_calls += 1;
    }

    fn render(
        context: *anyopaque,
        block: standalone.CaptureRenderBlock(f32),
    ) void {
        const self: *CallbackProbe = @ptrCast(@alignCast(context));
        self.render_calls += 1;
        for (block.output_channels) |channel|
            @memset(channel, 0);
    }
};

test "PipeWire backend exposes bounded defaults and combined audio" {
    MockApi.reset();
    var backend = Backend(MockApi, f32){};
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        try backend.enumerate(&descriptors),
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        backend.currentTopologyGeneration(),
    );
    try std.testing.expect(descriptors[0].is_default);
    try std.testing.expect(descriptors[1].is_default);
    try std.testing.expect(!descriptors[2].is_default);
    try std.testing.expect(!descriptors[3].is_default);
    try backend.selectInput(descriptors[0].identifier);
    try backend.selectOutput(descriptors[1].identifier);

    var probe = CallbackProbe{};
    try backend.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 4,
        .input_channel_count = 1,
        .output_channel_count = 1,
    }, .{
        .context = &probe,
        .process_block = CallbackProbe.process,
    });
    try std.testing.expect(backend.isRunning());
    try std.testing.expectEqual(@as(usize, 1), probe.process_calls);
    const snapshot = try backend.failureSource().snapshot();
    try std.testing.expectEqual(@as(u64, 6), snapshot.audio_input);
    try std.testing.expectEqual(@as(u64, 6), snapshot.audio_output);
    backend.stop();
    try std.testing.expect(!backend.isRunning());
    try std.testing.expectEqual(
        MockApi.final_statistics,
        backend.statistics(),
    );
}

test "PipeWire split callbacks and failed start are transactional" {
    MockApi.reset();
    var backend = Backend(MockApi, f32){};
    var probe = CallbackProbe{};
    const configuration = standalone.DeviceConfiguration{
        .sample_rate = 48_000.0,
        .max_block_size = 4,
        .input_channel_count = 1,
        .output_channel_count = 1,
    };
    try backend.startSplit(configuration, .{
        .context = &probe,
        .capture_block = CallbackProbe.capture,
        .render_block = CallbackProbe.render,
    });
    try std.testing.expectEqual(@as(usize, 1), probe.capture_calls);
    try std.testing.expectEqual(@as(usize, 1), probe.render_calls);
    backend.stop();

    MockApi.fail_start = true;
    try std.testing.expectError(
        error.MockStartFailed,
        backend.start(configuration, .{
            .context = &probe,
            .process_block = CallbackProbe.process,
        }),
    );
    try std.testing.expect(!backend.isRunning());
}

test "PipeWire named node selection resolves current targets" {
    MockApi.reset();
    MockApi.expect_named_targets = true;
    var backend = Backend(MockApi, f32){};
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        try backend.enumerate(&descriptors),
    );
    try backend.selectInput(descriptors[2].identifier);
    try backend.selectOutput(descriptors[3].identifier);
    var probe = CallbackProbe{};
    try backend.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 4,
        .input_channel_count = 1,
        .output_channel_count = 1,
    }, .{
        .context = &probe,
        .process_block = CallbackProbe.process,
    });
    backend.stop();
}

test "PipeWire topology generation changes with node identity" {
    MockApi.reset();
    var backend = Backend(MockApi, f32){};
    try std.testing.expectEqual(
        @as(u64, 1),
        try backend.refreshTopology(),
    );
    try std.testing.expect(!try backend.pollTopology());
    MockApi.topology_revision = 2;
    try std.testing.expect(try backend.pollTopology());
    try std.testing.expectEqual(
        @as(u64, 2),
        backend.currentTopologyGeneration(),
    );
}

test "PipeWire backend rejects malformed configuration and selection" {
    MockApi.reset();
    var backend = Backend(MockApi, f32){};
    var probe = CallbackProbe{};
    const missing = try device_catalog.DeviceIdentifier.init("missing");
    try std.testing.expectError(
        error.PipeWireDeviceNotFound,
        backend.selectInput(missing),
    );
    try std.testing.expectError(
        error.PipeWireRequiresAudioChannels,
        backend.start(.{
            .sample_rate = 48_000.0,
            .max_block_size = 4,
            .input_channel_count = 0,
            .output_channel_count = 0,
        }, .{
            .context = &probe,
            .process_block = CallbackProbe.process,
        }),
    );
    try std.testing.expectError(
        error.InvalidPipeWireSampleRate,
        backend.start(.{
            .sample_rate = 48_000.5,
            .max_block_size = 4,
            .input_channel_count = 1,
            .output_channel_count = 1,
        }, .{
            .context = &probe,
            .process_block = CallbackProbe.process,
        }),
    );
}
