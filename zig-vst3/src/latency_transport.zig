const std = @import("std");
const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_message = @import("vst_message.zig");

pub const message_id = "zig-vst3.latency-changed";
const LatencyMessage = vst_message.Message(message_id.len + 1, 1, 1, 1);

pub fn send(peer: ?*ivstmessage.IConnectionPoint) types.tresult {
    const target = peer orelse return types.kResultFalse;
    var message = LatencyMessage{};
    const iface = message.asInterface();
    iface.vtable.setMessageID(iface, message_id);
    return target.vtable.notify(target, iface);
}

pub fn receive(message: ?*ivstmessage.IMessage) types.tresult {
    const iface = message orelse return types.kInvalidArgument;
    const id = iface.vtable.getMessageID(iface);
    return if (std.mem.eql(u8, std.mem.span(id), message_id))
        types.kResultOk
    else
        types.kResultFalse;
}

test "latency change message is recognized without attributes" {
    const ReceiverConfig = struct {
        var received: bool = false;

        pub fn notify(_: anytype, message: ?*ivstmessage.IMessage) types.tresult {
            const result = receive(message);
            if (result == types.kResultOk) received = true;
            return result;
        }
    };
    const Receiver = vst_message.ConnectionPoint(ReceiverConfig);
    var receiver = Receiver{};
    ReceiverConfig.received = false;
    try std.testing.expectEqual(types.kResultOk, send(receiver.asInterface()));
    try std.testing.expect(ReceiverConfig.received);
    try std.testing.expectEqual(types.kInvalidArgument, receive(null));

    var unrelated = LatencyMessage{};
    unrelated.asInterface().vtable.setMessageID(unrelated.asInterface(), "unrelated");
    try std.testing.expectEqual(types.kResultFalse, receive(unrelated.asInterface()));
}
