const std = @import("std");
const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_message = @import("vst_message.zig");

pub const message_id = "zig-vst3.gui-note";
const NoteMessage = vst_message.Message(32, 4, 1, 1);

pub const Command = struct {
    channel: i16 = 0,
    pitch: i16,
    velocity: f64,
    pressed: bool,

    pub fn validate(self: Command) !void {
        if (self.channel < 0 or self.channel > 15) return error.InvalidChannel;
        if (self.pitch < 0 or self.pitch > 127) return error.InvalidPitch;
        if (!std.math.isFinite(self.velocity) or self.velocity < 0.0 or self.velocity > 1.0) {
            return error.InvalidVelocity;
        }
        if (self.pressed and self.velocity == 0.0) return error.InvalidVelocity;
    }
};

pub const Mailbox = struct {
    const sequence_shift = 21;
    const channel_shift = 17;
    const pressed_mask: u64 = 1 << 16;
    const velocity_mask: u64 = 0xffff;
    const sequence_mask: u64 = std.math.maxInt(u64) >> sequence_shift;

    slots: [128]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** 128,

    pub fn publish(self: *Mailbox, command: Command) !void {
        try command.validate();
        const slot = &self.slots[@intCast(command.pitch)];
        var previous = slot.load(.monotonic);
        while (true) {
            const previous_sequence = (previous >> sequence_shift) & sequence_mask;
            const sequence = if (previous_sequence == sequence_mask) 1 else previous_sequence + 1;
            const velocity: u64 = @intFromFloat(@round(
                command.velocity * @as(f64, @floatFromInt(velocity_mask)),
            ));
            const next = (sequence << sequence_shift) |
                (@as(u64, @intCast(command.channel)) << channel_shift) |
                (if (command.pressed) pressed_mask else 0) |
                velocity;
            if (slot.cmpxchgWeak(previous, next, .release, .monotonic)) |observed| {
                previous = observed;
            } else break;
        }
    }

    pub fn collect(self: *const Mailbox, seen: *[128]u64, output: []Command) usize {
        var count: usize = 0;
        for ([_]bool{ false, true }) |pressed| {
            for (&self.slots, 0..) |*slot, pitch| {
                const state = slot.load(.acquire);
                if (state == 0 or state == seen[pitch] or decodePressed(state) != pressed) continue;
                if (count == output.len) return count;
                output[count] = .{
                    .channel = decodeChannel(state),
                    .pitch = @intCast(pitch),
                    .velocity = decodeVelocity(state),
                    .pressed = pressed,
                };
                seen[pitch] = state;
                count += 1;
            }
        }
        return count;
    }

    fn decodeChannel(state: u64) i16 {
        return @intCast((state >> channel_shift) & 0xf);
    }

    fn decodePressed(state: u64) bool {
        return state & pressed_mask != 0;
    }

    fn decodeVelocity(state: u64) f64 {
        return @as(f64, @floatFromInt(state & velocity_mask)) /
            @as(f64, @floatFromInt(velocity_mask));
    }
};

pub fn send(peer: ?*ivstmessage.IConnectionPoint, command: Command) types.tresult {
    command.validate() catch return types.kInvalidArgument;
    const target = peer orelse return types.kResultFalse;
    var message = NoteMessage{};
    const iface = message.asInterface();
    iface.vtable.setMessageID(iface, message_id);
    const attributes = iface.vtable.getAttributes(iface) orelse return types.kResultFalse;
    if (attributes.vtable.setInt(attributes, "channel", command.channel) != types.kResultOk or
        attributes.vtable.setInt(attributes, "pitch", command.pitch) != types.kResultOk or
        attributes.vtable.setFloat(attributes, "velocity", command.velocity) != types.kResultOk or
        attributes.vtable.setInt(attributes, "pressed", @intFromBool(command.pressed)) != types.kResultOk)
    {
        return types.kResultFalse;
    }
    return target.vtable.notify(target, iface);
}

pub fn receive(mailbox: *Mailbox, message: ?*ivstmessage.IMessage) types.tresult {
    const iface = message orelse return types.kInvalidArgument;
    if (!ivstmessage.messageIdEquals(iface, message_id)) return types.kResultFalse;
    const attributes = iface.vtable.getAttributes(iface) orelse return types.kInvalidArgument;
    var channel: types.int64 = 0;
    var pitch: types.int64 = 0;
    var velocity: f64 = 0.0;
    var pressed: types.int64 = 0;
    if (attributes.vtable.getInt(attributes, "channel", &channel) != types.kResultOk or
        attributes.vtable.getInt(attributes, "pitch", &pitch) != types.kResultOk or
        attributes.vtable.getFloat(attributes, "velocity", &velocity) != types.kResultOk or
        attributes.vtable.getInt(attributes, "pressed", &pressed) != types.kResultOk or
        channel < std.math.minInt(i16) or channel > std.math.maxInt(i16) or
        pitch < std.math.minInt(i16) or pitch > std.math.maxInt(i16) or
        (pressed != 0 and pressed != 1))
    {
        return types.kInvalidArgument;
    }
    mailbox.publish(.{
        .channel = @intCast(channel),
        .pitch = @intCast(pitch),
        .velocity = velocity,
        .pressed = pressed != 0,
    }) catch return types.kInvalidArgument;
    return types.kResultOk;
}

test "mailbox keeps the latest state and releases before presses" {
    var mailbox = Mailbox{};
    try mailbox.publish(.{ .pitch = 72, .velocity = 0.8, .pressed = true });
    try mailbox.publish(.{ .pitch = 60, .velocity = 0.7, .pressed = true });
    var seen: [128]u64 = @splat(0);
    var commands: [4]Command = undefined;
    var count = mailbox.collect(&seen, &commands);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(@as(i16, 60), commands[0].pitch);
    try std.testing.expectEqual(@as(i16, 72), commands[1].pitch);

    try mailbox.publish(.{ .pitch = 72, .velocity = 0.0, .pressed = false });
    try mailbox.publish(.{ .pitch = 64, .velocity = 0.9, .pressed = true });
    count = mailbox.collect(&seen, commands[0..1]);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(i16, 72), commands[0].pitch);
    try std.testing.expect(!commands[0].pressed);
    count = mailbox.collect(&seen, &commands);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(i16, 64), commands[0].pitch);
    try std.testing.expect(commands[0].pressed);
}

test "mailbox sequence rollover preserves a channel zero release" {
    var mailbox = Mailbox{};
    const pitch = 60;
    const saturated_sequence = Mailbox.sequence_mask << Mailbox.sequence_shift;
    mailbox.slots[pitch].store(saturated_sequence, .monotonic);
    var seen: [128]u64 = @splat(0);
    seen[pitch] = saturated_sequence;

    try mailbox.publish(.{ .channel = 0, .pitch = pitch, .velocity = 0.0, .pressed = false });
    try std.testing.expect(mailbox.slots[pitch].load(.monotonic) != 0);
    var commands: [1]Command = undefined;
    try std.testing.expectEqual(@as(usize, 1), mailbox.collect(&seen, &commands));
    try std.testing.expectEqual(@as(i16, pitch), commands[0].pitch);
    try std.testing.expectEqual(@as(i16, 0), commands[0].channel);
    try std.testing.expect(!commands[0].pressed);
    try std.testing.expectEqual(@as(f64, 0.0), commands[0].velocity);
}

test "connection message round trips into the mailbox" {
    const ReceiverConfig = struct {
        var mailbox: Mailbox = .{};

        pub fn notify(_: anytype, message: ?*ivstmessage.IMessage) types.tresult {
            return receive(&mailbox, message);
        }
    };
    const Receiver = vst_message.ConnectionPoint(ReceiverConfig);
    var receiver = Receiver{};
    try std.testing.expectEqual(types.kResultOk, send(receiver.asInterface(), .{
        .channel = 2,
        .pitch = 67,
        .velocity = 0.75,
        .pressed = true,
    }));
    var seen: [128]u64 = @splat(0);
    var commands: [1]Command = undefined;
    try std.testing.expectEqual(@as(usize, 1), ReceiverConfig.mailbox.collect(&seen, &commands));
    try std.testing.expectEqual(@as(i16, 2), commands[0].channel);
    try std.testing.expectEqual(@as(i16, 67), commands[0].pitch);
    try std.testing.expect(commands[0].pressed);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), commands[0].velocity, 0.00002);
}

test "note receiver rejects malformed routing without publishing" {
    var mailbox = Mailbox{};
    try std.testing.expectEqual(types.kInvalidArgument, receive(&mailbox, null));

    var message = NoteMessage{};
    const iface = message.asInterface();
    iface.vtable.setMessageID(iface, "unrelated-message");
    try std.testing.expectEqual(types.kResultFalse, receive(&mailbox, iface));

    iface.vtable.setMessageID(iface, message_id);
    const attributes = iface.vtable.getAttributes(iface) orelse return error.MissingAttributes;
    try std.testing.expectEqual(types.kInvalidArgument, receive(&mailbox, iface));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "channel", 0));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "pitch", 60));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setFloat(attributes, "velocity", std.math.nan(f64)));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "pressed", 1));
    try std.testing.expectEqual(types.kInvalidArgument, receive(&mailbox, iface));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setFloat(attributes, "velocity", 0.75));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "pressed", 2));
    try std.testing.expectEqual(types.kInvalidArgument, receive(&mailbox, iface));

    var seen: [128]u64 = @splat(0);
    var commands: [1]Command = undefined;
    try std.testing.expectEqual(@as(usize, 0), mailbox.collect(&seen, &commands));

    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "pressed", 1));
    try std.testing.expectEqual(types.kResultOk, receive(&mailbox, iface));
    try std.testing.expectEqual(@as(usize, 1), mailbox.collect(&seen, &commands));
    try std.testing.expectEqual(@as(i16, 60), commands[0].pitch);
}
