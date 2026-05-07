const std = @import("std");

pub fn AudioInputs(comptime Sample: type) type {
    return struct {
        const Self = @This();

        channels: []const []const Sample,
        frame_count: usize,

        pub fn init(channels: []const []const Sample) !Self {
            const frame_count = if (channels.len == 0) 0 else channels[0].len;
            for (channels) |channel_samples| {
                if (channel_samples.len != frame_count) {
                    return error.MismatchedFrameCount;
                }
            }
            return .{
                .channels = channels,
                .frame_count = frame_count,
            };
        }

        pub fn channel(self: Self, index: usize) ?[]const Sample {
            if (index >= self.channels.len) return null;
            return self.channels[index];
        }
    };
}

pub fn AudioOutputs(comptime Sample: type) type {
    return struct {
        const Self = @This();

        channels: []const []Sample,
        frame_count: usize,

        pub fn init(channels: []const []Sample) !Self {
            const frame_count = if (channels.len == 0) 0 else channels[0].len;
            for (channels) |channel_samples| {
                if (channel_samples.len != frame_count) {
                    return error.MismatchedFrameCount;
                }
            }
            return .{
                .channels = channels,
                .frame_count = frame_count,
            };
        }

        pub fn channel(self: Self, index: usize) ?[]Sample {
            if (index >= self.channels.len) return null;
            return self.channels[index];
        }
    };
}

pub fn ProcessContext(comptime Sample: type) type {
    return struct {
        sample_rate: f64,
        inputs: AudioInputs(Sample),
        outputs: AudioOutputs(Sample),

        pub fn frameCount(self: @This()) usize {
            return @min(self.inputs.frame_count, self.outputs.frame_count);
        }
    };
}

test "audio input view validates channel frame counts" {
    const left = [_]f32{ 0.1, 0.2 };
    const right = [_]f32{ 0.3, 0.4 };
    const channels = [_][]const f32{ &left, &right };
    const inputs = try AudioInputs(f32).init(&channels);

    try std.testing.expectEqual(@as(usize, 2), inputs.channels.len);
    try std.testing.expectEqual(@as(usize, 2), inputs.frame_count);
    try std.testing.expectEqual(@as(f32, 0.3), inputs.channel(1).?[0]);
    try std.testing.expectEqual(@as(?[]const f32, null), inputs.channel(2));
}

test "audio output view rejects mismatched channel frame counts" {
    var left = [_]f32{ 0.1, 0.2 };
    var right = [_]f32{0.3};
    const channels = [_][]f32{ &left, &right };

    try std.testing.expectError(error.MismatchedFrameCount, AudioOutputs(f32).init(&channels));
}

test "process context reports usable frame count" {
    const in_left = [_]f64{ 0.1, 0.2, 0.3 };
    const in_right = [_]f64{ 0.4, 0.5, 0.6 };
    var out_left = [_]f64{ 0.0, 0.0, 0.0 };
    var out_right = [_]f64{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f64{ &in_left, &in_right };
    const output_channels = [_][]f64{ &out_left, &out_right };
    const context = ProcessContext(f64){
        .sample_rate = 48_000.0,
        .inputs = try AudioInputs(f64).init(&input_channels),
        .outputs = try AudioOutputs(f64).init(&output_channels),
    };

    try std.testing.expectEqual(@as(usize, 3), context.frameCount());
}
