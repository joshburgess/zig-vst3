const builtin = @import("builtin");
const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const device_catalog = core.plugin;
const process_api = core.process;
const standalone = core.plugin;

const ReceiveBytes = *const fn (
    context: ?*anyopaque,
    timestamp_ticks: u64,
    bytes: [*c]const u8,
    length: usize,
) callconv(.c) void;

const NotifyTopologyChanged = *const fn (
    context: ?*anyopaque,
) callconv(.c) void;

pub const Timebase = struct {
    numerator: u32,
    denominator: u32,

    pub fn valid(self: Timebase) bool {
        return self.numerator != 0 and self.denominator != 0;
    }

    pub fn ticksToNanoseconds(self: Timebase, ticks: u64) !u64 {
        if (!self.valid()) return error.InvalidCoreMidiTimebase;
        return scaleTime(ticks, self.numerator, self.denominator);
    }

    pub fn nanosecondsToTicks(
        self: Timebase,
        nanoseconds: u64,
    ) !u64 {
        if (!self.valid()) return error.InvalidCoreMidiTimebase;
        return scaleTimeCeil(
            nanoseconds,
            self.denominator,
            self.numerator,
        );
    }
};

pub const InputStatistics = struct {
    received: usize,
    unsupported: usize,
    malformed: usize,
    disconnect_failures: usize,
};

pub fn Backend(comptime Api: type) type {
    return struct {
        const Self = @This();
        const Endpoint = Api.Endpoint;
        const Client = Api.Client;
        const Port = Api.Port;

        api_state: Api.State = .{},
        client: ?Client = null,
        input_port: ?Port = null,
        output_port: ?Port = null,
        selected_input: ?Endpoint = null,
        selected_output: std.atomic.Value(Endpoint) =
            std.atomic.Value(Endpoint).init(0),
        timebase: Timebase = .{
            .numerator = 0,
            .denominator = 0,
        },
        input_callback: ?standalone.Midi1InputCallback = null,
        input_running: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        topology_generation: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),
        received_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        unsupported_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        malformed_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        disconnect_failure_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),

        /// Keep the backend at a stable address from `open` through `close`.
        pub fn open(self: *Self, client_name: []const u8) !void {
            if (self.client != null or
                self.input_port != null or
                self.output_port != null)
                return error.CoreMidiBackendAlreadyOpen;
            if (client_name.len == 0)
                return error.EmptyCoreMidiClientName;
            if (!std.unicode.utf8ValidateSlice(client_name) or
                std.mem.indexOfScalar(u8, client_name, 0) != null)
                return error.InvalidCoreMidiClientName;

            const next_timebase = try Api.timebase();
            if (!next_timebase.valid())
                return error.InvalidCoreMidiTimebase;
            errdefer Api.reset(&self.api_state);
            const next_client = try Api.createClient(
                &self.api_state,
                client_name,
                self,
                notifyTopologyChanged,
            );
            errdefer Api.disposeClient(next_client);
            const next_input_port = try Api.createInputPort(
                &self.api_state,
                next_client,
                client_name,
                self,
                receiveBytes,
            );
            errdefer Api.disposePort(next_input_port);
            const next_output_port = try Api.createOutputPort(
                next_client,
                client_name,
            );

            self.client = next_client;
            self.input_port = next_input_port;
            self.output_port = next_output_port;
            self.timebase = next_timebase;
            self.topology_generation.store(1, .release);
        }

        pub fn close(self: *Self) void {
            self.stopInput();
            if (self.output_port) |port|
                Api.disposePort(port);
            if (self.input_port) |port|
                Api.disposePort(port);
            if (self.client) |client|
                Api.disposeClient(client);
            self.client = null;
            self.input_port = null;
            self.output_port = null;
            self.selected_input = null;
            self.selected_output.store(0, .release);
            self.timebase = .{
                .numerator = 0,
                .denominator = 0,
            };
            self.input_callback = null;
            Api.reset(&self.api_state);
            self.topology_generation.store(0, .release);
        }

        pub fn isOpen(self: *const Self) bool {
            return self.client != null and
                self.input_port != null and
                self.output_port != null and
                self.timebase.valid();
        }

        pub fn currentTopologyGeneration(
            self: *const Self,
        ) u64 {
            return self.topology_generation.load(.acquire);
        }

        pub fn nowNanoseconds(self: *const Self) !u64 {
            if (!self.isOpen())
                return error.CoreMidiBackendNotOpen;
            return self.timebase.ticksToNanoseconds(
                Api.nowTicks(),
            );
        }

        pub fn enumerate(
            self: *const Self,
            output: []device_catalog.DeviceDescriptor,
        ) !usize {
            if (!self.isOpen())
                return error.CoreMidiBackendNotOpen;
            const initial_generation =
                self.currentTopologyGeneration();
            const source_count = Api.sourceCount();
            const destination_count = Api.destinationCount();
            const required = std.math.add(
                usize,
                source_count,
                destination_count,
            ) catch return error.CoreMidiDeviceCountOverflow;
            if (output.len < required)
                return error.CoreMidiDeviceStorageTooSmall;

            var count: usize = 0;
            var name_storage: [device_catalog.maximum_device_name_bytes]u8 = undefined;
            for (0..source_count) |index| {
                const endpoint = try Api.sourceAt(index);
                const identifier = try endpointIdentifier(
                    Api,
                    endpoint,
                );
                const name = try Api.endpointName(
                    endpoint,
                    &name_storage,
                );
                output[count] = try device_catalog.DeviceDescriptor.init(
                    .midi_input,
                    identifier.slice(),
                    name,
                    0,
                    0,
                    index == 0,
                );
                count += 1;
            }
            for (0..destination_count) |index| {
                const endpoint = try Api.destinationAt(index);
                const identifier = try endpointIdentifier(
                    Api,
                    endpoint,
                );
                const name = try Api.endpointName(
                    endpoint,
                    &name_storage,
                );
                output[count] = try device_catalog.DeviceDescriptor.init(
                    .midi_output,
                    identifier.slice(),
                    name,
                    0,
                    0,
                    index == 0,
                );
                count += 1;
            }
            if (self.currentTopologyGeneration() !=
                initial_generation)
                return error.CoreMidiTopologyChanged;
            return count;
        }

        pub fn selectInput(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            if (!self.isOpen())
                return error.CoreMidiBackendNotOpen;
            if (self.input_running.load(.acquire))
                return error.CoreMidiInputAlreadyRunning;
            self.selected_input = try findEndpoint(
                Api,
                .input,
                identifier,
            );
        }

        pub fn selectOutput(
            self: *Self,
            identifier: device_catalog.DeviceIdentifier,
        ) !void {
            if (!self.isOpen())
                return error.CoreMidiBackendNotOpen;
            const endpoint = try findEndpoint(
                Api,
                .output,
                identifier,
            );
            self.selected_output.store(endpoint, .release);
        }

        pub fn clearInputSelection(self: *Self) !void {
            if (self.input_running.load(.acquire))
                return error.CoreMidiInputAlreadyRunning;
            self.selected_input = null;
        }

        pub fn clearOutputSelection(self: *Self) void {
            self.selected_output.store(0, .release);
        }

        pub fn startInput(
            self: *Self,
            callback: standalone.Midi1InputCallback,
        ) !void {
            const port = self.input_port orelse
                return error.CoreMidiBackendNotOpen;
            const endpoint = self.selected_input orelse
                return error.CoreMidiInputNotSelected;
            if (self.input_running.load(.acquire))
                return error.CoreMidiInputAlreadyRunning;
            self.input_callback = callback;
            self.input_running.store(true, .release);
            Api.connectSource(port, endpoint) catch |connect_error| {
                self.input_running.store(false, .release);
                return connect_error;
            };
        }

        pub fn stopInput(self: *Self) void {
            if (!self.input_running.swap(false, .acq_rel))
                return;
            const port = self.input_port orelse return;
            const endpoint = self.selected_input orelse return;
            Api.disconnectSource(port, endpoint) catch
                incrementSaturating(&self.disconnect_failure_count);
        }

        pub fn send(
            self: *Self,
            packet: standalone.TimestampedMidi1Packet,
        ) !void {
            const port = self.output_port orelse
                return error.CoreMidiBackendNotOpen;
            const endpoint = self.selected_output.load(.acquire);
            if (endpoint == 0)
                return error.CoreMidiOutputNotSelected;
            if (!packet.message.valid())
                return error.InvalidMidiPacket;
            const timestamp_ticks =
                try self.timebase.nanosecondsToTicks(
                    packet.timestamp_nanoseconds,
                );
            try Api.send(
                port,
                endpoint,
                timestamp_ticks,
                packet.message.bytes(),
            );
        }

        pub fn inputDevice(
            self: *Self,
        ) standalone.Midi1InputDevice {
            return .{
                .context = self,
                .start_input = startInputErased,
                .stop_input = stopInputErased,
            };
        }

        pub fn outputDevice(
            self: *Self,
        ) standalone.Midi1OutputDevice {
            return .{
                .context = self,
                .send_output = sendErased,
            };
        }

        pub fn inputStatistics(
            self: *const Self,
        ) InputStatistics {
            return .{
                .received = self.received_count.load(.acquire),
                .unsupported = self.unsupported_count.load(.acquire),
                .malformed = self.malformed_count.load(.acquire),
                .disconnect_failures = self.disconnect_failure_count.load(.acquire),
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
            return .{
                .midi_input = @intCast(
                    self.inputStatistics().disconnect_failures,
                ),
            };
        }

        pub fn resetInputStatistics(self: *Self) !void {
            if (self.input_running.load(.acquire))
                return error.CoreMidiInputAlreadyRunning;
            self.received_count.store(0, .release);
            self.unsupported_count.store(0, .release);
            self.malformed_count.store(0, .release);
            self.disconnect_failure_count.store(0, .release);
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

        pub fn receiveBytes(
            optional_context: ?*anyopaque,
            timestamp_ticks: u64,
            bytes_pointer: [*c]const u8,
            length: usize,
        ) callconv(.c) void {
            const self = callbackContext(optional_context) orelse return;
            if (!self.input_running.load(.acquire)) return;
            const callback = self.input_callback orelse return;
            if (bytes_pointer == null or length == 0) {
                incrementSaturating(&self.malformed_count);
                return;
            }
            const timestamp_nanoseconds =
                self.timebase.ticksToNanoseconds(
                    timestamp_ticks,
                ) catch {
                    incrementSaturating(&self.malformed_count);
                    return;
                };
            parseMidi1Bytes(
                bytes_pointer[0..length],
                timestamp_nanoseconds,
                callback,
                &self.received_count,
                &self.unsupported_count,
                &self.malformed_count,
            );
        }

        pub fn notifyTopologyChanged(
            optional_context: ?*anyopaque,
        ) callconv(.c) void {
            const self = callbackContext(optional_context) orelse return;
            incrementGeneration(&self.topology_generation);
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

pub const CoreMidiBackend = Backend(CoreMidiSystemApi);

const EndpointDirection = enum {
    input,
    output,
};

fn findEndpoint(
    comptime Api: type,
    direction: EndpointDirection,
    identifier: device_catalog.DeviceIdentifier,
) !Api.Endpoint {
    if (!identifier.valid())
        return error.InvalidDeviceIdentifier;
    const unique_id = try parseEndpointIdentifier(
        identifier.slice(),
    );
    const count = switch (direction) {
        .input => Api.sourceCount(),
        .output => Api.destinationCount(),
    };
    for (0..count) |index| {
        const endpoint = switch (direction) {
            .input => try Api.sourceAt(index),
            .output => try Api.destinationAt(index),
        };
        if (try Api.endpointUniqueId(endpoint) == unique_id)
            return endpoint;
    }
    return error.CoreMidiEndpointNotFound;
}

fn endpointIdentifier(
    comptime Api: type,
    endpoint: Api.Endpoint,
) !device_catalog.DeviceIdentifier {
    const unique_id = try Api.endpointUniqueId(endpoint);
    var storage: [device_catalog.maximum_device_identifier_bytes]u8 = undefined;
    const text = try std.fmt.bufPrint(
        &storage,
        "coremidi:{d}",
        .{unique_id},
    );
    return device_catalog.DeviceIdentifier.init(text);
}

fn parseEndpointIdentifier(value: []const u8) !i32 {
    const prefix = "coremidi:";
    if (!std.mem.startsWith(u8, value, prefix))
        return error.InvalidCoreMidiEndpointIdentifier;
    const number = value[prefix.len..];
    if (number.len == 0)
        return error.InvalidCoreMidiEndpointIdentifier;
    const unique_id = std.fmt.parseInt(i32, number, 10) catch
        return error.InvalidCoreMidiEndpointIdentifier;
    if (unique_id == 0)
        return error.InvalidCoreMidiEndpointIdentifier;
    return unique_id;
}

fn parseMidi1Bytes(
    bytes: []const u8,
    timestamp_nanoseconds: u64,
    callback: standalone.Midi1InputCallback,
    received_count: *std.atomic.Value(usize),
    unsupported_count: *std.atomic.Value(usize),
    malformed_count: *std.atomic.Value(usize),
) void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const status = bytes[offset];
        if (status < 0x80) {
            incrementSaturating(malformed_count);
            offset += 1;
            continue;
        }
        if (status < 0xf0) {
            const length: usize = switch (status & 0xf0) {
                0xc0, 0xd0 => 2,
                else => 3,
            };
            var message_storage: [3]u8 = @splat(0);
            message_storage[0] = status;
            var message_length: usize = 1;
            var cursor = offset + 1;
            var interrupted = false;
            while (message_length < length and cursor < bytes.len) {
                const byte = bytes[cursor];
                if (byte >= 0xf8) {
                    incrementSaturating(unsupported_count);
                    cursor += 1;
                    continue;
                }
                if (byte >= 0x80) {
                    incrementSaturating(malformed_count);
                    offset = cursor;
                    interrupted = true;
                    break;
                }
                message_storage[message_length] = byte;
                message_length += 1;
                cursor += 1;
            }
            if (interrupted) continue;
            if (message_length != length) {
                incrementSaturating(malformed_count);
                return;
            }
            const message = process_api.Midi1Message.parse(
                message_storage[0..length],
            ) catch {
                incrementSaturating(malformed_count);
                offset = cursor;
                continue;
            };
            callback.receive(callback.context, .{
                .timestamp_nanoseconds = timestamp_nanoseconds,
                .message = message,
            });
            incrementSaturating(received_count);
            offset = cursor;
            continue;
        }

        const unsupported_length: usize = switch (status) {
            0xf0 => blk: {
                const end = std.mem.indexOfScalarPos(
                    u8,
                    bytes,
                    offset + 1,
                    0xf7,
                ) orelse {
                    incrementSaturating(malformed_count);
                    return;
                };
                break :blk end - offset + 1;
            },
            0xf1, 0xf3 => 2,
            0xf2 => 3,
            0xf6, 0xf7, 0xf8...0xff => 1,
            else => 1,
        };
        const end = std.math.add(
            usize,
            offset,
            unsupported_length,
        ) catch {
            incrementSaturating(malformed_count);
            return;
        };
        if (end > bytes.len) {
            incrementSaturating(malformed_count);
            return;
        }
        incrementSaturating(unsupported_count);
        offset = end;
    }
}

fn scaleTime(value: u64, multiplier: u32, divisor: u32) !u64 {
    if (multiplier == 0 or divisor == 0)
        return error.InvalidCoreMidiTimebase;
    const quotient = value / divisor;
    const remainder = value % divisor;
    const whole = std.math.mul(
        u64,
        quotient,
        multiplier,
    ) catch return error.CoreMidiTimestampOverflow;
    const fractional_product = std.math.mul(
        u64,
        remainder,
        multiplier,
    ) catch return error.CoreMidiTimestampOverflow;
    return std.math.add(
        u64,
        whole,
        fractional_product / divisor,
    ) catch return error.CoreMidiTimestampOverflow;
}

fn scaleTimeCeil(
    value: u64,
    multiplier: u32,
    divisor: u32,
) !u64 {
    if (multiplier == 0 or divisor == 0)
        return error.InvalidCoreMidiTimebase;
    const quotient = value / divisor;
    const remainder = value % divisor;
    const whole = std.math.mul(
        u64,
        quotient,
        multiplier,
    ) catch return error.CoreMidiTimestampOverflow;
    const fractional_product = std.math.mul(
        u64,
        remainder,
        multiplier,
    ) catch return error.CoreMidiTimestampOverflow;
    var result = std.math.add(
        u64,
        whole,
        fractional_product / divisor,
    ) catch return error.CoreMidiTimestampOverflow;
    if (fractional_product % divisor != 0) {
        result = std.math.add(
            u64,
            result,
            1,
        ) catch return error.CoreMidiTimestampOverflow;
    }
    return result;
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

const CoreMidiSystemApi = if (builtin.os.tag == .macos)
    MacOsCoreMidiApi
else
    UnsupportedCoreMidiApi;

const UnsupportedCoreMidiApi = struct {
    const Endpoint = u32;
    const Client = u32;
    const Port = u32;
    const State = struct {};

    fn timebase() !Timebase {
        return error.UnsupportedPlatform;
    }

    fn createClient(
        _: *State,
        _: []const u8,
        _: *anyopaque,
        _: NotifyTopologyChanged,
    ) !Client {
        return error.UnsupportedPlatform;
    }

    fn createInputPort(
        _: *State,
        _: Client,
        _: []const u8,
        _: *anyopaque,
        _: ReceiveBytes,
    ) !Port {
        return error.UnsupportedPlatform;
    }

    fn createOutputPort(_: Client, _: []const u8) !Port {
        return error.UnsupportedPlatform;
    }

    fn disposeClient(_: Client) void {}
    fn disposePort(_: Port) void {}
    fn sourceCount() usize {
        return 0;
    }
    fn destinationCount() usize {
        return 0;
    }
    fn sourceAt(_: usize) !Endpoint {
        return error.UnsupportedPlatform;
    }
    fn destinationAt(_: usize) !Endpoint {
        return error.UnsupportedPlatform;
    }
    fn endpointUniqueId(_: Endpoint) !i32 {
        return error.UnsupportedPlatform;
    }
    fn endpointName(_: Endpoint, _: []u8) ![]const u8 {
        return error.UnsupportedPlatform;
    }
    fn connectSource(_: Port, _: Endpoint) !void {
        return error.UnsupportedPlatform;
    }
    fn disconnectSource(_: Port, _: Endpoint) !void {
        return error.UnsupportedPlatform;
    }
    fn send(_: Port, _: Endpoint, _: u64, _: []const u8) !void {
        return error.UnsupportedPlatform;
    }
    fn nowTicks() u64 {
        return 0;
    }
    fn reset(_: *State) void {}
};

const MacOsCoreMidiApi = if (builtin.os.tag == .macos) struct {
    const c = @cImport({
        @cInclude("core_midi_shim.h");
    });

    const Endpoint = u32;
    const Client = u32;
    const Port = u32;
    const State = struct {
        notify: c.zv3_core_midi_notify_state = .{
            .context = null,
            .callback = null,
        },
        receive: c.zv3_core_midi_receive_state = .{
            .context = null,
            .callback = null,
        },
    };

    fn timebase() !Timebase {
        var result: c.zv3_core_midi_timebase = undefined;
        if (c.zv3_core_midi_get_timebase(&result) != 0)
            return error.CoreMidiClockFailure;
        return .{
            .numerator = result.numerator,
            .denominator = result.denominator,
        };
    }

    fn createClient(
        state: *State,
        name: []const u8,
        notify_context: *anyopaque,
        notify_callback: NotifyTopologyChanged,
    ) !Client {
        state.notify = .{
            .context = notify_context,
            .callback = notify_callback,
        };
        var client: Client = 0;
        if (c.zv3_core_midi_create_client(
            name.ptr,
            name.len,
            &state.notify,
            &client,
        ) != 0)
            return error.CoreMidiClientCreateFailed;
        return client;
    }

    fn createInputPort(
        state: *State,
        client: Client,
        name: []const u8,
        context: *anyopaque,
        callback: ReceiveBytes,
    ) !Port {
        state.receive = .{
            .context = context,
            .callback = callback,
        };
        var port: Port = 0;
        if (c.zv3_core_midi_create_input_port(
            client,
            name.ptr,
            name.len,
            &state.receive,
            &port,
        ) != 0)
            return error.CoreMidiInputPortCreateFailed;
        return port;
    }

    fn createOutputPort(
        client: Client,
        name: []const u8,
    ) !Port {
        var port: Port = 0;
        if (c.zv3_core_midi_create_output_port(
            client,
            name.ptr,
            name.len,
            &port,
        ) != 0)
            return error.CoreMidiOutputPortCreateFailed;
        return port;
    }

    fn disposeClient(client: Client) void {
        c.zv3_core_midi_dispose_client(client);
    }

    fn disposePort(port: Port) void {
        c.zv3_core_midi_dispose_port(port);
    }

    fn sourceCount() usize {
        return c.zv3_core_midi_source_count();
    }

    fn destinationCount() usize {
        return c.zv3_core_midi_destination_count();
    }

    fn sourceAt(index: usize) !Endpoint {
        var endpoint: Endpoint = 0;
        if (c.zv3_core_midi_source_at(index, &endpoint) != 0)
            return error.CoreMidiEndpointNotFound;
        return endpoint;
    }

    fn destinationAt(index: usize) !Endpoint {
        var endpoint: Endpoint = 0;
        if (c.zv3_core_midi_destination_at(
            index,
            &endpoint,
        ) != 0)
            return error.CoreMidiEndpointNotFound;
        return endpoint;
    }

    fn endpointUniqueId(endpoint: Endpoint) !i32 {
        var unique_id: i32 = 0;
        if (c.zv3_core_midi_endpoint_unique_id(
            endpoint,
            &unique_id,
        ) != 0)
            return error.CoreMidiEndpointHasNoUniqueId;
        return unique_id;
    }

    fn endpointName(
        endpoint: Endpoint,
        destination: []u8,
    ) ![]const u8 {
        var length: usize = 0;
        if (c.zv3_core_midi_endpoint_name(
            endpoint,
            destination.ptr,
            destination.len,
            &length,
        ) != 0)
            return error.CoreMidiEndpointHasNoName;
        if (length == 0 or length > destination.len)
            return error.CoreMidiEndpointNameTooLong;
        return destination[0..length];
    }

    fn connectSource(port: Port, endpoint: Endpoint) !void {
        if (c.zv3_core_midi_connect_source(
            port,
            endpoint,
        ) != 0)
            return error.CoreMidiInputConnectFailed;
    }

    fn disconnectSource(port: Port, endpoint: Endpoint) !void {
        if (c.zv3_core_midi_disconnect_source(
            port,
            endpoint,
        ) != 0)
            return error.CoreMidiInputDisconnectFailed;
    }

    fn send(
        port: Port,
        endpoint: Endpoint,
        timestamp_ticks: u64,
        bytes: []const u8,
    ) !void {
        if (c.zv3_core_midi_send(
            port,
            endpoint,
            timestamp_ticks,
            bytes.ptr,
            bytes.len,
        ) != 0)
            return error.CoreMidiSendFailed;
    }

    fn nowTicks() u64 {
        return c.zv3_core_midi_now_ticks();
    }

    fn reset(state: *State) void {
        state.* = .{};
    }
} else UnsupportedCoreMidiApi;

const TestApi = struct {
    const Endpoint = u32;
    const Client = u32;
    const Port = u32;
    const State = struct {};

    const Source = struct {
        endpoint: Endpoint,
        unique_id: i32,
        name: []const u8,
    };

    var sources: []const Source = &.{
        .{ .endpoint = 11, .unique_id = 101, .name = "Input A" },
        .{ .endpoint = 12, .unique_id = -202, .name = "Input B" },
    };
    var destinations: []const Source = &.{
        .{ .endpoint = 21, .unique_id = 303, .name = "Output A" },
    };
    var notify_context: ?*anyopaque = null;
    var notify_callback: ?NotifyTopologyChanged = null;
    var receive_context: ?*anyopaque = null;
    var receive_callback: ?ReceiveBytes = null;
    var connected_endpoint: ?Endpoint = null;
    var sent_endpoint: ?Endpoint = null;
    var sent_ticks: u64 = 0;
    var sent_storage: [3]u8 = @splat(0);
    var sent_length: usize = 0;
    var fail_input_port = false;
    var fail_output_port = false;
    var fail_connect = false;
    var fail_disconnect = false;
    var fail_send = false;
    var notify_during_enumeration = false;
    var disposed_clients: usize = 0;
    var disposed_ports: usize = 0;

    fn resetTestState() void {
        notify_context = null;
        notify_callback = null;
        receive_context = null;
        receive_callback = null;
        connected_endpoint = null;
        sent_endpoint = null;
        sent_ticks = 0;
        sent_storage = @splat(0);
        sent_length = 0;
        fail_input_port = false;
        fail_output_port = false;
        fail_connect = false;
        fail_disconnect = false;
        fail_send = false;
        notify_during_enumeration = false;
        disposed_clients = 0;
        disposed_ports = 0;
    }

    fn timebase() !Timebase {
        return .{ .numerator = 125, .denominator = 3 };
    }

    fn createClient(
        _: *State,
        _: []const u8,
        context: *anyopaque,
        callback: NotifyTopologyChanged,
    ) !Client {
        notify_context = context;
        notify_callback = callback;
        return 1;
    }

    fn createInputPort(
        _: *State,
        _: Client,
        _: []const u8,
        context: *anyopaque,
        callback: ReceiveBytes,
    ) !Port {
        if (fail_input_port)
            return error.InjectedInputPortFailure;
        receive_context = context;
        receive_callback = callback;
        return 2;
    }

    fn createOutputPort(_: Client, _: []const u8) !Port {
        if (fail_output_port)
            return error.InjectedOutputPortFailure;
        return 3;
    }

    fn disposeClient(_: Client) void {
        disposed_clients += 1;
    }

    fn disposePort(_: Port) void {
        disposed_ports += 1;
    }

    fn sourceCount() usize {
        return sources.len;
    }

    fn destinationCount() usize {
        return destinations.len;
    }

    fn sourceAt(index: usize) !Endpoint {
        if (index >= sources.len)
            return error.CoreMidiEndpointNotFound;
        return sources[index].endpoint;
    }

    fn destinationAt(index: usize) !Endpoint {
        if (index >= destinations.len)
            return error.CoreMidiEndpointNotFound;
        return destinations[index].endpoint;
    }

    fn endpointUniqueId(endpoint: Endpoint) !i32 {
        for (sources) |source| {
            if (source.endpoint == endpoint)
                return source.unique_id;
        }
        for (destinations) |destination| {
            if (destination.endpoint == endpoint)
                return destination.unique_id;
        }
        return error.CoreMidiEndpointNotFound;
    }

    fn endpointName(
        endpoint: Endpoint,
        output: []u8,
    ) ![]const u8 {
        var found: ?[]const u8 = null;
        for (sources) |source| {
            if (source.endpoint == endpoint)
                found = source.name;
        }
        for (destinations) |destination| {
            if (destination.endpoint == endpoint)
                found = destination.name;
        }
        const name = found orelse
            return error.CoreMidiEndpointNotFound;
        if (output.len < name.len)
            return error.CoreMidiEndpointNameTooLong;
        @memcpy(output[0..name.len], name);
        if (notify_during_enumeration) {
            notify_during_enumeration = false;
            notify();
        }
        return output[0..name.len];
    }

    fn connectSource(_: Port, endpoint: Endpoint) !void {
        if (fail_connect)
            return error.InjectedConnectFailure;
        connected_endpoint = endpoint;
    }

    fn disconnectSource(_: Port, endpoint: Endpoint) !void {
        if (fail_disconnect)
            return error.InjectedDisconnectFailure;
        if (connected_endpoint != endpoint)
            return error.InvalidTestConnection;
        connected_endpoint = null;
    }

    fn send(
        _: Port,
        endpoint: Endpoint,
        timestamp_ticks: u64,
        bytes: []const u8,
    ) !void {
        if (fail_send)
            return error.InjectedSendFailure;
        if (bytes.len > sent_storage.len)
            return error.InvalidTestMessage;
        sent_endpoint = endpoint;
        sent_ticks = timestamp_ticks;
        sent_length = bytes.len;
        @memcpy(sent_storage[0..bytes.len], bytes);
    }

    fn nowTicks() u64 {
        return 24;
    }

    fn emit(timestamp_ticks: u64, bytes: []const u8) void {
        const context = receive_context orelse return;
        const callback = receive_callback orelse return;
        callback(
            context,
            timestamp_ticks,
            bytes.ptr,
            bytes.len,
        );
    }

    fn notify() void {
        const context = notify_context orelse return;
        const callback = notify_callback orelse return;
        callback(context);
    }

    fn reset(_: *State) void {}
};

test "CoreMIDI timebase conversion is checked and invertible" {
    const timebase = Timebase{
        .numerator = 125,
        .denominator = 3,
    };
    try std.testing.expectEqual(
        @as(u64, 1_000),
        try timebase.ticksToNanoseconds(24),
    );
    try std.testing.expectEqual(
        @as(u64, 24),
        try timebase.nanosecondsToTicks(1_000),
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        try timebase.nanosecondsToTicks(1),
    );
    try std.testing.expectError(
        error.InvalidCoreMidiTimebase,
        (Timebase{
            .numerator = 1,
            .denominator = 0,
        }).ticksToNanoseconds(1),
    );
    try std.testing.expectError(
        error.CoreMidiTimestampOverflow,
        (Timebase{
            .numerator = std.math.maxInt(u32),
            .denominator = 1,
        }).ticksToNanoseconds(std.math.maxInt(u64)),
    );
}

test "CoreMIDI endpoint identifiers are stable and strict" {
    const positive = try endpointIdentifier(TestApi, 11);
    try std.testing.expectEqualStrings(
        "coremidi:101",
        positive.slice(),
    );
    const negative = try endpointIdentifier(TestApi, 12);
    try std.testing.expectEqualStrings(
        "coremidi:-202",
        negative.slice(),
    );
    try std.testing.expectEqual(
        @as(i32, -202),
        try parseEndpointIdentifier(negative.slice()),
    );
    try std.testing.expectError(
        error.InvalidCoreMidiEndpointIdentifier,
        parseEndpointIdentifier("other:101"),
    );
    try std.testing.expectError(
        error.InvalidCoreMidiEndpointIdentifier,
        parseEndpointIdentifier("coremidi:0"),
    );
}

test "CoreMIDI unsupported backend fails before partial open" {
    const UnsupportedBackend = Backend(UnsupportedCoreMidiApi);
    var backend = UnsupportedBackend{};
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.open("Test client"),
    );
    try std.testing.expect(!backend.isOpen());
    try std.testing.expectEqual(
        @as(u64, 0),
        backend.currentTopologyGeneration(),
    );
}

test "CoreMIDI backend enumerates selects schedules and receives" {
    TestApi.resetTestState();
    const TestBackend = Backend(TestApi);
    var backend = TestBackend{};
    try backend.open("Test client");
    defer backend.close();
    try std.testing.expect(backend.isOpen());
    try std.testing.expectEqual(@as(u64, 1_000), try backend.nowNanoseconds());

    var devices: [3]device_catalog.DeviceDescriptor = undefined;
    const count = try backend.enumerate(&devices);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(
        device_catalog.DeviceKind.midi_input,
        devices[0].kind,
    );
    try std.testing.expect(devices[0].is_default);
    try std.testing.expectEqualStrings("Input A", devices[0].name());
    try std.testing.expectEqualStrings(
        "coremidi:-202",
        devices[1].identifier.slice(),
    );
    try std.testing.expectEqual(
        device_catalog.DeviceKind.midi_output,
        devices[2].kind,
    );

    try backend.selectInput(devices[1].identifier);
    try backend.selectOutput(devices[2].identifier);
    var scheduler = standalone.Midi1BlockScheduler(8){};
    var input_device = backend.inputDevice();
    try input_device.start(scheduler.inputCallback());
    try std.testing.expectEqual(@as(?u32, 12), TestApi.connected_endpoint);

    TestApi.emit(
        30,
        &.{
            0x90,
            60,
            0xf8,
            100,
            0xb0,
            74,
            64,
            0xf1,
            1,
        },
    );
    var events = standalone.Midi1EventBuffer(8){};
    const report = try scheduler.fillBlock(
        8,
        &events,
        1_000,
        1_000_000_000.0,
        1_000,
        0,
    );
    try std.testing.expectEqual(@as(usize, 2), report.scheduled);
    try std.testing.expectEqual(@as(usize, 2), events.count);
    const statistics = backend.inputStatistics();
    try std.testing.expectEqual(@as(usize, 2), statistics.received);
    try std.testing.expectEqual(@as(usize, 2), statistics.unsupported);
    try std.testing.expectEqual(@as(usize, 0), statistics.malformed);

    var output_device = backend.outputDevice();
    try output_device.send(.{
        .timestamp_nanoseconds = 2_000,
        .message = try process_api.Midi1Message.noteOff(
            3,
            60,
            64,
        ),
    });
    try std.testing.expectEqual(@as(?u32, 21), TestApi.sent_endpoint);
    try std.testing.expectEqual(@as(u64, 48), TestApi.sent_ticks);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x83, 60, 64 },
        TestApi.sent_storage[0..TestApi.sent_length],
    );

    input_device.stop();
    try std.testing.expectEqual(
        @as(?u32, null),
        TestApi.connected_endpoint,
    );
}

test "CoreMIDI backend open and input failures are transactional" {
    TestApi.resetTestState();
    const TestBackend = Backend(TestApi);
    var backend = TestBackend{};

    TestApi.fail_output_port = true;
    try std.testing.expectError(
        error.InjectedOutputPortFailure,
        backend.open("Test client"),
    );
    try std.testing.expect(!backend.isOpen());
    try std.testing.expectEqual(@as(usize, 1), TestApi.disposed_clients);
    try std.testing.expectEqual(@as(usize, 1), TestApi.disposed_ports);

    TestApi.fail_output_port = false;
    try backend.open("Test client");
    defer backend.close();
    try std.testing.expectError(
        error.CoreMidiInputNotSelected,
        backend.startInput(.{
            .context = &backend,
            .receive = struct {
                fn receive(
                    _: *anyopaque,
                    _: standalone.TimestampedMidi1Packet,
                ) void {}
            }.receive,
        }),
    );
    try std.testing.expectError(
        error.CoreMidiDeviceStorageTooSmall,
        backend.enumerate(&.{}),
    );
    try std.testing.expectError(
        error.CoreMidiEndpointNotFound,
        backend.selectInput(
            try device_catalog.DeviceIdentifier.init(
                "coremidi:999",
            ),
        ),
    );

    var devices: [3]device_catalog.DeviceDescriptor = undefined;
    TestApi.notify_during_enumeration = true;
    try std.testing.expectError(
        error.CoreMidiTopologyChanged,
        backend.enumerate(&devices),
    );
}

test "CoreMIDI connect and send failures preserve reusable state" {
    TestApi.resetTestState();
    const TestBackend = Backend(TestApi);
    var backend = TestBackend{};
    try backend.open("Test client");
    defer backend.close();
    var devices: [3]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&devices);
    try backend.selectInput(devices[0].identifier);
    try backend.selectOutput(devices[2].identifier);

    const Capture = struct {
        fn receive(
            _: *anyopaque,
            _: standalone.TimestampedMidi1Packet,
        ) void {}
    };
    var capture: u8 = 0;
    TestApi.fail_connect = true;
    try std.testing.expectError(
        error.InjectedConnectFailure,
        backend.startInput(.{
            .context = &capture,
            .receive = Capture.receive,
        }),
    );
    try std.testing.expect(
        !backend.input_running.load(.acquire),
    );
    TestApi.fail_connect = false;
    try backend.startInput(.{
        .context = &capture,
        .receive = Capture.receive,
    });
    try std.testing.expectError(
        error.CoreMidiInputAlreadyRunning,
        backend.resetInputStatistics(),
    );
    backend.stopInput();

    const packet = standalone.TimestampedMidi1Packet{
        .timestamp_nanoseconds = 2_000,
        .message = try process_api.Midi1Message.noteOn(
            0,
            60,
            100,
        ),
    };
    TestApi.fail_send = true;
    try std.testing.expectError(
        error.InjectedSendFailure,
        backend.send(packet),
    );
    TestApi.fail_send = false;
    try backend.send(packet);
    try std.testing.expectEqual(@as(?u32, 21), TestApi.sent_endpoint);
}

test "CoreMIDI input parsing fails closed and tracks topology" {
    TestApi.resetTestState();
    const TestBackend = Backend(TestApi);
    var backend = TestBackend{};
    try backend.open("Test client");
    defer backend.close();
    var devices: [3]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&devices);
    try backend.selectInput(devices[0].identifier);

    const Capture = struct {
        count: usize = 0,

        fn receive(
            context: *anyopaque,
            _: standalone.TimestampedMidi1Packet,
        ) void {
            const self: *@This() =
                @ptrCast(@alignCast(context));
            self.count += 1;
        }
    };
    var capture = Capture{};
    try backend.startInput(.{
        .context = &capture,
        .receive = Capture.receive,
    });
    TestApi.emit(24, &.{ 1, 0x90, 60 });
    TestApi.emit(24, &.{ 0xf0, 1, 2 });
    try std.testing.expectEqual(@as(usize, 0), capture.count);
    const statistics = backend.inputStatistics();
    try std.testing.expectEqual(@as(usize, 0), statistics.received);
    try std.testing.expectEqual(@as(usize, 3), statistics.malformed);

    try std.testing.expectEqual(
        @as(u64, 1),
        backend.currentTopologyGeneration(),
    );
    TestApi.notify();
    try std.testing.expectEqual(
        @as(u64, 2),
        backend.currentTopologyGeneration(),
    );

    TestApi.fail_disconnect = true;
    backend.stopInput();
    try std.testing.expectEqual(
        @as(usize, 1),
        backend.inputStatistics().disconnect_failures,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        (try backend.failureSource().snapshot()).midi_input,
    );
    try backend.resetInputStatistics();
    try std.testing.expectEqual(
        InputStatistics{
            .received = 0,
            .unsupported = 0,
            .malformed = 0,
            .disconnect_failures = 0,
        },
        backend.inputStatistics(),
    );
}

test "CoreMIDI callbacks reject misaligned context" {
    const TestBackend = Backend(TestApi);
    var storage: [@sizeOf(TestBackend) + 1]u8 align(@alignOf(TestBackend)) = undefined;
    const misaligned: *anyopaque = @ptrCast(&storage[1]);
    const bytes = [_]u8{ 0x90, 60, 100 };
    TestBackend.receiveBytes(
        misaligned,
        123,
        &bytes,
        bytes.len,
    );
    TestBackend.notifyTopologyChanged(misaligned);
}

test "native CoreMIDI client and ports open without device access" {
    if (builtin.os.tag != .macos) return;
    var backend = CoreMidiBackend{};
    backend.open("zig-vst3 CoreMIDI test") catch |err| switch (err) {
        error.CoreMidiClockFailure,
        error.CoreMidiClientCreateFailed,
        error.CoreMidiInputPortCreateFailed,
        error.CoreMidiOutputPortCreateFailed,
        => return error.SkipZigTest,
        else => return err,
    };
    defer backend.close();
    var second_backend = CoreMidiBackend{};
    second_backend.open("zig-vst3 CoreMIDI second test") catch |err| switch (err) {
        error.CoreMidiClockFailure,
        error.CoreMidiClientCreateFailed,
        error.CoreMidiInputPortCreateFailed,
        error.CoreMidiOutputPortCreateFailed,
        => return error.SkipZigTest,
        else => return err,
    };
    defer second_backend.close();
    try std.testing.expect(backend.isOpen());
    try std.testing.expect(second_backend.isOpen());
    try std.testing.expect(try backend.nowNanoseconds() > 0);

    var devices: [512]device_catalog.DeviceDescriptor = undefined;
    const count = try backend.enumerate(&devices);
    for (devices[0..count]) |descriptor|
        try std.testing.expect(descriptor.valid());
}
