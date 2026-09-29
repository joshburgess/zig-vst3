const std = @import("std");
const midi1 = @import("midi1.zig");

pub const Event = struct {
    channel_index: u8,
    parameter_number: u14,
    value_msb: u7,
    value_lsb: ?u7,

    pub fn value(self: Event) u14 {
        return (@as(u14, self.value_msb) << 7) | (self.value_lsb orelse 0);
    }
};

const ChannelState = struct {
    parameter_msb: ?u7 = null,
    parameter_lsb: ?u7 = null,
    value_msb: ?u7 = null,

    fn parameterNumber(self: ChannelState) ?u14 {
        const msb = self.parameter_msb orelse return null;
        const lsb = self.parameter_lsb orelse return null;
        if (msb == 127 and lsb == 127) return null;
        return (@as(u14, msb) << 7) | lsb;
    }
};

pub const Decoder = struct {
    channels: [16]ChannelState = [_]ChannelState{.{}} ** 16,

    pub fn reset(self: *Decoder) void {
        self.* = .{};
    }

    pub fn resetChannel(self: *Decoder, channel_index: u8) !void {
        if (channel_index >= self.channels.len) return error.InvalidMidiChannel;
        self.channels[channel_index] = .{};
    }

    pub fn push(self: *Decoder, message: midi1.Message) !?Event {
        if (!message.valid()) return error.InvalidMidiMessage;
        if (message.kind() != .control_change) return null;

        const channel_index = message.channel() orelse
            return error.InvalidMidiMessage;
        const controller = message.data1() orelse
            return error.InvalidMidiMessage;
        const data = message.data2() orelse
            return error.InvalidMidiMessage;
        const value: u7 = @intCast(data);
        const state = &self.channels[channel_index];

        return switch (controller) {
            101 => selectParameter(state, true, value),
            100 => selectParameter(state, false, value),
            99, 98 => resetForNrpn(state),
            6 => dataEntryMsb(state, channel_index, value),
            38 => dataEntryLsb(state, channel_index, value),
            121 => resetControllerState(state),
            else => null,
        };
    }
};

pub fn coarseMessages(channel_index: u8, parameter_number: u14, value: u7) ![3]midi1.Message {
    return .{
        try midi1.Message.controlChange(channel_index, 101, @intCast(parameter_number >> 7)),
        try midi1.Message.controlChange(channel_index, 100, @intCast(parameter_number & 0x7F)),
        try midi1.Message.controlChange(channel_index, 6, value),
    };
}

pub fn fineMessages(
    channel_index: u8,
    parameter_number: u14,
    value_msb: u7,
    value_lsb: u7,
) ![4]midi1.Message {
    return .{
        try midi1.Message.controlChange(channel_index, 101, @intCast(parameter_number >> 7)),
        try midi1.Message.controlChange(channel_index, 100, @intCast(parameter_number & 0x7F)),
        try midi1.Message.controlChange(channel_index, 6, value_msb),
        try midi1.Message.controlChange(channel_index, 38, value_lsb),
    };
}

pub fn nullSelectionMessages(channel_index: u8) ![2]midi1.Message {
    return .{
        try midi1.Message.controlChange(channel_index, 101, 127),
        try midi1.Message.controlChange(channel_index, 100, 127),
    };
}

fn selectParameter(state: *ChannelState, msb: bool, value: u7) ?Event {
    if (msb) {
        state.parameter_msb = value;
    } else {
        state.parameter_lsb = value;
    }
    state.value_msb = null;
    return null;
}

fn resetForNrpn(state: *ChannelState) ?Event {
    state.* = .{};
    return null;
}

fn resetControllerState(state: *ChannelState) ?Event {
    state.* = .{};
    return null;
}

fn dataEntryMsb(state: *ChannelState, channel_index: u8, value: u7) ?Event {
    const parameter_number = state.parameterNumber() orelse return null;
    state.value_msb = value;
    return .{
        .channel_index = channel_index,
        .parameter_number = parameter_number,
        .value_msb = value,
        .value_lsb = null,
    };
}

fn dataEntryLsb(state: *ChannelState, channel_index: u8, value: u7) ?Event {
    const parameter_number = state.parameterNumber() orelse return null;
    const value_msb = state.value_msb orelse return null;
    return .{
        .channel_index = channel_index,
        .parameter_number = parameter_number,
        .value_msb = value_msb,
        .value_lsb = value,
    };
}

test "RPN decoder emits MSB and optional LSB data entry" {
    var decoder = Decoder{};
    try std.testing.expect((try decoder.push(try midi1.Message.controlChange(2, 101, 1))) == null);
    try std.testing.expect((try decoder.push(try midi1.Message.controlChange(2, 100, 2))) == null);

    const coarse = (try decoder.push(try midi1.Message.controlChange(2, 6, 3))).?;
    try std.testing.expectEqual(@as(u8, 2), coarse.channel_index);
    try std.testing.expectEqual(@as(u14, 130), coarse.parameter_number);
    try std.testing.expectEqual(@as(u14, 384), coarse.value());
    try std.testing.expect(coarse.value_lsb == null);

    const fine = (try decoder.push(try midi1.Message.controlChange(2, 38, 4))).?;
    try std.testing.expectEqual(@as(u14, 388), fine.value());
    try std.testing.expectEqual(@as(?u7, 4), fine.value_lsb);

    const repeated = (try decoder.push(try midi1.Message.controlChange(2, 6, 5))).?;
    try std.testing.expectEqual(@as(u7, 5), repeated.value_msb);
}

test "RPN decoder clears null selections NRPN selections and controller resets" {
    var decoder = Decoder{};
    _ = try decoder.push(try midi1.Message.controlChange(0, 101, 127));
    _ = try decoder.push(try midi1.Message.controlChange(0, 100, 127));
    try std.testing.expect((try decoder.push(try midi1.Message.controlChange(0, 6, 1))) == null);

    _ = try decoder.push(try midi1.Message.controlChange(0, 101, 0));
    _ = try decoder.push(try midi1.Message.controlChange(0, 100, 6));
    _ = try decoder.push(try midi1.Message.controlChange(0, 99, 0));
    try std.testing.expect((try decoder.push(try midi1.Message.controlChange(0, 6, 2))) == null);

    _ = try decoder.push(try midi1.Message.controlChange(0, 101, 0));
    _ = try decoder.push(try midi1.Message.controlChange(0, 100, 6));
    _ = try decoder.push(try midi1.Message.controlChange(0, 121, 0));
    try std.testing.expect((try decoder.push(try midi1.Message.controlChange(0, 6, 3))) == null);
    try std.testing.expect((try decoder.push(try midi1.Message.noteOn(0, 60, 100))) == null);
}

test "RPN decoder keeps selection state isolated by channel" {
    var decoder = Decoder{};
    _ = try decoder.push(try midi1.Message.controlChange(0, 101, 0));
    _ = try decoder.push(try midi1.Message.controlChange(0, 100, 6));
    try std.testing.expect((try decoder.push(try midi1.Message.controlChange(1, 6, 7))) == null);
    const event = (try decoder.push(try midi1.Message.controlChange(0, 6, 8))).?;
    try std.testing.expectEqual(@as(u8, 0), event.channel_index);
}

test "RPN message helpers round trip coarse fine and null selections" {
    var decoder = Decoder{};
    const coarse = try coarseMessages(3, 130, 5);
    for (coarse[0..2]) |message| {
        try std.testing.expect((try decoder.push(message)) == null);
    }
    const coarse_event = (try decoder.push(coarse[2])).?;
    try std.testing.expectEqual(@as(u14, 130), coarse_event.parameter_number);
    try std.testing.expectEqual(@as(u14, 640), coarse_event.value());

    const fine = try fineMessages(3, 7, 8, 9);
    for (fine[0..3]) |message| {
        _ = try decoder.push(message);
    }
    const fine_event = (try decoder.push(fine[3])).?;
    try std.testing.expectEqual(@as(u14, 7), fine_event.parameter_number);
    try std.testing.expectEqual(@as(u14, 1_033), fine_event.value());

    const null_messages = try nullSelectionMessages(3);
    for (null_messages) |message| {
        _ = try decoder.push(message);
    }
    try std.testing.expect((try decoder.push(try midi1.Message.controlChange(3, 6, 1))) == null);
    try std.testing.expectError(error.InvalidMidiChannel, decoder.resetChannel(16));
}
