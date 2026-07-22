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
    if (!validSnapshot(snapshot) or transfer_generation == 0 or transfer_generation > std.math.maxInt(i64)) {
        return types.kInvalidArgument;
    }
    const sample_count = std.math.mul(usize, snapshot.decoded_frames, snapshot.channels) catch return types.kInvalidArgument;
    const generation: i64 = @intCast(transfer_generation);
    if (sendHeader(target, .begin, target_id, generation, snapshot.sample_rate, snapshot.channels, snapshot.decoded_frames) != types.kResultOk) {
        return types.kResultFalse;
    }

    var offset: usize = 0;
    var samples: [samples_per_chunk]f32 = undefined;
    var bytes: [samples_per_chunk * @sizeOf(f32)]u8 = undefined;
    while (offset < sample_count) {
        const requested = @min(samples.len, sample_count - offset);
        const count = importer.copyDecoded(offset, samples[0..requested]);
        if (count == 0 or count > requested or !finiteSamples(samples[0..@min(count, requested)])) {
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
    if (!sameMedia(snapshot, importer.snapshot())) {
        _ = sendScalar(target, .cancel, target_id, generation);
        return types.kResultFalse;
    }
    return sendScalar(target, .commit, target_id, generation);
}

fn validSnapshot(snapshot: anytype) bool {
    return snapshot.import.status == .ready and snapshot.import.generation != 0 and
        snapshot.sample_rate >= 8_000 and snapshot.sample_rate <= 384_000 and
        snapshot.channels > 0 and snapshot.channels <= core.gui_audio_file_importer.maximum_channels and
        snapshot.decoded_frames > 0 and snapshot.decoded_frames <= core.gui_audio_file_importer.maximum_sample_frames and
        snapshot.sample_frames == snapshot.decoded_frames;
}

fn sameMedia(first: anytype, second: anytype) bool {
    return validSnapshot(second) and first.import.generation == second.import.generation and
        first.sample_rate == second.sample_rate and first.channels == second.channels and
        first.sample_frames == second.sample_frames and first.decoded_frames == second.decoded_frames;
}

fn finiteSamples(samples: []const f32) bool {
    for (samples) |sample| {
        if (!std.math.isFinite(sample)) return false;
    }
    return true;
}

pub fn sendClear(peer: ?*ivstmessage.IConnectionPoint, target_id: u32, generation: u64) types.tresult {
    if (generation == 0 or generation > std.math.maxInt(i64)) return types.kInvalidArgument;
    return sendScalar(peer orelse return types.kResultFalse, .clear, target_id, @intCast(generation));
}

pub fn receive(convolver: anytype, expected_target_id: u32, message: ?*ivstmessage.IMessage) types.tresult {
    const iface = message orelse return types.kInvalidArgument;
    if (!ivstmessage.messageIdEquals(iface, message_id)) return types.kResultFalse;
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
            const bounded_sample_rate = std.math.cast(u32, sample_rate) orelse return types.kInvalidArgument;
            const bounded_channels = std.math.cast(u8, channels) orelse return types.kInvalidArgument;
            const bounded_frames = std.math.cast(usize, frames) orelse return types.kInvalidArgument;
            convolver.begin(.{
                .generation = generation,
                .sample_rate = bounded_sample_rate,
                .channels = bounded_channels,
                .frames = bounded_frames,
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
            const offset = std.math.cast(usize, offset_value) orelse return types.kInvalidArgument;
            convolver.write(generation, offset, samples[0..count]) catch return types.kResultFalse;
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

const HostileImporter = struct {
    samples: [samples_per_chunk + 1]f32 = @splat(0.25),
    generation: u64 = 1,
    copies: usize = 0,
    reported_count_delta: usize = 0,
    replace_after_first_copy: bool = false,

    fn snapshot(self: *const HostileImporter) core.gui_audio_file_importer.Snapshot {
        return .{
            .import = .{
                .status = .ready,
                .entry_point = .picker,
                .path_count = 1,
                .completed_units = self.samples.len,
                .total_units = self.samples.len,
                .generation = self.generation,
                .cancellation_pending = false,
            },
            .failure = .none,
            .sample_rate = 48_000,
            .channels = 1,
            .sample_frames = self.samples.len,
            .preview_points = 0,
            .decoded_frames = self.samples.len,
        };
    }

    fn copyDecoded(self: *HostileImporter, offset: usize, output: []f32) usize {
        const count = @min(output.len, self.samples.len - offset);
        @memcpy(output[0..count], self.samples[offset .. offset + count]);
        self.copies += 1;
        if (self.replace_after_first_copy and self.copies == 1) self.generation += 1;
        return count + self.reported_count_delta;
    }
};

test "IR transport rejects invalid callback lengths and non-finite samples" {
    const Convolver = core.gui_ir_convolution.PartitionedConvolver(samples_per_chunk + 8, 8);
    const ReceiverConfig = struct {
        var convolver = Convolver.init(48_000);

        pub fn notify(_: anytype, message: ?*ivstmessage.IMessage) types.tresult {
            return receive(&convolver, 11, message);
        }
    };
    const Receiver = vst_message.ConnectionPoint(ReceiverConfig);
    var receiver = Receiver{};

    var oversized = HostileImporter{ .reported_count_delta = 1 };
    try std.testing.expectEqual(types.kResultFalse, sendDecodedGeneration(receiver.asInterface(), 11, 1, &oversized));
    try std.testing.expectEqual(@as(?core.gui_ir_convolution.Metadata, null), ReceiverConfig.convolver.activeMetadata());

    var non_finite = HostileImporter{};
    non_finite.samples[17] = std.math.nan(f32);
    try std.testing.expectEqual(types.kResultFalse, sendDecodedGeneration(receiver.asInterface(), 11, 2, &non_finite));
    try std.testing.expectEqual(@as(?core.gui_ir_convolution.Metadata, null), ReceiverConfig.convolver.activeMetadata());
}

test "IR transport cancels a source replaced during publication" {
    const Convolver = core.gui_ir_convolution.PartitionedConvolver(samples_per_chunk + 8, 8);
    const ReceiverConfig = struct {
        var convolver = Convolver.init(48_000);

        pub fn notify(_: anytype, message: ?*ivstmessage.IMessage) types.tresult {
            return receive(&convolver, 12, message);
        }
    };
    const Receiver = vst_message.ConnectionPoint(ReceiverConfig);
    var receiver = Receiver{};
    var importer = HostileImporter{ .replace_after_first_copy = true };

    try std.testing.expectEqual(types.kResultFalse, sendDecodedGeneration(receiver.asInterface(), 12, 1, &importer));
    try std.testing.expectEqual(@as(usize, 2), importer.copies);
    try std.testing.expectEqual(@as(?core.gui_ir_convolution.Metadata, null), ReceiverConfig.convolver.activeMetadata());
}

test "IR transport rejects attributes outside receiver integer widths" {
    const Convolver = core.gui_ir_convolution.PartitionedConvolver(16, 8);
    var convolver = Convolver.init(48_000);
    var message = TransportMessage{};
    const iface = message.asInterface();
    iface.vtable.setMessageID(iface, message_id);
    const attributes = iface.vtable.getAttributes(iface) orelse return error.MissingAttributes;
    try std.testing.expect(setCommon(attributes, .begin, 14, 1));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "sample-rate", 48_000));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "channels", 256));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "frames", 1));
    try std.testing.expectEqual(types.kInvalidArgument, receive(&convolver, 14, iface));
    try std.testing.expect(!convolver.cancel(1));

    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "sample-rate", std.math.maxInt(i64)));
    try std.testing.expectEqual(types.kResultOk, attributes.vtable.setInt(attributes, "channels", 1));
    try std.testing.expectEqual(types.kInvalidArgument, receive(&convolver, 14, iface));
    try std.testing.expect(!convolver.cancel(1));
}

test "IR transport recovers after hostile receiver chunks" {
    const Store = core.gui_audio_sample_store.Store(16);
    var store = Store{};
    var begin_message = TransportMessage{};
    const begin_iface = begin_message.asInterface();
    begin_iface.vtable.setMessageID(begin_iface, message_id);
    const begin_attributes = begin_iface.vtable.getAttributes(begin_iface) orelse return error.MissingAttributes;

    try std.testing.expect(setCommon(begin_attributes, .begin, 15, 1));
    try std.testing.expectEqual(types.kResultOk, begin_attributes.vtable.setInt(begin_attributes, "sample-rate", 48_000));
    try std.testing.expectEqual(types.kResultOk, begin_attributes.vtable.setInt(begin_attributes, "channels", 1));
    try std.testing.expectEqual(types.kResultOk, begin_attributes.vtable.setInt(begin_attributes, "frames", 2));
    try std.testing.expectEqual(types.kResultOk, receive(&store, 15, begin_iface));

    var bytes: [2 * @sizeOf(f32)]u8 = undefined;
    encodeSamples(&.{ 1.0, 0.5 }, &bytes);
    var chunk_message = TransportMessage{};
    const chunk_iface = chunk_message.asInterface();
    chunk_iface.vtable.setMessageID(chunk_iface, message_id);
    const chunk_attributes = chunk_iface.vtable.getAttributes(chunk_iface) orelse return error.MissingAttributes;
    try std.testing.expect(setCommon(chunk_attributes, .chunk, 15, 1));
    try std.testing.expectEqual(types.kResultOk, chunk_attributes.vtable.setInt(chunk_attributes, "offset", std.math.maxInt(i64)));
    try std.testing.expectEqual(types.kResultOk, chunk_attributes.vtable.setBinary(chunk_attributes, "samples", bytes[0..4].ptr, 4));
    try std.testing.expectEqual(types.kResultFalse, receive(&store, 15, chunk_iface));

    encodeSamples(&.{ std.math.nan(f32), 0.5 }, &bytes);
    try std.testing.expectEqual(types.kResultOk, chunk_attributes.vtable.setInt(chunk_attributes, "offset", 0));
    try std.testing.expectEqual(types.kResultOk, chunk_attributes.vtable.setBinary(chunk_attributes, "samples", &bytes, bytes.len));
    try std.testing.expectEqual(types.kResultFalse, receive(&store, 15, chunk_iface));

    encodeSamples(&.{ 1.0, 0.5 }, &bytes);
    try std.testing.expectEqual(types.kResultOk, chunk_attributes.vtable.setBinary(chunk_attributes, "samples", &bytes, bytes.len));
    try std.testing.expectEqual(types.kResultOk, receive(&store, 15, chunk_iface));

    var commit_message = TransportMessage{};
    const commit_iface = commit_message.asInterface();
    commit_iface.vtable.setMessageID(commit_iface, message_id);
    const commit_attributes = commit_iface.vtable.getAttributes(commit_iface) orelse return error.MissingAttributes;
    try std.testing.expect(setCommon(commit_attributes, .commit, 15, 1));
    try std.testing.expectEqual(types.kResultOk, receive(&store, 15, commit_iface));
    try std.testing.expect(store.adoptPending());
    try std.testing.expectEqual(@as(u64, 1), store.activeMetadata().?.generation);
}

test "IR transport rejects unrelated routing without disturbing staging" {
    const Store = core.gui_audio_sample_store.Store(16);
    var store = Store{};
    var begin_message = TransportMessage{};
    const begin_iface = begin_message.asInterface();
    begin_iface.vtable.setMessageID(begin_iface, message_id);
    const begin_attributes = begin_iface.vtable.getAttributes(begin_iface) orelse return error.MissingAttributes;
    try std.testing.expect(setCommon(begin_attributes, .begin, 16, 1));
    try std.testing.expectEqual(types.kResultOk, begin_attributes.vtable.setInt(begin_attributes, "sample-rate", 48_000));
    try std.testing.expectEqual(types.kResultOk, begin_attributes.vtable.setInt(begin_attributes, "channels", 1));
    try std.testing.expectEqual(types.kResultOk, begin_attributes.vtable.setInt(begin_attributes, "frames", 1));
    try std.testing.expectEqual(types.kResultOk, receive(&store, 16, begin_iface));

    var unrelated_message = TransportMessage{};
    const unrelated_iface = unrelated_message.asInterface();
    unrelated_iface.vtable.setMessageID(unrelated_iface, "unrelated-message");
    try std.testing.expectEqual(types.kResultFalse, receive(&store, 16, unrelated_iface));

    var routed_message = TransportMessage{};
    const routed_iface = routed_message.asInterface();
    routed_iface.vtable.setMessageID(routed_iface, message_id);
    const routed_attributes = routed_iface.vtable.getAttributes(routed_iface) orelse return error.MissingAttributes;
    try std.testing.expect(setCommon(routed_attributes, .commit, 17, 1));
    try std.testing.expectEqual(types.kInvalidArgument, receive(&store, 16, routed_iface));
    try std.testing.expectEqual(types.kResultOk, routed_attributes.vtable.setInt(routed_attributes, "target", 16));
    try std.testing.expectEqual(types.kResultOk, routed_attributes.vtable.setInt(routed_attributes, "operation", 99));
    try std.testing.expectEqual(types.kInvalidArgument, receive(&store, 16, routed_iface));

    var chunk_message = TransportMessage{};
    const chunk_iface = chunk_message.asInterface();
    chunk_iface.vtable.setMessageID(chunk_iface, message_id);
    const chunk_attributes = chunk_iface.vtable.getAttributes(chunk_iface) orelse return error.MissingAttributes;
    try std.testing.expect(setCommon(chunk_attributes, .chunk, 16, 1));
    try std.testing.expectEqual(types.kResultOk, chunk_attributes.vtable.setInt(chunk_attributes, "offset", 0));
    var bytes: [@sizeOf(f32)]u8 = undefined;
    encodeSamples(&.{0.25}, &bytes);
    try std.testing.expectEqual(types.kResultOk, chunk_attributes.vtable.setBinary(chunk_attributes, "samples", &bytes, bytes.len));
    try std.testing.expectEqual(types.kResultOk, receive(&store, 16, chunk_iface));

    try std.testing.expectEqual(types.kResultOk, routed_attributes.vtable.setInt(routed_attributes, "operation", @intFromEnum(Operation.commit)));
    try std.testing.expectEqual(types.kResultOk, receive(&store, 16, routed_iface));
    try std.testing.expect(store.adoptPending());
    try std.testing.expectEqual(@as(u64, 1), store.activeMetadata().?.generation);
}
