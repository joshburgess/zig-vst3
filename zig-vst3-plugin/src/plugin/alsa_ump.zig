const builtin = @import("builtin");
const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const native_callback_gate = @import("zig-vst3-native-callback-gate");
const device_catalog = core.plugin;
const process_api = core.process;
const standalone = core.plugin;

const ReceiveWords = *const fn (
    context: ?*anyopaque,
    timestamp_nanoseconds: u64,
    words: [*c]const u32,
    word_count: usize,
) callconv(.c) void;

pub const maximum_input_words_per_callback: usize = 64;

pub const InputStatistics = struct {
    received: usize,
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
    return BackendWithContract(Api, AlsaUmpContract);
}

pub fn BackendWithContract(
    comptime Api: type,
    comptime Contract: type,
) type {
    return struct {
        const Self = @This();

        opened: bool = false,
        selected_input: ?device_catalog.DeviceIdentifier = null,
        selected_output: ?device_catalog.DeviceIdentifier = null,
        input_session: ?Api.Input = null,
        output_session: ?Api.Output = null,
        input_callback: ?standalone.UmpInputCallback = null,
        input_running: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        input_callbacks: native_callback_gate.Gate = .{},
        topology_generation: u64 = 0,
        topology_fingerprint: u64 = 0,
        received_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        malformed_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        final_read_failures: u64 = 0,
        final_output_statistics: OutputStatistics =
            emptyOutputStatistics(),
        pending_words: [4]u32 = @splat(0),
        pending_count: u3 = 0,
        pending_required: u3 = 0,
        pending_timestamp: u64 = 0,

        /// Keep the backend at a stable address from `open` through `close`.
        pub fn open(self: *Self, client_name: []const u8) !void {
            if (self.opened) return Contract.backend_already_open;
            if (client_name.len == 0)
                return Contract.empty_client_name;
            if (!std.unicode.utf8ValidateSlice(client_name) or
                std.mem.indexOfScalar(u8, client_name, 0) != null)
                return Contract.invalid_client_name;
            try requireAvailable(Api, Contract);
            if (@hasDecl(Api, "acquire"))
                try Api.acquire(client_name);
            self.opened = true;
            _ = self.refreshTopology() catch |open_error| {
                self.opened = false;
                if (@hasDecl(Api, "release")) Api.release();
                return open_error;
            };
        }

        pub fn close(self: *Self) void {
            const was_open = self.opened;
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
            if (was_open and @hasDecl(Api, "release")) Api.release();
        }

        pub fn isOpen(self: *const Self) bool {
            return self.opened;
        }

        pub fn available(self: *const Self) bool {
            _ = self;
            return Api.supported and Api.available();
        }

        pub fn nowNanoseconds(self: *const Self) !u64 {
            if (!self.opened) return Contract.backend_not_open;
            const result = Api.nowNanoseconds();
            if (result == 0) return Contract.clock_unavailable;
            return result;
        }

        pub fn currentTopologyGeneration(self: *const Self) u64 {
            return self.topology_generation;
        }

        pub fn refreshTopology(self: *Self) !u64 {
            if (!self.opened) return Contract.backend_not_open;
            if (@hasDecl(Api, "refreshTopology"))
                try Api.refreshTopology();
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
            if (!self.opened) return Contract.backend_not_open;
            if (@hasDecl(Api, "refreshTopology"))
                try Api.refreshTopology();
            const initial_fingerprint = try topologyFingerprint(Api);
            var count: usize = 0;
            count = try enumerateDirection(
                Api,
                Contract,
                .input,
                output,
                count,
            );
            count = try enumerateDirection(
                Api,
                Contract,
                .output,
                output,
                count,
            );
            if (@hasDecl(Api, "refreshTopology"))
                try Api.refreshTopology();
            const final_fingerprint = try topologyFingerprint(Api);
            if (final_fingerprint != initial_fingerprint)
                return Contract.topology_changed;
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
            if (!self.opened) return Contract.backend_not_open;
            if (self.input_running.load(.acquire))
                return Contract.input_already_running;
            _ = try resolveIdentifier(
                Api,
                Contract,
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
            if (!self.opened) return Contract.backend_not_open;
            var storage: [Api.maximum_open_name_bytes]u8 = undefined;
            const length = try resolveIdentifier(
                Api,
                Contract,
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
                return Contract.input_already_running;
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
            callback: standalone.UmpInputCallback,
        ) !void {
            if (!self.opened) return Contract.backend_not_open;
            if (self.input_running.load(.acquire))
                return Contract.input_already_running;
            const identifier = self.selected_input orelse
                return Contract.input_not_selected;
            var storage: [Api.maximum_open_name_bytes]u8 = undefined;
            const length = try resolveIdentifier(
                Api,
                Contract,
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
                receiveWords,
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
            packet: standalone.TimestampedUmpPacket,
        ) !void {
            if (!self.opened) return Contract.backend_not_open;
            const session = self.output_session orelse
                return Contract.output_not_selected;
            if (!packet.valid() or packet.timestamp_nanoseconds == 0)
                return error.InvalidUmpPacket;
            try Api.send(
                session,
                packet.timestamp_nanoseconds,
                packet.packet.words(),
            );
        }

        pub fn inputDevice(self: *Self) standalone.UmpInputDevice {
            return .{
                .context = self,
                .start_input = startInputErased,
                .stop_input = stopInputErased,
            };
        }

        pub fn outputDevice(self: *Self) standalone.UmpOutputDevice {
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
                .malformed = self.malformed_count.load(.acquire),
                .read_failures = read_failures,
            };
        }

        pub fn outputStatistics(self: *const Self) OutputStatistics {
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

        pub fn resetInputStatistics(self: *Self) !void {
            if (self.input_running.load(.acquire))
                return Contract.input_already_running;
            self.received_count.store(0, .release);
            self.malformed_count.store(0, .release);
            self.final_read_failures = 0;
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

        fn startInputErased(
            context: *anyopaque,
            callback: standalone.UmpInputCallback,
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
            packet: standalone.TimestampedUmpPacket,
        ) !void {
            const self: *Self = @ptrCast(@alignCast(context));
            try self.send(packet);
        }

        fn resetParser(self: *Self) void {
            self.pending_count = 0;
            self.pending_required = 0;
            self.pending_timestamp = 0;
        }

        fn receiveWords(
            optional_context: ?*anyopaque,
            timestamp_nanoseconds: u64,
            words_pointer: [*c]const u32,
            word_count: usize,
        ) callconv(.c) void {
            const self = callbackContext(optional_context) orelse return;
            var admission = self.input_callbacks.admit() orelse return;
            defer admission.release();
            if (words_pointer == null or word_count == 0 or
                word_count > maximum_input_words_per_callback or
                timestamp_nanoseconds == 0)
            {
                incrementSaturating(&self.malformed_count);
                return;
            }
            for (words_pointer[0..word_count]) |word|
                self.consumeWord(word, timestamp_nanoseconds);
        }

        fn callbackContext(
            optional_context: ?*anyopaque,
        ) ?*Self {
            const context = optional_context orelse return null;
            if (@intFromPtr(context) % @alignOf(Self) != 0)
                return null;
            return @ptrCast(@alignCast(context));
        }

        fn consumeWord(
            self: *Self,
            word: u32,
            timestamp_nanoseconds: u64,
        ) void {
            if (self.pending_count == 0) {
                self.pending_required = wordCount(word);
                self.pending_timestamp = timestamp_nanoseconds;
            }
            if (self.pending_count >= self.pending_words.len or
                self.pending_required == 0)
            {
                incrementSaturating(&self.malformed_count);
                self.resetParser();
                return;
            }
            self.pending_words[self.pending_count] = word;
            self.pending_count += 1;
            if (self.pending_count != self.pending_required) return;
            const callback = self.input_callback orelse {
                self.resetParser();
                return;
            };
            const packet = process_api.UmpPacket.init(
                self.pending_words[0..self.pending_count],
            ) catch {
                incrementSaturating(&self.malformed_count);
                self.resetParser();
                return;
            };
            callback.receive(callback.context, .{
                .timestamp_nanoseconds = self.pending_timestamp,
                .packet = packet,
            });
            incrementSaturating(&self.received_count);
            self.resetParser();
        }
    };
}

pub const AlsaUmpBackend = Backend(AlsaUmpSystemApi);

const AlsaUmpContract = struct {
    const backend_already_open = error.AlsaUmpBackendAlreadyOpen;
    const backend_not_open = error.AlsaUmpBackendNotOpen;
    const clock_unavailable = error.AlsaUmpClockUnavailable;
    const device_name_too_long = error.AlsaUmpDeviceNameTooLong;
    const device_not_found = error.AlsaUmpDeviceNotFound;
    const device_storage_too_small = error.AlsaUmpDeviceStorageTooSmall;
    const empty_client_name = error.EmptyAlsaUmpClientName;
    const input_already_running = error.AlsaUmpInputAlreadyRunning;
    const input_not_selected = error.AlsaUmpInputNotSelected;
    const invalid_client_name = error.InvalidAlsaUmpClientName;
    const invalid_device_name = error.InvalidAlsaUmpDeviceName;
    const invalid_endpoint_identity =
        error.InvalidAlsaUmpEndpointIdentity;
    const library_unavailable = error.AlsaUmpLibraryUnavailable;
    const open_name_storage_too_small =
        error.AlsaUmpOpenNameStorageTooSmall;
    const output_not_selected = error.AlsaUmpOutputNotSelected;
    const topology_changed = error.AlsaUmpTopologyChanged;
    const input_identifier_prefix = "alsaump-input:";
    const output_identifier_prefix = "alsaump-output:";
};

const Direction = enum(u8) {
    input,
    output,
};

fn wordCount(word: u32) u3 {
    return switch (@as(u4, @truncate(word >> 28))) {
        0x0, 0x1, 0x2, 0x6, 0x7 => 1,
        0x3, 0x4, 0x8, 0x9, 0xa => 2,
        0xb, 0xc => 3,
        0x5, 0xd, 0xe, 0xf => 4,
    };
}

fn requireAvailable(comptime Api: type, comptime Contract: type) !void {
    if (!Api.supported) return error.UnsupportedPlatform;
    if (!Api.available()) return Contract.library_unavailable;
}

fn enumerateDirection(
    comptime Api: type,
    comptime Contract: type,
    direction: Direction,
    output: []device_catalog.DeviceDescriptor,
    initial_count: usize,
) !usize {
    var count = initial_count;
    var identity_storage: [Api.maximum_identity_bytes]u8 = undefined;
    var raw_name_storage: [Api.maximum_name_bytes]u8 = undefined;
    var name_storage: [device_catalog.maximum_device_name_bytes]u8 =
        undefined;
    const device_count = try Api.deviceCount(direction);
    for (0..device_count) |index| {
        if (count == output.len)
            return Contract.device_storage_too_small;
        const identity = try Api.deviceIdentity(
            direction,
            index,
            &identity_storage,
        );
        const identifier = try endpointIdentifier(
            Contract,
            direction,
            identity,
        );
        const raw_name = try Api.deviceName(
            direction,
            index,
            &raw_name_storage,
        );
        const name = try boundedDeviceName(
            Contract,
            raw_name,
            &name_storage,
        );
        output[count] = try device_catalog.DeviceDescriptor.init(
            if (direction == .input)
                .midi_input
            else
                .midi_output,
            identifier.slice(),
            name,
            0,
            0,
            index == 0,
        );
        count += 1;
    }
    return count;
}

fn boundedDeviceName(
    comptime Contract: type,
    raw: []const u8,
    storage: []u8,
) ![]const u8 {
    if (raw.len == 0 or !std.unicode.utf8ValidateSlice(raw) or
        std.mem.indexOfScalar(u8, raw, 0) != null)
        return Contract.invalid_device_name;
    var source_length = @min(raw.len, storage.len);
    while (source_length != 0 and
        !std.unicode.utf8ValidateSlice(raw[0..source_length]))
        source_length -= 1;
    if (source_length == 0) return Contract.device_name_too_long;
    for (raw[0..source_length], 0..) |byte, index| {
        storage[index] = if (byte == '\n' or byte == '\r')
            ' '
        else
            byte;
    }
    return std.mem.trim(u8, storage[0..source_length], " ");
}

fn endpointIdentifier(
    comptime Contract: type,
    direction: Direction,
    identity: []const u8,
) !device_catalog.DeviceIdentifier {
    if (identity.len == 0 or !std.unicode.utf8ValidateSlice(identity) or
        std.mem.indexOfScalar(u8, identity, 0) != null)
        return Contract.invalid_endpoint_identity;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(identity, &digest, .{});
    const prefix = if (direction == .input)
        Contract.input_identifier_prefix
    else
        Contract.output_identifier_prefix;
    var storage: [device_catalog.maximum_device_identifier_bytes]u8 =
        undefined;
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

fn resolveIdentifier(
    comptime Api: type,
    comptime Contract: type,
    direction: Direction,
    identifier: device_catalog.DeviceIdentifier,
    output: ?[]u8,
) !usize {
    if (!identifier.valid())
        return error.InvalidDeviceIdentifier;
    var identity_storage: [Api.maximum_identity_bytes]u8 = undefined;
    var open_name_storage: [Api.maximum_open_name_bytes]u8 = undefined;
    for (0..try Api.deviceCount(direction)) |index| {
        const identity = try Api.deviceIdentity(
            direction,
            index,
            &identity_storage,
        );
        const candidate = try endpointIdentifier(
            Contract,
            direction,
            identity,
        );
        if (!candidate.eql(&identifier)) continue;
        const open_name = try Api.deviceOpenName(
            direction,
            index,
            &open_name_storage,
        );
        if (output) |destination| {
            if (destination.len < open_name.len)
                return Contract.open_name_storage_too_small;
            @memcpy(destination[0..open_name.len], open_name);
        }
        return open_name.len;
    }
    return Contract.device_not_found;
}

fn topologyFingerprint(comptime Api: type) !u64 {
    var hasher = std.hash.Wyhash.init(0);
    inline for (.{ Direction.input, Direction.output }) |direction| {
        const count = try Api.deviceCount(direction);
        hasher.update(std.mem.asBytes(&count));
        var storage: [Api.maximum_identity_bytes]u8 = undefined;
        for (0..count) |index|
            hasher.update(try Api.deviceIdentity(
                direction,
                index,
                &storage,
            ));
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

const AlsaUmpSystemApi = if (builtin.os.tag == .linux)
    LinuxAlsaUmpApi
else
    UnsupportedAlsaUmpApi;

const UnsupportedAlsaUmpApi = struct {
    const supported = false;
    const maximum_identity_bytes = 1024;
    const maximum_open_name_bytes = 128;
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

    fn deviceIdentity(_: Direction, _: usize, _: []u8) ![]const u8 {
        return error.UnsupportedPlatform;
    }

    fn deviceOpenName(_: Direction, _: usize, _: []u8) ![]const u8 {
        return error.UnsupportedPlatform;
    }

    fn deviceName(_: Direction, _: usize, _: []u8) ![]const u8 {
        return error.UnsupportedPlatform;
    }

    fn startInput(_: []const u8, _: *anyopaque, _: ReceiveWords) !Input {
        return error.UnsupportedPlatform;
    }

    fn stopInput(_: Input) InputStatistics {
        return .{ .received = 0, .malformed = 0, .read_failures = 0 };
    }

    fn inputStatistics(input: Input) InputStatistics {
        return stopInput(input);
    }

    fn openOutput(_: []const u8) !Output {
        return error.UnsupportedPlatform;
    }

    fn closeOutput(_: Output) OutputStatistics {
        return emptyOutputStatistics();
    }

    fn send(_: Output, _: u64, _: []const u32) !void {
        return error.UnsupportedPlatform;
    }

    fn outputStatistics(_: Output) OutputStatistics {
        return emptyOutputStatistics();
    }
};

const LinuxAlsaUmpApi = if (builtin.os.tag == .linux) struct {
    const c = @cImport({
        @cInclude("alsa_ump_shim.h");
    });
    const supported = true;
    const maximum_identity_bytes = 1024;
    const maximum_open_name_bytes = 128;
    const maximum_name_bytes = 1024;
    const Input = *c.zv3_alsa_ump_input;
    const Output = *c.zv3_alsa_ump_output;

    fn available() bool {
        return c.zv3_alsa_ump_available() != 0;
    }

    fn nowNanoseconds() u64 {
        return c.zv3_alsa_ump_now_nanoseconds();
    }

    fn deviceCount(direction: Direction) !usize {
        var result: usize = 0;
        if (c.zv3_alsa_ump_device_count(
            @intFromEnum(direction),
            &result,
        ) != 0)
            return error.AlsaUmpDeviceQueryFailed;
        return result;
    }

    fn deviceIdentity(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        return queryText(
            c.zv3_alsa_ump_device_identity,
            direction,
            index,
            storage,
            error.InvalidAlsaUmpEndpointIdentity,
        );
    }

    fn deviceOpenName(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        return queryText(
            c.zv3_alsa_ump_device_open_name,
            direction,
            index,
            storage,
            error.InvalidAlsaUmpOpenName,
        );
    }

    fn deviceName(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        return queryText(
            c.zv3_alsa_ump_device_name,
            direction,
            index,
            storage,
            error.InvalidAlsaUmpDeviceName,
        );
    }

    fn startInput(
        open_name: []const u8,
        context: *anyopaque,
        receive: ReceiveWords,
    ) !Input {
        var input: ?Input = null;
        if (c.zv3_alsa_ump_start_input(
            open_name.ptr,
            open_name.len,
            context,
            receive,
            &input,
        ) != 0)
            return error.AlsaUmpInputStartFailed;
        return input orelse error.AlsaUmpInputStartFailed;
    }

    fn stopInput(input: Input) InputStatistics {
        var result: c.zv3_alsa_ump_input_statistics = undefined;
        c.zv3_alsa_ump_stop_input(input, &result);
        return .{
            .received = 0,
            .malformed = 0,
            .read_failures = result.read_failures,
        };
    }

    fn inputStatistics(input: Input) InputStatistics {
        var result: c.zv3_alsa_ump_input_statistics = undefined;
        c.zv3_alsa_ump_get_input_statistics(input, &result);
        return .{
            .received = 0,
            .malformed = 0,
            .read_failures = result.read_failures,
        };
    }

    fn openOutput(open_name: []const u8) !Output {
        var output: ?Output = null;
        if (c.zv3_alsa_ump_open_output(
            open_name.ptr,
            open_name.len,
            &output,
        ) != 0)
            return error.AlsaUmpOutputOpenFailed;
        return output orelse error.AlsaUmpOutputOpenFailed;
    }

    fn closeOutput(output: Output) OutputStatistics {
        var result: c.zv3_alsa_ump_output_statistics = undefined;
        c.zv3_alsa_ump_close_output(output, &result);
        return outputStatisticsValue(result);
    }

    fn send(
        output: Output,
        timestamp_nanoseconds: u64,
        words: []const u32,
    ) !void {
        const result = c.zv3_alsa_ump_send(
            output,
            timestamp_nanoseconds,
            words.ptr,
            words.len,
        );
        if (result == -2) return error.AlsaUmpOutputQueueFull;
        if (result != 0) return error.AlsaUmpSendFailed;
    }

    fn outputStatistics(output: Output) OutputStatistics {
        var result: c.zv3_alsa_ump_output_statistics = undefined;
        c.zv3_alsa_ump_get_output_statistics(output, &result);
        return outputStatisticsValue(result);
    }

    fn queryText(
        callback: anytype,
        direction: Direction,
        index: usize,
        storage: []u8,
        failure: anyerror,
    ) ![]const u8 {
        var length: usize = 0;
        if (callback(
            @intFromEnum(direction),
            index,
            storage.ptr,
            storage.len,
            &length,
        ) != 0 or length == 0 or length > storage.len)
            return failure;
        return storage[0..length];
    }

    fn outputStatisticsValue(
        result: c.zv3_alsa_ump_output_statistics,
    ) OutputStatistics {
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

test "unsupported ALSA UMP backend fails explicitly" {
    if (builtin.os.tag == .linux) return error.SkipZigTest;
    var backend = AlsaUmpBackend{};
    try std.testing.expect(!backend.available());
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.open("test"),
    );
}

test "native ALSA UMP loader can build a discovery snapshot" {
    if (builtin.os.tag != .linux) return;
    var backend = AlsaUmpBackend{};
    if (!backend.available()) return;
    try backend.open("zig-vst3 ALSA UMP test");
    defer backend.close();
    var descriptors: [256]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
}

const MockApi = struct {
    const supported = true;
    const maximum_identity_bytes = 64;
    const maximum_open_name_bytes = 32;
    const maximum_name_bytes = 128;
    const Input = u32;
    const Output = u32;
    const input_identities = [_][]const u8{
        "card-a:0:input-a",
        "card-b:0:input-b",
    };
    const output_identities = [_][]const u8{
        "card-a:0:output-a",
        "card-c:0:output-c",
    };
    const input_open_names = [_][]const u8{ "hw:A,0", "hw:B,0" };
    const output_open_names = [_][]const u8{ "hw:A,0", "hw:C,0" };
    var receive_context: ?*anyopaque = null;
    var receive_function: ?ReceiveWords = null;
    var fail_input = false;
    var fail_output = false;
    var fail_device_count = false;
    var reject_output = false;
    var output_close_count: usize = 0;
    var sent_words: [4]u32 = @splat(0);
    var sent_word_count: usize = 0;
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
        sent_word_count = 0;
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

    fn values(
        direction: Direction,
        input: []const []const u8,
        output: []const []const u8,
    ) []const []const u8 {
        return if (direction == .input) input else output;
    }

    fn identities(direction: Direction) []const []const u8 {
        return values(
            direction,
            &input_identities,
            &output_identities,
        );
    }

    fn openNames(direction: Direction) []const []const u8 {
        return values(
            direction,
            &input_open_names,
            &output_open_names,
        );
    }

    fn deviceCount(direction: Direction) !usize {
        if (fail_device_count)
            return error.MockDeviceQueryFailed;
        return identities(direction).len;
    }

    fn copyValue(
        value: []const u8,
        storage: []u8,
    ) ![]const u8 {
        if (value.len > storage.len)
            return error.MockStorageTooSmall;
        @memcpy(storage[0..value.len], value);
        return storage[0..value.len];
    }

    fn deviceIdentity(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        const value = identities(direction)[index];
        const result = try copyValue(value, storage);
        if (index == 1)
            storage[result.len - 1] = topology_suffix;
        return result;
    }

    fn deviceOpenName(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        return copyValue(openNames(direction)[index], storage);
    }

    fn deviceName(
        direction: Direction,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        const names = if (direction == .input)
            [_][]const u8{ "UMP Source A", "UMP\nSource B" }
        else
            [_][]const u8{ "UMP Destination A", "UMP Destination C" };
        return copyValue(names[index], storage);
    }

    fn startInput(
        _: []const u8,
        context: *anyopaque,
        receive: ReceiveWords,
    ) !Input {
        if (fail_input) return error.MockInputFailed;
        receive_context = context;
        receive_function = receive;
        return 11;
    }

    fn stopInput(_: Input) InputStatistics {
        receive_context = null;
        receive_function = null;
        return .{ .received = 0, .malformed = 0, .read_failures = 2 };
    }

    fn inputStatistics(_: Input) InputStatistics {
        return .{ .received = 0, .malformed = 0, .read_failures = 1 };
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
        words: []const u32,
    ) !void {
        if (reject_output) {
            output_statistics.rejected += 1;
            return error.AlsaUmpOutputQueueFull;
        }
        @memcpy(sent_words[0..words.len], words);
        sent_word_count = words.len;
        sent_timestamp = timestamp_nanoseconds;
        output_statistics.queued += 1;
        output_statistics.delivered += 1;
        if (timestamp_nanoseconds < now)
            output_statistics.late += 1;
    }

    fn outputStatistics(_: Output) OutputStatistics {
        return output_statistics;
    }

    fn inject(words: []const u32, timestamp: u64) !void {
        const callback = receive_function orelse
            return error.MissingAlsaUmpCallback;
        callback(
            receive_context,
            timestamp,
            words.ptr,
            words.len,
        );
    }
};

test "ALSA UMP discovery publishes directional stable defaults" {
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
    try std.testing.expect(descriptors[0].is_default);
    try std.testing.expect(descriptors[2].is_default);
    try std.testing.expectEqualStrings(
        "UMP Source B",
        descriptors[1].name(),
    );
    try backend.selectInput(descriptors[0].identifier);
    try backend.selectOutput(descriptors[3].identifier);
    try std.testing.expect(!(try backend.pollTopology()));
    MockApi.topology_suffix = 'z';
    try std.testing.expect(try backend.pollTopology());
}

test "ALSA UMP input preserves all packet widths across fragments" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    const Probe = struct {
        packets: [4]standalone.TimestampedUmpPacket = undefined,
        count: usize = 0,

        fn receive(
            context: *anyopaque,
            packet: standalone.TimestampedUmpPacket,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.packets[self.count] = packet;
            self.count += 1;
        }
    };
    const words32 = [_]u32{0x20903c64};
    const words64 = [_]u32{ 0x40903c00, 0x80000000 };
    const words96 = [_]u32{ 0xb0000000, 0x11223344, 0x55667788 };
    const words128 = [_]u32{
        0x50000000,
        0x01020304,
        0x05060708,
        0x090a0b0c,
    };
    var backend = TestBackend{};
    try backend.open("test");
    defer backend.close();
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
    try backend.selectInput(descriptors[0].identifier);
    var probe = Probe{};
    var input = backend.inputDevice();
    try input.start(.{
        .context = &probe,
        .receive = Probe.receive,
    });
    try MockApi.inject(&.{ words32[0], words64[0] }, 100);
    try MockApi.inject(&.{
        words64[1],
        words96[0],
        words96[1],
    }, 200);
    try MockApi.inject(&.{
        words96[2],
        words128[0],
        words128[1],
        words128[2],
        words128[3],
    }, 300);
    try std.testing.expectEqual(@as(usize, 4), probe.count);
    try std.testing.expectEqual(@as(u64, 100), probe.packets[0].timestamp_nanoseconds);
    try std.testing.expectEqual(@as(u64, 100), probe.packets[1].timestamp_nanoseconds);
    try std.testing.expectEqual(@as(u64, 200), probe.packets[2].timestamp_nanoseconds);
    try std.testing.expectEqual(@as(u64, 300), probe.packets[3].timestamp_nanoseconds);
    try std.testing.expectEqualSlices(
        u32,
        &words128,
        probe.packets[3].packet.words(),
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        backend.inputStatistics().received,
    );
    input.stop();
    try std.testing.expectEqual(
        @as(u64, 2),
        backend.inputStatistics().read_failures,
    );
}

test "ALSA UMP input stop drains an admitted callback" {
    const synchronization = struct {
        var started = std.atomic.Value(bool).init(false);
        var release = std.atomic.Value(bool).init(false);
        var emit_failed = std.atomic.Value(bool).init(false);

        fn receive(
            _: *anyopaque,
            _: standalone.TimestampedUmpPacket,
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
            MockApi.inject(&.{0x20903c64}, 100) catch {
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

test "ALSA UMP input contains invalid callback boundaries" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = TestBackend{};
    try backend.open("test");
    defer backend.close();
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
    try backend.selectInput(descriptors[0].identifier);
    var received: usize = 0;
    try backend.startInput(.{
        .context = &received,
        .receive = struct {
            fn receive(
                context: *anyopaque,
                _: standalone.TimestampedUmpPacket,
            ) void {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 1;
            }
        }.receive,
    });
    try MockApi.inject(&.{0x20903c64}, 0);
    try MockApi.inject(&.{}, 100);
    try std.testing.expectEqual(
        @as(usize, 2),
        backend.inputStatistics().malformed,
    );

    const exact = [_]u32{0x20903c64} **
        maximum_input_words_per_callback;
    try MockApi.inject(&exact, 200);
    const one = [_]u32{0x20903c64};
    TestBackend.receiveWords(
        &backend,
        300,
        &one,
        maximum_input_words_per_callback + 1,
    );
    try std.testing.expectEqual(
        maximum_input_words_per_callback,
        received,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        backend.inputStatistics().malformed,
    );
}

test "ALSA UMP output preserves complete packets and selection rollback" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = TestBackend{};
    try backend.open("test");
    defer backend.close();
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
    try backend.selectOutput(descriptors[2].identifier);
    const packet = try process_api.UmpPacket.init(&.{
        0x50000000,
        0x01020304,
        0x05060708,
        0x090a0b0c,
    });
    var output = backend.outputDevice();
    try output.send(.{
        .timestamp_nanoseconds = MockApi.now + 1,
        .packet = packet,
    });
    try std.testing.expectEqualSlices(
        u32,
        packet.words(),
        MockApi.sent_words[0..MockApi.sent_word_count],
    );
    try std.testing.expectEqual(MockApi.now + 1, MockApi.sent_timestamp);
    MockApi.reject_output = true;
    try std.testing.expectError(
        error.AlsaUmpOutputQueueFull,
        output.send(.{
            .timestamp_nanoseconds = MockApi.now + 2,
            .packet = packet,
        }),
    );
    MockApi.reject_output = false;
    try std.testing.expectError(
        error.InvalidUmpPacket,
        output.send(.{
            .timestamp_nanoseconds = 0,
            .packet = packet,
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
        @as(u64, 2),
        backend.outputStatistics().canceled,
    );
    try std.testing.expectEqual(@as(usize, 1), MockApi.output_close_count);
}

test "ALSA UMP failed input start remains retryable" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = TestBackend{};
    try backend.open("test");
    defer backend.close();
    var descriptors: [4]device_catalog.DeviceDescriptor = undefined;
    _ = try backend.enumerate(&descriptors);
    try backend.selectInput(descriptors[0].identifier);
    var context: u8 = 0;
    const callback = standalone.UmpInputCallback{
        .context = &context,
        .receive = struct {
            fn receive(
                _: *anyopaque,
                _: standalone.TimestampedUmpPacket,
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

test "ALSA UMP failed open restores the closed state" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = TestBackend{};
    MockApi.fail_device_count = true;
    try std.testing.expectError(
        error.MockDeviceQueryFailed,
        backend.open("test"),
    );
    try std.testing.expect(!backend.isOpen());
    MockApi.fail_device_count = false;
    try backend.open("test");
    defer backend.close();
    try std.testing.expect(backend.isOpen());
}
