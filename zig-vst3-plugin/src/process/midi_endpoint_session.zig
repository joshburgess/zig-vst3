const std = @import("std");
const stream = @import("midi_stream.zig");
const stream_text = @import("midi_stream_text.zig");
const ump = @import("midi_ump.zig");

pub const EndpointFilter = struct {
    endpoint_info: bool = false,
    device_identity: bool = false,
    endpoint_name: bool = false,
    product_instance_id: bool = false,
    stream_configuration: bool = false,

    pub fn all() EndpointFilter {
        return .{
            .endpoint_info = true,
            .device_identity = true,
            .endpoint_name = true,
            .product_instance_id = true,
            .stream_configuration = true,
        };
    }

    pub fn bits(self: EndpointFilter) u5 {
        return @as(u5, @intFromBool(self.endpoint_info)) |
            (@as(u5, @intFromBool(self.device_identity)) << 1) |
            (@as(u5, @intFromBool(self.endpoint_name)) << 2) |
            (@as(u5, @intFromBool(self.product_instance_id)) << 3) |
            (@as(u5, @intFromBool(self.stream_configuration)) << 4);
    }
};

pub const FunctionBlockFilter = struct {
    info: bool = false,
    name: bool = false,

    pub fn all() FunctionBlockFilter {
        return .{ .info = true, .name = true };
    }

    pub fn bits(self: FunctionBlockFilter) u2 {
        return @as(u2, @intFromBool(self.info)) |
            (@as(u2, @intFromBool(self.name)) << 1);
    }
};

pub const Requester = struct {
    endpoint_info: ?stream.EndpointInfo = null,
    device_identity: ?stream.DeviceIdentity = null,
    configuration: ?stream.StreamConfiguration = null,
    requested_configuration: ?stream.StreamConfiguration = null,
    function_blocks: [32]?stream.FunctionBlockInfo = .{null} ** 32,
    pending_endpoint: u5 = 0,
    pending_function_info: u32 = 0,
    pending_function_names: u32 = 0,
    function_name_fingerprints: [32]?u64 = .{null} ** 32,

    pub fn endpointDiscovery(
        self: *Requester,
        version_major: u8,
        version_minor: u8,
        filter: EndpointFilter,
    ) !ump.Packet {
        const bits = filter.bits();
        if (bits == 0) return error.EmptyEndpointDiscovery;
        if ((self.pending_endpoint & bits) != 0)
            return error.EndpointDiscoveryAlreadyPending;
        const packet = try (stream.Message{ .payload = .{ .endpoint_discovery = .{
            .version_major = version_major,
            .version_minor = version_minor,
            .filter = bits,
        } } }).packet();
        self.pending_endpoint |= bits;
        return packet;
    }

    pub fn configurationRequest(
        self: *Requester,
        desired: stream.StreamConfiguration,
    ) !ump.Packet {
        if (self.requested_configuration != null)
            return error.StreamConfigurationAlreadyPending;
        try self.validateConfiguration(desired);
        const packet = try (stream.Message{ .payload = .{
            .stream_configuration_request = desired,
        } }).packet();
        self.requested_configuration = desired;
        return packet;
    }

    pub fn functionBlockDiscovery(
        self: *Requester,
        selector: stream.FunctionBlockSelector,
        filter: FunctionBlockFilter,
    ) !ump.Packet {
        const filter_bits = filter.bits();
        if (filter_bits == 0) return error.EmptyFunctionBlockDiscovery;
        const target_mask = try self.targetMask(selector);
        if ((filter.info and (self.pending_function_info & target_mask) != 0) or
            (filter.name and (self.pending_function_names & target_mask) != 0))
            return error.FunctionBlockDiscoveryAlreadyPending;
        const packet = try (stream.Message{ .payload = .{ .function_block_discovery = .{
            .selector = selector,
            .filter = filter_bits,
        } } }).packet();
        if (filter.info) self.pending_function_info |= target_mask;
        if (filter.name) self.pending_function_names |= target_mask;
        return packet;
    }

    pub fn acceptPacket(self: *Requester, packet: ump.Packet) !void {
        try self.accept(try stream.Message.parse(packet));
    }

    pub fn accept(self: *Requester, message: stream.Message) !void {
        switch (message.payload) {
            .endpoint_info => |value| try self.acceptEndpointInfo(value),
            .device_identity => |value| {
                self.device_identity = value;
                self.pending_endpoint &= ~@as(u5, 1 << 1);
            },
            .stream_configuration_notification => |value| {
                if (self.endpoint_info != null) try self.validateConfiguration(value);
                self.configuration = value;
                self.requested_configuration = null;
                self.pending_endpoint &= ~@as(u5, 1 << 4);
            },
            .function_block_info => |value| try self.acceptFunctionBlock(value),
            .endpoint_discovery,
            .stream_configuration_request,
            .function_block_discovery,
            .start_of_clip,
            .end_of_clip,
            => return error.UnexpectedRequesterMessage,
        }
    }

    pub fn acceptText(
        self: *Requester,
        kind: stream_text.Kind,
        block: ?u5,
        value: []const u8,
    ) !void {
        _ = try stream_text.Packetizer.init(kind, block, value);
        switch (kind) {
            .endpoint_name => self.pending_endpoint &= ~@as(u5, 1 << 2),
            .product_instance_id => self.pending_endpoint &= ~@as(u5, 1 << 3),
            .function_block_name => {
                const index = block orelse return error.MissingStreamTextBlock;
                const endpoint = self.endpoint_info orelse
                    return error.EndpointInfoRequired;
                if (index >= endpoint.function_block_count)
                    return error.FunctionBlockOutOfRange;
                const fingerprint = std.hash.Wyhash.hash(0, value);
                if (endpoint.static_function_blocks) {
                    if (self.function_name_fingerprints[index]) |previous| {
                        if (previous != fingerprint)
                            return error.StaticFunctionBlockChanged;
                    }
                }
                self.function_name_fingerprints[index] = fingerprint;
                self.pending_function_names &= ~blockBit(index);
            },
        }
    }

    pub fn endpointDiscoveryComplete(self: *const Requester) bool {
        return self.pending_endpoint == 0;
    }

    pub fn functionBlockDiscoveryComplete(self: *const Requester) bool {
        return self.pending_function_info == 0 and self.pending_function_names == 0;
    }

    pub fn valid(self: *const Requester) bool {
        const endpoint = self.endpoint_info orelse {
            if (self.requested_configuration != null) return false;
            if (self.pending_function_info != 0 or self.pending_function_names != 0)
                return false;
            for (self.function_blocks) |value| if (value != null) return false;
            for (self.function_name_fingerprints) |value| if (value != null) return false;
            return true;
        };
        if (!endpoint.valid()) return false;
        if (self.configuration) |value| self.validateConfiguration(value) catch return false;
        if (self.requested_configuration) |value|
            self.validateConfiguration(value) catch return false;
        const declared = blockMask(endpoint.function_block_count);
        if ((self.pending_function_info & ~declared) != 0 or
            (self.pending_function_names & ~declared) != 0)
            return false;
        for (self.function_blocks, 0..) |value, index| {
            if (index >= endpoint.function_block_count and value != null) return false;
            if (value) |info| {
                if (info.block != index or !info.valid()) return false;
                if (endpoint.static_function_blocks and !info.enabled) return false;
            }
        }
        for (self.function_name_fingerprints, 0..) |value, index| {
            if (index >= endpoint.function_block_count and value != null) return false;
        }
        return true;
    }

    fn acceptEndpointInfo(self: *Requester, value: stream.EndpointInfo) !void {
        if (!value.valid()) return error.InvalidEndpointInfo;
        if (self.endpoint_info) |previous| {
            if (previous.function_block_count != value.function_block_count)
                return error.FunctionBlockCountChanged;
        }
        if (self.configuration) |configuration|
            try configurationSupported(value, configuration);
        if (self.requested_configuration) |configuration|
            try configurationSupported(value, configuration);
        if (value.static_function_blocks) {
            for (self.function_blocks[0..value.function_block_count]) |block| {
                if (block) |info| {
                    if (!info.enabled) return error.StaticFunctionBlockInactive;
                }
            }
        }
        self.endpoint_info = value;
        self.pending_endpoint &= ~@as(u5, 1);
    }

    fn acceptFunctionBlock(
        self: *Requester,
        value: stream.FunctionBlockInfo,
    ) !void {
        if (!value.valid()) return error.InvalidFunctionBlockInfo;
        const endpoint = self.endpoint_info orelse return error.EndpointInfoRequired;
        if (value.block >= endpoint.function_block_count)
            return error.FunctionBlockOutOfRange;
        if (endpoint.static_function_blocks and !value.enabled)
            return error.StaticFunctionBlockInactive;
        if (endpoint.static_function_blocks) {
            if (self.function_blocks[value.block]) |previous| {
                if (!std.meta.eql(previous, value))
                    return error.StaticFunctionBlockChanged;
            }
        }
        self.function_blocks[value.block] = value;
        self.pending_function_info &= ~blockBit(value.block);
    }

    fn validateConfiguration(
        self: *const Requester,
        value: stream.StreamConfiguration,
    ) !void {
        const endpoint = self.endpoint_info orelse return error.EndpointInfoRequired;
        try configurationSupported(endpoint, value);
    }

    fn targetMask(
        self: *const Requester,
        selector: stream.FunctionBlockSelector,
    ) !u32 {
        const endpoint = self.endpoint_info orelse return error.EndpointInfoRequired;
        return switch (selector) {
            .one => |block| if (block < endpoint.function_block_count)
                blockBit(block)
            else
                error.FunctionBlockOutOfRange,
            .all => blockMask(endpoint.function_block_count),
        };
    }
};

pub const FunctionBlockDescriptor = struct {
    info: stream.FunctionBlockInfo,
    name: []const u8,
};

pub const Descriptor = struct {
    info: stream.EndpointInfo,
    identity: stream.DeviceIdentity,
    name: []const u8,
    product_instance_id: []const u8,
    configuration: stream.StreamConfiguration,
    function_blocks: []const FunctionBlockDescriptor,

    pub fn valid(self: Descriptor) bool {
        if (!self.info.valid() or self.function_blocks.len > 32) return false;
        if (self.function_blocks.len != self.info.function_block_count) return false;
        configurationSupported(self.info, self.configuration) catch return false;
        _ = stream_text.Packetizer.init(.endpoint_name, null, self.name) catch return false;
        _ = stream_text.Packetizer.init(
            .product_instance_id,
            null,
            self.product_instance_id,
        ) catch return false;
        for (self.function_blocks, 0..) |block, index| {
            if (!block.info.valid() or block.info.block != index) return false;
            if (self.info.static_function_blocks and !block.info.enabled) return false;
            _ = stream_text.Packetizer.init(
                .function_block_name,
                block.info.block,
                block.name,
            ) catch return false;
        }
        return true;
    }
};

pub const Responder = struct {
    descriptor: Descriptor,
    configuration: stream.StreamConfiguration,

    pub fn init(descriptor: Descriptor) !Responder {
        if (!descriptor.valid()) return error.InvalidEndpointDescriptor;
        return .{
            .descriptor = descriptor,
            .configuration = descriptor.configuration,
        };
    }

    pub fn valid(self: *const Responder) bool {
        if (!self.descriptor.valid()) return false;
        configurationSupported(self.descriptor.info, self.configuration) catch return false;
        return true;
    }

    pub fn handlePacket(self: *Responder, packet: ump.Packet) !Replies {
        return self.handle(try stream.Message.parse(packet));
    }

    pub fn handle(self: *Responder, message: stream.Message) !Replies {
        if (!self.valid()) return error.InvalidEndpointResponderState;
        return switch (message.payload) {
            .endpoint_discovery => |request| Replies.endpoint(
                self.descriptor,
                self.configuration,
                request.filter,
            ),
            .stream_configuration_request => |request| blk: {
                var accepted = true;
                configurationSupported(self.descriptor.info, request) catch {
                    accepted = false;
                };
                const selected = if (accepted) request else self.configuration;
                const packet = try (stream.Message{ .payload = .{
                    .stream_configuration_notification = selected,
                } }).packet();
                if (accepted) self.configuration = request;
                break :blk Replies.fixed(packet);
            },
            .function_block_discovery => |request| try Replies.functionBlocks(
                self.descriptor,
                request.selector,
                request.filter,
            ),
            .endpoint_info,
            .device_identity,
            .stream_configuration_notification,
            .function_block_info,
            .start_of_clip,
            .end_of_clip,
            => error.UnexpectedResponderMessage,
        };
    }
};

pub const Replies = struct {
    const Mode = union(enum) {
        empty,
        fixed: ump.Packet,
        endpoint: EndpointState,
        function_blocks: FunctionBlockState,
    };

    const EndpointState = struct {
        descriptor: Descriptor,
        configuration: stream.StreamConfiguration,
        filter: u5,
        cursor: u3 = 0,
    };

    const FunctionBlockStage = enum {
        info,
        name,
        advance,
    };

    const FunctionBlockState = struct {
        descriptor: Descriptor,
        filter: u2,
        cursor: u6,
        end: u6,
        stage: FunctionBlockStage = .info,
    };

    mode: Mode = .empty,
    text: ?stream_text.Packetizer = null,

    fn fixed(packet: ump.Packet) Replies {
        return .{ .mode = .{ .fixed = packet } };
    }

    fn endpoint(
        descriptor: Descriptor,
        configuration: stream.StreamConfiguration,
        filter: u5,
    ) Replies {
        return .{ .mode = .{ .endpoint = .{
            .descriptor = descriptor,
            .configuration = configuration,
            .filter = filter,
        } } };
    }

    fn functionBlocks(
        descriptor: Descriptor,
        selector: stream.FunctionBlockSelector,
        filter: u2,
    ) !Replies {
        const range: struct { start: u6, end: u6 } = switch (selector) {
            .one => |block| blk: {
                if (block >= descriptor.info.function_block_count)
                    return error.FunctionBlockOutOfRange;
                break :blk .{
                    .start = block,
                    .end = @as(u6, block) + 1,
                };
            },
            .all => .{
                .start = 0,
                .end = descriptor.info.function_block_count,
            },
        };
        return .{ .mode = .{ .function_blocks = .{
            .descriptor = descriptor,
            .filter = filter,
            .cursor = range.start,
            .end = range.end,
        } } };
    }

    pub fn next(self: *Replies) !?ump.Packet {
        var trial = self.*;
        const packet = try trial.nextInPlace();
        self.* = trial;
        return packet;
    }

    pub fn valid(self: *const Replies) bool {
        self.validateState() catch return false;
        return true;
    }

    fn nextInPlace(self: *Replies) !?ump.Packet {
        try self.validateState();
        while (true) {
            if (self.text) |*packetizer| {
                if (try packetizer.next()) |packet| return packet;
                self.text = null;
            }
            switch (self.mode) {
                .empty => return null,
                .fixed => |packet| {
                    self.mode = .empty;
                    return packet;
                },
                .endpoint => {
                    const state = &self.mode.endpoint;
                    if (!state.descriptor.valid() or state.cursor > 5)
                        return error.InvalidEndpointRepliesState;
                    if (state.cursor == 5) {
                        self.mode = .empty;
                        continue;
                    }
                    const field = state.cursor;
                    state.cursor += 1;
                    if ((state.filter & (@as(u5, 1) << field)) == 0) continue;
                    switch (field) {
                        0 => return try (stream.Message{ .payload = .{
                            .endpoint_info = state.descriptor.info,
                        } }).packet(),
                        1 => return try (stream.Message{ .payload = .{
                            .device_identity = state.descriptor.identity,
                        } }).packet(),
                        2 => self.text = try stream_text.Packetizer.init(
                            .endpoint_name,
                            null,
                            state.descriptor.name,
                        ),
                        3 => self.text = try stream_text.Packetizer.init(
                            .product_instance_id,
                            null,
                            state.descriptor.product_instance_id,
                        ),
                        4 => return try (stream.Message{ .payload = .{
                            .stream_configuration_notification = state.configuration,
                        } }).packet(),
                        else => return error.InvalidEndpointRepliesState,
                    }
                },
                .function_blocks => {
                    const state = &self.mode.function_blocks;
                    if (!state.descriptor.valid() or
                        state.end > state.descriptor.function_blocks.len or
                        state.cursor > state.end)
                        return error.InvalidEndpointRepliesState;
                    if (state.cursor == state.end) {
                        self.mode = .empty;
                        continue;
                    }
                    const block = state.descriptor.function_blocks[state.cursor];
                    switch (state.stage) {
                        .info => {
                            state.stage = .name;
                            if ((state.filter & 1) != 0) {
                                return try (stream.Message{ .payload = .{
                                    .function_block_info = block.info,
                                } }).packet();
                            }
                        },
                        .name => {
                            state.stage = .advance;
                            if ((state.filter & 2) != 0) {
                                self.text = try stream_text.Packetizer.init(
                                    .function_block_name,
                                    block.info.block,
                                    block.name,
                                );
                            }
                        },
                        .advance => {
                            state.cursor += 1;
                            state.stage = .info;
                        },
                    }
                },
            }
        }
    }

    fn validateState(self: *const Replies) !void {
        if (self.text) |*packetizer| {
            if (!packetizer.valid())
                return error.InvalidEndpointRepliesState;
        }
        switch (self.mode) {
            .empty, .fixed => if (self.text != null)
                return error.InvalidEndpointRepliesState,
            .endpoint => |state| {
                if (!state.descriptor.valid() or state.cursor > 5)
                    return error.InvalidEndpointRepliesState;
                configurationSupported(
                    state.descriptor.info,
                    state.configuration,
                ) catch return error.InvalidEndpointRepliesState;
                if (self.text != null and
                    state.cursor != 3 and state.cursor != 4)
                {
                    return error.InvalidEndpointRepliesState;
                }
            },
            .function_blocks => |state| {
                if (!state.descriptor.valid() or
                    state.end > state.descriptor.function_blocks.len or
                    state.cursor > state.end or
                    (self.text != null and state.stage != .advance))
                {
                    return error.InvalidEndpointRepliesState;
                }
            },
        }
    }
};

fn blockBit(block: u5) u32 {
    return @as(u32, 1) << block;
}

fn configurationSupported(
    endpoint: stream.EndpointInfo,
    value: stream.StreamConfiguration,
) !void {
    switch (value.protocol) {
        .midi1 => if (!endpoint.supports_midi1)
            return error.UnsupportedStreamConfiguration,
        .midi2 => if (!endpoint.supports_midi2)
            return error.UnsupportedStreamConfiguration,
    }
    if ((value.transmit_jr_timestamps and !endpoint.supports_transmit_jr) or
        (value.receive_jr_timestamps and !endpoint.supports_receive_jr))
        return error.UnsupportedStreamConfiguration;
}

fn blockMask(count: u6) u32 {
    if (count == 32) return std.math.maxInt(u32);
    if (count == 0) return 0;
    return (@as(u32, 1) << @intCast(count)) - 1;
}

fn discardPacket(result: anyerror!ump.Packet) !void {
    _ = try result;
}

fn endpointInfo(static: bool) stream.EndpointInfo {
    return .{
        .version_major = 1,
        .version_minor = 1,
        .function_block_count = 2,
        .static_function_blocks = static,
        .supports_midi1 = true,
        .supports_midi2 = true,
        .supports_receive_jr = true,
        .supports_transmit_jr = true,
    };
}

fn functionBlock(block: u5) stream.FunctionBlockInfo {
    return .{
        .block = block,
        .enabled = true,
        .ui_hint = .bidirectional,
        .midi1_proxy = .inapplicable,
        .direction = .bidirectional,
        .first_group = @intCast(block % 16),
        .group_count = 1,
        .ci_version = 1,
        .max_sysex8_streams = 1,
    };
}

fn deviceIdentity() stream.DeviceIdentity {
    return .{
        .manufacturer = .{ 0x7D, 0, 0 },
        .family = .{ 1, 2 },
        .model = .{ 3, 4 },
        .revision = .{ 1, 0, 0, 0 },
    };
}

fn endpointDescriptor(
    blocks: []const FunctionBlockDescriptor,
    static: bool,
) Descriptor {
    var info = endpointInfo(static);
    info.function_block_count = @intCast(blocks.len);
    return .{
        .info = info,
        .identity = deviceIdentity(),
        .name = "Endpoint",
        .product_instance_id = "SERIAL-1",
        .configuration = .{ .protocol = .midi1 },
        .function_blocks = blocks,
    };
}

test "requester completes endpoint configuration and function block discovery" {
    var requester = Requester{};
    _ = try requester.endpointDiscovery(1, 1, EndpointFilter.all());
    try requester.accept(.{ .payload = .{ .stream_configuration_notification = .{
        .protocol = .midi1,
    } } });
    try requester.accept(.{ .payload = .{ .endpoint_info = endpointInfo(false) } });
    try requester.accept(.{ .payload = .{ .device_identity = deviceIdentity() } });
    try requester.acceptText(.endpoint_name, null, "Endpoint");
    try requester.acceptText(.product_instance_id, null, "SERIAL-1");
    try std.testing.expect(requester.endpointDiscoveryComplete());

    const desired = stream.StreamConfiguration{
        .protocol = .midi2,
        .transmit_jr_timestamps = true,
        .receive_jr_timestamps = true,
    };
    _ = try requester.configurationRequest(desired);
    try std.testing.expectEqual(.midi1, requester.configuration.?.protocol);
    try requester.accept(.{ .payload = .{
        .stream_configuration_notification = desired,
    } });
    try std.testing.expectEqualDeep(desired, requester.configuration.?);

    _ = try requester.functionBlockDiscovery(.all, FunctionBlockFilter.all());
    try requester.accept(.{ .payload = .{ .function_block_info = functionBlock(0) } });
    try requester.acceptText(.function_block_name, 0, "Input");
    try requester.accept(.{ .payload = .{ .function_block_info = functionBlock(1) } });
    try requester.acceptText(.function_block_name, 1, "Output");
    try std.testing.expect(requester.functionBlockDiscoveryComplete());
    try std.testing.expect(requester.valid());
}

test "responder emits endpoint replies and negotiates configuration" {
    const blocks = [_]FunctionBlockDescriptor{
        .{ .info = functionBlock(0), .name = "Input" },
        .{ .info = functionBlock(1), .name = "Output" },
    };
    var responder = try Responder.init(endpointDescriptor(&blocks, true));
    var replies = try responder.handle(.{ .payload = .{ .endpoint_discovery = .{
        .version_major = 1,
        .version_minor = 1,
        .filter = EndpointFilter.all().bits(),
    } } });
    try std.testing.expectEqual(
        stream.Status.endpoint_info,
        std.meta.activeTag((try stream.Message.parse((try replies.next()).?)).payload),
    );
    try std.testing.expectEqual(
        stream.Status.device_identity,
        std.meta.activeTag((try stream.Message.parse((try replies.next()).?)).payload),
    );
    try std.testing.expectEqual(
        stream_text.Kind.endpoint_name,
        (try stream_text.Chunk.parse((try replies.next()).?)).kind,
    );
    try std.testing.expectEqual(
        stream_text.Kind.product_instance_id,
        (try stream_text.Chunk.parse((try replies.next()).?)).kind,
    );
    try std.testing.expectEqual(
        stream.Status.stream_configuration_notification,
        std.meta.activeTag((try stream.Message.parse((try replies.next()).?)).payload),
    );
    try std.testing.expect((try replies.next()) == null);

    const desired = stream.StreamConfiguration{
        .protocol = .midi2,
        .transmit_jr_timestamps = true,
        .receive_jr_timestamps = true,
    };
    var accepted = try responder.handle(.{ .payload = .{
        .stream_configuration_request = desired,
    } });
    const notification = try stream.Message.parse((try accepted.next()).?);
    try std.testing.expectEqualDeep(
        desired,
        notification.payload.stream_configuration_notification,
    );
    try std.testing.expectEqualDeep(desired, responder.configuration);

    var midi1_only = endpointDescriptor(&blocks, true);
    midi1_only.info.supports_midi2 = false;
    var restricted = try Responder.init(midi1_only);
    var rejected = try restricted.handle(.{ .payload = .{
        .stream_configuration_request = desired,
    } });
    const retained = try stream.Message.parse((try rejected.next()).?);
    try std.testing.expectEqual(
        stream.Protocol.midi1,
        retained.payload.stream_configuration_notification.protocol,
    );
    try std.testing.expectEqual(stream.Protocol.midi1, restricted.configuration.protocol);
}

test "responder lazily emits the largest function block reply set" {
    var name: [91]u8 = undefined;
    @memset(&name, 'n');
    var blocks: [32]FunctionBlockDescriptor = undefined;
    for (&blocks, 0..) |*block, index| {
        block.* = .{
            .info = functionBlock(@intCast(index)),
            .name = &name,
        };
    }
    var responder = try Responder.init(endpointDescriptor(&blocks, true));
    var replies = try responder.handle(.{ .payload = .{ .function_block_discovery = .{
        .selector = .all,
        .filter = FunctionBlockFilter.all().bits(),
    } } });
    var packet_count: usize = 0;
    while (try replies.next()) |_| packet_count += 1;
    try std.testing.expectEqual(@as(usize, 32 * 8), packet_count);
    try std.testing.expect(responder.valid());
}

test "responder rejects invalid requests without changing configuration" {
    const blocks = [_]FunctionBlockDescriptor{
        .{ .info = functionBlock(0), .name = "Input" },
        .{ .info = functionBlock(1), .name = "Output" },
    };
    var responder = try Responder.init(endpointDescriptor(&blocks, false));
    const before = responder;
    try std.testing.expectError(
        error.FunctionBlockOutOfRange,
        responder.handle(.{ .payload = .{ .function_block_discovery = .{
            .selector = .{ .one = 2 },
            .filter = 1,
        } } }),
    );
    try std.testing.expectEqualDeep(before, responder);
    try std.testing.expectError(
        error.UnexpectedResponderMessage,
        responder.handle(.{ .payload = .{ .endpoint_info = endpointInfo(false) } }),
    );
    try std.testing.expectEqualDeep(before, responder);
}

test "endpoint reply iteration contains malformed retained cursors" {
    const blocks = [_]FunctionBlockDescriptor{
        .{ .info = functionBlock(0), .name = "Input" },
    };
    var responder = try Responder.init(endpointDescriptor(&blocks, false));

    var endpoint_replies = try responder.handle(.{ .payload = .{
        .endpoint_discovery = .{
            .version_major = 1,
            .version_minor = 1,
            .filter = EndpointFilter.all().bits(),
        },
    } });
    endpoint_replies.mode.endpoint.cursor = 6;
    try std.testing.expect(!endpoint_replies.valid());
    const endpoint_before = endpoint_replies;
    try std.testing.expectError(
        error.InvalidEndpointRepliesState,
        endpoint_replies.next(),
    );
    try std.testing.expectEqualDeep(endpoint_before, endpoint_replies);

    var block_replies = try responder.handle(.{ .payload = .{
        .function_block_discovery = .{
            .selector = .all,
            .filter = FunctionBlockFilter.all().bits(),
        },
    } });
    block_replies.mode.function_blocks.cursor = 2;
    try std.testing.expect(!block_replies.valid());
    const block_before = block_replies;
    try std.testing.expectError(
        error.InvalidEndpointRepliesState,
        block_replies.next(),
    );
    try std.testing.expectEqualDeep(block_before, block_replies);

    var configuration_replies = try responder.handle(.{ .payload = .{
        .endpoint_discovery = .{
            .version_major = 1,
            .version_minor = 1,
            .filter = EndpointFilter.all().bits(),
        },
    } });
    configuration_replies.mode.endpoint.cursor = 4;
    configuration_replies.mode.endpoint.descriptor.info.supports_midi2 = false;
    configuration_replies.mode.endpoint.configuration = .{
        .protocol = .midi2,
    };
    const configuration_before = configuration_replies;
    try std.testing.expect(!configuration_replies.valid());
    try std.testing.expectError(
        error.InvalidEndpointRepliesState,
        configuration_replies.next(),
    );
    try std.testing.expectEqualDeep(
        configuration_before,
        configuration_replies,
    );
}

test "responder generated requests preserve invariants" {
    const blocks = [_]FunctionBlockDescriptor{
        .{ .info = functionBlock(0), .name = "Input" },
        .{ .info = functionBlock(1), .name = "Output" },
    };
    var responder = try Responder.init(endpointDescriptor(&blocks, false));
    var random = std.Random.DefaultPrng.init(0x5245_5350_4F4E_4445);
    for (0..32_768) |_| {
        const before = responder;
        const result: anyerror!Replies = switch (random.random().uintLessThan(u8, 5)) {
            0 => responder.handle(.{ .payload = .{ .endpoint_discovery = .{
                .version_major = 1,
                .version_minor = 1,
                .filter = random.random().int(u5),
            } } }),
            1 => responder.handle(.{ .payload = .{ .stream_configuration_request = .{
                .protocol = if (random.random().boolean()) .midi1 else .midi2,
                .transmit_jr_timestamps = random.random().boolean(),
                .receive_jr_timestamps = random.random().boolean(),
            } } }),
            2 => responder.handle(.{ .payload = .{ .function_block_discovery = .{
                .selector = .{ .one = random.random().uintLessThan(u5, 4) },
                .filter = random.random().int(u2),
            } } }),
            3 => responder.handle(.{ .payload = .{ .function_block_discovery = .{
                .selector = .all,
                .filter = random.random().int(u2),
            } } }),
            else => responder.handle(.{ .payload = .{
                .stream_configuration_notification = .{ .protocol = .midi1 },
            } }),
        };
        if (result) |initial_replies| {
            var replies = initial_replies;
            var count: usize = 0;
            while (try replies.next()) |_| {
                count += 1;
                try std.testing.expect(count <= 16);
            }
            try std.testing.expect(responder.valid());
        } else |_| {
            try std.testing.expectEqualDeep(before, responder);
        }
    }
}

test "requester rejects invalid transitions without partial mutation" {
    var requester = Requester{};
    try std.testing.expectError(
        error.EndpointInfoRequired,
        requester.configurationRequest(.{ .protocol = .midi2 }),
    );
    try requester.accept(.{ .payload = .{ .endpoint_info = endpointInfo(true) } });
    const before_count_change = requester;
    var changed_count = endpointInfo(true);
    changed_count.function_block_count = 1;
    try std.testing.expectError(
        error.FunctionBlockCountChanged,
        requester.accept(.{ .payload = .{ .endpoint_info = changed_count } }),
    );
    try std.testing.expectEqualDeep(before_count_change, requester);

    _ = try requester.functionBlockDiscovery(
        .{ .one = 0 },
        FunctionBlockFilter.all(),
    );
    try requester.accept(.{ .payload = .{ .function_block_info = functionBlock(0) } });
    try requester.acceptText(.function_block_name, 0, "Static");
    const before_static_change = requester;
    var changed_block = functionBlock(0);
    changed_block.first_group = 4;
    try std.testing.expectError(
        error.StaticFunctionBlockChanged,
        requester.accept(.{ .payload = .{ .function_block_info = changed_block } }),
    );
    try std.testing.expectEqualDeep(before_static_change, requester);
    try std.testing.expectError(
        error.StaticFunctionBlockChanged,
        requester.acceptText(.function_block_name, 0, "Changed"),
    );
    try std.testing.expectEqualDeep(before_static_change, requester);
}

test "requester rejects capability withdrawal that invalidates configuration" {
    var requester = Requester{};
    try requester.accept(.{ .payload = .{ .endpoint_info = endpointInfo(false) } });
    const configuration = stream.StreamConfiguration{
        .protocol = .midi2,
        .transmit_jr_timestamps = true,
    };
    try requester.accept(.{ .payload = .{
        .stream_configuration_notification = configuration,
    } });
    const before = requester;
    var reduced = endpointInfo(false);
    reduced.supports_midi2 = false;
    try std.testing.expectError(
        error.UnsupportedStreamConfiguration,
        requester.accept(.{ .payload = .{ .endpoint_info = reduced } }),
    );
    try std.testing.expectEqualDeep(before, requester);
}

test "requester generated transitions preserve invariants" {
    var random = std.Random.DefaultPrng.init(0x454E_4450_4F49_4E54);
    var requester = Requester{};
    for (0..32_768) |_| {
        const before = requester;
        const result: anyerror!void = switch (random.random().uintLessThan(u8, 8)) {
            0 => requester.accept(.{ .payload = .{ .endpoint_info = endpointInfo(false) } }),
            1 => discardPacket(requester.configurationRequest(.{
                .protocol = if (random.random().boolean()) .midi1 else .midi2,
                .transmit_jr_timestamps = random.random().boolean(),
                .receive_jr_timestamps = random.random().boolean(),
            })),
            2 => requester.accept(.{ .payload = .{ .stream_configuration_notification = .{
                .protocol = if (random.random().boolean()) .midi1 else .midi2,
                .transmit_jr_timestamps = random.random().boolean(),
                .receive_jr_timestamps = random.random().boolean(),
            } } }),
            3 => discardPacket(requester.functionBlockDiscovery(
                .{ .one = random.random().uintLessThan(u5, 4) },
                .{ .info = true },
            )),
            4 => requester.accept(.{ .payload = .{ .function_block_info = functionBlock(
                random.random().uintLessThan(u5, 4),
            ) } }),
            5 => discardPacket(requester.endpointDiscovery(
                1,
                1,
                .{ .endpoint_info = true },
            )),
            6 => requester.acceptText(
                .function_block_name,
                random.random().uintLessThan(u5, 4),
                "Generated",
            ),
            else => requester.accept(.{ .payload = .{ .device_identity = .{
                .manufacturer = .{ 1, 0, 0 },
                .family = .{ 0, 0 },
                .model = .{ 0, 0 },
                .revision = .{ 0, 0, 0, 0 },
            } } }),
        };
        if (result) |_| {
            try std.testing.expect(requester.valid());
        } else |_| {
            try std.testing.expectEqualDeep(before, requester);
        }
    }
}
