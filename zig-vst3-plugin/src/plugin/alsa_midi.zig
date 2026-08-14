const builtin = @import("builtin");
const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const native_callback_gate = @import("native_callback_gate.zig");
const device_catalog = core.plugin;
const process_api = core.process;
const standalone = core.plugin;

const ReceiveBytes = *const fn (
    context: ?*anyopaque,
    timestamp_nanoseconds: u64,
    bytes: [*c]const u8,
    length: usize,
) callconv(.c) void;

pub const InputStatistics = struct {
    received: usize,
    unsupported: usize,
    malformed: usize,
    read_failures: u64,
};

pub const OutputStatistics = struct {
    queued: u64,
    delivered: u64,
    late: u64,
    rejected: u64,
    canceled: u64,
    write_failures: u64,
};

pub fn Backend(comptime Api: type) type {
    return struct {
        const Self = @This();

        opened: bool = false,
        selected_input: ?device_catalog.DeviceIdentifier = null,
        selected_output: ?device_catalog.DeviceIdentifier = null,
        input_session: ?Api.Input = null,
        output_session: ?Api.Output = null,
        input_callback: ?standalone.Midi1InputCallback = null,
        input_running: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        input_callbacks: native_callback_gate.Gate = .{},
        topology_generation: u64 = 0,
        topology_fingerprint: u64 = 0,
        received_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        unsupported_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        malformed_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        final_read_failures: u64 = 0,
        final_output_statistics: OutputStatistics = emptyOutputStatistics(),
        running_status: u8 = 0,
        pending: [3]u8 = @splat(0),
        pending_length: u8 = 0,
        pending_required: u8 = 0,
        pending_timestamp: u64 = 0,
        system_remaining: u8 = 0,
        in_sysex: bool = false,

        /// Keep the backend at a stable address from `open` through `close`.
        pub fn open(self: *Self, client_name: []const u8) !void {
            if (self.opened) return error.AlsaMidiBackendAlreadyOpen;
            if (client_name.len == 0)
                return error.EmptyAlsaMidiClientName;
            if (!std.unicode.utf8ValidateSlice(client_name) or
                std.mem.indexOfScalar(u8, client_name, 0) != null)
                return error.InvalidAlsaMidiClientName;
            try requireAvailable(Api);
            self.opened = true;
            errdefer {
                self.opened = false;
                self.topology_generation = 0;
                self.topology_fingerprint = 0;
            }
            _ = try self.refreshTopology();
        }

        pub fn close(self: *Self) void {
            self.stopInput();
            if (self.output_session) |session| {
                self.final_output_statistics =
                    Api.closeOutput(session);
            }
            self.output_session = null;
            self.selected_input = null;
            self.selected_output = null;
            self.opened = false;
            self.topology_generation = 0;
            self.topology_fingerprint = 0;
            self.resetParser();
        }

        pub fn isOpen(self: *const Self) bool {
            return self.opened;
        }

        pub fn available(self: *const Self) bool {
            _ = self;
            return Api.supported and Api.available();
        }

        pub fn nowNanoseconds(self: *const Self) !u64 {
            if (!self.opened) return error.AlsaMidiBackendNotOpen;
            const result = Api.nowNanoseconds();
            if (result == 0) return error.AlsaMidiClockUnavailable;
            return result;
        }

        pub fn currentTopologyGeneration(self: *const Self) u64 {
            return self.topology_generation;
        }

        pub fn refreshTopology(self: *Self) !u64 {
            if (!self.opened) return error.AlsaMidiBackendNotOpen;
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
            if (!self.opened) return error.AlsaMidiBackendNotOpen;
            const initial_fingerprint = try topologyFingerprint(Api);
            const default_input = try defaultIdentifier(Api, .input);
            const default_output = try defaultIdentifier(Api, .output);
            var count: usize = 0;
            count = try enumerateDirection(
                Api,
                .input,
                default_input,
                output,
                count,
            );
            count = try enumerateDirection(
                Api,
                .output,
                default_output,
                output,
                count,
            );
            const final_fingerprint = try topologyFingerprint(Api);
            if (final_fingerprint != initial_fingerprint)
                return error.AlsaMidiTopologyChanged;
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
            if (!self.opened) return error.AlsaMidiBackendNotOpen;
            if (self.input_running.load(.acquire))
                return error.AlsaMidiInputAlreadyRunning;
            _ = try resolveIdentifier(
                Api,
                .input,
                identifier,
                null,
            );
            self.selected_input = identifier;
        }

        pub fn selectOutput(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            if (!self.opened) return error.AlsaMidiBackendNotOpen;
            var storage: [Api.maximum_identifier_bytes]u8 = undefined;
            const length = try resolveIdentifier(
                Api,
                .output,
                identifier,
                &storage,
            );
            const next = try Api.openOutput(storage[0..length]);
            if (self.output_session) |session| {
                self.final_output_statistics =
                    Api.closeOutput(session);
            }
            self.output_session = next;
            self.selected_output = identifier;
            self.final_output_statistics = emptyOutputStatistics();
        }

        pub fn clearInputSelection(self: *Self) !void {
            if (self.input_running.load(.acquire))
                return error.AlsaMidiInputAlreadyRunning;
            self.selected_input = null;
        }

        pub fn clearOutputSelection(self: *Self) void {
            if (self.output_session) |session| {
                self.final_output_statistics =
                    Api.closeOutput(session);
            }
            self.output_session = null;
            self.selected_output = null;
        }

        pub fn startInput(
            self: *Self,
            callback: standalone.Midi1InputCallback,
        ) !void {
            if (!self.opened) return error.AlsaMidiBackendNotOpen;
            if (self.input_running.load(.acquire))
                return error.AlsaMidiInputAlreadyRunning;
            const identifier = self.selected_input orelse
                return error.AlsaMidiInputNotSelected;
            var storage: [Api.maximum_identifier_bytes]u8 = undefined;
            const length = try resolveIdentifier(
                Api,
                .input,
                identifier,
                &storage,
            );
            self.resetParser();
            self.input_callback = callback;
            self.final_read_failures = 0;
            self.input_callbacks.open() catch |open_error| {
                self.input_callback = null;
                return open_error;
            };
            self.input_running.store(true, .release);
            self.input_session = Api.startInput(
                storage[0..length],
                self,
                receiveBytes,
            ) catch |start_error| {
                self.input_running.store(false, .release);
                self.input_callbacks.closeAdmission();
                self.input_callbacks.drain();
                self.input_callback = null;
                return start_error;
            };
        }

        pub fn stopInput(self: *Self) void {
            if (!self.input_running.swap(false, .acq_rel))
                return;
            self.input_callbacks.closeAdmission();
            if (self.input_session) |session| {
                self.final_read_failures =
                    Api.stopInput(session).read_failures;
            }
            self.input_callbacks.drain();
            self.input_session = null;
            self.input_callback = null;
            self.resetParser();
        }

        pub fn send(
            self: *Self,
            packet: standalone.TimestampedMidi1Packet,
        ) !void {
            if (!self.opened) return error.AlsaMidiBackendNotOpen;
            const session = self.output_session orelse
                return error.AlsaMidiOutputNotSelected;
            if (!packet.message.valid())
                return error.InvalidMidiPacket;
            if (packet.timestamp_nanoseconds == 0)
                return error.InvalidMidiPacket;
            try Api.send(
                session,
                packet.timestamp_nanoseconds,
                packet.message.bytes(),
            );
        }

        pub fn inputDevice(self: *Self) standalone.Midi1InputDevice {
            return .{
                .context = self,
                .start_input = startInputErased,
                .stop_input = stopInputErased,
            };
        }

        pub fn outputDevice(self: *Self) standalone.Midi1OutputDevice {
            return .{
                .context = self,
                .send_output = sendErased,
            };
        }

        pub fn inputStatistics(self: *const Self) InputStatistics {
            const read_failures = if (self.input_session) |session|
                Api.inputStatistics(session).read_failures
            else
                self.final_read_failures;
            return .{
                .received = self.received_count.load(.acquire),
                .unsupported = self.unsupported_count.load(.acquire),
                .malformed = self.malformed_count.load(.acquire),
                .read_failures = read_failures,
            };
        }

        pub fn outputStatistics(
            self: *const Self,
        ) OutputStatistics {
            return if (self.output_session) |session|
                Api.outputStatistics(session)
            else
                self.final_output_statistics;
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
            return .{
                .midi_input = self.inputStatistics().read_failures,
                .midi_output = self.outputStatistics().write_failures,
            };
        }

        pub fn resetInputStatistics(self: *Self) !void {
            if (self.input_running.load(.acquire))
                return error.AlsaMidiInputAlreadyRunning;
            self.received_count.store(0, .release);
            self.unsupported_count.store(0, .release);
            self.malformed_count.store(0, .release);
            self.final_read_failures = 0;
        }

        fn startInputErased(
            context: *anyopaque,
            callback: standalone.Midi1InputCallback,
        ) !void {
            const self: *Self = @ptrCast(@alignCast(context));
            try self.startInput(callback);
        }

        fn stopInputErased(context: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(context));
            self.stopInput();
        }

        fn sendErased(
            context: *anyopaque,
            packet: standalone.TimestampedMidi1Packet,
        ) !void {
            const self: *Self = @ptrCast(@alignCast(context));
            try self.send(packet);
        }

        fn resetParser(self: *Self) void {
            self.running_status = 0;
            self.pending_length = 0;
            self.pending_required = 0;
            self.pending_timestamp = 0;
            self.system_remaining = 0;
            self.in_sysex = false;
        }

        fn receiveBytes(
            optional_context: ?*anyopaque,
            timestamp_nanoseconds: u64,
            bytes_pointer: [*c]const u8,
            length: usize,
        ) callconv(.c) void {
            const self = callbackContext(optional_context) orelse return;
            var admission = self.input_callbacks.admit() orelse return;
            defer admission.release();
            if (bytes_pointer == null or length == 0 or
                timestamp_nanoseconds == 0)
            {
                incrementSaturating(&self.malformed_count);
                return;
            }
            for (bytes_pointer[0..length]) |byte|
                self.consumeByte(byte, timestamp_nanoseconds);
        }

        fn callbackContext(
            optional_context: ?*anyopaque,
        ) ?*Self {
            const context = optional_context orelse return null;
            if (@intFromPtr(context) % @alignOf(Self) != 0)
                return null;
            return @ptrCast(@alignCast(context));
        }

        fn consumeByte(
            self: *Self,
            byte: u8,
            timestamp_nanoseconds: u64,
        ) void {
            if (byte >= 0xf8) {
                incrementSaturating(&self.unsupported_count);
                return;
            }
            if (self.in_sysex) {
                if (byte == 0xf7) {
                    self.in_sysex = false;
                    return;
                }
                if (byte < 0x80) return;
                self.in_sysex = false;
                incrementSaturating(&self.malformed_count);
            }
            if (self.system_remaining != 0) {
                if (byte < 0x80) {
                    self.system_remaining -= 1;
                    return;
                }
                self.system_remaining = 0;
                incrementSaturating(&self.malformed_count);
            }
            if (byte >= 0x80) {
                self.consumeStatus(byte, timestamp_nanoseconds);
                return;
            }
            self.consumeData(byte, timestamp_nanoseconds);
        }

        fn consumeStatus(
            self: *Self,
            status: u8,
            timestamp_nanoseconds: u64,
        ) void {
            if (self.pending_length != 0 and
                self.pending_length < self.pending_required)
                incrementSaturating(&self.malformed_count);
            self.pending_length = 0;
            self.pending_required = 0;
            if (status < 0xf0) {
                self.running_status = status;
                self.pending[0] = status;
                self.pending_length = 1;
                self.pending_required = channelMessageLength(status);
                self.pending_timestamp = timestamp_nanoseconds;
                return;
            }
            self.running_status = 0;
            switch (status) {
                0xf0 => {
                    self.in_sysex = true;
                    incrementSaturating(&self.unsupported_count);
                },
                0xf1, 0xf3 => {
                    self.system_remaining = 1;
                    incrementSaturating(&self.unsupported_count);
                },
                0xf2 => {
                    self.system_remaining = 2;
                    incrementSaturating(&self.unsupported_count);
                },
                0xf6, 0xf7 => incrementSaturating(
                    &self.unsupported_count,
                ),
                else => incrementSaturating(&self.malformed_count),
            }
        }

        fn consumeData(
            self: *Self,
            byte: u8,
            timestamp_nanoseconds: u64,
        ) void {
            if (self.pending_length == 0) {
                if (self.running_status == 0) {
                    incrementSaturating(&self.malformed_count);
                    return;
                }
                self.pending[0] = self.running_status;
                self.pending_length = 1;
                self.pending_required =
                    channelMessageLength(self.running_status);
                self.pending_timestamp = timestamp_nanoseconds;
            }
            self.pending[self.pending_length] = byte;
            self.pending_length += 1;
            if (self.pending_length != self.pending_required) return;
            const callback = self.input_callback orelse {
                self.pending_length = 0;
                return;
            };
            const message = process_api.Midi1Message.parse(
                self.pending[0..self.pending_required],
            ) catch {
                incrementSaturating(&self.malformed_count);
                self.pending_length = 0;
                return;
            };
            callback.receive(callback.context, .{
                .timestamp_nanoseconds = self.pending_timestamp,
                .message = message,
            });
            incrementSaturating(&self.received_count);
            self.pending_length = 0;
            self.pending_required = 0;
        }
    };
}

pub const AlsaMidiBackend = Backend(AlsaMidiSystemApi);

const Direction = enum(u8) {
    input,
    output,
};

fn channelMessageLength(status: u8) u8 {
    return switch (status & 0xf0) {
        0xc0, 0xd0 => 2,
        else => 3,
    };
}

fn requireAvailable(comptime Api: type) !void {
    if (!Api.supported) return error.UnsupportedPlatform;
    if (!Api.available()) return error.AlsaLibraryUnavailable;
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
        if (count == output.len)
            return error.AlsaMidiDeviceStorageTooSmall;
        const raw_identifier = try Api.deviceId(
            direction,
            index,
            &id_storage,
        );
        const identifier = try endpointIdentifier(
            direction,
            raw_identifier,
        );
        const raw_name = try Api.deviceName(
            direction,
            index,
            &raw_name_storage,
        );
        const name = try boundedDeviceName(raw_name, &name_storage);
        output[count] = try device_catalog.DeviceDescriptor.init(
            if (direction == .input)
                .midi_input
            else
                .midi_output,
            identifier.slice(),
            name,
            0,
            0,
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
        return error.InvalidAlsaMidiDeviceName;
    var source_length = @min(raw.len, storage.len);
    while (source_length != 0 and
        !std.unicode.utf8ValidateSlice(raw[0..source_length]))
        source_length -= 1;
    if (source_length == 0) return error.AlsaMidiDeviceNameTooLong;
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
        return error.InvalidAlsaMidiEndpointIdentifier;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(
        raw_identifier,
        &digest,
        .{},
    );
    const prefix = if (direction == .input)
        "alsamidi-input:"
    else
        "alsamidi-output:";
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
                return error.AlsaMidiEndpointStorageTooSmall;
            @memcpy(destination[0..raw.len], raw);
        }
        return raw.len;
    }
    return error.AlsaMidiDeviceNotFound;
}

fn topologyFingerprint(comptime Api: type) !u64 {
    var hasher = std.hash.Wyhash.init(0);
    inline for (.{ Direction.input, Direction.output }) |direction| {
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

const AlsaMidiSystemApi = if (builtin.os.tag == .linux)
    LinuxAlsaMidiApi
else
    UnsupportedAlsaMidiApi;

const UnsupportedAlsaMidiApi = struct {
    const supported = false;
    const maximum_identifier_bytes = 1024;
    const maximum_name_bytes = 1024;
    const Input = u32;
    const Output = u32;

    fn available() bool {
        return false;
    }

    fn nowNanoseconds() u64 {
        return 0;
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

    fn startInput(_: []const u8, _: *anyopaque, _: ReceiveBytes) !Input {
        return error.UnsupportedPlatform;
    }

    fn stopInput(_: Input) InputStatistics {
        return .{
            .received = 0,
            .unsupported = 0,
            .malformed = 0,
            .read_failures = 0,
        };
    }

    fn inputStatistics(_: Input) InputStatistics {
        return stopInput(0);
    }

    fn openOutput(_: []const u8) !Output {
        return error.UnsupportedPlatform;
    }

    fn closeOutput(_: Output) OutputStatistics {
        return emptyOutputStatistics();
    }

    fn send(_: Output, _: u64, _: []const u8) !void {
        return error.UnsupportedPlatform;
    }

    fn outputStatistics(_: Output) OutputStatistics {
        return emptyOutputStatistics();
    }
};

fn emptyOutputStatistics() OutputStatistics {
    return .{
        .queued = 0,
        .delivered = 0,
        .late = 0,
        .rejected = 0,
        .canceled = 0,
        .write_failures = 0,
    };
}

const LinuxAlsaMidiApi = if (builtin.os.tag == .linux) struct {
    const c = @cImport({
        @cInclude("alsa_midi_shim.h");
    });
    const supported = true;
    const maximum_identifier_bytes = 1024;
    const maximum_name_bytes = 1024;
    const Input = *c.zv3_alsa_midi_input;
    const Output = *c.zv3_alsa_midi_output;

    fn available() bool {
        return c.zv3_alsa_midi_available() != 0;
    }

    fn nowNanoseconds() u64 {
        return c.zv3_alsa_midi_now_nanoseconds();
    }

    fn deviceCount(direction: Direction) !usize {
        var result: usize = 0;
        if (c.zv3_alsa_midi_device_count(
            @intFromEnum(direction),
            &result,
        ) != 0)
            return error.AlsaMidiDeviceQueryFailed;
        return result;
    }

    fn deviceId(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_alsa_midi_device_id(
            @intFromEnum(direction),
            index,
            storage.ptr,
            storage.len,
            &length,
        ) != 0)
            return error.AlsaMidiDeviceQueryFailed;
        if (length == 0 or length > storage.len)
            return error.InvalidAlsaMidiEndpointIdentifier;
        return storage[0..length];
    }

    fn defaultDeviceId(
        direction: Direction,
        storage: []u8,
    ) !?[]const u8 {
        var length: usize = 0;
        if (c.zv3_alsa_midi_default_device_id(
            @intFromEnum(direction),
            storage.ptr,
            storage.len,
            &length,
        ) != 0)
            return null;
        if (length == 0 or length > storage.len)
            return error.InvalidAlsaMidiEndpointIdentifier;
        return storage[0..length];
    }

    fn deviceName(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_alsa_midi_device_name(
            @intFromEnum(direction),
            index,
            storage.ptr,
            storage.len,
            &length,
        ) != 0)
            return error.AlsaMidiDeviceQueryFailed;
        if (length == 0 or length > storage.len)
            return error.AlsaMidiDeviceNameTooLong;
        return storage[0..length];
    }

    fn startInput(
        identifier: []const u8,
        context: *anyopaque,
        receive: ReceiveBytes,
    ) !Input {
        var input: ?Input = null;
        if (c.zv3_alsa_midi_start_input(
            identifier.ptr,
            identifier.len,
            context,
            receive,
            &input,
        ) != 0)
            return error.AlsaMidiInputStartFailed;
        return input orelse error.AlsaMidiInputStartFailed;
    }

    fn stopInput(input: Input) InputStatistics {
        var result: c.zv3_alsa_midi_input_statistics = undefined;
        c.zv3_alsa_midi_stop_input(input, &result);
        return .{
            .received = 0,
            .unsupported = 0,
            .malformed = 0,
            .read_failures = result.read_failures,
        };
    }

    fn inputStatistics(input: Input) InputStatistics {
        var result: c.zv3_alsa_midi_input_statistics = undefined;
        c.zv3_alsa_midi_get_input_statistics(input, &result);
        return .{
            .received = 0,
            .unsupported = 0,
            .malformed = 0,
            .read_failures = result.read_failures,
        };
    }

    fn openOutput(identifier: []const u8) !Output {
        var output: ?Output = null;
        if (c.zv3_alsa_midi_open_output(
            identifier.ptr,
            identifier.len,
            &output,
        ) != 0)
            return error.AlsaMidiOutputOpenFailed;
        return output orelse error.AlsaMidiOutputOpenFailed;
    }

    fn closeOutput(output: Output) OutputStatistics {
        var result: c.zv3_alsa_midi_output_statistics = undefined;
        c.zv3_alsa_midi_close_output(output, &result);
        return .{
            .queued = result.queued,
            .delivered = result.delivered,
            .late = result.late,
            .rejected = result.rejected,
            .canceled = result.canceled,
            .write_failures = result.write_failures,
        };
    }

    fn send(
        output: Output,
        timestamp_nanoseconds: u64,
        bytes: []const u8,
    ) !void {
        const result = c.zv3_alsa_midi_send(
            output,
            timestamp_nanoseconds,
            bytes.ptr,
            bytes.len,
        );
        if (result == -2) return error.AlsaMidiOutputQueueFull;
        if (result != 0) return error.AlsaMidiSendFailed;
    }

    fn outputStatistics(output: Output) OutputStatistics {
        var result: c.zv3_alsa_midi_output_statistics = undefined;
        c.zv3_alsa_midi_get_output_statistics(output, &result);
        return .{
            .queued = result.queued,
            .delivered = result.delivered,
            .late = result.late,
            .rejected = result.rejected,
            .canceled = result.canceled,
            .write_failures = result.write_failures,
        };
    }
} else struct {};

test "unsupported ALSA MIDI backend fails explicitly" {
    if (builtin.os.tag == .linux) return error.SkipZigTest;
    var backend = AlsaMidiBackend{};
    try std.testing.expect(!backend.available());
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.open("test"),
    );
}

test "native ALSA RawMIDI loader can build a discovery snapshot" {
    if (builtin.os.tag != .linux) return;
    var backend = AlsaMidiBackend{};
    if (!backend.available()) return;
    try backend.open("zig-vst3 ALSA RawMIDI test");
    defer backend.close();
    var descriptors: [256]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
}

const MockApi = struct {
    const supported = true;
    const maximum_identifier_bytes = 64;
    const maximum_name_bytes = 128;
    const Input = u32;
    const Output = u32;
    const inputs = [_][]const u8{ "midi-in-a", "midi-in-b" };
    const outputs = [_][]const u8{ "midi-out-a", "midi-out-b" };
    var receive_context: ?*anyopaque = null;
    var receive_function: ?ReceiveBytes = null;
    var fail_input = false;
    var fail_output = false;
    var fail_device_count = false;
    var reject_output = false;
    var output_close_count: usize = 0;
    var sent: [3]u8 = @splat(0);
    var sent_length: usize = 0;
    var sent_timestamp: u64 = 0;
    var output_statistics = emptyOutputStatistics();
    var now: u64 = 1_000;
    var topology_suffix: u8 = 'b';

    fn reset() void {
        receive_context = null;
        receive_function = null;
        fail_input = false;
        fail_output = false;
        fail_device_count = false;
        reject_output = false;
        output_close_count = 0;
        sent_length = 0;
        sent_timestamp = 0;
        output_statistics = emptyOutputStatistics();
        now = 1_000;
        topology_suffix = 'b';
    }

    fn available() bool {
        return true;
    }

    fn nowNanoseconds() u64 {
        return now;
    }

    fn values(direction: Direction) []const []const u8 {
        return if (direction == .input) &inputs else &outputs;
    }

    fn deviceCount(direction: Direction) !usize {
        if (fail_device_count) return error.MockDeviceQueryFailed;
        return values(direction).len;
    }

    fn deviceId(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        const value = values(direction)[index];
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
            if (direction == .input) 1 else 0,
            storage,
        );
    }

    fn deviceName(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        const names = if (direction == .input)
            [_][]const u8{ "Keyboard A", "Keyboard B" }
        else
            [_][]const u8{ "Synth A", "Synth\nB" };
        const value = names[index];
        @memcpy(storage[0..value.len], value);
        return storage[0..value.len];
    }

    fn startInput(
        _: []const u8,
        context: *anyopaque,
        receive: ReceiveBytes,
    ) !Input {
        if (fail_input) return error.MockInputFailed;
        receive_context = context;
        receive_function = receive;
        return 11;
    }

    fn stopInput(_: Input) InputStatistics {
        receive_context = null;
        receive_function = null;
        return .{
            .received = 0,
            .unsupported = 0,
            .malformed = 0,
            .read_failures = 2,
        };
    }

    fn inputStatistics(_: Input) InputStatistics {
        return .{
            .received = 0,
            .unsupported = 0,
            .malformed = 0,
            .read_failures = 1,
        };
    }

    fn openOutput(_: []const u8) !Output {
        if (fail_output) return error.MockOutputFailed;
        return 22;
    }

    fn closeOutput(_: Output) OutputStatistics {
        output_close_count += 1;
        return output_statistics;
    }

    fn send(
        _: Output,
        timestamp_nanoseconds: u64,
        bytes: []const u8,
    ) !void {
        if (reject_output) {
            output_statistics.rejected += 1;
            return error.AlsaMidiOutputQueueFull;
        }
        @memcpy(sent[0..bytes.len], bytes);
        sent_length = bytes.len;
        sent_timestamp = timestamp_nanoseconds;
        output_statistics.queued += 1;
        output_statistics.delivered += 1;
        if (timestamp_nanoseconds < now)
            output_statistics.late += 1;
    }

    fn outputStatistics(_: Output) OutputStatistics {
        return output_statistics;
    }

    fn inject(bytes: []const u8, timestamp: u64) !void {
        const function = receive_function orelse
            return error.MissingAlsaMidiCallback;
        function(
            receive_context,
            timestamp,
            bytes.ptr,
            bytes.len,
        );
    }
};

test "ALSA MIDI discovery publishes directional stable defaults" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = TestBackend{};
    try backend.open("test");
    defer backend.close();
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        try backend.enumerate(&descriptors),
    );
    try std.testing.expectEqual(
        device_catalog.DeviceKind.midi_input,
        descriptors[0].kind,
    );
    try std.testing.expectEqual(
        device_catalog.DeviceKind.midi_output,
        descriptors[2].kind,
    );
    try std.testing.expect(descriptors[1].is_default);
    try std.testing.expect(descriptors[2].is_default);
    try std.testing.expectEqualStrings("Synth B", descriptors[3].name());
    try backend.selectInput(descriptors[0].identifier);
    try backend.selectOutput(descriptors[3].identifier);
}

test "ALSA MIDI parser retains fragments and running status" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    const Probe = struct {
        packets: [3]standalone.TimestampedMidi1Packet = undefined,
        count: usize = 0,

        fn receive(
            context: *anyopaque,
            packet: standalone.TimestampedMidi1Packet,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.packets[self.count] = packet;
            self.count += 1;
        }
    };
    var backend = TestBackend{};
    try backend.open("test");
    defer backend.close();
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
    try backend.selectInput(descriptors[0].identifier);
    var probe = Probe{};
    try backend.startInput(.{
        .context = &probe,
        .receive = Probe.receive,
    });
    try MockApi.inject(&.{ 0x90, 60 }, 100);
    try MockApi.inject(&.{ 100, 61, 101, 0xf8, 62, 102 }, 200);
    try std.testing.expectEqual(@as(usize, 3), probe.count);
    try std.testing.expectEqual(@as(u64, 100), probe.packets[0].timestamp_nanoseconds);
    try std.testing.expectEqual(@as(u64, 200), probe.packets[1].timestamp_nanoseconds);
    try std.testing.expectEqual(
        @as(usize, 3),
        backend.inputStatistics().received,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        backend.inputStatistics().unsupported,
    );
    backend.stopInput();
    try std.testing.expectEqual(
        @as(u64, 2),
        backend.inputStatistics().read_failures,
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        (try backend.failureSource().snapshot()).midi_input,
    );
}

test "ALSA MIDI input stop drains an admitted callback" {
    const synchronization = struct {
        var started = std.atomic.Value(bool).init(false);
        var release = std.atomic.Value(bool).init(false);
        var emit_failed = std.atomic.Value(bool).init(false);

        fn receive(
            _: *anyopaque,
            _: standalone.TimestampedMidi1Packet,
        ) void {
            started.store(true, .release);
            while (!release.load(.acquire))
                std.Thread.yield() catch {};
        }
    };
    const TestBackend = Backend(MockApi);
    const StopContext = struct {
        backend: *TestBackend,
        started: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        finished: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),

        fn run(self: *@This()) void {
            self.started.store(true, .release);
            self.backend.stopInput();
            self.finished.store(true, .release);
        }
    };

    MockApi.reset();
    synchronization.started.store(false, .release);
    synchronization.release.store(false, .release);
    synchronization.emit_failed.store(false, .release);
    var backend = TestBackend{};
    try backend.open("drain test");
    defer backend.close();
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
    try backend.selectInput(descriptors[0].identifier);
    var callback_context: u8 = 0;
    try backend.startInput(.{
        .context = &callback_context,
        .receive = synchronization.receive,
    });

    const emit_thread = try std.Thread.spawn(.{}, struct {
        fn run() void {
            MockApi.inject(&.{ 0x90, 60, 100 }, 100) catch {
                synchronization.emit_failed.store(true, .release);
                synchronization.started.store(true, .release);
            };
        }
    }.run, .{});
    while (!synchronization.started.load(.acquire))
        std.Thread.yield() catch {};

    var stop_context = StopContext{ .backend = &backend };
    const stop_thread = try std.Thread.spawn(
        .{},
        StopContext.run,
        .{&stop_context},
    );
    while (!stop_context.started.load(.acquire))
        std.Thread.yield() catch {};
    for (0..1000) |_| std.Thread.yield() catch {};
    try std.testing.expect(!stop_context.finished.load(.acquire));
    synchronization.release.store(true, .release);
    emit_thread.join();
    stop_thread.join();
    try std.testing.expect(!synchronization.emit_failed.load(.acquire));
    try std.testing.expect(stop_context.finished.load(.acquire));
    try std.testing.expect(backend.input_callback == null);
    try std.testing.expectEqual(
        @as(u32, 0),
        backend.input_callbacks.activeCount(),
    );
}

test "ALSA MIDI parser contains malformed and system traffic" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = TestBackend{};
    try backend.open("test");
    defer backend.close();
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
    try backend.selectInput(descriptors[0].identifier);
    var context: u8 = 0;
    try backend.startInput(.{
        .context = &context,
        .receive = struct {
            fn receive(
                _: *anyopaque,
                _: standalone.TimestampedMidi1Packet,
            ) void {}
        }.receive,
    });
    try MockApi.inject(&.{ 0x01, 0xf0, 0x7d }, 100);
    try MockApi.inject(&.{ 0xf8, 0xf7, 0xf2, 0x01, 0x02 }, 200);
    const statistics = backend.inputStatistics();
    try std.testing.expectEqual(@as(usize, 3), statistics.unsupported);
    try std.testing.expectEqual(@as(usize, 1), statistics.malformed);
}

test "ALSA MIDI callback rejects misaligned context" {
    const TestBackend = Backend(MockApi);
    var storage: [@sizeOf(TestBackend) + 1]u8 align(@alignOf(TestBackend)) = undefined;
    const misaligned: *anyopaque = @ptrCast(&storage[1]);
    const bytes = [_]u8{ 0x90, 60, 100 };
    TestBackend.receiveBytes(
        misaligned,
        123,
        &bytes,
        bytes.len,
    );
}

test "ALSA MIDI output preserves future timestamps and selection is transactional" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = TestBackend{};
    try backend.open("test");
    defer backend.close();
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
    try backend.selectOutput(descriptors[2].identifier);
    const message = try process_api.Midi1Message.parse(&.{
        0x90,
        60,
        100,
    });
    try backend.send(.{
        .timestamp_nanoseconds = MockApi.now + 1,
        .message = message,
    });
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x90, 60, 100 },
        MockApi.sent[0..MockApi.sent_length],
    );
    try std.testing.expectEqual(
        MockApi.now + 1,
        MockApi.sent_timestamp,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        backend.outputStatistics().queued,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        backend.outputStatistics().delivered,
    );
    MockApi.reject_output = true;
    try std.testing.expectError(
        error.AlsaMidiOutputQueueFull,
        backend.send(.{
            .timestamp_nanoseconds = MockApi.now + 2,
            .message = message,
        }),
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        backend.outputStatistics().rejected,
    );
    MockApi.reject_output = false;
    try std.testing.expectError(
        error.InvalidMidiPacket,
        backend.send(.{
            .timestamp_nanoseconds = 0,
            .message = message,
        }),
    );
    MockApi.fail_output = true;
    try std.testing.expectError(
        error.MockOutputFailed,
        backend.selectOutput(descriptors[3].identifier),
    );
    try std.testing.expect(backend.output_session != null);
    try std.testing.expectEqual(@as(usize, 0), MockApi.output_close_count);
    MockApi.output_statistics.write_failures = 3;
    MockApi.output_statistics.canceled = 2;
    try std.testing.expectEqual(
        @as(u64, 3),
        (try backend.failureSource().snapshot()).midi_output,
    );
    backend.clearOutputSelection();
    try std.testing.expectEqual(
        @as(u64, 3),
        backend.outputStatistics().write_failures,
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        backend.outputStatistics().canceled,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        MockApi.output_close_count,
    );
}

test "ALSA MIDI topology polling and failed input start are retryable" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = TestBackend{};
    try backend.open("test");
    defer backend.close();
    try std.testing.expect(!(try backend.pollTopology()));
    MockApi.topology_suffix = 'z';
    try std.testing.expect(try backend.pollTopology());
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
    try backend.selectInput(descriptors[0].identifier);
    var context: u8 = 0;
    const callback = standalone.Midi1InputCallback{
        .context = &context,
        .receive = struct {
            fn receive(
                _: *anyopaque,
                _: standalone.TimestampedMidi1Packet,
            ) void {}
        }.receive,
    };
    MockApi.fail_input = true;
    try std.testing.expectError(
        error.MockInputFailed,
        backend.startInput(callback),
    );
    try std.testing.expect(!backend.input_running.load(.acquire));
    try std.testing.expect(backend.input_callback == null);
    try std.testing.expect(!backend.input_callbacks.isOpen());
    MockApi.fail_input = false;
    try backend.startInput(callback);
    backend.stopInput();
}

test "ALSA MIDI failed open restores the closed state" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = TestBackend{};
    MockApi.fail_device_count = true;
    try std.testing.expectError(
        error.MockDeviceQueryFailed,
        backend.open("test"),
    );
    try std.testing.expect(!backend.isOpen());
    try std.testing.expectEqual(@as(u64, 0), backend.currentTopologyGeneration());
    MockApi.fail_device_count = false;
    try backend.open("test");
    defer backend.close();
    try std.testing.expect(backend.isOpen());
}
