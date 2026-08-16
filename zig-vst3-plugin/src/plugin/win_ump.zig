const builtin = @import("builtin");
const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const shared = @import("zig-vst3-native-ump");

pub const InputStatistics = shared.InputStatistics;
pub const OutputStatistics = shared.OutputStatistics;
pub const maximum_input_words_per_callback =
    shared.maximum_input_words_per_callback;

const ReceiveWords = *const fn (
    context: ?*anyopaque,
    timestamp_nanoseconds: u64,
    words: [*c]const u32,
    word_count: usize,
) callconv(.c) void;

const WinUmpContract = struct {
    pub const backend_already_open = error.WinUmpBackendAlreadyOpen;
    pub const backend_not_open = error.WinUmpBackendNotOpen;
    pub const clock_unavailable = error.WinUmpClockUnavailable;
    pub const device_name_too_long = error.WinUmpDeviceNameTooLong;
    pub const device_not_found = error.WinUmpDeviceNotFound;
    pub const device_storage_too_small =
        error.WinUmpDeviceStorageTooSmall;
    pub const empty_client_name = error.EmptyWinUmpClientName;
    pub const input_already_running = error.WinUmpInputAlreadyRunning;
    pub const input_not_selected = error.WinUmpInputNotSelected;
    pub const invalid_client_name = error.InvalidWinUmpClientName;
    pub const invalid_device_name = error.InvalidWinUmpDeviceName;
    pub const invalid_endpoint_identity =
        error.InvalidWinUmpEndpointIdentity;
    pub const library_unavailable = error.WinUmpRuntimeUnavailable;
    pub const open_name_storage_too_small =
        error.WinUmpEndpointIdStorageTooSmall;
    pub const output_not_selected = error.WinUmpOutputNotSelected;
    pub const topology_changed = error.WinUmpTopologyChanged;
    pub const input_identifier_prefix = "winump-input:";
    pub const output_identifier_prefix = "winump-output:";
};

const WinUmpSystemApi = struct {
    const c = @cImport({
        @cInclude("win_ump_shim.h");
    });

    pub const supported = builtin.os.tag == .windows;
    pub const maximum_identity_bytes = 1024;
    pub const maximum_open_name_bytes = 1024;
    pub const maximum_name_bytes = 1024;
    pub const Input = *c.zv3_win_ump_input;
    pub const Output = *c.zv3_win_ump_output;

    pub fn available() bool {
        return supported and c.zv3_win_ump_available() != 0;
    }

    pub fn acquire(client_name: []const u8) !void {
        if (!supported) return error.UnsupportedPlatform;
        if (c.zv3_win_ump_acquire(
            client_name.ptr,
            client_name.len,
        ) != 0)
            return error.WinUmpRuntimeUnavailable;
    }

    pub fn release() void {
        if (supported) c.zv3_win_ump_release();
    }

    pub fn refreshTopology() !void {
        if (!supported) return error.UnsupportedPlatform;
        if (c.zv3_win_ump_refresh_topology() != 0)
            return error.WinUmpDeviceQueryFailed;
    }

    pub fn nowNanoseconds() u64 {
        if (!supported) return 0;
        return c.zv3_win_ump_now_nanoseconds();
    }

    pub fn deviceCount(direction: anytype) !usize {
        if (!supported) return error.UnsupportedPlatform;
        var output: usize = 0;
        if (c.zv3_win_ump_device_count(
            @intFromEnum(direction),
            &output,
        ) != 0)
            return error.WinUmpDeviceQueryFailed;
        return output;
    }

    pub fn deviceIdentity(
        direction: anytype,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        return deviceText(
            direction,
            index,
            storage,
            c.zv3_win_ump_device_id,
        );
    }

    pub fn deviceOpenName(
        direction: anytype,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        return deviceIdentity(direction, index, storage);
    }

    pub fn deviceName(
        direction: anytype,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        return deviceText(
            direction,
            index,
            storage,
            c.zv3_win_ump_device_name,
        );
    }

    pub fn startInput(
        endpoint_id: []const u8,
        context: *anyopaque,
        receive: ReceiveWords,
    ) !Input {
        if (!supported) return error.UnsupportedPlatform;
        var output: ?Input = null;
        if (c.zv3_win_ump_start_input(
            endpoint_id.ptr,
            endpoint_id.len,
            context,
            receive,
            &output,
        ) != 0)
            return error.WinUmpInputStartFailed;
        return output orelse error.WinUmpInputStartFailed;
    }

    pub fn stopInput(input: Input) InputStatistics {
        if (!supported) return emptyInputStatistics();
        var native: c.zv3_win_ump_input_statistics = undefined;
        c.zv3_win_ump_stop_input(input, &native);
        return .{
            .received = 0,
            .malformed = 0,
            .read_failures = native.read_failures,
        };
    }

    pub fn inputStatistics(input: Input) InputStatistics {
        if (!supported) return emptyInputStatistics();
        var native: c.zv3_win_ump_input_statistics = undefined;
        c.zv3_win_ump_get_input_statistics(input, &native);
        return .{
            .received = 0,
            .malformed = 0,
            .read_failures = native.read_failures,
        };
    }

    pub fn openOutput(endpoint_id: []const u8) !Output {
        if (!supported) return error.UnsupportedPlatform;
        var output: ?Output = null;
        if (c.zv3_win_ump_open_output(
            endpoint_id.ptr,
            endpoint_id.len,
            &output,
        ) != 0)
            return error.WinUmpOutputOpenFailed;
        return output orelse error.WinUmpOutputOpenFailed;
    }

    pub fn closeOutput(output: Output) OutputStatistics {
        if (!supported) return emptyOutputStatistics();
        var native: c.zv3_win_ump_output_statistics = undefined;
        c.zv3_win_ump_close_output(output, &native);
        return outputStatisticsFromNative(native);
    }

    pub fn send(
        output: Output,
        timestamp_nanoseconds: u64,
        words: []const u32,
    ) !void {
        if (!supported) return error.UnsupportedPlatform;
        switch (c.zv3_win_ump_send(
            output,
            timestamp_nanoseconds,
            words.ptr,
            words.len,
        )) {
            0 => {},
            -4 => return error.WinUmpOutputQueueFull,
            else => return error.WinUmpSendFailed,
        }
    }

    pub fn outputStatistics(output: Output) OutputStatistics {
        if (!supported) return emptyOutputStatistics();
        var native: c.zv3_win_ump_output_statistics = undefined;
        c.zv3_win_ump_get_output_statistics(output, &native);
        return outputStatisticsFromNative(native);
    }

    fn deviceText(
        direction: anytype,
        index: usize,
        storage: []u8,
        function: anytype,
    ) ![]const u8 {
        if (!supported) return error.UnsupportedPlatform;
        var length: usize = 0;
        switch (function(
            @intFromEnum(direction),
            index,
            storage.ptr,
            storage.len,
            &length,
        )) {
            0 => {},
            -2 => return error.WinUmpEndpointStorageTooSmall,
            else => return error.WinUmpDeviceQueryFailed,
        }
        if (length == 0 or length > storage.len)
            return error.InvalidWinUmpEndpointData;
        return storage[0..length];
    }

    fn outputStatisticsFromNative(
        native: c.zv3_win_ump_output_statistics,
    ) OutputStatistics {
        return .{
            .queued = native.queued,
            .delivered = native.delivered,
            .late = native.late,
            .rejected = native.rejected,
            .canceled = native.canceled,
            .write_failures = native.write_failures,
        };
    }

    fn emptyInputStatistics() InputStatistics {
        return .{ .received = 0, .malformed = 0, .read_failures = 0 };
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
};

pub const WinUmpBackend = shared.BackendWithContract(
    WinUmpSystemApi,
    WinUmpContract,
);

const MockApi = struct {
    pub const supported = true;
    pub const maximum_identity_bytes = 64;
    pub const maximum_open_name_bytes = 64;
    pub const maximum_name_bytes = 64;
    pub const Input = u8;
    pub const Output = u8;

    var acquired = false;
    var released = false;
    var refresh_count: usize = 0;
    var receive_context: ?*anyopaque = null;
    var receive_function: ?ReceiveWords = null;
    var sent_timestamp: u64 = 0;
    var sent_words: [4]u32 = @splat(0);
    var sent_word_count: usize = 0;

    fn reset() void {
        acquired = false;
        released = false;
        refresh_count = 0;
        receive_context = null;
        receive_function = null;
        sent_timestamp = 0;
        sent_words = @splat(0);
        sent_word_count = 0;
    }

    pub fn available() bool {
        return true;
    }

    pub fn acquire(_: []const u8) !void {
        acquired = true;
    }

    pub fn release() void {
        released = true;
    }

    pub fn refreshTopology() !void {
        refresh_count += 1;
    }

    pub fn nowNanoseconds() u64 {
        return 1000;
    }

    pub fn deviceCount(_: anytype) !usize {
        return 1;
    }

    pub fn deviceIdentity(
        direction: anytype,
        _: usize,
        storage: []u8,
    ) ![]const u8 {
        return copyMock(
            if (@intFromEnum(direction) == 0)
                "endpoint-input"
            else
                "endpoint-output",
            storage,
        );
    }

    pub fn deviceOpenName(
        direction: anytype,
        index: usize,
        storage: []u8,
    ) ![]const u8 {
        return deviceIdentity(direction, index, storage);
    }

    pub fn deviceName(
        direction: anytype,
        _: usize,
        storage: []u8,
    ) ![]const u8 {
        return copyMock(
            if (@intFromEnum(direction) == 0)
                "Windows UMP Input"
            else
                "Windows UMP Output",
            storage,
        );
    }

    pub fn startInput(
        _: []const u8,
        context: *anyopaque,
        receive: ReceiveWords,
    ) !Input {
        receive_context = context;
        receive_function = receive;
        return 1;
    }

    pub fn stopInput(_: Input) InputStatistics {
        receive_context = null;
        receive_function = null;
        return .{ .received = 0, .malformed = 0, .read_failures = 0 };
    }

    pub fn inputStatistics(_: Input) InputStatistics {
        return .{ .received = 0, .malformed = 0, .read_failures = 0 };
    }

    pub fn openOutput(_: []const u8) !Output {
        return 2;
    }

    pub fn closeOutput(_: Output) OutputStatistics {
        return emptyMockOutputStatistics();
    }

    pub fn send(
        _: Output,
        timestamp_nanoseconds: u64,
        words: []const u32,
    ) !void {
        sent_timestamp = timestamp_nanoseconds;
        sent_word_count = words.len;
        @memcpy(sent_words[0..words.len], words);
    }

    pub fn outputStatistics(_: Output) OutputStatistics {
        return emptyMockOutputStatistics();
    }

    fn inject(words: []const u32, timestamp_nanoseconds: u64) !void {
        const receive = receive_function orelse
            return error.MockInputNotRunning;
        receive(
            receive_context,
            timestamp_nanoseconds,
            words.ptr,
            words.len,
        );
    }

    fn copyMock(value: []const u8, storage: []u8) ![]const u8 {
        if (storage.len < value.len) return error.MockStorageTooSmall;
        @memcpy(storage[0..value.len], value);
        return storage[0..value.len];
    }

    fn emptyMockOutputStatistics() OutputStatistics {
        return .{
            .queued = 0,
            .delivered = 0,
            .late = 0,
            .rejected = 0,
            .canceled = 0,
            .write_failures = 0,
        };
    }
};

test "Windows UMP contract acquires snapshots and routes complete packets" {
    MockApi.reset();
    const Backend = shared.BackendWithContract(
        MockApi,
        WinUmpContract,
    );
    var backend = Backend{};
    try backend.open("test");
    try std.testing.expect(MockApi.acquired);
    var descriptors: [2]core.plugin.DeviceDescriptor = undefined;
    try std.testing.expectEqual(
        @as(usize, 2),
        try backend.enumerate(&descriptors),
    );
    try std.testing.expect(std.mem.startsWith(
        u8,
        descriptors[0].identifier.slice(),
        WinUmpContract.input_identifier_prefix,
    ));
    try std.testing.expect(std.mem.startsWith(
        u8,
        descriptors[1].identifier.slice(),
        WinUmpContract.output_identifier_prefix,
    ));

    try backend.selectInput(descriptors[0].identifier);
    try backend.selectOutput(descriptors[1].identifier);
    var received: usize = 0;
    try backend.startInput(.{
        .context = &received,
        .receive = struct {
            fn receive(
                context: *anyopaque,
                _: core.plugin.TimestampedUmpPacket,
            ) void {
                const count: *usize = @ptrCast(@alignCast(context));
                count.* += 1;
            }
        }.receive,
    });
    try MockApi.inject(&.{ 0x50000000, 1 }, 2000);
    try MockApi.inject(&.{ 2, 3 }, 2000);
    try std.testing.expectEqual(@as(usize, 1), received);

    const packet = try core.process.UmpPacket.init(&.{
        0x50000000,
        4,
        5,
        6,
    });
    try backend.send(.{
        .timestamp_nanoseconds = 3000,
        .packet = packet,
    });
    try std.testing.expectEqual(@as(u64, 3000), MockApi.sent_timestamp);
    try std.testing.expectEqualSlices(
        u32,
        packet.words(),
        MockApi.sent_words[0..MockApi.sent_word_count],
    );
    backend.close();
    try std.testing.expect(MockApi.released);
    try std.testing.expect(MockApi.refresh_count >= 3);
}

test "Windows UMP unavailable backend rejects open off Windows" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var backend = WinUmpBackend{};
    try std.testing.expectError(
        error.UnsupportedPlatform,
        backend.open("test"),
    );
    try std.testing.expect(!backend.available());
}

test {
    std.testing.refAllDecls(WinUmpBackend);
}
