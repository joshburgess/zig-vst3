const std = @import("std");
const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_message = @import("vst_message.zig");

pub const message_id = "zig-vst3.resource-path";
pub const maximum_path_bytes = 4096;

pub const Command = enum(i64) {
    import = 1,
    relink = 2,
    cancel = 3,
    retry = 4,
};

const TransportMessage = vst_message.Message(32, 3, 1, maximum_path_bytes);

pub fn send(
    peer: ?*ivstmessage.IConnectionPoint,
    target_id: u32,
    command: Command,
    path: []const u8,
) types.tresult {
    const target = peer orelse return types.kResultFalse;
    if (commandNeedsPath(command)) {
        if (!validPath(path)) return types.kInvalidArgument;
    } else if (path.len != 0) {
        return types.kInvalidArgument;
    }

    var message = TransportMessage{};
    const iface = message.asInterface();
    iface.vtable.setMessageID(iface, message_id);
    const attributes = iface.vtable.getAttributes(iface) orelse return types.kResultFalse;
    if (attributes.vtable.setInt(attributes, "target", target_id) != types.kResultOk or
        attributes.vtable.setInt(attributes, "command", @intFromEnum(command)) != types.kResultOk)
    {
        return types.kResultFalse;
    }
    if (commandNeedsPath(command) and
        attributes.vtable.setBinary(attributes, "path", path.ptr, @intCast(path.len)) != types.kResultOk)
    {
        return types.kResultFalse;
    }
    return target.vtable.notify(target, iface);
}

pub fn sendImport(peer: ?*ivstmessage.IConnectionPoint, target_id: u32, path: []const u8) types.tresult {
    return send(peer, target_id, .import, path);
}

pub fn sendRelink(peer: ?*ivstmessage.IConnectionPoint, target_id: u32, path: []const u8) types.tresult {
    return send(peer, target_id, .relink, path);
}

pub fn sendCancel(peer: ?*ivstmessage.IConnectionPoint, target_id: u32) types.tresult {
    return send(peer, target_id, .cancel, "");
}

pub fn sendRetry(peer: ?*ivstmessage.IConnectionPoint, target_id: u32) types.tresult {
    return send(peer, target_id, .retry, "");
}

pub fn receive(receiver: anytype, expected_target_id: u32, message: ?*ivstmessage.IMessage) types.tresult {
    const iface = message orelse return types.kInvalidArgument;
    if (!ivstmessage.messageIdEquals(iface, message_id)) return types.kResultFalse;
    const attributes = iface.vtable.getAttributes(iface) orelse return types.kInvalidArgument;
    var target_value: i64 = 0;
    var command_value: i64 = 0;
    if (attributes.vtable.getInt(attributes, "target", &target_value) != types.kResultOk or
        attributes.vtable.getInt(attributes, "command", &command_value) != types.kResultOk or
        target_value != expected_target_id)
    {
        return types.kInvalidArgument;
    }
    const command: Command = switch (command_value) {
        1 => .import,
        2 => .relink,
        3 => .cancel,
        4 => .retry,
        else => return types.kInvalidArgument,
    };

    const accepted = switch (command) {
        .import, .relink => blk: {
            var payload: ?*const anyopaque = null;
            var byte_count: u32 = 0;
            if (attributes.vtable.getBinary(attributes, "path", &payload, &byte_count) != types.kResultOk or
                byte_count == 0 or byte_count > maximum_path_bytes or payload == null)
            {
                return types.kInvalidArgument;
            }
            const path_payload = payload orelse
                return types.kInvalidArgument;
            const bytes: [*]const u8 = @ptrCast(path_payload);
            const path = bytes[0..byte_count];
            if (!validPath(path)) return types.kInvalidArgument;
            break :blk if (command == .import) receiver.importPath(path) else receiver.relink(path);
        },
        .cancel => receiver.requestCancel(),
        .retry => receiver.retry(),
    };
    return if (accepted) types.kResultOk else types.kResultFalse;
}

fn commandNeedsPath(command: Command) bool {
    return switch (command) {
        .import, .relink => true,
        .cancel, .retry => false,
    };
}

fn validPath(path: []const u8) bool {
    return path.len > 0 and path.len <= maximum_path_bytes and std.mem.indexOfScalar(u8, path, 0) == null;
}

test "resource path transport routes bounded commands" {
    const ReceiverState = struct {
        imported: [32]u8 = @splat(0),
        imported_length: usize = 0,
        relinked: [32]u8 = @splat(0),
        relinked_length: usize = 0,
        cancel_count: usize = 0,
        retry_count: usize = 0,

        pub fn importPath(self: *@This(), path: []const u8) bool {
            if (path.len > self.imported.len) return false;
            @memcpy(self.imported[0..path.len], path);
            self.imported_length = path.len;
            return true;
        }

        pub fn relink(self: *@This(), path: []const u8) bool {
            if (path.len > self.relinked.len) return false;
            @memcpy(self.relinked[0..path.len], path);
            self.relinked_length = path.len;
            return true;
        }

        pub fn requestCancel(self: *@This()) bool {
            self.cancel_count += 1;
            return true;
        }

        pub fn retry(self: *@This()) bool {
            self.retry_count += 1;
            return true;
        }
    };
    const ReceiverConfig = struct {
        var state = ReceiverState{};

        pub fn notify(_: anytype, message: ?*ivstmessage.IMessage) types.tresult {
            return receive(&state, 19, message);
        }
    };
    const Connection = vst_message.ConnectionPoint(ReceiverConfig);
    var connection = Connection{};
    const peer = connection.asInterface();

    try std.testing.expectEqual(types.kResultOk, sendImport(peer, 19, "/models/clean.nam"));
    try std.testing.expectEqualStrings("/models/clean.nam", ReceiverConfig.state.imported[0..ReceiverConfig.state.imported_length]);
    try std.testing.expectEqual(types.kResultOk, sendRelink(peer, 19, "/moved/clean.nam"));
    try std.testing.expectEqualStrings("/moved/clean.nam", ReceiverConfig.state.relinked[0..ReceiverConfig.state.relinked_length]);
    try std.testing.expectEqual(types.kResultOk, sendCancel(peer, 19));
    try std.testing.expectEqual(types.kResultOk, sendRetry(peer, 19));
    try std.testing.expectEqual(@as(usize, 1), ReceiverConfig.state.cancel_count);
    try std.testing.expectEqual(@as(usize, 1), ReceiverConfig.state.retry_count);
}

test "resource path transport rejects malformed and unrelated messages" {
    const ReceiverState = struct {
        pub fn importPath(_: *@This(), _: []const u8) bool {
            return true;
        }
        pub fn relink(_: *@This(), _: []const u8) bool {
            return true;
        }
        pub fn requestCancel(_: *@This()) bool {
            return true;
        }
        pub fn retry(_: *@This()) bool {
            return true;
        }
    };
    var state = ReceiverState{};
    const Connection = vst_message.ConnectionPoint(struct {});
    var connection = Connection{};
    try std.testing.expectEqual(types.kInvalidArgument, sendImport(connection.asInterface(), 1, ""));
    try std.testing.expectEqual(types.kInvalidArgument, send(connection.asInterface(), 1, .cancel, "unexpected"));
    try std.testing.expectEqual(types.kInvalidArgument, sendImport(connection.asInterface(), 1, "bad\x00path"));
    try std.testing.expectEqual(types.kResultFalse, sendImport(null, 1, "/model.nam"));

    var unrelated = TransportMessage{};
    const unrelated_iface = unrelated.asInterface();
    unrelated_iface.vtable.setMessageID(unrelated_iface, "unrelated");
    try std.testing.expectEqual(types.kResultFalse, receive(&state, 1, unrelated_iface));

    var wrong_target = TransportMessage{};
    const wrong_iface = wrong_target.asInterface();
    wrong_iface.vtable.setMessageID(wrong_iface, message_id);
    const attributes = wrong_iface.vtable.getAttributes(wrong_iface) orelse return error.MissingAttributes;
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "target", 2));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "command", @intFromEnum(Command.cancel)));
    try std.testing.expectEqual(types.kInvalidArgument, receive(&state, 1, wrong_iface));
}

test "resource path transport rejects generated unknown commands without dispatch" {
    const ReceiverState = struct {
        calls: usize = 0,

        pub fn importPath(self: *@This(), _: []const u8) bool {
            self.calls += 1;
            return true;
        }
        pub fn relink(self: *@This(), _: []const u8) bool {
            self.calls += 1;
            return true;
        }
        pub fn requestCancel(self: *@This()) bool {
            self.calls += 1;
            return true;
        }
        pub fn retry(self: *@This()) bool {
            self.calls += 1;
            return true;
        }
    };
    var state = ReceiverState{};
    var message = TransportMessage{};
    const iface = message.asInterface();
    iface.vtable.setMessageID(iface, message_id);
    const attributes = iface.vtable.getAttributes(iface) orelse
        return error.MissingAttributes;
    try std.testing.expectEqual(
        types.kResultOk,
        attributes.vtable.setInt(attributes, "target", 73),
    );

    var seed: u64 = 0x9E37_79B9_7F4A_7C15;
    for (0..4_096) |_| {
        seed = seed *% 6_364_136_223_846_793_005 +% 1_442_695_040_888_963_407;
        var command_value: i64 = @bitCast(seed);
        if (command_value >= 1 and command_value <= 4)
            command_value = std.math.maxInt(i64);
        try std.testing.expectEqual(
            types.kResultOk,
            attributes.vtable.setInt(attributes, "command", command_value),
        );
        try std.testing.expectEqual(
            types.kInvalidArgument,
            receive(&state, 73, iface),
        );
    }
    try std.testing.expectEqual(@as(usize, 0), state.calls);
}
