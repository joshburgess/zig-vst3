const std = @import("std");
const base = @import("../base/types.zig");

pub const kMaxChannelsSupported: base.int32 = 64;

fn cappedStorageLen(len: usize) base.int32 {
    return @intCast(@min(len, @as(usize, @intCast(std.math.maxInt(base.int32)))));
}

fn advancedRingPosition(position: base.int32, frames: base.int32, buffer_size: base.int32) base.int32 {
    if (position < 0 or frames <= 0 or buffer_size <= 0) return position;
    return @intCast(@mod(@as(base.int64, position) + @as(base.int64, frames), @as(base.int64, buffer_size)));
}

pub fn AudioBuffer(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        buffer: []T = &.{},
        max_samples: base.int32 = 0,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.release();
        }

        pub fn resize(self: *Self, max_samples: base.int32) !void {
            if (self.max_samples == max_samples) return;

            if (max_samples <= 0) {
                self.allocator.free(self.buffer);
                self.buffer = &.{};
                self.max_samples = 0;
                return;
            }

            const resized = try self.allocator.realloc(self.buffer, @intCast(max_samples));
            self.buffer = resized;
            self.max_samples = max_samples;
        }

        pub fn clear(self: *Self, num_samples: base.int32) void {
            const count = @min(num_samples, self.max_samples);
            if (count <= 0) return;
            @memset(self.buffer[0..@intCast(count)], 0);
        }

        pub fn getMaxSamples(self: *const Self) base.int32 {
            return self.max_samples;
        }

        pub fn release(self: *Self) void {
            self.allocator.free(self.buffer);
            self.buffer = &.{};
            self.max_samples = 0;
        }

        pub fn clearAll(self: *Self) void {
            if (self.max_samples > 0) self.clear(self.max_samples);
        }

        pub fn ptr(self: *Self) ?[*]T {
            return if (self.buffer.len == 0) null else self.buffer.ptr;
        }
    };
}

pub fn delay(
    comptime T: type,
    sample_frames: base.int32,
    in_stream: [*]const T,
    out_stream: [*]T,
    delay_buffer: [*]T,
    buffer_size: base.int32,
    buffer_in_pos: base.int32,
    buffer_out_pos: base.int32,
) bool {
    if (sample_frames <= 0 or buffer_size <= 0) return false;
    if (buffer_in_pos < 0 or buffer_in_pos >= buffer_size) return false;
    if (buffer_out_pos < 0 or buffer_out_pos >= buffer_size) return false;

    var remain = sample_frames;
    var input_index: base.int32 = 0;
    var output_index: base.int32 = 0;
    var input_pos = buffer_in_pos;
    var output_pos = buffer_out_pos;

    while (remain > 0) {
        var in_frames = if (input_pos > output_pos)
            buffer_size - input_pos
        else
            output_pos - input_pos;
        var out_frames = buffer_size - output_pos;

        if (in_frames > remain) in_frames = remain;
        if (out_frames > in_frames) out_frames = in_frames;

        var index: base.int32 = 0;
        while (index < in_frames) : (index += 1) {
            delay_buffer[@intCast(input_pos + index)] = in_stream[@intCast(input_index + index)];
        }
        index = 0;
        while (index < out_frames) : (index += 1) {
            out_stream[@intCast(output_index + index)] = delay_buffer[@intCast(output_pos + index)];
        }

        input_index += in_frames;
        output_index += out_frames;

        input_pos += in_frames;
        if (input_pos >= buffer_size) input_pos -= buffer_size;
        output_pos += out_frames;
        if (output_pos >= buffer_size) output_pos -= buffer_size;

        if (in_frames > out_frames) {
            const extra_out_frames = in_frames - out_frames;
            index = 0;
            while (index < extra_out_frames) : (index += 1) {
                out_stream[@intCast(output_index + index)] = delay_buffer[@intCast(output_pos + index)];
            }

            output_index += extra_out_frames;
            output_pos += extra_out_frames;
            if (output_pos >= buffer_size) output_pos -= buffer_size;
        }

        remain -= in_frames;
    }

    return true;
}

pub fn Delay(comptime T: type) type {
    return struct {
        buffer: []T,
        buffer_samples: base.int32,
        delay_samples: base.int32,
        in_pos: base.int32 = -1,
        out_pos: base.int32 = -1,

        const Self = @This();

        pub fn init(storage: []T, max_samples_per_block: base.int32, delay_samples: base.int32) Self {
            const storage_samples = cappedStorageLen(storage.len);
            const requested_samples = if (delay_samples > 0 and max_samples_per_block > 0)
                @addWithOverflow(max_samples_per_block, delay_samples)
            else
                .{ 0, 0 };
            const buffer_samples: base.int32 = if (requested_samples[1] == 0)
                @min(requested_samples[0], storage_samples)
            else
                storage_samples;
            const max_delay = @max(buffer_samples -| 1, 0);
            const actual_delay = @min(@max(delay_samples, 0), max_delay);
            return .{
                .buffer = storage[0..@intCast(buffer_samples)],
                .buffer_samples = buffer_samples,
                .delay_samples = actual_delay,
                .in_pos = 0,
                .out_pos = if (actual_delay > 0) buffer_samples - actual_delay else 0,
            };
        }

        pub fn hasDelay(self: *const Self) bool {
            return self.delay_samples > 0;
        }

        pub fn getBufferSamples(self: *const Self) base.int32 {
            return self.buffer_samples;
        }

        pub fn process(self: *Self, src: ?[*]const T, dst: [*]T, num_samples: base.int32, silent_in: bool) bool {
            if (num_samples <= 0) return silent_in;
            var silent_out = false;
            if (self.hasDelay()) {
                if (src) |source| {
                    const buffer_size = self.getBufferSamples();
                    if (!delay(T, num_samples, source, dst, self.buffer.ptr, buffer_size, self.in_pos, self.out_pos)) {
                        var index: base.int32 = 0;
                        while (index < num_samples) : (index += 1) {
                            dst[@intCast(index)] = 0;
                        }
                        return true;
                    }
                    self.in_pos = advancedRingPosition(self.in_pos, num_samples, buffer_size);
                    self.out_pos = advancedRingPosition(self.out_pos, num_samples, buffer_size);
                    return silent_out;
                }
            }

            if (src) |source| {
                if (!silent_in) {
                    var index: base.int32 = 0;
                    while (index < num_samples) : (index += 1) {
                        dst[@intCast(index)] = source[@intCast(index)];
                    }
                } else {
                    var index: base.int32 = 0;
                    while (index < num_samples) : (index += 1) {
                        dst[@intCast(index)] = 0;
                    }
                    silent_out = true;
                }
            } else {
                var index: base.int32 = 0;
                while (index < num_samples) : (index += 1) {
                    dst[@intCast(index)] = 0;
                }
                silent_out = true;
            }
            return silent_out;
        }

        pub fn flush(self: *Self) void {
            var index: base.int32 = 0;
            while (index < self.buffer_samples) : (index += 1) {
                self.buffer[@intCast(index)] = 0;
            }

            self.in_pos = 0;
            self.out_pos = 0;
            if (self.hasDelay()) self.out_pos = self.getBufferSamples() - self.delay_samples;
        }
    };
}

test "delay helper copies through circular buffer" {
    var input = [_]f32{ 1, 2, 3, 4, 5 };
    var output = [_]f32{0} ** 5;
    var buffer = [_]f32{ 10, 20, 30, 40 };
    try @import("std").testing.expect(delay(f32, 5, &input, &output, &buffer, 4, 2, 0));
    try @import("std").testing.expectEqual(@as(f32, 10), output[0]);
    var storage = [_]f32{0} ** 8;
    var processor_delay = Delay(f32).init(&storage, 5, 3);
    processor_delay.flush();
    try @import("std").testing.expectEqual(@as(base.int32, 8), processor_delay.getBufferSamples());
    try @import("std").testing.expectEqual(@as(base.int32, 5), processor_delay.out_pos);
    var audio_buffer = AudioBuffer(f32).init(@import("std").testing.allocator);
    defer audio_buffer.deinit();
    try audio_buffer.resize(4);
    try @import("std").testing.expectEqual(@as(base.int32, 4), audio_buffer.getMaxSamples());
    audio_buffer.buffer[0] = 7;
    audio_buffer.clearAll();
    try @import("std").testing.expectEqual(@as(f32, 0), audio_buffer.buffer[0]);
    try audio_buffer.resize(0);
    try @import("std").testing.expectEqual(@as(base.int32, 0), audio_buffer.getMaxSamples());
}

test "delay processor starts with valid ring positions" {
    var input = [_]f32{ 1, 2 };
    var output = [_]f32{ 9, 9 };
    var storage = [_]f32{0} ** 8;
    var processor_delay = Delay(f32).init(&storage, 5, 3);

    try std.testing.expectEqual(@as(base.int32, 0), processor_delay.in_pos);
    try std.testing.expectEqual(@as(base.int32, 5), processor_delay.out_pos);

    const silent = processor_delay.process(&input, &output, 2, false);
    try std.testing.expect(!silent);
    try std.testing.expectEqual(@as(f32, 0), output[0]);
    try std.testing.expectEqual(@as(f32, 0), output[1]);
    try std.testing.expectEqual(@as(base.int32, 2), processor_delay.in_pos);
    try std.testing.expectEqual(@as(base.int32, 7), processor_delay.out_pos);
}

test "delay processor wraps ring positions for oversized blocks" {
    var input = [_]f32{ 1, 2, 3, 4, 5, 6 };
    var output = [_]f32{0} ** 6;
    var storage = [_]f32{0} ** 4;
    var processor_delay = Delay(f32).init(&storage, 2, 2);

    const silent = processor_delay.process(&input, &output, input.len, false);
    try std.testing.expect(!silent);
    try std.testing.expectEqual(@as(base.int32, 2), processor_delay.in_pos);
    try std.testing.expectEqual(@as(base.int32, 0), processor_delay.out_pos);
}

test "delay processor keeps one free ring slot when storage is undersized" {
    var single_input = [_]f32{42};
    var single_output = [_]f32{9};
    var single_storage = [_]f32{0};
    var single_delay = Delay(f32).init(&single_storage, 1, 1);

    try std.testing.expectEqual(@as(base.int32, 1), single_delay.getBufferSamples());
    try std.testing.expectEqual(@as(base.int32, 0), single_delay.delay_samples);

    const single_silent = single_delay.process(&single_input, &single_output, single_input.len, false);
    try std.testing.expect(!single_silent);
    try std.testing.expectEqual(@as(f32, 42), single_output[0]);

    var input = [_]f32{ 1, 2 };
    var output = [_]f32{ 9, 9 };
    var storage = [_]f32{0} ** 4;
    var processor_delay = Delay(f32).init(&storage, 4, 4);

    try std.testing.expectEqual(@as(base.int32, 4), processor_delay.getBufferSamples());
    try std.testing.expectEqual(@as(base.int32, 3), processor_delay.delay_samples);
    try std.testing.expectEqual(@as(base.int32, 0), processor_delay.in_pos);
    try std.testing.expectEqual(@as(base.int32, 1), processor_delay.out_pos);

    const silent = processor_delay.process(&input, &output, input.len, false);
    try std.testing.expect(!silent);
    try std.testing.expectEqualSlices(f32, &.{ 0, 0 }, &output);
}

test "delay processor clears output when ring state is invalid" {
    var input = [_]f32{ 1, 2 };
    var output = [_]f32{ 9, 9 };
    var storage = [_]f32{0} ** 4;
    var processor_delay = Delay(f32).init(&storage, 2, 2);
    processor_delay.in_pos = -1;

    const silent = processor_delay.process(&input, &output, input.len, false);
    try std.testing.expect(silent);
    try std.testing.expectEqualSlices(f32, &.{ 0, 0 }, &output);
    try std.testing.expectEqual(@as(base.int32, -1), processor_delay.in_pos);
    try std.testing.expectEqual(@as(base.int32, 2), processor_delay.out_pos);
}

test "bypass helpers reject invalid sizes and positions" {
    var input = [_]f32{ 1, 2 };
    var output = [_]f32{ 9, 9 };
    var buffer = [_]f32{ 0, 0 };
    try std.testing.expect(!delay(f32, -1, &input, &output, &buffer, 2, 0, 0));
    try std.testing.expect(!delay(f32, 1, &input, &output, &buffer, 2, -1, 0));
    try std.testing.expect(!delay(f32, 1, &input, &output, &buffer, 2, 0, 2));
    try std.testing.expectEqual(@as(f32, 9), output[0]);

    var storage = [_]f32{0} ** 4;
    var processor_delay = Delay(f32).init(&storage, std.math.maxInt(base.int32), 2);
    try std.testing.expectEqual(@as(base.int32, 4), processor_delay.getBufferSamples());
    const silent = processor_delay.process(&input, &output, -1, true);
    try std.testing.expect(silent);

    var audio_buffer = AudioBuffer(f32).init(std.testing.allocator);
    defer audio_buffer.deinit();
    try audio_buffer.resize(2);
    try audio_buffer.resize(-1);
    try std.testing.expectEqual(@as(base.int32, 0), audio_buffer.getMaxSamples());
    try std.testing.expectEqual(@as(usize, 0), audio_buffer.buffer.len);
}

test "audio buffer keeps size invariant when resize fails" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 1,
        .resize_fail_index = 0,
    });
    var audio_buffer = AudioBuffer(f32).init(failing_allocator.allocator());
    defer audio_buffer.deinit();

    try audio_buffer.resize(2);
    audio_buffer.buffer[0] = 3;
    try std.testing.expectError(error.OutOfMemory, audio_buffer.resize(4));
    try std.testing.expectEqual(@as(base.int32, 2), audio_buffer.getMaxSamples());
    try std.testing.expectEqual(@as(usize, 2), audio_buffer.buffer.len);
    try std.testing.expectEqual(@as(f32, 3), audio_buffer.buffer[0]);
}
