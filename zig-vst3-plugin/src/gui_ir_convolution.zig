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
    Incomplete,
};

const Complex = struct {
    real: f32 = 0.0,
    imaginary: f32 = 0.0,

    fn multiplyAdd(target: *Complex, left: Complex, right: Complex) void {
        target.real += left.real * right.real - left.imaginary * right.imaginary;
        target.imaginary += left.real * right.imaginary + left.imaginary * right.real;
    }
};

pub fn PartitionedConvolver(comptime maximum_frames: usize, comptime partition_size: usize) type {
    if (maximum_frames == 0) @compileError("PartitionedConvolver maximum_frames must be positive");
    if (partition_size < 8 or !std.math.isPowerOfTwo(partition_size)) {
        @compileError("PartitionedConvolver partition_size must be a power of two of at least 8");
    }
    const fft_size = partition_size * 2;
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
            spectra: [maximum_channels][partition_count][fft_size]Complex = @splat(@splat(@splat(.{}))),
        };

        slots: [3]Slot = .{ .{}, .{}, .{} },
        pending_slot: std.atomic.Value(u8) = std.atomic.Value(u8).init(no_slot),
        latest_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        active_slot: u8 = no_slot,
        staging_slot: u8 = no_slot,
        target_sample_rate: u32 = 0,
        twiddle_forward: [fft_size / 2]Complex = undefined,
        twiddle_inverse: [fft_size / 2]Complex = undefined,
        input_block: [maximum_channels][partition_size]f32 = @splat(@splat(0.0)),
        input_fill: usize = 0,
        input_spectra: [maximum_channels][partition_count][fft_size]Complex = @splat(@splat(@splat(.{}))),
        history_head: usize = 0,
        output_block: [maximum_channels][partition_size]f32 = @splat(@splat(0.0)),
        overlap: [maximum_channels][partition_size]f32 = @splat(@splat(0.0)),
        output_index: usize = 0,

        pub fn init(target_sample_rate: u32) Self {
            var self: Self = undefined;
            self.initInPlace(target_sample_rate);
            return self;
        }

        pub fn initInPlace(self: *Self, target_sample_rate: u32) void {
            self.* = .{ .target_sample_rate = target_sample_rate };
            for (0..fft_size / 2) |index| {
                const angle = std.math.tau * @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(fft_size));
                self.twiddle_forward[index] = .{ .real = @cos(angle), .imaginary = -@sin(angle) };
                self.twiddle_inverse[index] = .{ .real = @cos(angle), .imaginary = @sin(angle) };
            }
        }

        pub fn setTargetSampleRate(self: *Self, sample_rate: u32) StageError!void {
            if (sample_rate < 8_000 or sample_rate > 384_000) return error.InvalidSampleRate;
            self.target_sample_rate = sample_rate;
        }

        pub fn reprepareForSampleRate(self: *Self, sample_rate: u32) StageError!bool {
            try self.setTargetSampleRate(sample_rate);
            const pending = self.pending_slot.load(.acquire);
            const source_index = if (pending != no_slot and self.slots[pending].state.load(.acquire) == @intFromEnum(SlotState.ready))
                pending
            else
                self.active_slot;
            if (source_index == no_slot) return false;
            const source = &self.slots[source_index];
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
            if (replaced != no_slot) self.slots[replaced].state.store(@intFromEnum(SlotState.free), .release);
            return true;
        }

        pub fn begin(self: *Self, metadata: Metadata) StageError!void {
            if (self.staging_slot != no_slot) return error.Busy;
            try validateMetadata(metadata);
            if (metadata.generation <= self.latest_generation.load(.acquire)) return error.InvalidGeneration;
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
            const expected_samples = slot.metadata.frames * slot.metadata.channels;
            if (sample_offset != slot.received_samples or samples.len == 0 or sample_offset + samples.len > expected_samples) {
                return error.InvalidChunk;
            }
            @memcpy(slot.raw[sample_offset .. sample_offset + samples.len], samples);
            slot.received_samples += samples.len;
        }

        pub fn commit(self: *Self, generation: u64) StageError!void {
            const slot_index = self.staging_slot;
            const slot = self.staging() orelse return error.InvalidGeneration;
            if (slot.metadata.generation != generation) return error.InvalidGeneration;
            if (slot.received_samples != slot.metadata.frames * slot.metadata.channels) return error.Incomplete;
            try self.prepare(slot);
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
            try self.begin(.{ .generation = generation, .sample_rate = if (self.target_sample_rate == 0) 48_000 else self.target_sample_rate, .channels = 1, .frames = 0 });
            try self.commit(generation);
        }

        pub fn adoptPending(self: *Self) bool {
            _ = realtime_audit.observe(.decoded_audio_adoption);
            const next = self.pending_slot.swap(no_slot, .acq_rel);
            if (next == no_slot) return false;
            const next_slot = &self.slots[next];
            if (next_slot.state.load(.acquire) != @intFromEnum(SlotState.ready)) return false;
            if (self.active_slot != no_slot) self.slots[self.active_slot].state.store(@intFromEnum(SlotState.free), .release);
            next_slot.state.store(@intFromEnum(SlotState.reading), .release);
            self.active_slot = next;
            self.resetProcessing();
            return true;
        }

        pub fn activeMetadata(self: *const Self) ?Metadata {
            if (self.active_slot == no_slot) return null;
            return self.slots[self.active_slot].metadata;
        }

        pub fn processFrame(self: *Self, left: f32, right: f32) [2]f32 {
            const output = .{ self.output_block[0][self.output_index], self.output_block[1][self.output_index] };
            self.input_block[0][self.input_fill] = left;
            self.input_block[1][self.input_fill] = right;
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

        fn prepare(self: *Self, slot: *Slot) StageError!void {
            const target_rate = if (self.target_sample_rate == 0) slot.metadata.sample_rate else self.target_sample_rate;
            slot.prepared_sample_rate = target_rate;
            if (slot.metadata.frames == 0) return;
            const scaled_frames = @as(u128, slot.metadata.frames) * target_rate;
            const destination_frames: usize = @intCast((scaled_frames + slot.metadata.sample_rate / 2) / slot.metadata.sample_rate);
            if (destination_frames == 0 or destination_frames > maximum_frames) return error.TooManyFrames;
            slot.prepared_frames = destination_frames;
            slot.prepared_partitions = (destination_frames + partition_size - 1) / partition_size;
            slot.spectra = @splat(@splat(@splat(.{})));

            var transform: [fft_size]Complex = @splat(.{});
            for (0..slot.metadata.channels) |channel| {
                for (0..slot.prepared_partitions) |partition| {
                    transform = @splat(.{});
                    for (0..partition_size) |offset| {
                        const destination = partition * partition_size + offset;
                        if (destination >= destination_frames) break;
                        transform[offset].real = resample(slot, channel, destination, destination_frames);
                    }
                    self.fft(&transform, false);
                    slot.spectra[channel][partition] = transform;
                }
            }
        }

        fn resample(slot: *const Slot, channel: usize, destination: usize, destination_frames: usize) f32 {
            if (slot.metadata.frames == 1 or destination_frames == 1) return slot.raw[channel];
            const position = @as(f64, @floatFromInt(destination)) * @as(f64, @floatFromInt(slot.metadata.frames - 1)) /
                @as(f64, @floatFromInt(destination_frames - 1));
            const first: usize = @intFromFloat(@floor(position));
            const second = @min(first + 1, slot.metadata.frames - 1);
            const fraction: f32 = @floatCast(position - @floor(position));
            const channels: usize = slot.metadata.channels;
            const first_sample = slot.raw[first * channels + channel];
            const second_sample = slot.raw[second * channels + channel];
            return first_sample + (second_sample - first_sample) * fraction;
        }

        fn advanceSample(self: *Self) void {
            self.input_fill += 1;
            self.output_index += 1;
            if (self.input_fill < partition_size) return;
            self.input_fill = 0;
            self.output_index = 0;
            self.renderBlock();
        }

        fn renderBlock(self: *Self) void {
            const slot = if (self.active_slot == no_slot) null else &self.slots[self.active_slot];
            if (slot == null or slot.?.prepared_partitions == 0) {
                self.output_block = @splat(@splat(0.0));
                return;
            }
            for (0..maximum_channels) |channel| {
                var input_fft: [fft_size]Complex = @splat(.{});
                for (0..partition_size) |index| input_fft[index].real = self.input_block[channel][index];
                self.fft(&input_fft, false);
                self.input_spectra[channel][self.history_head] = input_fft;

                var output_fft: [fft_size]Complex = @splat(.{});
                const ir_channel = if (slot.?.metadata.channels == 1) 0 else channel;
                for (0..slot.?.prepared_partitions) |partition| {
                    const history = (self.history_head + partition_count - partition) % partition_count;
                    for (0..fft_size) |bin| {
                        Complex.multiplyAdd(&output_fft[bin], self.input_spectra[channel][history][bin], slot.?.spectra[ir_channel][partition][bin]);
                    }
                }
                self.fft(&output_fft, true);
                for (0..partition_size) |index| {
                    self.output_block[channel][index] = output_fft[index].real + self.overlap[channel][index];
                    self.overlap[channel][index] = output_fft[index + partition_size].real;
                }
            }
            self.history_head = (self.history_head + 1) % partition_count;
        }

        fn fft(self: *const Self, values: *[fft_size]Complex, inverse: bool) void {
            var target: usize = 0;
            for (1..fft_size) |index| {
                var bit = fft_size >> 1;
                while (target & bit != 0) : (bit >>= 1) target &= ~bit;
                target |= bit;
                if (index < target) std.mem.swap(Complex, &values[index], &values[target]);
            }
            const twiddles = if (inverse) &self.twiddle_inverse else &self.twiddle_forward;
            var length: usize = 2;
            while (length <= fft_size) : (length *= 2) {
                const stride = fft_size / length;
                var start: usize = 0;
                while (start < fft_size) : (start += length) {
                    for (0..length / 2) |offset| {
                        const even = start + offset;
                        const odd = even + length / 2;
                        const twiddle = twiddles[offset * stride];
                        const odd_value = Complex{
                            .real = values[odd].real * twiddle.real - values[odd].imaginary * twiddle.imaginary,
                            .imaginary = values[odd].real * twiddle.imaginary + values[odd].imaginary * twiddle.real,
                        };
                        values[odd] = .{
                            .real = values[even].real - odd_value.real,
                            .imaginary = values[even].imaginary - odd_value.imaginary,
                        };
                        values[even].real += odd_value.real;
                        values[even].imaginary += odd_value.imaginary;
                    }
                }
            }
            if (inverse) {
                const scale = 1.0 / @as(f32, @floatFromInt(fft_size));
                for (values) |*value| {
                    value.real *= scale;
                    value.imaginary *= scale;
                }
            }
        }
    };
}

test "partitioned convolver publishes an impulse without audio-thread preparation" {
    const Convolver = PartitionedConvolver(32, 8);
    var convolver = Convolver.init(48_000);
    try convolver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 3 });
    try convolver.write(1, 0, &.{ 1.0, 0.5, 0.25 });
    try convolver.commit(1);
    try std.testing.expect(convolver.adoptPending());

    var output: [24]f32 = undefined;
    for (&output, 0..) |*sample, index| {
        const input: f32 = if (index == 0) 1.0 else 0.0;
        sample.* = convolver.processFrame(input, input)[0];
    }
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), output[8], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), output[9], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), output[10], 0.0001);
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
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), output[8], 0.0001);
    try std.testing.expect(output[9] > output[10]);
    try std.testing.expect(output[10] > output[11]);
}

test "partitioned convolver rejects malformed staging sequences" {
    const Convolver = PartitionedConvolver(16, 8);
    var convolver = Convolver.init(48_000);
    try std.testing.expectError(error.InvalidGeneration, convolver.begin(.{ .generation = 0, .sample_rate = 48_000, .channels = 1, .frames = 1 }));
    try std.testing.expectError(error.InvalidChannelCount, convolver.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 3, .frames = 1 }));
    try convolver.begin(.{ .generation = 2, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try std.testing.expectError(error.InvalidChunk, convolver.write(2, 1, &.{1.0}));
    try convolver.write(2, 0, &.{1.0});
    try std.testing.expectError(error.Incomplete, convolver.commit(2));
    try std.testing.expect(convolver.cancel(2));
}
