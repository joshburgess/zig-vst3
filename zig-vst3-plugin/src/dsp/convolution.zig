const std = @import("std");
const dsp_fft = @import("fft.zig");
const dsp_resampler = @import("resampler.zig");
const realtime_audit = @import("../realtime_audit.zig");
const serial_generation = @import("../serial_generation.zig");

pub const maximum_channels = 2;

pub const LatencyMode = enum {
    partitioned,
    zero,
};

pub const Routing = enum {
    independent,
    mono,
};

pub const Options = struct {
    latency: LatencyMode = .partitioned,
    routing: Routing = .independent,
};

pub const Metadata = struct {
    generation: u64,
    sample_rate: u32,
    channels: u8,
    frames: usize,

    pub fn validate(self: Metadata, maximum_frames: usize) StageError!void {
        if (self.generation == 0) return error.InvalidGeneration;
        if (self.sample_rate < 8_000 or self.sample_rate > 384_000) return error.InvalidSampleRate;
        if (self.channels == 0 or self.channels > maximum_channels) return error.InvalidChannelCount;
        if (self.frames > maximum_frames) return error.TooManyFrames;
    }

    pub fn valid(self: Metadata, maximum_frames: usize) bool {
        self.validate(maximum_frames) catch return false;
        return true;
    }
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

/// One producer submits jobs while one consumer prepares or discards them.
pub fn PreparationQueue(
    comptime maximum_frames: usize,
    comptime queue_capacity: usize,
) type {
    if (maximum_frames == 0)
        @compileError(
            "PreparationQueue maximum_frames must be positive",
        );
    if (queue_capacity == 0)
        @compileError(
            "PreparationQueue capacity must be positive",
        );

    return struct {
        const Self = @This();
        const State = enum(u8) {
            free,
            writing,
            ready,
            reading,
        };
        const Slot = struct {
            state: std.atomic.Value(u8) =
                std.atomic.Value(u8).init(@intFromEnum(State.free)),
            metadata: Metadata = .{
                .generation = 0,
                .sample_rate = 0,
                .channels = 0,
                .frames = 0,
            },
            samples: [maximum_frames * maximum_channels]f32 =
                @splat(0.0),
        };

        slots: [queue_capacity]Slot =
            @splat(.{}),
        producer_cursor: usize = 0,
        consumer_cursor: usize = 0,
        latest_generation: u64 = 0,

        /// Requires producer and consumer operations to be stopped.
        pub fn valid(self: *const Self) bool {
            self.validateQuiescent() catch return false;
            return true;
        }

        pub fn submit(
            self: *Self,
            metadata: Metadata,
            samples: []const f32,
        ) !void {
            try self.validateProducerCursor();
            try metadata.validate(maximum_frames);
            if (!serial_generation.after(
                metadata.generation,
                self.latest_generation,
            ))
                return error.InvalidGeneration;
            const expected_samples =
                metadata.frames * metadata.channels;
            if (samples.len != expected_samples)
                return error.InvalidChunk;
            for (samples) |sample_value| {
                if (!std.math.isFinite(sample_value))
                    return error.NonFiniteSample;
            }

            const slot = &self.slots[self.producer_cursor];
            if (slot.state.cmpxchgStrong(
                @intFromEnum(State.free),
                @intFromEnum(State.writing),
                .acq_rel,
                .acquire,
            ) != null)
                return error.QueueFull;
            slot.metadata = metadata;
            @memcpy(slot.samples[0..samples.len], samples);
            if (samples.len < slot.samples.len)
                @memset(slot.samples[samples.len..], 0.0);
            slot.state.store(@intFromEnum(State.ready), .release);
            self.producer_cursor =
                (self.producer_cursor + 1) % queue_capacity;
            self.latest_generation = metadata.generation;
        }

        pub fn prepareNext(
            self: *Self,
            comptime partition_size: usize,
            convolver: *PartitionedConvolver(
                maximum_frames,
                partition_size,
            ),
        ) !?u64 {
            try self.validateConsumerCursor();
            const slot = &self.slots[self.consumer_cursor];
            const metadata = try readyMetadata(slot) orelse return null;
            if (slot.state.cmpxchgStrong(
                @intFromEnum(State.ready),
                @intFromEnum(State.reading),
                .acq_rel,
                .acquire,
            ) != null)
                return null;

            const sample_count =
                metadata.frames * metadata.channels;
            var began = false;
            errdefer {
                if (began) _ = convolver.cancel(metadata.generation);
                slot.state.store(@intFromEnum(State.ready), .release);
            }
            try convolver.begin(metadata);
            began = true;
            if (sample_count != 0) {
                try convolver.write(
                    metadata.generation,
                    0,
                    slot.samples[0..sample_count],
                );
            }
            try convolver.commit(metadata.generation);
            slot.state.store(@intFromEnum(State.free), .release);
            self.consumer_cursor =
                (self.consumer_cursor + 1) % queue_capacity;
            return metadata.generation;
        }

        pub fn discardNext(self: *Self) !?u64 {
            try self.validateConsumerCursor();
            const slot = &self.slots[self.consumer_cursor];
            const metadata = try readyMetadata(slot) orelse return null;
            if (slot.state.cmpxchgStrong(
                @intFromEnum(State.ready),
                @intFromEnum(State.free),
                .acq_rel,
                .acquire,
            ) != null)
                return null;
            self.consumer_cursor =
                (self.consumer_cursor + 1) % queue_capacity;
            return metadata.generation;
        }

        pub fn pendingCount(self: *const Self) !usize {
            try self.validateConsumerCursor();
            var result: usize = 0;
            for (&self.slots) |*slot| {
                const state = slot.state.load(.acquire);
                if (state == @intFromEnum(State.ready) or
                    state == @intFromEnum(State.reading))
                {
                    try slot.metadata.validate(maximum_frames);
                    result += 1;
                } else if (state != @intFromEnum(State.free) and
                    state != @intFromEnum(State.writing))
                    return error.InvalidQueueState;
            }
            return result;
        }

        fn validateProducerCursor(self: *const Self) !void {
            if (self.producer_cursor >= queue_capacity)
                return error.InvalidQueueState;
        }

        fn validateConsumerCursor(self: *const Self) !void {
            if (self.consumer_cursor >= queue_capacity)
                return error.InvalidQueueState;
        }

        fn validateQuiescent(self: *const Self) !void {
            try self.validateProducerCursor();
            try self.validateConsumerCursor();

            var ready_count: usize = 0;
            for (&self.slots) |*slot| {
                const state = slot.state.load(.acquire);
                if (state == @intFromEnum(State.free)) continue;
                if (state != @intFromEnum(State.ready))
                    return error.InvalidQueueState;
                ready_count += 1;
            }

            if (ready_count == 0) {
                if (self.producer_cursor != self.consumer_cursor)
                    return error.InvalidQueueState;
                return;
            }
            const expected_ready = if (self.producer_cursor == self.consumer_cursor) queue_capacity else (self.producer_cursor + queue_capacity -
                self.consumer_cursor) % queue_capacity;
            if (ready_count != expected_ready)
                return error.InvalidQueueState;

            var previous_generation: ?u64 = null;
            for (0..ready_count) |offset| {
                const index =
                    (self.consumer_cursor + offset) % queue_capacity;
                const slot = &self.slots[index];
                if (slot.state.load(.acquire) !=
                    @intFromEnum(State.ready))
                {
                    return error.InvalidQueueState;
                }
                try slot.metadata.validate(maximum_frames);
                if (previous_generation) |previous| {
                    if (!serial_generation.after(
                        slot.metadata.generation,
                        previous,
                    )) return error.InvalidGeneration;
                }
                const sample_count =
                    slot.metadata.frames * slot.metadata.channels;
                for (slot.samples[0..sample_count]) |sample_value| {
                    if (!std.math.isFinite(sample_value))
                        return error.NonFiniteSample;
                }
                previous_generation = slot.metadata.generation;
            }
            if (previous_generation) |latest| {
                if (latest != self.latest_generation)
                    return error.InvalidGeneration;
            } else {
                return error.InvalidQueueState;
            }
        }

        fn readyMetadata(slot: *const Slot) !?Metadata {
            const state = slot.state.load(.acquire);
            if (state == @intFromEnum(State.free) or
                state == @intFromEnum(State.writing))
            {
                return null;
            }
            if (state != @intFromEnum(State.ready))
                return error.InvalidQueueState;
            try slot.metadata.validate(maximum_frames);
            return slot.metadata;
        }
    };
}

/// One non-realtime producer stages responses for one audio-thread consumer.
/// Keep the convolver stable until both sides stop; reset is quiescent-only.
pub fn PartitionedConvolver(comptime maximum_frames: usize, comptime partition_size: usize) type {
    if (maximum_frames == 0) @compileError("PartitionedConvolver maximum_frames must be positive");
    if (partition_size < 8 or !std.math.isPowerOfTwo(partition_size)) {
        @compileError("PartitionedConvolver partition_size must be a power of two of at least 8");
    }
    const fft_size = partition_size * 2;
    const Fft = dsp_fft.Transform(f32, fft_size);
    const Complex = Fft.Value;
    const partition_count = (maximum_frames + partition_size - 1) / partition_size;
    const no_slot = std.math.maxInt(u8);

    return struct {
        const Self = @This();

        pub const latency_samples = partition_size;
        pub const frame_capacity = maximum_frames;
        pub const partitions = partition_count;

        const SlotState = enum(u8) { free, writing, ready, reading };

        const Slot = struct {
            state: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(SlotState.free)),
            metadata: Metadata = .{ .generation = 0, .sample_rate = 0, .channels = 0, .frames = 0 },
            received_samples: usize = 0,
            prepared_frames: usize = 0,
            prepared_partitions: usize = 0,
            prepared_sample_rate: u32 = 0,
            raw: [maximum_frames * maximum_channels]f32 = @splat(0.0),
            head: [maximum_channels][partition_size]f32 =
                @splat(@splat(0.0)),
            spectra: [maximum_channels][partition_count][fft_size]Complex = @splat(@splat(@splat(.{}))),
        };

        options: Options = .{},
        slots: [3]Slot = .{ .{}, .{}, .{} },
        pending_slot: std.atomic.Value(u8) = std.atomic.Value(u8).init(no_slot),
        latest_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        active_slot: u8 = no_slot,
        staging_slot: u8 = no_slot,
        target_sample_rate: u32 = 0,
        fft: Fft,
        input_block: [maximum_channels][partition_size]f32 = @splat(@splat(0.0)),
        input_fill: usize = 0,
        input_spectra: [maximum_channels][partition_count][fft_size]Complex = @splat(@splat(@splat(.{}))),
        history_head: usize = 0,
        output_block: [maximum_channels][partition_size]f32 = @splat(@splat(0.0)),
        overlap: [maximum_channels][partition_size]f32 = @splat(@splat(0.0)),
        output_index: usize = 0,
        direct_history: [maximum_channels][partition_size]f32 =
            @splat(@splat(0.0)),
        direct_index: usize = 0,

        pub fn init(target_sample_rate: u32) Self {
            var self: Self = undefined;
            self.initInPlace(target_sample_rate);
            return self;
        }

        pub fn initWithOptions(
            target_sample_rate: u32,
            options: Options,
        ) Self {
            var self: Self = undefined;
            self.initInPlaceWithOptions(target_sample_rate, options);
            return self;
        }

        pub fn initInPlace(
            self: *Self,
            target_sample_rate: u32,
        ) void {
            self.initInPlaceWithOptions(target_sample_rate, .{});
        }

        pub fn initInPlaceWithOptions(
            self: *Self,
            target_sample_rate: u32,
            options: Options,
        ) void {
            @setEvalBranchQuota(
                maximum_channels * partition_count * fft_size * 8 +
                    10_000,
            );
            self.options = options;
            for (&self.slots) |*slot| {
                slot.state = std.atomic.Value(u8).init(
                    @intFromEnum(SlotState.free),
                );
                slot.metadata = .{
                    .generation = 0,
                    .sample_rate = 0,
                    .channels = 0,
                    .frames = 0,
                };
                slot.received_samples = 0;
                slot.prepared_frames = 0;
                slot.prepared_partitions = 0;
                slot.prepared_sample_rate = 0;
                @memset(&slot.raw, 0.0);
                @memset(std.mem.asBytes(&slot.head), 0);
                clearSpectra(&slot.spectra);
            }
            self.pending_slot = std.atomic.Value(u8).init(no_slot);
            self.latest_generation = std.atomic.Value(u64).init(0);
            self.active_slot = no_slot;
            self.staging_slot = no_slot;
            self.target_sample_rate = target_sample_rate;
            self.fft = Fft.init();
            @memset(std.mem.asBytes(&self.input_block), 0);
            self.input_fill = 0;
            clearSpectra(&self.input_spectra);
            self.history_head = 0;
            @memset(std.mem.asBytes(&self.output_block), 0);
            @memset(std.mem.asBytes(&self.overlap), 0);
            self.output_index = 0;
            @memset(std.mem.asBytes(&self.direct_history), 0);
            self.direct_index = 0;
        }

        /// Requires producer, preparation, and audio processing to be stopped.
        pub fn valid(self: *const Self) bool {
            self.validateQuiescent() catch return false;
            return true;
        }

        fn clearSpectra(
            spectra: *[maximum_channels][partition_count][fft_size]Complex,
        ) void {
            for (spectra) |*channel| {
                for (channel) |*partition| {
                    for (partition) |*value| value.* = .{};
                }
            }
        }

        pub fn latencySamples(self: *const Self) usize {
            return switch (self.options.latency) {
                .partitioned => partition_size,
                .zero => 0,
            };
        }

        pub fn setOptions(self: *Self, options: Options) void {
            if (self.options.latency != options.latency or
                self.options.routing != options.routing)
                self.resetProcessing();
            self.options = options;
        }

        pub fn setTargetSampleRate(self: *Self, sample_rate: u32) StageError!void {
            if (sample_rate < 8_000 or sample_rate > 384_000) return error.InvalidSampleRate;
            self.target_sample_rate = sample_rate;
        }

        pub fn reprepareForSampleRate(self: *Self, sample_rate: u32) StageError!bool {
            try self.setTargetSampleRate(sample_rate);
            const pending = self.pending_slot.load(.acquire);
            const source_index = if (slotIndex(pending)) |pending_index|
                if (self.slots[pending_index].state.load(.acquire) == @intFromEnum(SlotState.ready))
                    pending_index
                else
                    self.activeSlotIndex() orelse return false
            else
                self.activeSlotIndex() orelse return false;
            const source = &self.slots[source_index];
            try validatePreparedSlot(source);
            if (source.prepared_sample_rate == sample_rate) return false;

            const destination_index = self.claimFreeSlot() orelse return error.Busy;
            const destination = &self.slots[destination_index];
            destination.metadata = source.metadata;
            destination.received_samples = source.received_samples;
            destination.prepared_frames = 0;
            destination.prepared_partitions = 0;
            destination.prepared_sample_rate = 0;
            @memcpy(destination.raw[0..source.received_samples], source.raw[0..source.received_samples]);
            self.staging_slot = destination_index;
            self.prepare(destination) catch |err| {
                destination.state.store(@intFromEnum(SlotState.free), .release);
                self.staging_slot = no_slot;
                return err;
            };
            destination.state.store(@intFromEnum(SlotState.ready), .release);
            self.staging_slot = no_slot;
            const replaced = self.pending_slot.swap(destination_index, .acq_rel);
            if (slotIndex(replaced)) |replaced_index| {
                if (replaced_index != destination_index) {
                    self.slots[replaced_index].state.store(@intFromEnum(SlotState.free), .release);
                }
            }
            return true;
        }

        pub fn begin(self: *Self, metadata: Metadata) StageError!void {
            if (self.staging_slot != no_slot) return error.Busy;
            try metadata.validate(maximum_frames);
            if (!serial_generation.after(metadata.generation, self.latest_generation.load(.acquire))) {
                return error.InvalidGeneration;
            }
            const slot_index = self.claimFreeSlot() orelse return error.Busy;
            const slot = &self.slots[slot_index];
            slot.metadata = metadata;
            slot.received_samples = 0;
            slot.prepared_frames = 0;
            slot.prepared_partitions = 0;
            slot.prepared_sample_rate = 0;
            self.staging_slot = slot_index;
        }

        pub fn write(self: *Self, generation: u64, sample_offset: usize, samples: []const f32) StageError!void {
            const slot = self.staging() orelse return error.InvalidGeneration;
            if (slot.metadata.generation != generation) return error.InvalidGeneration;
            try slot.metadata.validate(maximum_frames);
            const expected_samples = slot.metadata.frames * slot.metadata.channels;
            if (sample_offset != slot.received_samples or
                samples.len == 0 or
                sample_offset > expected_samples or
                samples.len > expected_samples - sample_offset)
            {
                return error.InvalidChunk;
            }
            for (samples) |sample_value| {
                if (!std.math.isFinite(sample_value)) return error.NonFiniteSample;
            }
            @memcpy(slot.raw[sample_offset .. sample_offset + samples.len], samples);
            slot.received_samples += samples.len;
        }

        pub fn commit(self: *Self, generation: u64) StageError!void {
            const slot_index = self.staging_slot;
            const slot = self.staging() orelse return error.InvalidGeneration;
            if (slot.metadata.generation != generation) return error.InvalidGeneration;
            try slot.metadata.validate(maximum_frames);
            if (slot.received_samples != slot.metadata.frames * slot.metadata.channels) return error.Incomplete;
            try self.prepare(slot);
            slot.state.store(@intFromEnum(SlotState.ready), .release);
            self.staging_slot = no_slot;
            self.latest_generation.store(generation, .release);
            const replaced = self.pending_slot.swap(slot_index, .acq_rel);
            if (slotIndex(replaced)) |replaced_index| {
                if (replaced_index != slot_index) {
                    self.slots[replaced_index].state.store(@intFromEnum(SlotState.free), .release);
                }
            }
        }

        pub fn cancel(self: *Self, generation: u64) bool {
            const slot = self.staging() orelse return false;
            if (slot.metadata.generation != generation) return false;
            slot.state.store(@intFromEnum(SlotState.free), .release);
            self.staging_slot = no_slot;
            return true;
        }

        pub fn clear(self: *Self, generation: u64) StageError!void {
            try self.begin(.{ .generation = generation, .sample_rate = if (self.target_sample_rate == 0) 48_000 else self.target_sample_rate, .channels = 1, .frames = 0 });
            try self.commit(generation);
        }

        pub fn adoptPending(self: *Self) bool {
            _ = realtime_audit.observe(.decoded_audio_adoption);
            const next = self.pending_slot.swap(no_slot, .acq_rel);
            const next_index = slotIndex(next) orelse return false;
            const next_slot = &self.slots[next_index];
            if (next_slot.state.load(.acquire) != @intFromEnum(SlotState.ready)) return false;
            validatePreparedSlot(next_slot) catch {
                next_slot.state.store(@intFromEnum(SlotState.free), .release);
                return false;
            };
            if (self.activeSlotIndex()) |active_index| {
                if (active_index != next_index) {
                    self.slots[active_index].state.store(@intFromEnum(SlotState.free), .release);
                }
            }
            next_slot.state.store(@intFromEnum(SlotState.reading), .release);
            self.active_slot = next;
            self.resetProcessing();
            return true;
        }

        pub fn activeMetadata(self: *const Self) ?Metadata {
            const slot = self.activeSlot() orelse return null;
            return slot.metadata;
        }

        pub fn processFrame(self: *Self, left: f32, right: f32) [2]f32 {
            const finite_left = if (std.math.isFinite(left)) left else 0.0;
            const finite_right = if (std.math.isFinite(right)) right else 0.0;
            const inputs = switch (self.options.routing) {
                .independent => .{ finite_left, finite_right },
                .mono => blk: {
                    const mono =
                        finite_left * 0.5 + finite_right * 0.5;
                    break :blk .{ mono, mono };
                },
            };
            if (!self.processingPreflight()) return .{ 0.0, 0.0 };
            var output = [2]f32{
                self.output_block[0][self.output_index],
                self.output_block[1][self.output_index],
            };
            if (self.options.latency == .zero) {
                const direct = self.processDirect(inputs);
                for (0..maximum_channels) |channel| {
                    output[channel] += direct[channel];
                }
            }
            for (0..maximum_channels) |channel| {
                if (!std.math.isFinite(output[channel]))
                    output[channel] = 0.0;
            }
            self.input_block[0][self.input_fill] = inputs[0];
            self.input_block[1][self.input_fill] = inputs[1];
            self.advanceSample();
            return output;
        }

        pub fn resetProcessing(self: *Self) void {
            self.input_block = @splat(@splat(0.0));
            self.input_fill = 0;
            self.input_spectra = @splat(@splat(@splat(.{})));
            self.history_head = 0;
            self.output_block = @splat(@splat(0.0));
            self.overlap = @splat(@splat(0.0));
            self.output_index = 0;
            self.direct_history = @splat(@splat(0.0));
            self.direct_index = 0;
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
            const index = slotIndex(self.staging_slot) orelse return null;
            const slot = &self.slots[index];
            if (slot.state.load(.acquire) != @intFromEnum(SlotState.writing)) return null;
            return slot;
        }

        fn prepare(self: *Self, slot: *Slot) StageError!void {
            const target_rate = if (self.target_sample_rate == 0) slot.metadata.sample_rate else self.target_sample_rate;
            slot.prepared_sample_rate = target_rate;
            if (slot.metadata.frames == 0) return;
            const IrResampler = dsp_resampler.FiniteImpulseResponseResampler(
                f32,
                maximum_frames,
                maximum_frames,
            );
            const ir_resampler = IrResampler.init(
                slot.metadata.sample_rate,
                target_rate,
            ) catch return error.InvalidSampleRate;
            const destination_frames = ir_resampler.outputFrameCount(
                slot.metadata.frames,
            ) catch return error.TooManyFrames;
            slot.prepared_frames = destination_frames;
            slot.prepared_partitions = (destination_frames + partition_size - 1) / partition_size;
            slot.head = @splat(@splat(0.0));
            slot.spectra = @splat(@splat(@splat(.{})));

            var transform: [fft_size]Complex = @splat(.{});
            var source: [maximum_frames]f32 = undefined;
            var response: [maximum_frames]f32 = undefined;
            for (0..slot.metadata.channels) |channel| {
                for (source[0..slot.metadata.frames], 0..) |*sample, frame|
                    sample.* = slot.raw[frame * slot.metadata.channels + channel];
                ir_resampler.resample(
                    source[0..slot.metadata.frames],
                    response[0..destination_frames],
                ) catch |err| switch (err) {
                    error.InvalidFiniteImpulseResponseShape,
                    error.FiniteImpulseResponseCapacityExceeded,
                    => return error.TooManyFrames,
                    else => return error.NonFiniteSample,
                };
                for (0..slot.prepared_partitions) |partition| {
                    transform = @splat(.{});
                    for (0..partition_size) |offset| {
                        const destination = partition * partition_size + offset;
                        if (destination >= destination_frames) break;
                        const sample_value = response[destination];
                        transform[offset].real = sample_value;
                        if (partition == 0)
                            slot.head[channel][offset] = sample_value;
                    }
                    self.fft.forward(&transform) catch
                        return error.NonFiniteSample;
                    slot.spectra[channel][partition] = transform;
                }
            }
        }

        fn advanceSample(self: *Self) void {
            self.input_fill += 1;
            self.output_index += 1;
            if (self.input_fill < partition_size) return;
            self.input_fill = 0;
            self.output_index = 0;
            self.renderBlock();
        }

        fn processDirect(
            self: *Self,
            inputs: [maximum_channels]f32,
        ) [maximum_channels]f32 {
            for (0..maximum_channels) |channel|
                self.direct_history[channel][self.direct_index] =
                    inputs[channel];
            var output: [maximum_channels]f32 = @splat(0.0);
            if (self.activeSlot()) |slot| {
                const head_frames =
                    @min(slot.prepared_frames, partition_size);
                for (0..maximum_channels) |channel| {
                    const ir_channel = switch (self.options.routing) {
                        .independent => if (slot.metadata.channels == 1)
                            0
                        else
                            channel,
                        .mono => 0,
                    };
                    var sample_value: f32 = 0.0;
                    for (0..head_frames) |tap| {
                        const history =
                            (self.direct_index + partition_size - tap) %
                            partition_size;
                        sample_value +=
                            self.direct_history[channel][history] *
                            slot.head[ir_channel][tap];
                    }
                    output[channel] = if (std.math.isFinite(sample_value))
                        sample_value
                    else
                        0.0;
                }
            }
            self.direct_index =
                (self.direct_index + 1) % partition_size;
            return output;
        }

        fn renderBlock(self: *Self) void {
            const slot = self.activeSlot() orelse {
                self.output_block = @splat(@splat(0.0));
                return;
            };
            if (slot.prepared_partitions == 0) {
                self.output_block = @splat(@splat(0.0));
                return;
            }
            for (0..maximum_channels) |channel| {
                var input_fft: [fft_size]Complex = @splat(.{});
                for (0..partition_size) |index| input_fft[index].real = self.input_block[channel][index];
                self.fft.forward(&input_fft) catch {
                    self.resetProcessing();
                    return;
                };
                self.input_spectra[channel][self.history_head] = input_fft;

                var output_fft: [fft_size]Complex = @splat(.{});
                const ir_channel = switch (self.options.routing) {
                    .independent => if (slot.metadata.channels == 1)
                        0
                    else
                        channel,
                    .mono => 0,
                };
                const first_partition: usize =
                    if (self.options.latency == .zero) 1 else 0;
                for (
                    first_partition..slot.prepared_partitions,
                ) |partition| {
                    const delay = if (self.options.latency == .zero)
                        partition - 1
                    else
                        partition;
                    const history =
                        (self.history_head + partition_count - delay) %
                        partition_count;
                    for (0..fft_size) |bin| {
                        Complex.multiplyAdd(&output_fft[bin], self.input_spectra[channel][history][bin], slot.spectra[ir_channel][partition][bin]);
                    }
                }
                self.fft.inverse(&output_fft) catch {
                    self.resetProcessing();
                    return;
                };
                for (0..partition_size) |index| {
                    self.output_block[channel][index] = output_fft[index].real + self.overlap[channel][index];
                    self.overlap[channel][index] = output_fft[index + partition_size].real;
                }
            }
            self.history_head = (self.history_head + 1) % partition_count;
        }

        fn activeSlot(self: *const Self) ?*const Slot {
            const index = self.activeSlotIndex() orelse return null;
            const slot = &self.slots[index];
            validatePreparedSlot(slot) catch return null;
            return slot;
        }

        fn validatePreparedSlot(slot: *const Slot) StageError!void {
            try slot.metadata.validate(maximum_frames);
            if (slot.received_samples !=
                slot.metadata.frames * slot.metadata.channels)
            {
                return error.Incomplete;
            }
            const expected_partitions =
                slot.prepared_frames / partition_size +
                @intFromBool(slot.prepared_frames % partition_size != 0);
            if (slot.prepared_frames > maximum_frames or
                slot.prepared_partitions != expected_partitions)
            {
                return error.Incomplete;
            }
            if (slot.prepared_sample_rate < 8_000 or
                slot.prepared_sample_rate > 384_000)
            {
                return error.InvalidSampleRate;
            }
        }

        fn processingShapeValid(self: *const Self) bool {
            if (self.input_fill >= partition_size or
                self.output_index != self.input_fill or
                self.history_head >= partition_count or
                self.direct_index >= partition_size)
            {
                return false;
            }
            return switch (self.options.latency) {
                .partitioned => self.direct_index == 0,
                .zero => self.direct_index == self.input_fill,
            };
        }

        fn processingPreflight(self: *const Self) bool {
            if (!self.processingShapeValid()) return false;
            if (self.target_sample_rate != 0 and
                (self.target_sample_rate < 8_000 or
                    self.target_sample_rate > 384_000))
            {
                return false;
            }
            for (0..maximum_channels) |channel| {
                if (!std.math.isFinite(
                    self.output_block[channel][self.output_index],
                )) return false;
            }

            const slot = if (self.active_slot == no_slot)
                null
            else
                self.activeSlot() orelse return false;
            if (self.options.latency == .zero) {
                if (slot) |active| {
                    const head_frames =
                        @min(active.prepared_frames, partition_size);
                    for (0..maximum_channels) |channel| {
                        const ir_channel = switch (self.options.routing) {
                            .independent => if (active.metadata.channels == 1)
                                0
                            else
                                channel,
                            .mono => 0,
                        };
                        for (active.head[ir_channel][0..head_frames]) |
                            sample_value,
                        | {
                            if (!std.math.isFinite(sample_value))
                                return false;
                        }
                        for (self.direct_history[channel]) |sample_value| {
                            if (!std.math.isFinite(sample_value))
                                return false;
                        }
                    }
                }
            }
            if (self.input_fill + 1 == partition_size) {
                validateProcessingSamples(self) catch return false;
                if (slot) |active|
                    validatePreparedSlotContents(active) catch return false;
            }
            return true;
        }

        fn validateQuiescent(self: *const Self) StageError!void {
            if (self.target_sample_rate != 0 and
                (self.target_sample_rate < 8_000 or
                    self.target_sample_rate > 384_000))
            {
                return error.InvalidSampleRate;
            }
            if (!self.processingShapeValid()) return error.Incomplete;

            const pending = self.pending_slot.load(.acquire);
            const pending_index = if (pending == no_slot)
                null
            else
                slotIndex(pending) orelse return error.Incomplete;
            const staging_index = if (self.staging_slot == no_slot)
                null
            else
                slotIndex(self.staging_slot) orelse
                    return error.Incomplete;
            const active_index = if (self.active_slot == no_slot)
                null
            else
                slotIndex(self.active_slot) orelse return error.Incomplete;

            for (&self.slots, 0..) |*slot, index| {
                const state = slot.state.load(.acquire);
                if (state == @intFromEnum(SlotState.free)) {
                    if (pending_index == index or staging_index == index or
                        active_index == index)
                    {
                        return error.Incomplete;
                    }
                    continue;
                }
                if (state == @intFromEnum(SlotState.writing)) {
                    if (staging_index != index) return error.Incomplete;
                    try validateStagingSlot(slot);
                    continue;
                }
                if (state == @intFromEnum(SlotState.ready)) {
                    if (pending_index != index) return error.Incomplete;
                    try validatePreparedSlotContents(slot);
                    continue;
                }
                if (state == @intFromEnum(SlotState.reading)) {
                    if (active_index != index) return error.Incomplete;
                    try validatePreparedSlotContents(slot);
                    continue;
                }
                return error.Incomplete;
            }

            try validateProcessingSamples(self);
        }

        fn validateStagingSlot(slot: *const Slot) StageError!void {
            try slot.metadata.validate(maximum_frames);
            const expected_samples =
                slot.metadata.frames * slot.metadata.channels;
            if (slot.received_samples > expected_samples or
                slot.prepared_frames != 0 or
                slot.prepared_partitions != 0 or
                slot.prepared_sample_rate != 0)
            {
                return error.Incomplete;
            }
            for (slot.raw[0..slot.received_samples]) |sample_value| {
                if (!std.math.isFinite(sample_value))
                    return error.NonFiniteSample;
            }
        }

        fn validatePreparedSlotContents(slot: *const Slot) StageError!void {
            try validatePreparedSlot(slot);
            for (slot.raw[0..slot.received_samples]) |sample_value| {
                if (!std.math.isFinite(sample_value))
                    return error.NonFiniteSample;
            }
            for (0..slot.metadata.channels) |channel| {
                const head_frames =
                    @min(slot.prepared_frames, partition_size);
                for (slot.head[channel][0..head_frames]) |sample_value| {
                    if (!std.math.isFinite(sample_value))
                        return error.NonFiniteSample;
                }
                for (slot.spectra[channel][0..slot.prepared_partitions]) |
                    *spectrum,
                | {
                    for (spectrum) |value| {
                        if (!std.math.isFinite(value.real) or
                            !std.math.isFinite(value.imaginary))
                        {
                            return error.NonFiniteSample;
                        }
                    }
                }
            }
        }

        fn validateProcessingSamples(self: *const Self) StageError!void {
            for (&self.input_block) |*channel| {
                for (channel) |sample_value| {
                    if (!std.math.isFinite(sample_value))
                        return error.NonFiniteSample;
                }
            }
            for (&self.input_spectra) |*channel| {
                for (channel) |*spectrum| {
                    for (spectrum) |value| {
                        if (!std.math.isFinite(value.real) or
                            !std.math.isFinite(value.imaginary))
                        {
                            return error.NonFiniteSample;
                        }
                    }
                }
            }
            for (&self.output_block) |*channel| {
                for (channel) |sample_value| {
                    if (!std.math.isFinite(sample_value))
                        return error.NonFiniteSample;
                }
            }
            for (&self.overlap) |*channel| {
                for (channel) |sample_value| {
                    if (!std.math.isFinite(sample_value))
                        return error.NonFiniteSample;
                }
            }
            for (&self.direct_history) |*channel| {
                for (channel) |sample_value| {
                    if (!std.math.isFinite(sample_value))
                        return error.NonFiniteSample;
                }
            }
        }

        fn activeSlotIndex(self: *const Self) ?usize {
            const index = slotIndex(self.active_slot) orelse return null;
            if (self.slots[index].state.load(.acquire) != @intFromEnum(SlotState.reading)) return null;
            return index;
        }

        fn slotIndex(index: u8) ?usize {
            return if (index < 3) index else null;
        }
    };
}

test "partitioned convolver publishes an impulse without audio-thread preparation" {
    const Convolver = PartitionedConvolver(32, 8);
    var convolver = Convolver.init(48_000);
    try std.testing.expect(convolver.valid());
    try convolver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 3 });
    try convolver.write(1, 0, &.{ 1.0, 0.5, 0.25 });
    try convolver.commit(1);
    try std.testing.expect(convolver.valid());
    try std.testing.expect(convolver.adoptPending());
    try std.testing.expect(convolver.valid());

    var output: [24]f32 = undefined;
    for (&output, 0..) |*sample, index| {
        const input: f32 = if (index == 0) 1.0 else 0.0;
        sample.* = convolver.processFrame(input, input)[0];
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), output[8], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), output[9], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), output[10], 0.0001);
    try std.testing.expect(convolver.valid());
}

test "partitioned convolver isolates stereo IR channels" {
    const Convolver = PartitionedConvolver(32, 8);
    var convolver = Convolver.init(48_000);
    try convolver.begin(.{ .generation = 7, .sample_rate = 48_000, .channels = 2, .frames = 2 });
    try convolver.write(7, 0, &.{ 1.0, 0.0, 0.0, 1.0 });
    try convolver.commit(7);
    _ = convolver.adoptPending();

    var left: [20]f32 = undefined;
    var right: [20]f32 = undefined;
    for (0..left.len) |index| {
        const output = convolver.processFrame(if (index == 0) 1.0 else 0.0, if (index == 0) 1.0 else 0.0);
        left[index] = output[0];
        right[index] = output[1];
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), left[8], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), left[9], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), right[8], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), right[9], 0.0001);
}

test "partitioned convolver zero-latency mode aligns head and tail" {
    const Convolver = PartitionedConvolver(32, 8);
    var convolver = Convolver.initWithOptions(
        48_000,
        .{ .latency = .zero },
    );
    try std.testing.expectEqual(@as(usize, 0), convolver.latencySamples());
    try convolver.begin(.{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 9,
    });
    try convolver.write(
        1,
        0,
        &.{ 0.25, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0 },
    );
    try convolver.commit(1);
    try std.testing.expect(convolver.adoptPending());

    var output: [24]f32 = undefined;
    for (&output, 0..) |*sample, index| {
        sample.* = convolver.processFrame(
            if (index == 0) 1.0 else 0.0,
            0.0,
        )[0];
    }
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        output[0],
        0.0001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        output[1],
        0.0001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        output[8],
        0.0001,
    );
    for (output, 0..) |sample, index| {
        if (index == 0 or index == 1 or index == 8) continue;
        try std.testing.expectApproxEqAbs(
            @as(f32, 0.0),
            sample,
            0.0001,
        );
    }
}

test "partitioned convolver exposes independent and mono routing" {
    const Convolver = PartitionedConvolver(16, 8);
    var convolver = Convolver.initWithOptions(
        48_000,
        .{ .latency = .zero },
    );
    try convolver.begin(.{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 2,
        .frames = 1,
    });
    try convolver.write(1, 0, &.{ 1.0, 2.0 });
    try convolver.commit(1);
    try std.testing.expect(convolver.adoptPending());

    const independent = convolver.processFrame(1.0, 3.0);
    try std.testing.expectEqual(
        @as([2]f32, .{ 1.0, 6.0 }),
        independent,
    );

    convolver.setOptions(.{
        .latency = .zero,
        .routing = .mono,
    });
    const mono = convolver.processFrame(1.0, 3.0);
    try std.testing.expectEqual(
        @as([2]f32, .{ 2.0, 2.0 }),
        mono,
    );

    convolver.setOptions(.{});
    try std.testing.expectEqual(
        @as(usize, 8),
        convolver.latencySamples(),
    );
    try std.testing.expectEqual(
        @as([2]f32, .{ 0.0, 0.0 }),
        convolver.processFrame(
            std.math.floatMax(f32),
            std.math.floatMax(f32),
        ),
    );
}

test "partitioned convolver replaces pending generations without touching the active slot" {
    const Convolver = PartitionedConvolver(16, 8);
    var convolver = Convolver.init(48_000);
    try convolver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 1 });
    try convolver.write(1, 0, &.{1.0});
    try convolver.commit(1);
    _ = convolver.adoptPending();
    try convolver.begin(.{ .generation = 2, .sample_rate = 48_000, .channels = 1, .frames = 1 });
    try convolver.write(2, 0, &.{0.5});
    try convolver.commit(2);
    try convolver.begin(.{ .generation = 3, .sample_rate = 48_000, .channels = 1, .frames = 1 });
    try convolver.write(3, 0, &.{0.25});
    try convolver.commit(3);
    try std.testing.expectEqual(@as(u64, 1), convolver.activeMetadata().?.generation);
    try std.testing.expectError(error.InvalidGeneration, convolver.begin(.{ .generation = 2, .sample_rate = 48_000, .channels = 1, .frames = 1 }));
    try std.testing.expect(convolver.adoptPending());
    try std.testing.expectEqual(@as(u64, 3), convolver.activeMetadata().?.generation);
}

test "partitioned convolver republishes immutable IR data for sample rate changes" {
    const Convolver = PartitionedConvolver(32, 8);
    var convolver = Convolver.init(48_000);
    try convolver.begin(.{ .generation = 5, .sample_rate = 24_000, .channels = 1, .frames = 2 });
    try convolver.write(5, 0, &.{ 1.0, 0.0 });
    try convolver.commit(5);
    try std.testing.expect(convolver.adoptPending());
    try std.testing.expect(try convolver.reprepareForSampleRate(96_000));
    try std.testing.expectEqual(@as(u64, 5), convolver.activeMetadata().?.generation);
    try std.testing.expect(convolver.adoptPending());
    try std.testing.expectEqual(@as(u64, 5), convolver.activeMetadata().?.generation);
    try std.testing.expect(!try convolver.reprepareForSampleRate(96_000));

    var output: [20]f32 = undefined;
    for (&output, 0..) |*sample, index| {
        sample.* = convolver.processFrame(if (index == 0) 1.0 else 0.0, 0.0)[0];
    }
    var response_sum: f32 = 0.0;
    for (output[8..16]) |sample| response_sum += sample;
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        response_sum,
        0.000_01,
    );
    for (output[16..20]) |sample|
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), sample, 0.000_001);
}

test "partitioned convolver rejects malformed staging sequences" {
    const Convolver = PartitionedConvolver(16, 8);
    var convolver = Convolver.init(48_000);
    try std.testing.expectError(error.InvalidGeneration, convolver.begin(.{ .generation = 0, .sample_rate = 48_000, .channels = 1, .frames = 1 }));
    try std.testing.expectError(error.InvalidChannelCount, convolver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 3, .frames = 1 }));
    try convolver.begin(.{ .generation = 2, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try std.testing.expectError(error.InvalidChunk, convolver.write(2, 1, &.{1.0}));
    try std.testing.expectError(error.NonFiniteSample, convolver.write(2, 0, &.{ std.math.nan(f32), 1.0 }));
    try std.testing.expectError(error.NonFiniteSample, convolver.write(2, 0, &.{ std.math.inf(f32), 1.0 }));
    try convolver.write(2, 0, &.{1.0});
    try std.testing.expectError(error.Incomplete, convolver.commit(2));
    try std.testing.expect(convolver.cancel(2));
}

test "partitioned convolver publishes across generation rollover" {
    const Convolver = PartitionedConvolver(16, 8);
    var convolver = Convolver.init(48_000);
    convolver.latest_generation.store(std.math.maxInt(u64), .release);

    try convolver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 1 });
    try convolver.write(1, 0, &.{1.0});
    try convolver.commit(1);
    try std.testing.expect(convolver.adoptPending());
    try std.testing.expectEqual(@as(u64, 1), convolver.activeMetadata().?.generation);

    try std.testing.expectError(
        error.InvalidGeneration,
        convolver.begin(.{ .generation = std.math.maxInt(u64) - 1, .sample_rate = 48_000, .channels = 1, .frames = 1 }),
    );
}

test "partitioned convolver metadata exposes public bounded validation" {
    const valid = Metadata{ .generation = 1, .sample_rate = 48_000, .channels = 2, .frames = 16 };
    try valid.validate(16);
    try std.testing.expect(valid.valid(16));

    var malformed = valid;
    malformed.sample_rate = 7_999;
    try std.testing.expectError(error.InvalidSampleRate, malformed.validate(16));
    malformed = valid;
    malformed.channels = 3;
    try std.testing.expectError(error.InvalidChannelCount, malformed.validate(16));
}

test "partitioned convolver rejects overflowing chunk offsets" {
    const Convolver = PartitionedConvolver(16, 8);
    var convolver = Convolver.init(48_000);
    try convolver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    convolver.slots[convolver.staging_slot].received_samples = std.math.maxInt(usize);
    try std.testing.expectError(
        error.InvalidChunk,
        convolver.write(1, std.math.maxInt(usize), &.{0.5}),
    );
}

test "partitioned convolver recovers after a rejected non-finite chunk" {
    const Convolver = PartitionedConvolver(16, 8);
    var convolver = Convolver.init(48_000);
    try convolver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try std.testing.expectError(error.NonFiniteSample, convolver.write(1, 0, &.{ 1.0, -std.math.inf(f32) }));
    try convolver.write(1, 0, &.{ 1.0, 0.5 });
    try convolver.commit(1);
    try std.testing.expect(convolver.adoptPending());

    var output: [18]f32 = undefined;
    for (&output, 0..) |*sample, index| {
        sample.* = convolver.processFrame(if (index == 0) 1.0 else 0.0, 0.0)[0];
        try std.testing.expect(std.math.isFinite(sample.*));
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), output[8], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), output[9], 0.0001);
}

test "partitioned convolver rejects malformed public slot state" {
    const Convolver = PartitionedConvolver(16, 8);
    var convolver = Convolver.init(48_000);
    try convolver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 1 });
    try convolver.write(1, 0, &.{1.0});
    try convolver.commit(1);
    try std.testing.expect(convolver.adoptPending());

    convolver.active_slot = 3;
    try std.testing.expectEqual(@as(?Metadata, null), convolver.activeMetadata());
    try std.testing.expect(!try convolver.reprepareForSampleRate(96_000));

    try convolver.begin(.{ .generation = 2, .sample_rate = 48_000, .channels = 1, .frames = 1 });
    try convolver.write(2, 0, &.{0.5});
    try convolver.commit(2);
    try std.testing.expect(convolver.adoptPending());
    try std.testing.expectEqual(@as(u64, 2), convolver.activeMetadata().?.generation);

    convolver.pending_slot.store(3, .release);
    try std.testing.expect(!convolver.adoptPending());
    try std.testing.expectEqual(@as(u64, 2), convolver.activeMetadata().?.generation);

    try convolver.begin(.{ .generation = 3, .sample_rate = 48_000, .channels = 1, .frames = 1 });
    try convolver.write(3, 0, &.{0.25});
    try convolver.commit(3);
    const incomplete = convolver.pending_slot.load(.acquire);
    convolver.slots[incomplete].received_samples = 0;
    try std.testing.expect(!convolver.adoptPending());
    try std.testing.expectEqual(@as(u64, 2), convolver.activeMetadata().?.generation);

    convolver.slots[convolver.active_slot].received_samples =
        std.math.maxInt(usize);
    try std.testing.expectError(
        error.Incomplete,
        convolver.reprepareForSampleRate(96_000),
    );
    convolver.slots[convolver.active_slot].received_samples = 1;

    convolver.staging_slot = 3;
    try std.testing.expectError(error.InvalidGeneration, convolver.write(3, 0, &.{0.25}));
    try std.testing.expectError(error.InvalidGeneration, convolver.commit(3));
    try std.testing.expect(!convolver.cancel(3));
}

test "partitioned convolver rejects malformed retained processing state" {
    const Convolver = PartitionedConvolver(16, 8);
    var convolver = Convolver.init(48_000);

    convolver.input_fill = 8;
    convolver.output_index = 8;
    convolver.history_head = Convolver.partitions;
    try std.testing.expect(!convolver.valid());
    const input_block = convolver.input_block;
    const output = convolver.processFrame(std.math.nan(f32), std.math.inf(f32));

    try std.testing.expectEqual(@as([2]f32, .{ 0.0, 0.0 }), output);
    try std.testing.expectEqual(@as(usize, 8), convolver.input_fill);
    try std.testing.expectEqual(@as(usize, 8), convolver.output_index);
    try std.testing.expectEqual(Convolver.partitions, convolver.history_head);
    try std.testing.expectEqual(input_block, convolver.input_block);

    convolver.resetProcessing();
    try std.testing.expect(convolver.valid());
    convolver.output_block[0][convolver.output_index] =
        std.math.nan(f32);
    convolver.output_block[1][convolver.output_index] =
        std.math.inf(f32);
    try std.testing.expect(!convolver.valid());
    const input_fill = convolver.input_fill;
    const output_index = convolver.output_index;
    try std.testing.expectEqual(
        @as([2]f32, .{ 0.0, 0.0 }),
        convolver.processFrame(0.0, 0.0),
    );
    try std.testing.expectEqual(input_fill, convolver.input_fill);
    try std.testing.expectEqual(output_index, convolver.output_index);

    convolver.resetProcessing();
    try convolver.begin(.{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 1,
    });
    try convolver.write(1, 0, &.{1.0});
    try convolver.commit(1);
    try std.testing.expect(convolver.adoptPending());
    convolver.input_fill = 7;
    convolver.output_index = 7;
    convolver.slots[convolver.active_slot].spectra[0][0][0].real =
        std.math.nan(f32);
    try std.testing.expect(!convolver.valid());
    try std.testing.expectEqual(
        @as([2]f32, .{ 0.0, 0.0 }),
        convolver.processFrame(1.0, 0.0),
    );
    try std.testing.expectEqual(@as(usize, 7), convolver.input_fill);
    try std.testing.expectEqual(@as(usize, 7), convolver.output_index);
}

test "convolution preparation queue validates retained ring state" {
    const Queue = PreparationQueue(16, 3);
    var queue = Queue{};
    try std.testing.expect(queue.valid());

    try queue.submit(.{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 2,
    }, &.{ 1.0, 0.5 });
    try queue.submit(.{
        .generation = 2,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 1,
    }, &.{0.25});
    try std.testing.expect(queue.valid());

    queue.slots[queue.consumer_cursor].samples[0] = std.math.nan(f32);
    try std.testing.expect(!queue.valid());
    queue.slots[queue.consumer_cursor].samples[0] = 1.0;
    try std.testing.expect(queue.valid());

    queue.producer_cursor = 3;
    try std.testing.expect(!queue.valid());
    queue.producer_cursor = 2;
    queue.latest_generation = 1;
    try std.testing.expect(!queue.valid());
    queue.latest_generation = 2;
    try std.testing.expect(queue.valid());
}

test "convolution preparation queue publishes ordered jobs" {
    const Queue = PreparationQueue(16, 2);
    const Convolver = PartitionedConvolver(16, 8);
    var queue = Queue{};
    var convolver = Convolver.init(48_000);
    try std.testing.expect(queue.valid());

    try queue.submit(
        .{
            .generation = 1,
            .sample_rate = 48_000,
            .channels = 1,
            .frames = 1,
        },
        &.{1.0},
    );
    try std.testing.expect(queue.valid());
    try queue.submit(
        .{
            .generation = 2,
            .sample_rate = 48_000,
            .channels = 2,
            .frames = 1,
        },
        &.{ 0.5, 0.25 },
    );
    try std.testing.expect(queue.valid());
    try std.testing.expectEqual(
        @as(usize, 2),
        try queue.pendingCount(),
    );
    try std.testing.expectError(
        error.QueueFull,
        queue.submit(
            .{
                .generation = 3,
                .sample_rate = 48_000,
                .channels = 1,
                .frames = 1,
            },
            &.{0.125},
        ),
    );

    try std.testing.expectEqual(
        @as(?u64, 1),
        try queue.prepareNext(8, &convolver),
    );
    try std.testing.expect(queue.valid());
    try std.testing.expect(convolver.adoptPending());
    try std.testing.expectEqual(
        @as(?u64, 2),
        try queue.prepareNext(8, &convolver),
    );
    try std.testing.expect(convolver.adoptPending());
    try std.testing.expectEqual(
        @as(u64, 2),
        convolver.activeMetadata().?.generation,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        try queue.pendingCount(),
    );
}

test "convolution preparation queue retries busy consumers" {
    const Queue = PreparationQueue(16, 1);
    const Convolver = PartitionedConvolver(16, 8);
    var queue = Queue{};
    var convolver = Convolver.init(48_000);
    try queue.submit(
        .{
            .generation = 1,
            .sample_rate = 48_000,
            .channels = 1,
            .frames = 1,
        },
        &.{0.5},
    );
    try convolver.begin(.{
        .generation = 10,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 1,
    });
    try std.testing.expectError(
        error.Busy,
        queue.prepareNext(8, &convolver),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        try queue.pendingCount(),
    );
    try std.testing.expect(convolver.cancel(10));
    try std.testing.expectEqual(
        @as(?u64, 1),
        try queue.prepareNext(8, &convolver),
    );
}

test "convolution preparation queue validates before mutation" {
    const Queue = PreparationQueue(16, 2);
    var queue = Queue{};
    try std.testing.expectError(
        error.InvalidChunk,
        queue.submit(
            .{
                .generation = 1,
                .sample_rate = 48_000,
                .channels = 2,
                .frames = 1,
            },
            &.{1.0},
        ),
    );
    try std.testing.expectError(
        error.NonFiniteSample,
        queue.submit(
            .{
                .generation = 1,
                .sample_rate = 48_000,
                .channels = 1,
                .frames = 1,
            },
            &.{std.math.nan(f32)},
        ),
    );
    try queue.submit(
        .{
            .generation = 1,
            .sample_rate = 48_000,
            .channels = 1,
            .frames = 0,
        },
        &.{},
    );
    try std.testing.expectEqual(
        @as(?u64, 1),
        try queue.discardNext(),
    );
    try std.testing.expectEqual(
        @as(?u64, null),
        try queue.discardNext(),
    );

    queue.consumer_cursor = 2;
    try std.testing.expectError(
        error.InvalidQueueState,
        queue.pendingCount(),
    );
    queue.consumer_cursor = 0;
    queue.producer_cursor = 2;
    try std.testing.expectError(
        error.InvalidQueueState,
        queue.submit(
            .{
                .generation = 2,
                .sample_rate = 48_000,
                .channels = 1,
                .frames = 0,
            },
            &.{},
        ),
    );

    queue.producer_cursor = 1;
    queue.consumer_cursor = 1;
    try queue.submit(
        .{
            .generation = 2,
            .sample_rate = 48_000,
            .channels = 1,
            .frames = 1,
        },
        &.{0.5},
    );
    queue.slots[1].metadata.generation = 0;
    var convolver = PartitionedConvolver(16, 8).init(48_000);
    try std.testing.expectError(
        error.InvalidGeneration,
        queue.pendingCount(),
    );
    try std.testing.expectError(
        error.InvalidGeneration,
        queue.prepareNext(8, &convolver),
    );
    try std.testing.expectError(
        error.InvalidGeneration,
        queue.discardNext(),
    );
    queue.slots[1].metadata.generation = 2;
    try std.testing.expectEqual(
        @as(?u64, 2),
        try queue.discardNext(),
    );
    queue.slots[queue.consumer_cursor].state.store(
        std.math.maxInt(u8),
        .release,
    );
    try std.testing.expectError(
        error.InvalidQueueState,
        queue.pendingCount(),
    );
    try std.testing.expectError(
        error.InvalidQueueState,
        queue.prepareNext(8, &convolver),
    );
    try std.testing.expectError(
        error.InvalidQueueState,
        queue.discardNext(),
    );
    queue.slots[queue.consumer_cursor].state.store(
        @intFromEnum(Queue.State.free),
        .release,
    );
}

test "convolution preparation queue transfers concurrent SPSC jobs" {
    const Queue = PreparationQueue(8, 4);
    const Convolver = PartitionedConvolver(8, 8);
    const Shared = struct {
        queue: Queue = .{},
        convolver: Convolver = Convolver.init(48_000),
        failed: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),

        fn produce(shared: *@This()) void {
            var generation: u64 = 1;
            while (generation <= 100) {
                shared.queue.submit(
                    .{
                        .generation = generation,
                        .sample_rate = 48_000,
                        .channels = 1,
                        .frames = 0,
                    },
                    &.{},
                ) catch |err| switch (err) {
                    error.QueueFull => {
                        std.Thread.yield() catch {};
                        continue;
                    },
                    else => {
                        shared.failed.store(true, .release);
                        return;
                    },
                };
                generation += 1;
            }
        }

        fn consume(shared: *@This()) void {
            var consumed: usize = 0;
            while (consumed < 100) {
                const generation =
                    shared.queue.prepareNext(
                        8,
                        &shared.convolver,
                    ) catch {
                        shared.failed.store(true, .release);
                        return;
                    };
                if (generation == null) {
                    std.Thread.yield() catch {};
                    continue;
                }
                consumed += 1;
            }
        }
    };

    var shared = Shared{};
    const producer = try std.Thread.spawn(
        .{},
        Shared.produce,
        .{&shared},
    );
    const consumer = try std.Thread.spawn(
        .{},
        Shared.consume,
        .{&shared},
    );
    producer.join();
    consumer.join();
    try std.testing.expect(!shared.failed.load(.acquire));
    try std.testing.expectEqual(
        @as(u64, 100),
        shared.convolver.latest_generation.load(.acquire),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        try shared.queue.pendingCount(),
    );
}

test "large convolver processes on a bounded worker stack" {
    const LargeConvolver = PartitionedConvolver(131_072, 512);
    const Worker = struct {
        convolver: *LargeConvolver,
        output: [2]f32 = .{ 1.0, 1.0 },

        fn run(self: *@This()) void {
            self.output = self.convolver.processFrame(0.0, 0.0);
        }
    };

    const convolver = try std.testing.allocator.create(LargeConvolver);
    defer std.testing.allocator.destroy(convolver);
    convolver.initInPlace(48_000);

    var worker = Worker{ .convolver = convolver };
    const thread = try std.Thread.spawn(
        .{ .stack_size = 512 * 1024 },
        Worker.run,
        .{&worker},
    );
    thread.join();

    try std.testing.expectEqual([2]f32{ 0.0, 0.0 }, worker.output);
}
