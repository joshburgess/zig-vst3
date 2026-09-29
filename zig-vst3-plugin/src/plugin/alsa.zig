const builtin = @import("builtin");
const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const device_catalog = core.plugin;
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

pub const Statistics = struct {
    processed: u64,
    callback_failures: u64,
    capture_underflows: u64,
    capture_overflows: u64,
    recoveries: u64,
    device_failures: u64,
    realtime_priority_acquired: bool,
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
        @compileError("ALSA supports f32 and f64");
    if (maximum_auxiliary_buses >= std.math.maxInt(u8))
        @compileError("ALSA supports at most 254 auxiliary buses");

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
        auxiliary_input_channel_counts: [maximum_auxiliary_buses]usize = @splat(0),
        auxiliary_input_bus_count: usize = 0,
        auxiliary_output_channel_counts: [maximum_auxiliary_buses]usize = @splat(0),
        auxiliary_output_bus_count: usize = 0,
        input_views: [standalone.maximum_routed_channels][]const Sample = undefined,
        output_views: [standalone.maximum_routed_channels][]Sample = undefined,
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
            const before = self.currentTopologyGeneration();
            return try self.refreshTopology() != before;
        }

        pub fn enumerate(
            self: *Self,
            output: []device_catalog.DeviceDescriptor,
        ) !usize {
            try requireAvailable(Api);
            const initial_fingerprint = try topologyFingerprint(Api);
            const default_input = try defaultIdentifier(Api, .capture);
            const default_output = try defaultIdentifier(Api, .playback);
            var count: usize = 0;
            count = try enumerateDirection(
                Api,
                .capture,
                default_input,
                output,
                count,
            );
            count = try enumerateDirection(
                Api,
                .playback,
                default_output,
                output,
                count,
            );
            const final_fingerprint = try topologyFingerprint(Api);
            if (final_fingerprint != initial_fingerprint)
                return error.AlsaTopologyChanged;
            if (self.topology_generation == 0 or
                final_fingerprint != self.topology_fingerprint)
            {
                self.topology_generation +%= 1;
                if (self.topology_generation == 0)
                    self.topology_generation = 1;
                self.topology_fingerprint = final_fingerprint;
            }
            return count;
        }

        pub fn selectInput(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            try requireAvailable(Api);
            if (self.session != null)
                return error.AlsaBackendRunning;
            _ = try resolveIdentifier(
                Api,
                .capture,
                identifier,
                null,
            );
            self.selected_input = identifier;
        }

        pub fn selectOutput(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            try requireAvailable(Api);
            if (self.session != null)
                return error.AlsaBackendRunning;
            _ = try resolveIdentifier(
                Api,
                .playback,
                identifier,
                null,
            );
            self.selected_output = identifier;
        }

        pub fn clearInputSelection(self: *Self) !void {
            if (self.session != null)
                return error.AlsaBackendRunning;
            self.selected_input = null;
        }

        pub fn clearOutputSelection(self: *Self) !void {
            if (self.session != null)
                return error.AlsaBackendRunning;
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

        fn readFailureSnapshot(
            context: *anyopaque,
        ) !device_catalog.DeviceFailureSnapshot {
            const self: *Self = @ptrCast(@alignCast(context));
            const count = self.statistics().device_failures;
            return .{
                .audio_input = if (self.main_input_channel_count != 0 or
                    self.auxiliary_input_bus_count != 0)
                    count
                else
                    0,
                .audio_output = if (self.main_output_channel_count != 0 or
                    self.auxiliary_output_bus_count != 0)
                    count
                else
                    0,
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

        fn startInternal(
            self: *Self,
            configuration: standalone.DeviceConfiguration,
            callback: ?standalone.AudioCallback(Sample),
            split_callback: ?standalone.SplitAudioCallback(Sample),
        ) !void {
            try requireAvailable(Api);
            if (self.session != null)
                return error.AlsaBackendRunning;
            if ((callback == null) == (split_callback == null))
                return error.InvalidAlsaCallbackMode;
            try configuration.validate();
            if (configuration.auxiliary_input_bus_channel_counts.len >
                maximum_auxiliary_buses or
                configuration.auxiliary_output_bus_channel_counts.len >
                    maximum_auxiliary_buses)
                return error.TooManyAudioBuses;
            if (@floor(configuration.sample_rate) !=
                configuration.sample_rate or
                configuration.sample_rate >
                    std.math.maxInt(u32))
                return error.InvalidAlsaSampleRate;
            const input_count = try totalChannels(
                configuration.input_channel_count,
                configuration.auxiliary_input_bus_channel_counts,
            );
            const output_count = try totalChannels(
                configuration.output_channel_count,
                configuration.auxiliary_output_bus_channel_counts,
            );
            if (input_count == 0 and output_count == 0)
                return error.AlsaRequiresAudioChannels;
            if (split_callback != null and
                (input_count == 0 or output_count == 0))
                return error.AlsaSplitRequiresDuplex;

            var input_storage: [Api.maximum_identifier_bytes]u8 = undefined;
            var output_storage: [Api.maximum_identifier_bytes]u8 = undefined;
            const input_identifier = if (input_count == 0)
                null
            else
                try resolveSelectedOrDefault(
                    Api,
                    .capture,
                    self.selected_input,
                    &input_storage,
                );
            const output_identifier = if (output_count == 0)
                null
            else
                try resolveSelectedOrDefault(
                    Api,
                    .playback,
                    self.selected_output,
                    &output_storage,
                );
            if (input_identifier) |identifier| {
                if (try Api.deviceChannels(.capture, identifier) <
                    input_count)
                    return error.AlsaInsufficientInputChannels;
            }
            if (output_identifier) |identifier| {
                if (try Api.deviceChannels(.playback, identifier) <
                    output_count)
                    return error.AlsaInsufficientOutputChannels;
            }

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
                    input_identifier,
                    output_identifier,
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
                    input_identifier,
                    output_identifier,
                    @sizeOf(Sample),
                    @intFromFloat(configuration.sample_rate),
                    configuration.max_block_size,
                    @intCast(input_count),
                    @intCast(output_count),
                    self,
                    processChannels,
                );
        }

        pub fn stop(self: *Self) void {
            if (self.session) |session|
                self.final_statistics = Api.stop(session);
            self.clearRuntimeState();
        }

        pub fn deinit(self: *Self) void {
            self.stop();
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
            const input_count = self.totalInputChannels() catch
                return -1;
            const output_count = self.totalOutputChannels() catch
                return -1;
            const frame_count: usize = frame_count_u32;
            if (frame_count > self.maximum_frames)
                return -1;
            if (input_count != 0 and input_channels == null)
                return -1;
            if (output_count != 0 and output_channels == null)
                return -1;
            for (0..input_count) |index| {
                const pointer = input_channels[index] orelse
                    return -1;
                if (@intFromPtr(pointer) % @alignOf(Sample) != 0)
                    return -1;
                const samples: [*]const Sample =
                    @ptrCast(@alignCast(pointer));
                self.input_views[index] = samples[0..frame_count];
            }
            for (0..output_count) |index| {
                const pointer = output_channels[index] orelse
                    return -1;
                if (@intFromPtr(pointer) % @alignOf(Sample) != 0)
                    return -1;
                const samples: [*]Sample =
                    @ptrCast(@alignCast(pointer));
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
            return 0;
        }

        fn captureChannels(
            context: ?*anyopaque,
            frame_count_u32: u32,
            input_channels: [*c]const ?*const anyopaque,
        ) callconv(.c) i32 {
            const self = callbackContext(context) orelse return -1;
            const callback = self.split_callback orelse return -1;
            const input_count = self.totalInputChannels() catch
                return -1;
            const frame_count: usize = frame_count_u32;
            if (frame_count > self.maximum_frames)
                return -1;
            if (input_count != 0 and input_channels == null)
                return -1;
            for (0..input_count) |index| {
                const pointer = input_channels[index] orelse
                    return -1;
                if (@intFromPtr(pointer) % @alignOf(Sample) != 0)
                    return -1;
                const samples: [*]const Sample =
                    @ptrCast(@alignCast(pointer));
                self.input_views[index] = samples[0..frame_count];
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
            const callback = self.split_callback orelse return -1;
            const output_count = self.totalOutputChannels() catch
                return -1;
            const frame_count: usize = frame_count_u32;
            if (frame_count > self.maximum_frames)
                return -1;
            if (output_count != 0 and output_channels == null)
                return -1;
            for (0..output_count) |index| {
                const pointer = output_channels[index] orelse
                    return -1;
                if (@intFromPtr(pointer) % @alignOf(Sample) != 0)
                    return -1;
                const samples: [*]Sample =
                    @ptrCast(@alignCast(pointer));
                self.output_views[index] = samples[0..frame_count];
            }
            callback.render_block(callback.context, .{
                .frame_count = frame_count,
                .output_channels = self.output_views[0..self.main_output_channel_count],
                .auxiliary_output_channels = self.output_views[self.main_output_channel_count..output_count],
                .auxiliary_output_bus_channel_counts = self.auxiliary_output_channel_counts[0..self.auxiliary_output_bus_count],
            });
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

pub fn AlsaBackend(comptime Sample: type) type {
    return Backend(AlsaSystemApi, Sample);
}

pub fn BoundedAlsaBackend(
    comptime Sample: type,
    comptime maximum_auxiliary_buses: usize,
) type {
    return BoundedBackend(
        AlsaSystemApi,
        Sample,
        maximum_auxiliary_buses,
    );
}

const Direction = enum(u8) {
    capture,
    playback,
};

fn requireAvailable(comptime Api: type) !void {
    if (!Api.supported) return error.UnsupportedPlatform;
    if (!Api.available()) return error.AlsaLibraryUnavailable;
}

fn emptyStatistics() Statistics {
    return .{
        .processed = 0,
        .callback_failures = 0,
        .capture_underflows = 0,
        .capture_overflows = 0,
        .recoveries = 0,
        .device_failures = 0,
        .realtime_priority_acquired = false,
    };
}

fn enumerateDirection(
    comptime Api: type,
    direction: Direction,
    default: ?device_catalog.DeviceIdentifier,
    output: []device_catalog.DeviceDescriptor,
    initial_count: usize,
) !usize {
    var count = initial_count;
    var id_storage: [Api.maximum_identifier_bytes]u8 = undefined;
    var raw_name_storage: [Api.maximum_name_bytes]u8 = undefined;
    var name_storage: [device_catalog.maximum_device_name_bytes]u8 = undefined;
    for (0..try Api.deviceCount(direction)) |index| {
        const raw_identifier = try Api.deviceId(
            direction,
            index,
            &id_storage,
        );
        const channels = Api.deviceChannels(
            direction,
            raw_identifier,
        ) catch continue;
        if (channels == 0 or channels > std.math.maxInt(u8))
            continue;
        if (count == output.len)
            return error.AlsaDeviceStorageTooSmall;
        const identifier = try endpointIdentifier(
            direction,
            raw_identifier,
        );
        const raw_name = try Api.deviceName(
            direction,
            index,
            &raw_name_storage,
        );
        const name = try boundedDeviceName(
            raw_name,
            &name_storage,
        );
        output[count] = try device_catalog.DeviceDescriptor.init(
            if (direction == .capture)
                .audio_input
            else
                .audio_output,
            identifier.slice(),
            name,
            if (direction == .capture) @intCast(channels) else 0,
            if (direction == .playback) @intCast(channels) else 0,
            if (default) |value|
                value.eql(&identifier)
            else
                false,
        );
        count += 1;
    }
    return count;
}

fn boundedDeviceName(raw: []const u8, storage: []u8) ![]const u8 {
    if (raw.len == 0 or !std.unicode.utf8ValidateSlice(raw) or
        std.mem.indexOfScalar(u8, raw, 0) != null)
        return error.InvalidAlsaDeviceName;
    var source_length = @min(raw.len, storage.len);
    while (source_length != 0 and
        !std.unicode.utf8ValidateSlice(raw[0..source_length]))
        source_length -= 1;
    if (source_length == 0) return error.AlsaDeviceNameTooLong;
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
        return error.InvalidAlsaEndpointIdentifier;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(
        raw_identifier,
        &digest,
        .{},
    );
    const prefix = if (direction == .capture)
        "alsa-input:"
    else
        "alsa-output:";
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

fn defaultIdentifier(
    comptime Api: type,
    direction: Direction,
) !?device_catalog.DeviceIdentifier {
    var storage: [Api.maximum_identifier_bytes]u8 = undefined;
    const raw = try Api.defaultDeviceId(
        direction,
        &storage,
    ) orelse return null;
    return try endpointIdentifier(direction, raw);
}

fn resolveSelectedOrDefault(
    comptime Api: type,
    direction: Direction,
    selected: ?device_catalog.DeviceIdentifier,
    storage: []u8,
) ![]const u8 {
    if (selected) |identifier| {
        const length = try resolveIdentifier(
            Api,
            direction,
            identifier,
            storage,
        );
        return storage[0..length];
    }
    return try Api.defaultDeviceId(
        direction,
        storage,
    ) orelse error.AlsaDefaultDeviceUnavailable;
}

fn resolveIdentifier(
    comptime Api: type,
    direction: Direction,
    identifier: device_catalog.DeviceIdentifier,
    output: ?[]u8,
) !usize {
    if (!identifier.valid())
        return error.InvalidDeviceIdentifier;
    var storage: [Api.maximum_identifier_bytes]u8 = undefined;
    for (0..try Api.deviceCount(direction)) |index| {
        const raw = try Api.deviceId(direction, index, &storage);
        const candidate = try endpointIdentifier(direction, raw);
        if (!candidate.eql(&identifier)) continue;
        if (output) |destination| {
            if (destination.len < raw.len)
                return error.AlsaEndpointStorageTooSmall;
            @memcpy(destination[0..raw.len], raw);
        }
        return raw.len;
    }
    return error.AlsaDeviceNotFound;
}

fn totalChannels(main: usize, auxiliary: []const usize) !usize {
    var total = main;
    for (auxiliary) |count| {
        total = std.math.add(usize, total, count) catch
            return error.AlsaChannelCountOverflow;
    }
    if (total > standalone.maximum_routed_channels)
        return error.AlsaChannelCountTooLarge;
    return total;
}

fn topologyFingerprint(comptime Api: type) !u64 {
    var hasher = std.hash.Wyhash.init(0);
    inline for (.{ Direction.capture, Direction.playback }) |direction| {
        const count = try Api.deviceCount(direction);
        hasher.update(std.mem.asBytes(&count));
        var storage: [Api.maximum_identifier_bytes]u8 = undefined;
        for (0..count) |index|
            hasher.update(try Api.deviceId(direction, index, &storage));
        if (try Api.defaultDeviceId(direction, &storage)) |default|
            hasher.update(default);
    }
    return hasher.final();
}

const AlsaSystemApi = if (builtin.os.tag == .linux)
    LinuxAlsaApi
else
    UnsupportedAlsaApi;

const UnsupportedAlsaApi = struct {
    const supported = false;
    const maximum_identifier_bytes = 1024;
    const maximum_name_bytes = 1024;
    const Session = u32;

    fn available() bool {
        return false;
    }

    fn deviceCount(_: Direction) !usize {
        return error.UnsupportedPlatform;
    }

    fn deviceId(_: Direction, _: usize, _: []u8) ![]const u8 {
        return error.UnsupportedPlatform;
    }

    fn defaultDeviceId(_: Direction, _: []u8) !?[]const u8 {
        return error.UnsupportedPlatform;
    }

    fn deviceName(_: Direction, _: usize, _: []u8) ![]const u8 {
        return error.UnsupportedPlatform;
    }

    fn deviceChannels(_: Direction, _: []const u8) !u32 {
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

const LinuxAlsaApi = if (builtin.os.tag == .linux) struct {
    const c = @cImport({
        @cInclude("alsa_shim.h");
    });
    const supported = true;
    const maximum_identifier_bytes = 1024;
    const maximum_name_bytes = 1024;
    const Session = *c.zv3_alsa_session;

    fn available() bool {
        return c.zv3_alsa_available() != 0;
    }

    fn deviceCount(direction: Direction) !usize {
        var result: usize = 0;
        if (c.zv3_alsa_device_count(
            @intFromEnum(direction),
            &result,
        ) != 0)
            return error.AlsaDeviceQueryFailed;
        return result;
    }

    fn deviceId(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_alsa_device_id(
            @intFromEnum(direction),
            index,
            storage.ptr,
            storage.len,
            &length,
        ) != 0)
            return error.AlsaDeviceQueryFailed;
        if (length == 0 or length > storage.len)
            return error.InvalidAlsaEndpointIdentifier;
        return storage[0..length];
    }

    fn defaultDeviceId(
        direction: Direction,
        storage: []u8,
    ) !?[]const u8 {
        var length: usize = 0;
        if (c.zv3_alsa_default_device_id(
            @intFromEnum(direction),
            storage.ptr,
            storage.len,
            &length,
        ) != 0)
            return null;
        if (length == 0 or length > storage.len)
            return error.InvalidAlsaEndpointIdentifier;
        return storage[0..length];
    }

    fn deviceName(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_alsa_device_name(
            @intFromEnum(direction),
            index,
            storage.ptr,
            storage.len,
            &length,
        ) != 0)
            return error.AlsaDeviceQueryFailed;
        if (length == 0 or length > storage.len)
            return error.AlsaDeviceNameTooLong;
        return storage[0..length];
    }

    fn deviceChannels(
        direction: Direction,
        identifier: []const u8,
    ) !u32 {
        var result: u32 = 0;
        if (c.zv3_alsa_device_channels(
            @intFromEnum(direction),
            identifier.ptr,
            identifier.len,
            &result,
        ) != 0)
            return error.AlsaDeviceQueryFailed;
        return result;
    }

    fn start(
        input_identifier: ?[]const u8,
        output_identifier: ?[]const u8,
        sample_bytes: usize,
        sample_rate: u32,
        maximum_frames: u32,
        input_channels: u32,
        output_channels: u32,
        context: *anyopaque,
        process: ProcessChannels,
    ) !Session {
        var session: ?Session = null;
        if (c.zv3_alsa_start(
            if (input_identifier) |value| value.ptr else null,
            if (input_identifier) |value| value.len else 0,
            if (output_identifier) |value| value.ptr else null,
            if (output_identifier) |value| value.len else 0,
            @intCast(sample_bytes),
            sample_rate,
            maximum_frames,
            input_channels,
            output_channels,
            context,
            process,
            &session,
        ) != 0)
            return error.AlsaStartFailed;
        return session orelse error.AlsaStartFailed;
    }

    fn startSplit(
        input_identifier: ?[]const u8,
        output_identifier: ?[]const u8,
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
        if (c.zv3_alsa_start_split(
            if (input_identifier) |value| value.ptr else null,
            if (input_identifier) |value| value.len else 0,
            if (output_identifier) |value| value.ptr else null,
            if (output_identifier) |value| value.len else 0,
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
            return error.AlsaStartFailed;
        return session orelse error.AlsaStartFailed;
    }

    fn statistics(session: Session) Statistics {
        var result: c.zv3_alsa_statistics = undefined;
        c.zv3_alsa_get_statistics(session, &result);
        return fromCStatistics(result);
    }

    fn stop(session: Session) Statistics {
        var result: c.zv3_alsa_statistics = undefined;
        c.zv3_alsa_stop(session, &result);
        return fromCStatistics(result);
    }

    fn fromCStatistics(value: c.zv3_alsa_statistics) Statistics {
        return .{
            .processed = value.processed,
            .callback_failures = value.callback_failures,
            .capture_underflows = value.capture_underflows,
            .capture_overflows = value.capture_overflows,
            .recoveries = value.recoveries,
            .device_failures = value.device_failures,
            .realtime_priority_acquired = value.realtime_priority_acquired != 0,
        };
    }
} else struct {};

test "unsupported ALSA backend fails explicitly" {
    if (builtin.os.tag == .linux) return error.SkipZigTest;
    var backend = AlsaBackend(f32){};
    var descriptors: [1]device_catalog.DeviceDescriptor = undefined;
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

test "native ALSA loader can build a discovery snapshot" {
    if (builtin.os.tag != .linux) return;
    var backend = AlsaBackend(f32){};
    if (!backend.available()) return;
    var descriptors: [256]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
}

const MockApi = struct {
    const supported = true;
    const maximum_identifier_bytes = 64;
    const maximum_name_bytes = 128;
    const Session = u32;
    const inputs = [_][]const u8{ "capture-a", "capture-b" };
    const outputs = [_][]const u8{ "playback-a", "playback-b" };
    var callback_context: ?*anyopaque = null;
    var callback_function: ?ProcessChannels = null;
    var capture_function: ?CaptureChannels = null;
    var render_function: ?RenderChannels = null;
    var fail_start = false;
    var stop_count: usize = 0;
    var topology_suffix: u8 = 'b';
    var large_channel_count = false;

    fn reset() void {
        callback_context = null;
        callback_function = null;
        capture_function = null;
        render_function = null;
        fail_start = false;
        stop_count = 0;
        topology_suffix = 'b';
        large_channel_count = false;
    }

    fn available() bool {
        return true;
    }

    fn values(direction: Direction) []const []const u8 {
        return switch (direction) {
            .capture => &inputs,
            .playback => &outputs,
        };
    }

    fn deviceCount(direction: Direction) !usize {
        return values(direction).len;
    }

    fn deviceId(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        const value = values(direction)[index];
        if (storage.len < value.len) return error.StorageTooSmall;
        @memcpy(storage[0..value.len], value);
        if (index == 1) storage[value.len - 1] = topology_suffix;
        return storage[0..value.len];
    }

    fn defaultDeviceId(
        direction: Direction,
        storage: []u8,
    ) !?[]const u8 {
        return try deviceId(
            direction,
            if (direction == .capture) 1 else 0,
            storage,
        );
    }

    fn deviceName(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        const names = switch (direction) {
            .capture => [_][]const u8{ "Microphone A", "Microphone B" },
            .playback => [_][]const u8{ "Speakers A", "Speakers\nB" },
        };
        const value = names[index];
        @memcpy(storage[0..value.len], value);
        return storage[0..value.len];
    }

    fn deviceChannels(
        _: Direction,
        identifier: []const u8,
    ) !u32 {
        if (large_channel_count) return 64;
        return if (std.mem.endsWith(u8, identifier, "a")) 2 else 8;
    }

    fn start(
        _: ?[]const u8,
        _: ?[]const u8,
        _: usize,
        _: u32,
        _: u32,
        _: u32,
        _: u32,
        context: *anyopaque,
        process: ProcessChannels,
    ) !Session {
        if (fail_start) return error.MockStartFailed;
        callback_context = context;
        callback_function = process;
        return 77;
    }

    fn startSplit(
        _: ?[]const u8,
        _: ?[]const u8,
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
        callback_context = context;
        capture_function = capture;
        render_function = render;
        return 77;
    }

    fn statistics(_: Session) Statistics {
        return .{
            .processed = 128,
            .callback_failures = 1,
            .capture_underflows = 2,
            .capture_overflows = 3,
            .recoveries = 4,
            .device_failures = 5,
            .realtime_priority_acquired = true,
        };
    }

    fn stop(_: Session) Statistics {
        stop_count += 1;
        callback_context = null;
        callback_function = null;
        capture_function = null;
        render_function = null;
        return statistics(77);
    }
};

test "ALSA discovery publishes directional stable defaults" {
    MockApi.reset();
    const TestBackend = Backend(MockApi, f32);
    var backend = TestBackend{};
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        try backend.enumerate(&descriptors),
    );
    try std.testing.expectEqual(
        device_catalog.DeviceKind.audio_input,
        descriptors[0].kind,
    );
    try std.testing.expectEqual(
        device_catalog.DeviceKind.audio_output,
        descriptors[2].kind,
    );
    try std.testing.expect(descriptors[1].is_default);
    try std.testing.expect(descriptors[2].is_default);
    try std.testing.expectEqualStrings(
        "Speakers B",
        descriptors[3].name(),
    );
    try backend.selectInput(descriptors[0].identifier);
    try backend.selectOutput(descriptors[3].identifier);
    try std.testing.expectEqual(@as(u64, 1), backend.topology_generation);
}

test "ALSA polling detects topology changes" {
    MockApi.reset();
    const TestBackend = Backend(MockApi, f32);
    var backend = TestBackend{};
    try std.testing.expect(try backend.pollTopology());
    try std.testing.expect(!(try backend.pollTopology()));
    MockApi.topology_suffix = 'z';
    try std.testing.expect(try backend.pollTopology());
    try std.testing.expectEqual(@as(u64, 2), backend.topology_generation);
}

test "ALSA backend adapts f64 callbacks and retains statistics" {
    MockApi.reset();
    const TestBackend = Backend(MockApi, f64);
    const Probe = struct {
        call_count: usize = 0,

        fn process(
            context: *anyopaque,
            block: standalone.CallbackBlock(f64),
        ) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.call_count += 1;
            @memcpy(block.output_channels[0], block.input_channels[0]);
        }
    };
    var backend = TestBackend{};
    var probe = Probe{};
    try backend.start(.{
        .sample_rate = 48_000,
        .max_block_size = 2,
        .input_channel_count = 1,
        .output_channel_count = 1,
    }, .{
        .context = &probe,
        .process_block = Probe.process,
    });
    const input = [_]f64{ 0.25, -0.5 };
    var output = [_]f64{ 0, 0 };
    const inputs = [_]?*const anyopaque{&input};
    const outputs = [_]?*anyopaque{&output};
    const process = MockApi.callback_function orelse
        return error.MissingAlsaCallback;
    try std.testing.expectEqual(
        @as(i32, 0),
        process(MockApi.callback_context, 2, &inputs, &outputs),
    );
    try std.testing.expectEqual(
        @as(i32, -1),
        process(MockApi.callback_context, 2, null, &outputs),
    );
    try std.testing.expectEqual(
        @as(i32, -1),
        process(MockApi.callback_context, 2, &inputs, null),
    );
    try std.testing.expectEqualSlices(f64, &input, &output);
    try std.testing.expectEqual(@as(usize, 1), probe.call_count);
    try std.testing.expect(backend.statistics().realtime_priority_acquired);
    const failure_snapshot = try backend.failureSource().snapshot();
    try std.testing.expectEqual(
        @as(u64, 5),
        failure_snapshot.audio_input,
    );
    try std.testing.expectEqual(
        @as(u64, 5),
        failure_snapshot.audio_output,
    );
    backend.stop();
    try std.testing.expectEqual(@as(usize, 1), MockApi.stop_count);
    try std.testing.expectEqual(
        @as(u64, 4),
        backend.statistics().recoveries,
    );
}

test "ALSA split callbacks feed the bounded capture-rate adapter" {
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
            .lifecycle = .{
                .startup_buffer_frames = 8,
                .recovery_buffer_frames = 8,
                .control_interval_frames = 4,
                .underflow_policy = .rebuffer,
            },
        },
        .{
            .context = &probe,
            .process_block = Probe.process,
        },
    );
    var backend = TestBackend{};
    try backend.startSplit(.{
        .sample_rate = 48_000.0,
        .max_block_size = 8,
        .input_channel_count = 1,
        .auxiliary_input_bus_channel_counts = &.{1},
        .output_channel_count = 1,
        .auxiliary_output_bus_channel_counts = &.{1},
    }, adapter.splitCallback());
    try std.testing.expect(backend.callback == null);
    try std.testing.expect(backend.split_callback != null);
    try std.testing.expect(MockApi.callback_function == null);

    const input_a: [8]f64 = @splat(0.25);
    const input_b: [8]f64 = @splat(0.5);
    const inputs = [_]?*const anyopaque{ &input_a, &input_b };
    const capture_callback = MockApi.capture_function orelse
        return error.MissingAlsaCaptureCallback;
    try std.testing.expectEqual(
        @as(i32, 0),
        capture_callback(MockApi.callback_context, 8, &inputs),
    );

    var output_a: [4]f64 = @splat(-1);
    var output_b: [4]f64 = @splat(-1);
    const outputs = [_]?*anyopaque{ &output_a, &output_b };
    const render_callback = MockApi.render_function orelse
        return error.MissingAlsaRenderCallback;
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
    try std.testing.expectEqual(
        @as(i32, 0),
        render_callback(MockApi.callback_context, 4, &outputs),
    );
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    try std.testing.expectEqual(
        standalone.CaptureRateOperatingState.running,
        adapter.bridge.operating_state,
    );
    for (output_a, output_b) |main, auxiliary| {
        try std.testing.expectApproxEqAbs(
            main * 2.0,
            auxiliary,
            1.0e-12,
        );
    }
    const adapter_statistics = try adapter.statistics();
    try std.testing.expectEqual(
        @as(usize, 8),
        adapter_statistics.fifo.written_frames,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        adapter_statistics.capture_failures,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        adapter_statistics.render_failures,
    );

    try std.testing.expectEqual(
        @as(i32, -1),
        capture_callback(MockApi.callback_context, 9, &inputs),
    );
    try std.testing.expectEqual(
        @as(i32, -1),
        capture_callback(MockApi.callback_context, 8, null),
    );
    const missing_input = [_]?*const anyopaque{ null, &input_b };
    try std.testing.expectEqual(
        @as(i32, -1),
        capture_callback(
            MockApi.callback_context,
            8,
            &missing_input,
        ),
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
    try std.testing.expectEqual(
        @as(i32, -1),
        render_callback(MockApi.callback_context, 4, null),
    );

    backend.stop();
    try std.testing.expect(backend.split_callback == null);
    try std.testing.expectEqual(@as(usize, 0), backend.maximum_frames);
    try std.testing.expect(MockApi.capture_function == null);
    try std.testing.expect(MockApi.render_function == null);

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
        error.AlsaSplitRequiresDuplex,
        backend.startSplit(.{
            .sample_rate = 48_000.0,
            .max_block_size = 8,
            .input_channel_count = 2,
            .output_channel_count = 0,
        }, no_op),
    );
    try std.testing.expect(!backend.isRunning());

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

test "ALSA startup is transactional and retryable" {
    MockApi.reset();
    const TestBackend = Backend(MockApi, f32);
    var backend = TestBackend{};
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
        error.InvalidAlsaSampleRate,
        backend.start(.{
            .sample_rate = 48_000.5,
            .max_block_size = 128,
            .input_channel_count = 0,
            .output_channel_count = 2,
        }, callback),
    );
    MockApi.fail_start = true;
    try std.testing.expectError(
        error.MockStartFailed,
        backend.start(.{
            .sample_rate = 48_000,
            .max_block_size = 128,
            .input_channel_count = 0,
            .output_channel_count = 2,
        }, callback),
    );
    try std.testing.expect(!backend.isRunning());
    try std.testing.expect(backend.callback == null);
    MockApi.fail_start = false;
    try backend.start(.{
        .sample_rate = 48_000,
        .max_block_size = 128,
        .input_channel_count = 0,
        .output_channel_count = 2,
    }, callback);
    backend.stop();
}

test "ALSA backend selects auxiliary bus storage capacity" {
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
        return error.MissingAlsaCallback;
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
