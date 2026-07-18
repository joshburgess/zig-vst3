const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_message = @import("vst_message.zig");

pub const message_id = "zig-vst3.audio-import";
pub const samples_per_chunk = 1024;

const Operation = enum(i64) {
    begin = 1,
    chunk = 2,
    commit = 3,
    cancel = 4,
    clear = 5,
};

const TransportMessage = vst_message.Message(32, 7, 1, samples_per_chunk * @sizeOf(f32));

pub fn sendDecoded(
    peer: ?*ivstmessage.IConnectionPoint,
    target_id: u32,
    importer: anytype,
) types.tresult {
    const snapshot = importer.snapshot();
    if (snapshot.import.status != .ready or snapshot.decoded_frames == 0 or
        snapshot.sample_frames != snapshot.decoded_frames or snapshot.import.generation > std.math.maxInt(i64))
    {
        return types.kInvalidArgument;
    }
    return sendDecodedGeneration(peer, target_id, snapshot.import.generation, importer);
}

pub fn sendDecodedGeneration(
    peer: ?*ivstmessage.IConnectionPoint,
    target_id: u32,
    transfer_generation: u64,
    importer: anytype,
) types.tresult {
    const target = peer orelse return types.kResultFalse;
    const snapshot = importer.snapshot();
    if (snapshot.import.status != .ready or snapshot.decoded_frames == 0 or
        snapshot.sample_frames != snapshot.decoded_frames or transfer_generation == 0 or
        transfer_generation > std.math.maxInt(i64))
    {
        return types.kInvalidArgument;
    }
    const generation: i64 = @intCast(transfer_generation);
    if (sendHeader(target, .begin, target_id, generation, snapshot.sample_rate, snapshot.channels, snapshot.decoded_frames) != types.kResultOk) {
        return types.kResultFalse;
    }

    const sample_count = snapshot.decoded_frames * snapshot.channels;
    var offset: usize = 0;
    var samples: [samples_per_chunk]f32 = undefined;
    var bytes: [samples_per_chunk * @sizeOf(f32)]u8 = undefined;
    while (offset < sample_count) {
        const count = importer.copyDecoded(offset, samples[0..@min(samples.len, sample_count - offset)]);
        if (count == 0) {
            _ = sendScalar(target, .cancel, target_id, generation);
            return types.kResultFalse;
        }
        encodeSamples(samples[0..count], bytes[0 .. count * @sizeOf(f32)]);
        if (sendChunk(target, target_id, generation, offset, bytes[0 .. count * @sizeOf(f32)]) != types.kResultOk) {
            _ = sendScalar(target, .cancel, target_id, generation);
            return types.kResultFalse;
        }
        offset += count;
    }
    return sendScalar(target, .commit, target_id, generation);
}

pub fn sendClear(peer: ?*ivstmessage.IConnectionPoint, target_id: u32, generation: u64) types.tresult {
    if (generation == 0 or generation > std.math.maxInt(i64)) return types.kInvalidArgument;
    return sendScalar(peer orelse return types.kResultFalse, .clear, target_id, @intCast(generation));
}

pub fn receive(convolver: anytype, expected_target_id: u32, message: ?*ivstmessage.IMessage) types.tresult {
    const iface = message orelse return types.kInvalidArgument;
    if (!std.mem.eql(u8, std.mem.span(iface.vtable.getMessageID(iface)), message_id)) return types.kResultFalse;
    const attributes = iface.vtable.getAttributes(iface) orelse return types.kInvalidArgument;
    var operation_value: i64 = 0;
    var target_value: i64 = 0;
    var generation_value: i64 = 0;
    if (attributes.vtable.getInt(attributes, "operation", &operation_value) != types.kResultOk or
        attributes.vtable.getInt(attributes, "target", &target_value) != types.kResultOk or
        attributes.vtable.getInt(attributes, "generation", &generation_value) != types.kResultOk or
        target_value != expected_target_id or generation_value <= 0)
    {
        return types.kInvalidArgument;
    }
    const operation: Operation = switch (operation_value) {
        1 => .begin,
        2 => .chunk,
        3 => .commit,
        4 => .cancel,
        5 => .clear,
        else => return types.kInvalidArgument,
    };
    const generation: u64 = @intCast(generation_value);
    switch (operation) {
        .begin => {
            var sample_rate: i64 = 0;
            var channels: i64 = 0;
            var frames: i64 = 0;
            if (attributes.vtable.getInt(attributes, "sample-rate", &sample_rate) != types.kResultOk or
                attributes.vtable.getInt(attributes, "channels", &channels) != types.kResultOk or
                attributes.vtable.getInt(attributes, "frames", &frames) != types.kResultOk or
                sample_rate < 0 or channels < 0 or frames < 0)
            {
                return types.kInvalidArgument;
            }
            convolver.begin(.{
                .generation = generation,
                .sample_rate = @intCast(sample_rate),
                .channels = @intCast(channels),
                .frames = @intCast(frames),
            }) catch return types.kResultFalse;
        },
        .chunk => {
            var offset_value: i64 = 0;
            var payload: ?*const anyopaque = null;
            var byte_count: u32 = 0;
            if (attributes.vtable.getInt(attributes, "offset", &offset_value) != types.kResultOk or
                offset_value < 0 or attributes.vtable.getBinary(attributes, "samples", &payload, &byte_count) != types.kResultOk or
                byte_count == 0 or byte_count % @sizeOf(f32) != 0 or byte_count > samples_per_chunk * @sizeOf(f32) or payload == null)
            {
                return types.kInvalidArgument;
            }
            var samples: [samples_per_chunk]f32 = undefined;
            const bytes: [*]const u8 = @ptrCast(payload.?);
            const count = byte_count / @sizeOf(f32);
            decodeSamples(bytes[0..byte_count], samples[0..count]);
            convolver.write(generation, @intCast(offset_value), samples[0..count]) catch return types.kResultFalse;
        },
        .commit => convolver.commit(generation) catch return types.kResultFalse,
        .cancel => {
            if (!convolver.cancel(generation)) return types.kResultFalse;
        },
        .clear => convolver.clear(generation) catch return types.kResultFalse,
    }
    return types.kResultOk;
}

fn sendHeader(
    target: *ivstmessage.IConnectionPoint,
    operation: Operation,
    target_id: u32,
    generation: i64,
    sample_rate: u32,
    channels: u8,
    frames: usize,
) types.tresult {
    if (frames > std.math.maxInt(i64)) return types.kInvalidArgument;
    var message = TransportMessage{};
    const iface = message.asInterface();
    iface.vtable.setMessageID(iface, message_id);
    const attributes = iface.vtable.getAttributes(iface) orelse return types.kResultFalse;
    if (!setCommon(attributes, operation, target_id, generation) or
        attributes.vtable.setInt(attributes, "sample-rate", sample_rate) != types.kResultOk or
        attributes.vtable.setInt(attributes, "channels", channels) != types.kResultOk or
        attributes.vtable.setInt(attributes, "frames", @intCast(frames)) != types.kResultOk)
    {
        return types.kResultFalse;
    }
    return target.vtable.notify(target, iface);
}

fn sendChunk(
    target: *ivstmessage.IConnectionPoint,
    target_id: u32,
    generation: i64,
    offset: usize,
    bytes: []const u8,
) types.tresult {
    if (offset > std.math.maxInt(i64) or bytes.len > std.math.maxInt(u32)) return types.kInvalidArgument;
    var message = TransportMessage{};
    const iface = message.asInterface();
    iface.vtable.setMessageID(iface, message_id);
    const attributes = iface.vtable.getAttributes(iface) orelse return types.kResultFalse;
    if (!setCommon(attributes, .chunk, target_id, generation) or
        attributes.vtable.setInt(attributes, "offset", @intCast(offset)) != types.kResultOk or
        attributes.vtable.setBinary(attributes, "samples", bytes.ptr, @intCast(bytes.len)) != types.kResultOk)
    {
        return types.kResultFalse;
    }
    return target.vtable.notify(target, iface);
}

fn sendScalar(target: *ivstmessage.IConnectionPoint, operation: Operation, target_id: u32, generation: i64) types.tresult {
    var message = TransportMessage{};
    const iface = message.asInterface();
    iface.vtable.setMessageID(iface, message_id);
    const attributes = iface.vtable.getAttributes(iface) orelse return types.kResultFalse;
    if (!setCommon(attributes, operation, target_id, generation)) return types.kResultFalse;
    return target.vtable.notify(target, iface);
}

fn setCommon(attributes: anytype, operation: Operation, target_id: u32, generation: i64) bool {
    return attributes.vtable.setInt(attributes, "operation", @intFromEnum(operation)) == types.kResultOk and
        attributes.vtable.setInt(attributes, "target", target_id) == types.kResultOk and
        attributes.vtable.setInt(attributes, "generation", generation) == types.kResultOk;
}

fn encodeSamples(samples: []const f32, bytes: []u8) void {
    for (samples, 0..) |sample, index| std.mem.writeInt(u32, bytes[index * 4 ..][0..4], @bitCast(sample), .little);
}

fn decodeSamples(bytes: []const u8, samples: []f32) void {
    for (samples, 0..) |*sample, index| sample.* = @bitCast(std.mem.readInt(u32, bytes[index * 4 ..][0..4], .little));
}

test "IR transport stages bounded chunks and commits one generation" {
    const Convolver = core.gui_ir_convolution.PartitionedConvolver(16, 8);
    const ReceiverConfig = struct {
        var convolver = Convolver.init(48_000);

        pub fn notify(_: anytype, message: ?*ivstmessage.IMessage) types.tresult {
            return receive(&convolver, 9, message);
        }
    };
    const Receiver = vst_message.ConnectionPoint(ReceiverConfig);
    var receiver = Receiver{};
    try std.testing.expectEqual(types.kResultOk, sendHeader(receiver.asInterface(), .begin, 9, 4, 48_000, 1, 2));
    var payload: [8]u8 = undefined;
    encodeSamples(&.{ 1.0, 0.5 }, &payload);
    try std.testing.expectEqual(types.kResultOk, sendChunk(receiver.asInterface(), 9, 4, 0, &payload));
    try std.testing.expectEqual(types.kResultOk, sendScalar(receiver.asInterface(), .commit, 9, 4));
    try std.testing.expect(ReceiverConfig.convolver.adoptPending());
    try std.testing.expectEqual(@as(u64, 4), ReceiverConfig.convolver.activeMetadata().?.generation);
}
