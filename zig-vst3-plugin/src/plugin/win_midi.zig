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
    driver_errors: u64,
};

pub const OutputStatistics = struct {
    queued: u64,
    delivered: u64,
    late: u64,
    rejected: u64,
    canceled: u64,
    driver_errors: u64,
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
        final_driver_errors: u64 = 0,
        final_output_statistics: OutputStatistics = emptyOutputStatistics(),

        /// Keep the backend at a stable address from `open` through `close`.
        pub fn open(self: *Self, client_name: []const u8) !void {
            if (!Api.supported) return error.UnsupportedPlatform;
            if (self.opened) return error.WinMidiBackendAlreadyOpen;
            if (client_name.len == 0)
                return error.EmptyWinMidiClientName;
            if (!std.unicode.utf8ValidateSlice(client_name) or
                std.mem.indexOfScalar(u8, client_name, 0) != null)
                return error.InvalidWinMidiClientName;
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
        }

        pub fn isOpen(self: *const Self) bool {
            return self.opened;
        }

        pub fn nowNanoseconds(self: *const Self) !u64 {
            if (!self.opened) return error.WinMidiBackendNotOpen;
            const result = Api.nowNanoseconds();
            if (result == 0) return error.WinMidiClockUnavailable;
            return result;
        }

        pub fn currentTopologyGeneration(self: *const Self) u64 {
            return self.topology_generation;
        }

        pub fn refreshTopology(self: *Self) !u64 {
            if (!self.opened) return error.WinMidiBackendNotOpen;
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
            if (!self.opened) return error.WinMidiBackendNotOpen;
            const initial_fingerprint = try topologyFingerprint(Api);
            var count: usize = 0;
            count = try enumerateDirection(
                Api,
                .input,
                output,
                count,
            );
            count = try enumerateDirection(
                Api,
                .output,
                output,
                count,
            );
            const final_fingerprint = try topologyFingerprint(Api);
            if (final_fingerprint != initial_fingerprint)
                return error.WinMidiTopologyChanged;
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
            if (!self.opened) return error.WinMidiBackendNotOpen;
            if (self.input_running.load(.acquire))
                return error.WinMidiInputAlreadyRunning;
            _ = try resolveIndex(Api, .input, identifier);
            self.selected_input = identifier;
        }

        pub fn selectOutput(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            if (!self.opened) return error.WinMidiBackendNotOpen;
            const index = try resolveIndex(Api, .output, identifier);
            const next = try Api.openOutput(index);
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
                return error.WinMidiInputAlreadyRunning;
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
            if (!self.opened) return error.WinMidiBackendNotOpen;
            if (self.input_running.load(.acquire))
                return error.WinMidiInputAlreadyRunning;
            const identifier = self.selected_input orelse
                return error.WinMidiInputNotSelected;
            const index = try resolveIndex(
                Api,
                .input,
                identifier,
            );
            self.input_callback = callback;
            self.final_driver_errors = 0;
            self.input_callbacks.open() catch |open_error| {
                self.input_callback = null;
                return open_error;
            };
            self.input_running.store(true, .release);
            self.input_session = Api.startInput(
                index,
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
                self.final_driver_errors =
                    Api.stopInput(session).driver_errors;
            }
            self.input_callbacks.drain();
            self.input_session = null;
            self.input_callback = null;
        }

        pub fn send(
            self: *Self,
            packet: standalone.TimestampedMidi1Packet,
        ) !void {
            if (!self.opened) return error.WinMidiBackendNotOpen;
            const session = self.output_session orelse
                return error.WinMidiOutputNotSelected;
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
            const driver_errors = if (self.input_session) |session|
                Api.inputStatistics(session).driver_errors
            else
                self.final_driver_errors;
            return .{
                .received = self.received_count.load(.acquire),
                .unsupported = self.unsupported_count.load(.acquire),
                .malformed = self.malformed_count.load(.acquire),
                .driver_errors = driver_errors,
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
                .midi_input = self.inputStatistics().driver_errors,
                .midi_output = self.outputStatistics().driver_errors,
            };
        }

        pub fn resetInputStatistics(self: *Self) !void {
            if (self.input_running.load(.acquire))
                return error.WinMidiInputAlreadyRunning;
            self.received_count.store(0, .release);
            self.unsupported_count.store(0, .release);
            self.malformed_count.store(0, .release);
            self.final_driver_errors = 0;
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

        fn receiveBytes(
            optional_context: ?*anyopaque,
            timestamp_nanoseconds: u64,
            bytes_pointer: [*c]const u8,
            length: usize,
        ) callconv(.c) void {
            const self = callbackContext(optional_context) orelse return;
            var admission = self.input_callbacks.admit() orelse return;
            defer admission.release();
            const callback = self.input_callback orelse return;
            if (bytes_pointer == null or
                timestamp_nanoseconds == 0 or
                length == 0 or length > 3)
            {
                incrementSaturating(&self.malformed_count);
                return;
            }
            const bytes = bytes_pointer[0..length];
            if (bytes[0] >= 0xf0) {
                incrementSaturating(&self.unsupported_count);
                return;
            }
            const message = process_api.Midi1Message.parse(
                bytes,
            ) catch {
                incrementSaturating(&self.malformed_count);
                return;
            };
            callback.receive(callback.context, .{
                .timestamp_nanoseconds = timestamp_nanoseconds,
                .message = message,
            });
            incrementSaturating(&self.received_count);
        }

        fn callbackContext(
            optional_context: ?*anyopaque,
        ) ?*Self {
            const context = optional_context orelse return null;
            if (@intFromPtr(context) % @alignOf(Self) != 0)
                return null;
            return @ptrCast(@alignCast(context));
        }
    };
}

pub const WinMidiBackend = Backend(WinMidiSystemApi);

const Direction = enum(u8) {
    input,
    output,
};

fn enumerateDirection(
    comptime Api: type,
    direction: Direction,
    output: []device_catalog.DeviceDescriptor,
    initial_count: usize,
) !usize {
    var count = initial_count;
    var id_storage: [Api.maximum_identifier_bytes]u8 = undefined;
    var raw_name_storage: [Api.maximum_name_bytes]u8 = undefined;
    var name_storage: [device_catalog.maximum_device_name_bytes]u8 = undefined;
    for (0..try Api.deviceCount(direction)) |index| {
        if (count == output.len)
            return error.WinMidiDeviceStorageTooSmall;
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
            false,
        );
        count += 1;
    }
    return count;
}

fn boundedDeviceName(raw: []const u8, storage: []u8) ![]const u8 {
    if (raw.len == 0 or !std.unicode.utf8ValidateSlice(raw) or
        std.mem.indexOfScalar(u8, raw, 0) != null)
        return error.InvalidWinMidiDeviceName;
    var source_length = @min(raw.len, storage.len);
    while (source_length != 0 and
        !std.unicode.utf8ValidateSlice(raw[0..source_length]))
        source_length -= 1;
    if (source_length == 0) return error.WinMidiDeviceNameTooLong;
    @memcpy(storage[0..source_length], raw[0..source_length]);
    return storage[0..source_length];
}

fn endpointIdentifier(
    direction: Direction,
    raw_identifier: []const u8,
) !device_catalog.DeviceIdentifier {
    if (raw_identifier.len == 0 or
        !std.unicode.utf8ValidateSlice(raw_identifier) or
        std.mem.indexOfScalar(u8, raw_identifier, 0) != null)
        return error.InvalidWinMidiEndpointIdentifier;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(
        raw_identifier,
        &digest,
        .{},
    );
    const prefix = if (direction == .input)
        "winmidi-input:"
    else
        "winmidi-output:";
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

fn resolveIndex(
    comptime Api: type,
    direction: Direction,
    identifier: device_catalog.DeviceIdentifier,
) !usize {
    if (!identifier.valid())
        return error.InvalidDeviceIdentifier;
    var storage: [Api.maximum_identifier_bytes]u8 = undefined;
    for (0..try Api.deviceCount(direction)) |index| {
        const raw = try Api.deviceId(direction, index, &storage);
        const candidate = try endpointIdentifier(direction, raw);
        if (candidate.eql(&identifier)) return index;
    }
    return error.WinMidiDeviceNotFound;
}

fn topologyFingerprint(comptime Api: type) !u64 {
    var hasher = std.hash.Wyhash.init(0);
    inline for (.{ Direction.input, Direction.output }) |direction| {
        const count = try Api.deviceCount(direction);
        hasher.update(std.mem.asBytes(&count));
        var storage: [Api.maximum_identifier_bytes]u8 = undefined;
        for (0..count) |index|
            hasher.update(try Api.deviceId(direction, index, &storage));
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

const WinMidiSystemApi = if (builtin.os.tag == .windows)
    WindowsWinMidiApi
else
    UnsupportedWinMidiApi;

const UnsupportedWinMidiApi = struct {
    const supported = false;
    const maximum_identifier_bytes = 1024;
    const maximum_name_bytes = 1024;
    const Input = u32;
    const Output = u32;

    fn nowNanoseconds() u64 {
        return 0;
    }

    fn deviceCount(_: Direction) !usize {
        return error.UnsupportedPlatform;
    }

    fn deviceId(_: Direction, _: usize, _: []u8) ![]const u8 {
        return error.UnsupportedPlatform;
    }

    fn deviceName(_: Direction, _: usize, _: []u8) ![]const u8 {
        return error.UnsupportedPlatform;
    }

    fn startInput(_: usize, _: *anyopaque, _: ReceiveBytes) !Input {
        return error.UnsupportedPlatform;
    }

    fn stopInput(_: Input) InputStatistics {
        return emptyStatistics();
    }

    fn inputStatistics(_: Input) InputStatistics {
        return emptyStatistics();
    }

    fn openOutput(_: usize) !Output {
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

fn emptyStatistics() InputStatistics {
    return .{
        .received = 0,
        .unsupported = 0,
        .malformed = 0,
        .driver_errors = 0,
    };
}

fn emptyOutputStatistics() OutputStatistics {
    return .{
        .queued = 0,
        .delivered = 0,
        .late = 0,
        .rejected = 0,
        .canceled = 0,
        .driver_errors = 0,
    };
}

const WindowsWinMidiApi = if (builtin.os.tag == .windows) struct {
    const c = @cImport({
        @cInclude("win_midi_shim.h");
    });
    const supported = true;
    const maximum_identifier_bytes = 4096;
    const maximum_name_bytes = 1024;
    const Input = *c.zv3_win_midi_input;
    const Output = *c.zv3_win_midi_output;

    fn nowNanoseconds() u64 {
        return c.zv3_win_midi_now_nanoseconds();
    }

    fn deviceCount(direction: Direction) !usize {
        var result: usize = 0;
        if (c.zv3_win_midi_device_count(
            @intFromEnum(direction),
            &result,
        ) != 0)
            return error.WinMidiDeviceQueryFailed;
        return result;
    }

    fn deviceId(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_win_midi_device_id(
            @intFromEnum(direction),
            index,
            storage.ptr,
            storage.len,
            &length,
        ) != 0)
            return error.WinMidiDeviceQueryFailed;
        if (length == 0 or length > storage.len)
            return error.InvalidWinMidiEndpointIdentifier;
        return storage[0..length];
    }

    fn deviceName(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_win_midi_device_name(
            @intFromEnum(direction),
            index,
            storage.ptr,
            storage.len,
            &length,
        ) != 0)
            return error.WinMidiDeviceQueryFailed;
        if (length == 0 or length > storage.len)
            return error.WinMidiDeviceNameTooLong;
        return storage[0..length];
    }

    fn startInput(
        index: usize,
        context: *anyopaque,
        receive: ReceiveBytes,
    ) !Input {
        var input: ?Input = null;
        if (c.zv3_win_midi_start_input(
            index,
            context,
            receive,
            &input,
        ) != 0)
            return error.WinMidiInputStartFailed;
        return input orelse error.WinMidiInputStartFailed;
    }

    fn stopInput(input: Input) InputStatistics {
        var result: c.zv3_win_midi_input_statistics = undefined;
        c.zv3_win_midi_stop_input(input, &result);
        return .{
            .received = 0,
            .unsupported = 0,
            .malformed = 0,
            .driver_errors = result.driver_errors,
        };
    }

    fn inputStatistics(input: Input) InputStatistics {
        var result: c.zv3_win_midi_input_statistics = undefined;
        c.zv3_win_midi_get_input_statistics(input, &result);
        return .{
            .received = 0,
            .unsupported = 0,
            .malformed = 0,
            .driver_errors = result.driver_errors,
        };
    }

    fn openOutput(index: usize) !Output {
        var output: ?Output = null;
        if (c.zv3_win_midi_open_output(index, &output) != 0)
            return error.WinMidiOutputOpenFailed;
        return output orelse error.WinMidiOutputOpenFailed;
    }

    fn closeOutput(output: Output) OutputStatistics {
        var result: c.zv3_win_midi_output_statistics = undefined;
        c.zv3_win_midi_close_output(output, &result);
        return .{
            .queued = result.queued,
            .delivered = result.delivered,
            .late = result.late,
            .rejected = result.rejected,
            .canceled = result.canceled,
            .driver_errors = result.driver_errors,
        };
    }

    fn send(
        output: Output,
        timestamp_nanoseconds: u64,
        bytes: []const u8,
    ) !void {
        const result = c.zv3_win_midi_send(
            output,
            timestamp_nanoseconds,
            bytes.ptr,
            bytes.len,
        );
        if (result == -2) return error.WinMidiOutputQueueFull;
        if (result != 0) return error.WinMidiSendFailed;
    }

    fn outputStatistics(output: Output) OutputStatistics {
        var result: c.zv3_win_midi_output_statistics = undefined;
        c.zv3_win_midi_get_output_statistics(output, &result);
        return .{
            .queued = result.queued,
            .delivered = result.delivered,
            .late = result.late,
            .rejected = result.rejected,
            .canceled = result.canceled,
            .driver_errors = result.driver_errors,
        };
    }
} else struct {};

test "unsupported Windows MIDI backend fails explicitly" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var backend = WinMidiBackend{};
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.open("test"),
    );
}

const MockApi = struct {
    const supported = true;
    const maximum_identifier_bytes = 64;
    const maximum_name_bytes = 128;
    const Input = u32;
    const Output = u32;
    const inputs = [_][]const u8{ "input-path-a", "input-path-b" };
    const outputs = [_][]const u8{ "output-path-a", "output-path-b" };
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

    fn deviceName(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        const names = if (direction == .input)
            [_][]const u8{ "Keyboard A", "Keyboard B" }
        else
            [_][]const u8{ "Synth A", "Synth B" };
        const value = names[index];
        @memcpy(storage[0..value.len], value);
        return storage[0..value.len];
    }

    fn startInput(
        _: usize,
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
            .driver_errors = 2,
        };
    }

    fn inputStatistics(_: Input) InputStatistics {
        return .{
            .received = 0,
            .unsupported = 0,
            .malformed = 0,
            .driver_errors = 1,
        };
    }

    fn openOutput(_: usize) !Output {
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
            return error.WinMidiOutputQueueFull;
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
            return error.MissingWinMidiCallback;
        function(
            receive_context,
            timestamp,
            bytes.ptr,
            bytes.len,
        );
    }
};

test "Windows MIDI discovery publishes stable directional endpoints" {
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
    try std.testing.expect(!descriptors[0].is_default);
    try std.testing.expect(!descriptors[2].is_default);
    try backend.selectInput(descriptors[1].identifier);
    try backend.selectOutput(descriptors[3].identifier);
}

test "Windows MIDI adapts short input and retains driver errors" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    const Probe = struct {
        packet: ?standalone.TimestampedMidi1Packet = null,

        fn receive(
            context: *anyopaque,
            packet: standalone.TimestampedMidi1Packet,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.packet = packet;
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
    try MockApi.inject(&.{ 0x90, 60, 100 }, 123);
    try std.testing.expectEqual(@as(usize, 1), backend.inputStatistics().received);
    try std.testing.expectEqual(@as(u64, 1), backend.inputStatistics().driver_errors);
    try std.testing.expectEqual(
        @as(u64, 123),
        probe.packet.?.timestamp_nanoseconds,
    );
    try MockApi.inject(&.{0xf8}, 124);
    try MockApi.inject(&.{ 0x90, 60 }, 125);
    try std.testing.expectEqual(@as(usize, 1), backend.inputStatistics().unsupported);
    try std.testing.expectEqual(@as(usize, 1), backend.inputStatistics().malformed);
    backend.stopInput();
    try std.testing.expectEqual(@as(u64, 2), backend.inputStatistics().driver_errors);
    try std.testing.expectEqual(
        @as(u64, 2),
        (try backend.failureSource().snapshot()).midi_input,
    );
}

test "Windows MIDI input stop drains an admitted callback" {
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

test "Windows MIDI callback rejects misaligned context" {
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

test "Windows MIDI output preserves future timestamps and selection is transactional" {
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
        error.WinMidiOutputQueueFull,
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
    MockApi.output_statistics.driver_errors = 3;
    MockApi.output_statistics.canceled = 2;
    try std.testing.expectEqual(
        @as(u64, 3),
        (try backend.failureSource().snapshot()).midi_output,
    );
    backend.clearOutputSelection();
    try std.testing.expectEqual(
        @as(u64, 3),
        backend.outputStatistics().driver_errors,
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

test "Windows MIDI topology polling and failed input start are retryable" {
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

test "Windows MIDI failed open restores the closed state" {
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
