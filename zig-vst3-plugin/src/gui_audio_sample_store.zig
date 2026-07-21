const std = @import("std");
const realtime_audit = @import("realtime_audit.zig");

pub const maximum_channels = 2;

pub const Metadata = struct {
    generation: u64,
    sample_rate: u32,
    channels: u8,
    frames: usize,
};

pub const StageError = error{
    Busy,
    InvalidGeneration,
    InvalidSampleRate,
    InvalidChannelCount,
    TooManyFrames,
    InvalidChunk,
    NonFiniteSample,
    Incomplete,
};

pub fn Store(comptime maximum_frames: usize) type {
    if (maximum_frames == 0) @compileError("sample store capacity must be positive");
    const no_slot = std.math.maxInt(u8);

    return struct {
        const Self = @This();
        const SlotState = enum(u8) { free, writing, ready, reading };

        const Slot = struct {
            state: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(SlotState.free)),
            metadata: Metadata = .{ .generation = 0, .sample_rate = 0, .channels = 0, .frames = 0 },
            received_samples: usize = 0,
            samples: [maximum_frames * maximum_channels]f32 = @splat(0.0),
        };

        slots: [3]Slot = .{ .{}, .{}, .{} },
        pending_slot: std.atomic.Value(u8) = std.atomic.Value(u8).init(no_slot),
        latest_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        active_slot: u8 = no_slot,
        staging_slot: u8 = no_slot,

        pub const frame_capacity = maximum_frames;

        pub fn begin(self: *Self, metadata: Metadata) StageError!void {
            if (self.staging_slot != no_slot) return error.Busy;
            try validateMetadata(metadata);
            if (metadata.generation <= self.latest_generation.load(.acquire)) return error.InvalidGeneration;
            const slot_index = self.claimFreeSlot() orelse return error.Busy;
            const slot = &self.slots[slot_index];
            slot.metadata = metadata;
            slot.received_samples = 0;
            self.staging_slot = slot_index;
        }

        pub fn write(self: *Self, generation: u64, sample_offset: usize, samples: []const f32) StageError!void {
            const slot = self.staging() orelse return error.InvalidGeneration;
            if (slot.metadata.generation != generation) return error.InvalidGeneration;
            const expected_samples = slot.metadata.frames * slot.metadata.channels;
            if (sample_offset != slot.received_samples or samples.len == 0 or sample_offset + samples.len > expected_samples) {
                return error.InvalidChunk;
            }
            for (samples) |sample_value| {
                if (!std.math.isFinite(sample_value)) return error.NonFiniteSample;
            }
            @memcpy(slot.samples[sample_offset .. sample_offset + samples.len], samples);
            slot.received_samples += samples.len;
        }

        pub fn commit(self: *Self, generation: u64) StageError!void {
            const slot_index = self.staging_slot;
            const slot = self.staging() orelse return error.InvalidGeneration;
            if (slot.metadata.generation != generation) return error.InvalidGeneration;
            if (slot.received_samples != slot.metadata.frames * slot.metadata.channels) return error.Incomplete;
            slot.state.store(@intFromEnum(SlotState.ready), .release);
            self.staging_slot = no_slot;
            self.latest_generation.store(generation, .release);
            const replaced = self.pending_slot.swap(slot_index, .acq_rel);
            if (replaced != no_slot) self.slots[replaced].state.store(@intFromEnum(SlotState.free), .release);
        }

        pub fn cancel(self: *Self, generation: u64) bool {
            const slot = self.staging() orelse return false;
            if (slot.metadata.generation != generation) return false;
            slot.state.store(@intFromEnum(SlotState.free), .release);
            self.staging_slot = no_slot;
            return true;
        }

        pub fn clear(self: *Self, generation: u64) StageError!void {
            try self.begin(.{ .generation = generation, .sample_rate = 48_000, .channels = 1, .frames = 0 });
            try self.commit(generation);
        }

        pub fn adoptPending(self: *Self) bool {
            _ = realtime_audit.observe(.decoded_audio_adoption);
            const next = self.pending_slot.swap(no_slot, .acq_rel);
            if (next == no_slot) return false;
            const slot = &self.slots[next];
            if (slot.state.load(.acquire) != @intFromEnum(SlotState.ready)) return false;
            if (self.active_slot != no_slot) self.slots[self.active_slot].state.store(@intFromEnum(SlotState.free), .release);
            slot.state.store(@intFromEnum(SlotState.reading), .release);
            self.active_slot = next;
            return true;
        }

        pub fn activeMetadata(self: *const Self) ?Metadata {
            if (self.active_slot == no_slot) return null;
            return self.slots[self.active_slot].metadata;
        }

        pub fn sample(self: *const Self, channel: usize, position: f64) f32 {
            const metadata = self.activeMetadata() orelse return 0.0;
            if (metadata.frames == 0 or !std.math.isFinite(position)) return 0.0;
            const bounded = std.math.clamp(position, 0.0, @as(f64, @floatFromInt(metadata.frames - 1)));
            const first: usize = @intFromFloat(@floor(bounded));
            const second = @min(first + 1, metadata.frames - 1);
            const fraction: f32 = @floatCast(bounded - @floor(bounded));
            const source_channel = @min(channel, metadata.channels - 1);
            const channels: usize = metadata.channels;
            const first_sample = self.slots[self.active_slot].samples[first * channels + source_channel];
            const second_sample = self.slots[self.active_slot].samples[second * channels + source_channel];
            return first_sample + (second_sample - first_sample) * fraction;
        }

        fn validateMetadata(metadata: Metadata) StageError!void {
            if (metadata.generation == 0) return error.InvalidGeneration;
            if (metadata.sample_rate < 8_000 or metadata.sample_rate > 384_000) return error.InvalidSampleRate;
            if (metadata.channels == 0 or metadata.channels > maximum_channels) return error.InvalidChannelCount;
            if (metadata.frames > maximum_frames) return error.TooManyFrames;
        }

        fn claimFreeSlot(self: *Self) ?u8 {
            for (&self.slots, 0..) |*slot, index| {
                if (slot.state.cmpxchgStrong(@intFromEnum(SlotState.free), @intFromEnum(SlotState.writing), .acq_rel, .acquire) == null) {
                    return @intCast(index);
                }
            }
            return null;
        }

        fn staging(self: *Self) ?*Slot {
            if (self.staging_slot == no_slot) return null;
            return &self.slots[self.staging_slot];
        }
    };
}

test "sample store publishes complete generations atomically" {
    var store = Store(4){};
    try store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 2, .frames = 2 });
    try store.write(1, 0, &.{ 0.0, 0.25, 0.5, 0.75 });
    try std.testing.expectEqual(@as(?Metadata, null), store.activeMetadata());
    try store.commit(1);
    try std.testing.expectEqual(@as(?Metadata, null), store.activeMetadata());
    try std.testing.expect(store.adoptPending());
    try std.testing.expectEqual(@as(usize, 2), store.activeMetadata().?.frames);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), store.sample(0, 0.5), 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), store.sample(1, 0.5), 0.000001);
}

test "sample store adoption is allowed in realtime scope" {
    var store: Store(4) = .{};
    try store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 1 });
    try store.write(1, 0, &.{0.5});
    try store.commit(1);
    const scope = realtime_audit.Scope.enter();
    try std.testing.expect(store.adoptPending());
    const report = scope.leave();
    try std.testing.expect(report.clean());
    try std.testing.expectEqual(@as(u32, 1), report.count(.decoded_audio_adoption));
}

test "sample store rejects stale incomplete and oversized transfers" {
    var store = Store(2){};
    try std.testing.expectError(error.TooManyFrames, store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 3 }));
    try store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try store.write(1, 0, &.{0.5});
    try std.testing.expectError(error.Incomplete, store.commit(1));
    try std.testing.expect(store.cancel(1));
    try store.begin(.{ .generation = 2, .sample_rate = 48_000, .channels = 1, .frames = 1 });
    try store.write(2, 0, &.{0.75});
    try store.commit(2);
    try std.testing.expectError(error.InvalidGeneration, store.begin(.{ .generation = 2, .sample_rate = 48_000, .channels = 1, .frames = 1 }));
}

test "sample store rejects non-finite chunks without advancing the transfer" {
    var store = Store(4){};
    try store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try std.testing.expectError(error.NonFiniteSample, store.write(1, 0, &.{ 0.25, std.math.nan(f32) }));
    try std.testing.expectError(error.Incomplete, store.commit(1));
    try std.testing.expectError(error.NonFiniteSample, store.write(1, 0, &.{ std.math.inf(f32), 0.5 }));
    try store.write(1, 0, &.{ 0.25, 0.5 });
    try store.commit(1);
    try std.testing.expect(store.adoptPending());
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), store.sample(0, 0.0), 0.000001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), store.sample(0, 1.0), 0.000001);
}

test "sample store generated stale callback sequences preserve atomic generations" {
    const seed = 0x57a1_ea00_2026_0720;
    var random_state = std.Random.DefaultPrng.init(seed);
    const random = random_state.random();

    for (0..128) |case_index| {
        var store = Store(16){};
        var last_active_generation: u64 = 0;
        for (0..256) |operation_index| {
            const generation = 1 + random.uintLessThan(u64, 48);
            switch (random.uintLessThan(u8, 6)) {
                0 => store.begin(.{
                    .generation = generation,
                    .sample_rate = if (random.boolean()) 48_000 else 7_999,
                    .channels = if (random.boolean()) 1 else 2,
                    .frames = random.uintLessThan(usize, 20),
                }) catch {},
                1 => {
                    if (store.staging()) |slot| {
                        const expected = slot.metadata.frames * slot.metadata.channels;
                        if (slot.received_samples < expected) {
                            const remaining = expected - slot.received_samples;
                            const count = @min(remaining, 1 + random.uintLessThan(usize, 8));
                            var samples: [8]f32 = undefined;
                            for (samples[0..count]) |*sample| sample.* = random.float(f32) * 2.0 - 1.0;
                            if (random.uintLessThan(u8, 16) == 0) {
                                samples[random.uintLessThan(usize, count)] = if (random.boolean()) std.math.nan(f32) else std.math.inf(f32);
                            }
                            store.write(slot.metadata.generation, slot.received_samples, samples[0..count]) catch {};
                        }
                    } else {
                        store.write(generation, 0, &.{0.0}) catch {};
                    }
                },
                2 => store.commit(generation) catch {},
                3 => _ = store.cancel(generation),
                4 => store.clear(generation) catch {},
                else => _ = store.adoptPending(),
            }
            if (store.activeMetadata()) |active| {
                const valid = active.generation >= last_active_generation and
                    active.generation <= store.latest_generation.load(.acquire) and
                    active.channels > 0 and active.channels <= maximum_channels and
                    active.frames <= Store(16).frame_capacity and
                    std.math.isFinite(store.sample(0, 0.5));
                if (!valid) {
                    std.debug.print("sample store seed={x} case={} operation={} active={} latest={}\n", .{
                        seed,
                        case_index,
                        operation_index,
                        active.generation,
                        store.latest_generation.load(.acquire),
                    });
                    return error.GeneratedSampleStoreInvariantFailed;
                }
                last_active_generation = active.generation;
            }
        }
    }
}
