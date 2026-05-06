const base = @import("../base/types.zig");

pub const kMaxChannelsSupported: base.int32 = 64;

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
            const buffer_samples = if (delay_samples > 0) max_samples_per_block + delay_samples else 0;
            return .{
                .buffer = storage[0..@intCast(buffer_samples)],
                .buffer_samples = buffer_samples,
                .delay_samples = delay_samples,
            };
        }

        pub fn hasDelay(self: *const Self) bool {
            return self.delay_samples > 0;
        }

        pub fn getBufferSamples(self: *const Self) base.int32 {
            return self.buffer_samples;
        }

        pub fn process(self: *Self, src: ?[*]const T, dst: [*]T, num_samples: base.int32, silent_in: bool) bool {
            var silent_out = false;
            if (self.hasDelay() and src != null) {
                const buffer_size = self.getBufferSamples();
                _ = delay(T, num_samples, src.?, dst, self.buffer.ptr, buffer_size, self.in_pos, self.out_pos);
                self.in_pos += num_samples;
                if (self.in_pos >= buffer_size) self.in_pos -= buffer_size;
                self.out_pos += num_samples;
                if (self.out_pos >= buffer_size) self.out_pos -= buffer_size;
            } else {
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
}
