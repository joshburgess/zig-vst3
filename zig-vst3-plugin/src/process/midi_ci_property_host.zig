const std = @import("std");
const midi_ci = @import("midi_ci.zig");
const property = @import("midi_ci_property.zig");
const property_json = @import("midi_ci_property_json.zig");
const property_session = @import("midi_ci_property_session.zig");

pub const Request = struct {
    remote: midi_ci.Muid,
    version: u5,
    request_id: u7,
    header: property_json.RequestHeader,
    data: []const u8,
};

pub const SubscriptionRequest = struct {
    remote: midi_ci.Muid,
    version: u5,
    request_id: u7,
    header: property_json.SubscriptionHeader,
    data: []const u8,
};

pub const Reply = struct {
    header: property_json.ReplyHeader,
    data: []const u8 = &.{},

    pub fn valid(self: Reply) bool {
        return self.header.valid();
    }
};

pub fn Result(comptime Message: type) type {
    return union(enum) {
        more: u7,
        reply: Message,
        aborted: u7,
    };
}

pub fn BorrowedHost(
    comptime Responder: type,
    comptime Subscriptions: type,
    comptime Delegate: type,
    comptime reply_header_capacity: usize,
) type {
    const Message = Responder.DataMessage;
    return struct {
        const Self = @This();

        responder: *Responder,
        subscriptions: *Subscriptions,
        delegate: *Delegate,

        pub fn accept(
            self: *Self,
            allocator: std.mem.Allocator,
            message: anytype,
        ) !Result(Message) {
            const receive = try self.responder.push(message);
            const handle = switch (receive) {
                .more => |value| return .{ .more = value },
                .complete => |value| value,
                .aborted => |value| {
                    try self.responder.release(value);
                    return .{ .aborted = value };
                },
                else => return error.InvalidMidiCiPropertyHostReceiveState,
            };
            errdefer self.responder.release(handle) catch {};

            const reassembly = try self.responder.request(handle);
            if (reassembly.kind == .subscription)
                return self.acceptSubscription(
                    allocator,
                    handle,
                    reassembly,
                );
            const reply = switch (reassembly.kind) {
                .get => try self.getReply(allocator, reassembly),
                .set => try self.setReply(allocator, reassembly),
                else => return error.InvalidMidiCiPropertyRequestKind,
            };
            return .{ .reply = try self.makeReply(handle, reply) };
        }

        fn getReply(
            self: *Self,
            allocator: std.mem.Allocator,
            reassembly: anytype,
        ) !Reply {
            const parsed = try property_json.RequestHeader.parseJson(
                allocator,
                reassembly.header(),
            );
            defer parsed.deinit();
            return self.delegate.getData(.{
                .remote = reassembly.source,
                .version = reassembly.version,
                .request_id = reassembly.request_id,
                .header = parsed.value,
                .data = reassembly.data(),
            });
        }

        fn setReply(
            self: *Self,
            allocator: std.mem.Allocator,
            reassembly: anytype,
        ) !Reply {
            const parsed = try property_json.RequestHeader.parseJson(
                allocator,
                reassembly.header(),
            );
            defer parsed.deinit();
            return self.delegate.setData(.{
                .remote = reassembly.source,
                .version = reassembly.version,
                .request_id = reassembly.request_id,
                .header = parsed.value,
                .data = reassembly.data(),
            });
        }

        fn acceptSubscription(
            self: *Self,
            allocator: std.mem.Allocator,
            handle: u7,
            reassembly: anytype,
        ) !Result(Message) {
            const parsed = try property_json.SubscriptionHeader.parseJson(
                allocator,
                reassembly.header(),
            );
            defer parsed.deinit();
            const reply = try self.delegate.subscriptionChanged(.{
                .remote = reassembly.source,
                .version = reassembly.version,
                .request_id = reassembly.request_id,
                .header = parsed.value,
                .data = reassembly.data(),
            });
            if (!reply.valid()) return error.InvalidMidiCiPropertyHostReply;
            if (reply.header.status != .ok and
                reply.header.status != .accepted)
                return .{ .reply = try self.makeReply(handle, reply) };

            const remote = reassembly.source;
            var existing: ?u7 = null;
            switch (parsed.value.command) {
                .start => {},
                else => {
                    const subscribe_id = parsed.value.subscribe_id orelse
                        return error.InvalidMidiCiPropertySubscribeId;
                    existing = self.subscriptions.findHandle(
                        remote,
                        subscribe_id,
                    ) orelse return error.MidiCiPropertySubscriptionNotFound;
                },
            }
            const response = try self.makeReply(handle, reply);
            switch (parsed.value.command) {
                .start => {
                    const resource = parsed.value.resource orelse
                        return error.InvalidMidiCiPropertySubscriptionHeader;
                    const subscribe_id = reply.header.subscribe_id orelse
                        return error.InvalidMidiCiPropertySubscribeId;
                    _ = try self.subscriptions.register(
                        remote,
                        resource,
                        subscribe_id,
                    );
                },
                .end => try self.subscriptions.release(
                    existing orelse
                        return error.MidiCiPropertySubscriptionNotFound,
                ),
                .partial, .full, .notify => {},
            }
            return .{ .reply = response };
        }

        fn makeReply(
            self: *Self,
            handle: u7,
            reply: Reply,
        ) !Message {
            if (!reply.valid()) return error.InvalidMidiCiPropertyHostReply;
            var header_storage: [reply_header_capacity]u8 = undefined;
            var writer: std.Io.Writer = .fixed(&header_storage);
            try reply.header.writeJson(&writer);
            return self.responder.reply(
                handle,
                writer.buffered(),
                1,
                reply.data,
            );
        }
    };
}

pub fn borrowed(
    comptime reply_header_capacity: usize,
    responder: anytype,
    subscriptions: anytype,
    delegate: anytype,
) BorrowedHost(
    @TypeOf(responder.*),
    @TypeOf(subscriptions.*),
    @TypeOf(delegate.*),
    reply_header_capacity,
) {
    return .{
        .responder = responder,
        .subscriptions = subscriptions,
        .delegate = delegate,
    };
}

pub fn Host(
    comptime session_capacity: usize,
    comptime header_capacity: usize,
    comptime data_capacity: usize,
    comptime subscription_capacity: usize,
    comptime Delegate: type,
) type {
    const Responder = property_session.Responder(
        session_capacity,
        header_capacity,
        data_capacity,
    );
    const Subscriptions = property_session.SubscriptionRegistry(
        subscription_capacity,
    );
    const Borrowed = BorrowedHost(
        Responder,
        Subscriptions,
        Delegate,
        header_capacity,
    );
    return struct {
        const Self = @This();

        responder: Responder,
        subscriptions: Subscriptions = .{},
        delegate: *Delegate,

        pub fn init(source: midi_ci.Muid, delegate: *Delegate) !Self {
            return .{
                .responder = try Responder.init(source),
                .delegate = delegate,
            };
        }

        pub fn accept(
            self: *Self,
            allocator: std.mem.Allocator,
            message: anytype,
        ) !Result(Responder.DataMessage) {
            var host = Borrowed{
                .responder = &self.responder,
                .subscriptions = &self.subscriptions,
                .delegate = self.delegate,
            };
            return host.accept(allocator, message);
        }
    };
}

const TestDelegate = struct {
    get_count: usize = 0,
    set_count: usize = 0,
    subscription_count: usize = 0,
    oversized_subscription_reply: bool = false,

    fn getData(self: *TestDelegate, request: Request) !Reply {
        self.get_count += 1;
        if (!std.mem.eql(u8, request.header.resource, "DeviceInfo"))
            return .{ .header = .{ .status = .not_found } };
        return .{
            .header = .{
                .status = .ok,
                .media_type = "application/json",
            },
            .data = "{\"manufacturer\":\"Example\"}",
        };
    }

    fn setData(self: *TestDelegate, request: Request) !Reply {
        self.set_count += 1;
        if (request.data.len == 0)
            return .{ .header = .{ .status = .bad_data } };
        return .{ .header = .{ .status = .ok } };
    }

    fn subscriptionChanged(
        self: *TestDelegate,
        request: SubscriptionRequest,
    ) !Reply {
        self.subscription_count += 1;
        return .{
            .header = .{
                .status = .ok,
                .subscribe_id = if (request.header.command == .start)
                    "sub_1"
                else
                    null,
            },
            .data = if (self.oversized_subscription_reply)
                "012345678901234567890123456789012"
            else
                &.{},
        };
    }
};

test "Property Host dispatches Get and Set requests" {
    const TestHost = Host(2, 128, 128, 2, TestDelegate);
    const Message = property.DataMessage(128, 128);
    const local = try midi_ci.Muid.init(1);
    const remote = try midi_ci.Muid.init(2);
    var delegate = TestDelegate{};
    var host = try TestHost.init(local, &delegate);

    const get_result = try host.accept(
        std.testing.allocator,
        try Message.init(
            .get,
            2,
            remote,
            local,
            1,
            "{\"resource\":\"DeviceInfo\"}",
            1,
            1,
            &.{},
        ),
    );
    const get_reply = get_result.reply;
    try std.testing.expectEqual(property.DataKind.get_reply, get_reply.kind);
    try std.testing.expectEqualStrings(
        "{\"manufacturer\":\"Example\"}",
        get_reply.data(),
    );

    const set_result = try host.accept(
        std.testing.allocator,
        try Message.init(
            .set,
            2,
            remote,
            local,
            2,
            "{\"resource\":\"State\"}",
            1,
            1,
            "{}",
        ),
    );
    try std.testing.expectEqual(
        property.DataKind.set_reply,
        set_result.reply.kind,
    );
    try std.testing.expectEqual(@as(usize, 1), delegate.get_count);
    try std.testing.expectEqual(@as(usize, 1), delegate.set_count);
    try std.testing.expectEqual(@as(usize, 0), host.responder.activeCount());
}

test "Property Host owns subscription lifecycle" {
    const TestHost = Host(2, 128, 32, 2, TestDelegate);
    const Message = property.DataMessage(128, 32);
    const local = try midi_ci.Muid.init(1);
    const remote = try midi_ci.Muid.init(2);
    var delegate = TestDelegate{};
    var host = try TestHost.init(local, &delegate);

    const start = try host.accept(
        std.testing.allocator,
        try Message.init(
            .subscription,
            2,
            remote,
            local,
            1,
            "{\"command\":\"start\",\"resource\":\"State\"}",
            1,
            1,
            &.{},
        ),
    );
    try std.testing.expectEqual(
        property.DataKind.subscription_reply,
        start.reply.kind,
    );
    try std.testing.expectEqual(@as(usize, 1), host.subscriptions.activeCount());

    _ = try host.accept(
        std.testing.allocator,
        try Message.init(
            .subscription,
            2,
            remote,
            local,
            2,
            "{\"command\":\"end\",\"subscribeId\":\"sub_1\"}",
            1,
            1,
            &.{},
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), host.subscriptions.activeCount());
    try std.testing.expectEqual(@as(usize, 2), delegate.subscription_count);

    delegate.oversized_subscription_reply = true;
    try std.testing.expectError(
        error.MidiCiPropertyDataCapacityExceeded,
        host.accept(
            std.testing.allocator,
            try Message.init(
                .subscription,
                2,
                remote,
                local,
                3,
                "{\"command\":\"start\",\"resource\":\"State\"}",
                1,
                1,
                &.{},
            ),
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), host.subscriptions.activeCount());
    try std.testing.expectEqual(@as(usize, 0), host.responder.activeCount());
}

test "Property Host releases malformed and rejected requests" {
    const RejectingDelegate = struct {
        fn getData(_: *@This(), _: Request) !Reply {
            return error.DelegateRejected;
        }

        fn setData(_: *@This(), _: Request) !Reply {
            return error.DelegateRejected;
        }

        fn subscriptionChanged(
            _: *@This(),
            _: SubscriptionRequest,
        ) !Reply {
            return error.DelegateRejected;
        }
    };
    const TestHost = Host(1, 64, 32, 1, RejectingDelegate);
    const Message = property.DataMessage(64, 32);
    const local = try midi_ci.Muid.init(1);
    const remote = try midi_ci.Muid.init(2);
    var delegate = RejectingDelegate{};
    var host = try TestHost.init(local, &delegate);

    try std.testing.expectError(
        error.InvalidMidiCiPropertyHeaderOrder,
        host.accept(
            std.testing.allocator,
            try Message.init(
                .get,
                2,
                remote,
                local,
                1,
                "{}",
                1,
                1,
                &.{},
            ),
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), host.responder.activeCount());

    try std.testing.expectError(
        error.DelegateRejected,
        host.accept(
            std.testing.allocator,
            try Message.init(
                .get,
                2,
                remote,
                local,
                2,
                "{\"resource\":\"State\"}",
                1,
                1,
                &.{},
            ),
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), host.responder.activeCount());
}
