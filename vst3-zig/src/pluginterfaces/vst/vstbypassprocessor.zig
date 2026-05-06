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

test "delay helper copies through circular buffer" {
    var input = [_]f32{ 1, 2, 3, 4, 5 };
    var output = [_]f32{0} ** 5;
    var buffer = [_]f32{ 10, 20, 30, 40 };
    try @import("std").testing.expect(delay(f32, 5, &input, &output, &buffer, 4, 2, 0));
    try @import("std").testing.expectEqual(@as(f32, 10), output[0]);
}
