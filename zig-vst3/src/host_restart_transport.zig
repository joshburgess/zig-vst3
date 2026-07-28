const std = @import("std");
const ivsteditcontroller =
    @import("pluginterfaces/vst/ivsteditcontroller.zig");
const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_message = @import("vst_message.zig");

pub const message_id = "zig-vst3.host-restart";
const flags_attribute = "flags";
const valid_flags_mask: types.int32 =
    ivsteditcontroller.RestartFlags.kReloadComponent |
    ivsteditcontroller.RestartFlags.kIoChanged |
    ivsteditcontroller.RestartFlags.kParamValuesChanged |
    ivsteditcontroller.RestartFlags.kLatencyChanged |
    ivsteditcontroller.RestartFlags.kParamTitlesChanged |
    ivsteditcontroller.RestartFlags.kMidiCCAssignmentChanged |
    ivsteditcontroller.RestartFlags.kNoteExpressionChanged |
    ivsteditcontroller.RestartFlags.kIoTitlesChanged |
    ivsteditcontroller.RestartFlags.kPrefetchableSupportChanged |
    ivsteditcontroller.RestartFlags.kRoutingInfoChanged |
    ivsteditcontroller.RestartFlags.kKeyswitchChanged |
    ivsteditcontroller.RestartFlags.kParamIDMappingChanged;
const RestartMessage = vst_message.Message(32, 1, 1, 1);

pub fn send(
    peer: ?*ivstmessage.IConnectionPoint,
    flags: types.int32,
) types.tresult {
    const target = peer orelse return types.kResultFalse;
    if (!validFlags(flags)) return types.kInvalidArgument;
    var message = RestartMessage{};
    const iface = message.asInterface();
    iface.vtable.setMessageID(iface, message_id);
    const attributes =
        iface.vtable.getAttributes(iface) orelse return types.kResultFalse;
    if (attributes.vtable.setInt(
        attributes,
        flags_attribute,
        flags,
    ) != types.kResultOk) return types.kResultFalse;
    return target.vtable.notify(target, iface);
}

pub fn receive(
    message: ?*ivstmessage.IMessage,
    out_flags: *types.int32,
) types.tresult {
    out_flags.* = 0;
    const iface = message orelse return types.kInvalidArgument;
    if (!ivstmessage.messageIdEquals(iface, message_id))
        return types.kResultFalse;
    const attributes =
        iface.vtable.getAttributes(iface) orelse
        return types.kInvalidArgument;
    var value: types.int64 = 0;
    if (attributes.vtable.getInt(
        attributes,
        flags_attribute,
        &value,
    ) != types.kResultOk or
        value < 0 or
        value > valid_flags_mask)
        return types.kInvalidArgument;
    const flags: types.int32 = @intCast(value);
    if (!validFlags(flags)) return types.kInvalidArgument;
    out_flags.* = flags;
    return types.kResultOk;
}

fn validFlags(flags: types.int32) bool {
    return flags > 0 and flags & ~valid_flags_mask == 0;
}

test "host restart transport combines and validates flags" {
    const ReceiverConfig = struct {
        var received_flags: types.int32 = 0;

        pub fn notify(
            _: anytype,
            message: ?*ivstmessage.IMessage,
        ) types.tresult {
            return receive(message, &received_flags);
        }
    };
    const Receiver = vst_message.ConnectionPoint(ReceiverConfig);
    var receiver = Receiver{};
    const flags =
        ivsteditcontroller.RestartFlags.kIoChanged |
        ivsteditcontroller.RestartFlags.kLatencyChanged;
    ReceiverConfig.received_flags = 0;
    try std.testing.expectEqual(
        types.kResultOk,
        send(receiver.asInterface(), flags),
    );
    try std.testing.expectEqual(
        flags,
        ReceiverConfig.received_flags,
    );
    try std.testing.expectEqual(
        types.kInvalidArgument,
        send(receiver.asInterface(), 0),
    );
    try std.testing.expectEqual(
        types.kInvalidArgument,
        send(receiver.asInterface(), 1 << 12),
    );

    var decoded_flags: types.int32 = 123;
    try std.testing.expectEqual(
        types.kInvalidArgument,
        receive(null, &decoded_flags),
    );
    try std.testing.expectEqual(@as(types.int32, 0), decoded_flags);

    var unrelated = RestartMessage{};
    unrelated.asInterface().vtable.setMessageID(
        unrelated.asInterface(),
        "unrelated",
    );
    decoded_flags = 123;
    try std.testing.expectEqual(
        types.kResultFalse,
        receive(unrelated.asInterface(), &decoded_flags),
    );
    try std.testing.expectEqual(@as(types.int32, 0), decoded_flags);

    var missing_flags = RestartMessage{};
    missing_flags.asInterface().vtable.setMessageID(
        missing_flags.asInterface(),
        message_id,
    );
    decoded_flags = 123;
    try std.testing.expectEqual(
        types.kInvalidArgument,
        receive(missing_flags.asInterface(), &decoded_flags),
    );
    try std.testing.expectEqual(@as(types.int32, 0), decoded_flags);

    var unknown_flags = RestartMessage{};
    unknown_flags.asInterface().vtable.setMessageID(
        unknown_flags.asInterface(),
        message_id,
    );
    const unknown_attributes =
        unknown_flags.asInterface().vtable.getAttributes(
            unknown_flags.asInterface(),
        ) orelse return error.MissingAttributes;
    try std.testing.expectEqual(
        types.kResultOk,
        unknown_attributes.vtable.setInt(
            unknown_attributes,
            flags_attribute,
            1 << 12,
        ),
    );
    decoded_flags = 123;
    try std.testing.expectEqual(
        types.kInvalidArgument,
        receive(unknown_flags.asInterface(), &decoded_flags),
    );
    try std.testing.expectEqual(@as(types.int32, 0), decoded_flags);
}
