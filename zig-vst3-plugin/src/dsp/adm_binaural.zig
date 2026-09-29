const std = @import("std");
const adm_sample_time = @import("adm_sample_time.zig");
const adm_time = @import("adm_time.zig");
const adm_xml = @import("adm_xml.zig");

pub fn StereoGainTimeline(
    comptime Sample: type,
    comptime maximum_blocks_per_ear: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("StereoGainTimeline supports f32 and f64 samples");
    if (maximum_blocks_per_ear == 0)
        @compileError("StereoGainTimeline requires at least one block per ear");

    return struct {
        const Self = @This();
        pub const channel_count: usize = 2;

        const Segment = struct {
            first_sample: u64 = 0,
            interpolation_end_sample: u64 = 0,
            end_sample: u64 = 0,
            start_position: ExactSamplePosition = .{
                .numerator = 0,
                .denominator = 1,
            },
            interpolation_end_position: ExactSamplePosition = .{
                .numerator = 0,
                .denominator = 1,
            },
            end_position: ExactSamplePosition = .{
                .numerator = 0,
                .denominator = 1,
            },
            interpolate_from_previous: bool = false,
            target_gain: Sample = 0.0,
        };

        input_indices: [channel_count]u1 = @splat(0),
        segment_counts: [channel_count]usize = @splat(0),
        declared_segment_counts: [channel_count]usize = @splat(0),
        segments: [channel_count][maximum_blocks_per_ear]Segment =
            @splat(@splat(.{})),

        pub fn init(
            input_blocks: []const []const adm_xml.BlockFormat,
            sample_rate: u32,
        ) !Self {
            if (sample_rate == 0)
                return error.InvalidAdmBinauralSampleRate;
            if (input_blocks.len != channel_count)
                return error.InvalidAdmBinauralInputCount;

            var result = Self{};
            var ear_seen: [channel_count]bool = @splat(false);
            for (input_blocks, 0..) |blocks, input_index| {
                if (blocks.len == 0)
                    return error.MissingAdmBinauralBlock;
                if (blocks.len > maximum_blocks_per_ear)
                    return error.AdmBinauralBlockCapacityExceeded;

                const ear_index = try validateBinauralBlock(&blocks[0]);
                if (ear_seen[ear_index])
                    return error.DuplicateAdmBinauralEar;
                ear_seen[ear_index] = true;
                result.input_indices[ear_index] = @intCast(input_index);
                result.segment_counts[ear_index] = blocks.len;
                result.declared_segment_counts[ear_index] = blocks.len;

                const channel = blocks[0].channel_identifier;
                for (blocks, 0..) |*block, block_index| {
                    if (try validateBinauralBlock(block) != ear_index or
                        !block.channel_identifier.eql(channel))
                    {
                        return error.AdmBinauralChannelMismatch;
                    }
                    const duration = block.duration orelse
                        return error.MissingAdmBinauralBlockDuration;
                    if (!block.rtime_explicit)
                        return error.MissingAdmBinauralBlockTime;
                    if (block_index != 0)
                        try validateBlockSequence(
                            &blocks[block_index - 1],
                            block,
                        );

                    const start_position = try exactSamplePosition(
                        block.rtime,
                        null,
                        sample_rate,
                    );
                    const end_position = try exactSamplePosition(
                        block.rtime,
                        duration,
                        sample_rate,
                    );
                    if (end_position.compare(start_position) == .lt)
                        return error.InvalidAdmBinauralBlockDuration;

                    var adjacent = false;
                    if (block_index != 0) {
                        const previous = &blocks[block_index - 1];
                        const previous_duration = previous.duration orelse
                            return error.MissingAdmBinauralBlockDuration;
                        const order = try compareAdmTimeSum(
                            previous.rtime,
                            previous_duration,
                            block.rtime,
                        );
                        if (order == .gt)
                            return error.OverlappingAdmBinauralBlocks;
                        adjacent = order == .eq;
                    }

                    const interpolation_length =
                        if (!adjacent or block_index == 0)
                            null
                        else if (block.jump_position.enabled)
                            block.jump_position.interpolation_length orelse
                                zeroAdmTime()
                        else
                            duration;
                    if (interpolation_length) |length| {
                        if (length.compare(duration) == .gt)
                            return error.InvalidAdmBinauralInterpolationLength;
                    }
                    const interpolation_end_position =
                        if (interpolation_length) |length|
                            try exactSamplePosition(
                                block.rtime,
                                length,
                                sample_rate,
                            )
                        else
                            start_position;

                    result.segments[ear_index][block_index] = .{
                        .first_sample = try ceilSamplePosition(start_position),
                        .interpolation_end_sample = try ceilSamplePosition(
                            interpolation_end_position,
                        ),
                        .end_sample = try ceilSamplePosition(end_position),
                        .start_position = start_position,
                        .interpolation_end_position = interpolation_end_position,
                        .end_position = end_position,
                        .interpolate_from_previous = adjacent and
                            interpolation_end_position.compare(
                                start_position,
                            ) == .gt,
                        .target_gain = try renderGain(Sample, block.gain),
                    };
                }
            }
            if (!ear_seen[0] or !ear_seen[1])
                return error.MissingAdmBinauralEar;
            if (!result.valid())
                return error.InvalidAdmBinauralTimelineState;
            return result;
        }

        pub fn processSample(
            self: *const Self,
            sample_position: u64,
            inputs: []const Sample,
            outputs: []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidAdmBinauralTimelineState;
            if (inputs.len != channel_count)
                return error.AdmBinauralInputCountMismatch;
            if (outputs.len != channel_count)
                return error.AdmBinauralOutputCountMismatch;

            var values: [channel_count]Sample = @splat(0.0);
            for (0..channel_count) |ear_index| {
                values[ear_index] = renderTimelineSample(
                    self,
                    ear_index,
                    sample_position,
                    inputs[self.input_indices[ear_index]],
                );
            }
            @memcpy(outputs, &values);
        }

        pub fn process(
            self: *const Self,
            first_sample: u64,
            inputs: []const []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidAdmBinauralTimelineState;
            const sample_count = try validateProcessBuffers(
                Sample,
                inputs,
                outputs,
            );
            const sample_count_u64 = std.math.cast(
                u64,
                sample_count,
            ) orelse return error.AdmBinauralSampleRangeOverflow;
            const end_sample = std.math.add(
                u64,
                first_sample,
                sample_count_u64,
            ) catch return error.AdmBinauralSampleRangeOverflow;

            for (outputs) |output| @memset(output, 0.0);
            for (outputs, 0..) |output, ear_index| {
                const input = inputs[self.input_indices[ear_index]];
                for (
                    self.segmentSlice(ear_index),
                    0..,
                ) |*segment, segment_index| {
                    const overlap_start =
                        @max(first_sample, segment.first_sample);
                    const overlap_end = @min(end_sample, segment.end_sample);
                    if (overlap_start >= overlap_end) continue;
                    const source_gain = if (segment.interpolate_from_previous)
                        self.segments[ear_index][segment_index - 1].target_gain
                    else
                        segment.target_gain;
                    var sample = overlap_start;
                    while (sample < overlap_end) : (sample += 1) {
                        const buffer_index: usize = @intCast(
                            sample - first_sample,
                        );
                        const phase =
                            if (segment.interpolate_from_previous and
                            sample < segment.interpolation_end_sample)
                                interpolationPhase(Sample, segment, sample)
                            else
                                1.0;
                        const gain = source_gain +
                            (segment.target_gain - source_gain) * phase;
                        output[buffer_index] = renderSample(
                            Sample,
                            input[buffer_index],
                            gain,
                        );
                    }
                }
            }
        }

        pub fn blockCount(self: *const Self, ear_index: usize) usize {
            if (ear_index >= channel_count or !self.valid()) return 0;
            return self.segment_counts[ear_index];
        }

        pub fn totalBlockCount(self: *const Self) usize {
            if (!self.valid()) return 0;
            return self.segment_counts[0] + self.segment_counts[1];
        }

        pub fn valid(self: *const Self) bool {
            if (self.input_indices[0] == self.input_indices[1])
                return false;
            for (0..channel_count) |ear_index| {
                const count = self.segment_counts[ear_index];
                if (count == 0 or
                    count > maximum_blocks_per_ear or
                    count != self.declared_segment_counts[ear_index])
                    return false;
                for (self.segmentSlice(ear_index), 0..) |segment, index| {
                    if (!std.math.isFinite(segment.target_gain) or
                        segment.first_sample >
                            segment.interpolation_end_sample or
                        segment.interpolation_end_sample >
                            segment.end_sample or
                        segment.interpolation_end_position.compare(
                            segment.start_position,
                        ) == .lt or
                        segment.end_position.compare(
                            segment.interpolation_end_position,
                        ) == .lt or
                        (segment.start_position.ceil() catch null) !=
                            segment.first_sample or
                        (segment.interpolation_end_position.ceil() catch null) !=
                            segment.interpolation_end_sample or
                        (segment.end_position.ceil() catch null) !=
                            segment.end_sample)
                    {
                        return false;
                    }
                    if (segment.interpolate_from_previous) {
                        if (index == 0 or
                            segment.interpolation_end_position.compare(
                                segment.start_position,
                            ) != .gt or
                            self.segments[ear_index][index - 1]
                                .end_position.compare(
                                segment.start_position,
                            ) != .eq)
                        {
                            return false;
                        }
                    } else if (segment.interpolation_end_position.compare(
                        segment.start_position,
                    ) != .eq) {
                        return false;
                    }
                    if (index != 0 and
                        self.segments[ear_index][index - 1]
                            .end_position.compare(
                            segment.start_position,
                        ) == .gt)
                    {
                        return false;
                    }
                }
            }
            return true;
        }

        fn segmentSlice(
            self: *const Self,
            ear_index: usize,
        ) []const Segment {
            return self.segments[ear_index][0..@min(
                self.segment_counts[ear_index],
                maximum_blocks_per_ear,
            )];
        }

        fn renderTimelineSample(
            self: *const Self,
            ear_index: usize,
            sample_position: u64,
            input: Sample,
        ) Sample {
            for (
                self.segmentSlice(ear_index),
                0..,
            ) |*segment, segment_index| {
                if (sample_position < segment.first_sample or
                    sample_position >= segment.end_sample)
                {
                    continue;
                }
                const source_gain = if (segment.interpolate_from_previous)
                    self.segments[ear_index][segment_index - 1].target_gain
                else
                    segment.target_gain;
                const phase =
                    if (segment.interpolate_from_previous and
                    sample_position < segment.interpolation_end_sample)
                        interpolationPhase(
                            Sample,
                            segment,
                            sample_position,
                        )
                    else
                        1.0;
                const gain = source_gain +
                    (segment.target_gain - source_gain) * phase;
                return renderSample(Sample, input, gain);
            }
            return 0.0;
        }
    };
}

pub fn StereoMixer(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("StereoMixer supports f32 and f64 samples");

    return struct {
        const Self = @This();
        pub const channel_count: usize = 2;

        input_indices: [channel_count]u1,
        gains: [channel_count]Sample,

        pub fn init(blocks: []const adm_xml.BlockFormat) !Self {
            if (blocks.len != channel_count)
                return error.InvalidAdmBinauralInputCount;

            var result = Self{
                .input_indices = undefined,
                .gains = undefined,
            };
            var ear_seen: [channel_count]bool = @splat(false);
            for (blocks, 0..) |block, input_index| {
                if (block.identifier.typeLabel() != 0x0005 or
                    block.channel_identifier.typeLabel() != 0x0005)
                {
                    return error.AdmBinauralMixerRequiresBinauralBlock;
                }
                if (block.rtime_explicit or block.duration != null)
                    return error.UnsupportedTimedAdmBinauralBlock;
                const channel_name = block.channel_name orelse
                    return error.MissingAdmBinauralChannelName;
                const ear_index = parseEar(channel_name.value()) orelse
                    return error.InvalidAdmBinauralChannelName;
                if (ear_seen[ear_index])
                    return error.DuplicateAdmBinauralEar;
                ear_seen[ear_index] = true;
                result.input_indices[ear_index] = @intCast(input_index);
                result.gains[ear_index] =
                    try renderGain(Sample, block.gain);
            }
            if (!ear_seen[0] or !ear_seen[1])
                return error.MissingAdmBinauralEar;
            return result;
        }

        pub fn processSample(
            self: *const Self,
            inputs: []const Sample,
            outputs: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmBinauralMixerState;
            if (inputs.len != channel_count)
                return error.AdmBinauralInputCountMismatch;
            if (outputs.len != channel_count)
                return error.AdmBinauralOutputCountMismatch;

            var values: [channel_count]Sample = undefined;
            for (0..channel_count) |ear_index| {
                values[ear_index] = renderSample(
                    Sample,
                    inputs[self.input_indices[ear_index]],
                    self.gains[ear_index],
                );
            }
            @memcpy(outputs, &values);
        }

        pub fn process(
            self: *const Self,
            inputs: []const []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmBinauralMixerState;
            if (inputs.len != channel_count)
                return error.AdmBinauralInputCountMismatch;
            if (outputs.len != channel_count)
                return error.AdmBinauralOutputCountMismatch;
            const sample_count = inputs[0].len;
            for (inputs) |input| {
                if (input.len != sample_count)
                    return error.AdmBinauralBufferLengthMismatch;
            }
            for (outputs, 0..) |output, output_index| {
                if (output.len != sample_count)
                    return error.AdmBinauralBufferLengthMismatch;
                for (inputs) |input| {
                    if (slicesOverlap(Sample, input, output))
                        return error.AdmBinauralAliasedBuffers;
                }
                for (outputs[0..output_index]) |previous| {
                    if (slicesOverlap(Sample, previous, output))
                        return error.AdmBinauralAliasedBuffers;
                }
            }

            for (outputs, 0..) |output, ear_index| {
                const input = inputs[self.input_indices[ear_index]];
                const gain = self.gains[ear_index];
                for (input, output) |input_sample, *output_sample| {
                    output_sample.* =
                        renderSample(Sample, input_sample, gain);
                }
            }
        }

        pub fn valid(self: *const Self) bool {
            return self.input_indices[0] != self.input_indices[1] and
                std.math.isFinite(self.gains[0]) and
                std.math.isFinite(self.gains[1]);
        }
    };
}

const ExactSamplePosition = adm_sample_time.Position;

fn validateBinauralBlock(block: *const adm_xml.BlockFormat) !usize {
    if (block.identifier.typeLabel() != 0x0005 or
        block.channel_identifier.typeLabel() != 0x0005)
    {
        return error.AdmBinauralMixerRequiresBinauralBlock;
    }
    if (block.identifier.primary != block.channel_identifier.primary)
        return error.AdmBinauralBlockIdentifierMismatch;
    const channel_name = block.channel_name orelse
        return error.MissingAdmBinauralChannelName;
    return parseEar(channel_name.value()) orelse
        return error.InvalidAdmBinauralChannelName;
}

fn validateBlockSequence(
    previous: *const adm_xml.BlockFormat,
    current: *const adm_xml.BlockFormat,
) !void {
    const previous_identifier = previous.identifier.secondary orelse
        return error.InvalidAdmBinauralBlockSequence;
    const identifier = current.identifier.secondary orelse
        return error.InvalidAdmBinauralBlockSequence;
    const expected_identifier = std.math.add(
        u32,
        previous_identifier,
        1,
    ) catch return error.InvalidAdmBinauralBlockSequence;
    if (identifier != expected_identifier)
        return error.InvalidAdmBinauralBlockSequence;
}

fn zeroAdmTime() adm_time.Value {
    return adm_sample_time.zero();
}

fn compareAdmTimeSum(
    first: adm_time.Value,
    second: adm_time.Value,
    expected: adm_time.Value,
) !std.math.Order {
    return adm_sample_time.compareSum(
        first,
        second,
        expected,
    ) catch |err| return mapSampleTimeError(err);
}

fn exactSamplePosition(
    first: adm_time.Value,
    second: ?adm_time.Value,
    sample_rate: u32,
) !ExactSamplePosition {
    return adm_sample_time.position(
        first,
        second,
        sample_rate,
    ) catch |err| return mapSampleTimeError(err);
}

fn ceilSamplePosition(position: ExactSamplePosition) !u64 {
    return position.ceil() catch |err|
        return mapSampleTimeError(err);
}

fn interpolationPhase(
    comptime Sample: type,
    segment: anytype,
    sample: u64,
) Sample {
    return adm_sample_time.interpolationPhase(
        Sample,
        segment.start_position,
        segment.interpolation_end_position,
        sample,
    );
}

fn mapSampleTimeError(
    err: error{
        InvalidAdmSampleTime,
        AdmSampleTimeOverflow,
    },
) error{
    InvalidAdmBinauralTime,
    AdmBinauralTimeOverflow,
} {
    return switch (err) {
        error.InvalidAdmSampleTime => error.InvalidAdmBinauralTime,
        error.AdmSampleTimeOverflow => error.AdmBinauralTimeOverflow,
    };
}

fn validateProcessBuffers(
    comptime Sample: type,
    inputs: []const []const Sample,
    outputs: []const []Sample,
) !usize {
    if (inputs.len != 2)
        return error.AdmBinauralInputCountMismatch;
    if (outputs.len != 2)
        return error.AdmBinauralOutputCountMismatch;
    const sample_count = inputs[0].len;
    for (inputs) |input| {
        if (input.len != sample_count)
            return error.AdmBinauralBufferLengthMismatch;
    }
    for (outputs, 0..) |output, output_index| {
        if (output.len != sample_count)
            return error.AdmBinauralBufferLengthMismatch;
        for (inputs) |input| {
            if (slicesOverlap(Sample, input, output))
                return error.AdmBinauralAliasedBuffers;
        }
        for (outputs[0..output_index]) |previous| {
            if (slicesOverlap(Sample, previous, output))
                return error.AdmBinauralAliasedBuffers;
        }
    }
    return sample_count;
}

fn parseEar(name: []const u8) ?usize {
    if (std.mem.eql(u8, name, "LeftEar") or
        std.mem.eql(u8, name, "leftEar"))
    {
        return 0;
    }
    if (std.mem.eql(u8, name, "RightEar") or
        std.mem.eql(u8, name, "rightEar"))
    {
        return 1;
    }
    return null;
}

fn renderSample(comptime Sample: type, input: Sample, gain: Sample) Sample {
    if (!std.math.isFinite(input)) return 0.0;
    const output = input * gain;
    return if (std.math.isFinite(output)) output else 0.0;
}

fn renderGain(
    comptime Sample: type,
    gain: adm_xml.Gain,
) !Sample {
    if (std.math.isNan(gain.value))
        return error.InvalidAdmBinauralGain;
    const linear = switch (gain.unit) {
        .linear => gain.value,
        .decibels => if (gain.value == -std.math.inf(f64))
            0.0
        else if (!std.math.isFinite(gain.value))
            return error.InvalidAdmBinauralGain
        else
            std.math.pow(f64, 10.0, gain.value / 20.0),
    };
    if (!std.math.isFinite(linear))
        return error.InvalidAdmBinauralGain;
    const converted: Sample = @floatCast(linear);
    if (!std.math.isFinite(converted))
        return error.InvalidAdmBinauralGain;
    return converted;
}

fn slicesOverlap(
    comptime Sample: type,
    input: []const Sample,
    output: []Sample,
) bool {
    if (input.len == 0 or output.len == 0) return false;
    const input_start = @intFromPtr(input.ptr);
    const output_start = @intFromPtr(output.ptr);
    const input_bytes = std.math.mul(
        usize,
        input.len,
        @sizeOf(Sample),
    ) catch return true;
    const output_bytes = std.math.mul(
        usize,
        output.len,
        @sizeOf(Sample),
    ) catch return true;
    const input_end = std.math.add(
        usize,
        input_start,
        input_bytes,
    ) catch return true;
    const output_end = std.math.add(
        usize,
        output_start,
        output_bytes,
    ) catch return true;
    return input_start < output_end and output_start < input_end;
}

test "ADM binaural gain timeline is invariant across processing partitions" {
    var left_blocks = [_]adm_xml.BlockFormat{
        try testTimedBinauralBlock(
            "LeftEar",
            0x1001,
            1,
            "0.00000",
            "1.00000",
            0.25,
        ),
        try testTimedBinauralBlock(
            "LeftEar",
            0x1001,
            2,
            "1.00000",
            "1.00000",
            1.0,
        ),
        try testTimedBinauralBlock(
            "LeftEar",
            0x1001,
            3,
            "2.00000",
            "1.00000",
            0.5,
        ),
        try testTimedBinauralBlock(
            "LeftEar",
            0x1001,
            4,
            "4.00000",
            "1.00000",
            0.75,
        ),
    };
    left_blocks[2].jump_position.enabled = true;
    const right_blocks = [_]adm_xml.BlockFormat{
        try testTimedBinauralBlock(
            "rightEar",
            0x1002,
            1,
            "0.00000",
            "5.00000",
            2.0,
        ),
    };
    const block_sequences = [_][]const adm_xml.BlockFormat{
        &right_blocks,
        &left_blocks,
    };
    const timeline = try StereoGainTimeline(f64, 4).init(
        &block_sequences,
        4,
    );
    try std.testing.expect(timeline.valid());
    try std.testing.expectEqual(@as(usize, 5), timeline.totalBlockCount());
    try std.testing.expectEqualDeep([_]u1{ 1, 0 }, timeline.input_indices);
    for (timeline.segments[1][right_blocks.len..]) |segment| {
        try std.testing.expectEqual(@as(u64, 0), segment.first_sample);
        try std.testing.expectEqual(
            @as(u128, 1),
            segment.start_position.denominator,
        );
        try std.testing.expectEqual(@as(f64, 0.0), segment.target_gain);
    }

    const input: [20]f64 = @splat(1.0);
    const inputs = [_][]const f64{ &input, &input };
    var whole_left: [input.len]f64 = undefined;
    var whole_right: [input.len]f64 = undefined;
    const whole_outputs = [_][]f64{ &whole_left, &whole_right };
    try timeline.process(0, &inputs, &whole_outputs);
    try std.testing.expectEqualDeep(
        [_]f64{
            0.25, 0.25,   0.25,  0.25,
            0.25, 0.4375, 0.625, 0.8125,
            0.5,  0.5,    0.5,   0.5,
            0.0,  0.0,    0.0,   0.0,
            0.75, 0.75,   0.75,  0.75,
        },
        whole_left,
    );
    try std.testing.expectEqualDeep(
        @as([input.len]f64, @splat(2.0)),
        whole_right,
    );

    var partitioned_left: [input.len]f64 = undefined;
    var partitioned_right: [input.len]f64 = undefined;
    const boundaries = [_]usize{ 0, 3, 11, input.len };
    for (boundaries[0 .. boundaries.len - 1], 0..) |first, index| {
        const end = boundaries[index + 1];
        const partition_inputs = [_][]const f64{
            input[first..end],
            input[first..end],
        };
        const partition_outputs = [_][]f64{
            partitioned_left[first..end],
            partitioned_right[first..end],
        };
        try timeline.process(
            @intCast(first),
            &partition_inputs,
            &partition_outputs,
        );
    }
    try std.testing.expectEqualDeep(whole_left, partitioned_left);
    try std.testing.expectEqualDeep(whole_right, partitioned_right);

    var frame: [2]f64 = undefined;
    try timeline.processSample(5, &.{ 1.0, 1.0 }, &frame);
    try std.testing.expectEqualDeep([_]f64{ 0.4375, 2.0 }, frame);
}

test "ADM binaural gain timeline preserves exact fractional phase" {
    const left_blocks = [_]adm_xml.BlockFormat{
        try testTimedBinauralBlock(
            "LeftEar",
            0x1001,
            1,
            "9007199254740992S1",
            "1S1",
            0.25,
        ),
        try testTimedBinauralBlock(
            "LeftEar",
            0x1001,
            2,
            "9007199254740993S1",
            "1S1",
            1.0,
        ),
    };
    const right_blocks = [_]adm_xml.BlockFormat{
        try testTimedBinauralBlock(
            "RightEar",
            0x1002,
            1,
            "9007199254740992S1",
            "2S1",
            0.5,
        ),
    };
    const block_sequences = [_][]const adm_xml.BlockFormat{
        &left_blocks,
        &right_blocks,
    };
    const timeline = try StereoGainTimeline(f64, 2).init(
        &block_sequences,
        4,
    );
    const input = [_]f64{ 1.0, std.math.nan(f64) };
    const inputs = [_][]const f64{ &input, &input };
    var left: [2]f64 = undefined;
    var right: [2]f64 = undefined;
    const outputs = [_][]f64{ &left, &right };
    try timeline.process(
        36_028_797_018_963_974,
        &inputs,
        &outputs,
    );
    try std.testing.expectEqualDeep([_]f64{ 0.625, 0.0 }, left);
    try std.testing.expectEqualDeep([_]f64{ 0.5, 0.0 }, right);
}

test "ADM binaural gain timeline honors shortened jump ramps" {
    var left_blocks = [_]adm_xml.BlockFormat{
        try testTimedBinauralBlock(
            "LeftEar",
            0x1001,
            1,
            "0.00000",
            "1.00000",
            0.0,
        ),
        try testTimedBinauralBlock(
            "LeftEar",
            0x1001,
            2,
            "1.00000",
            "1.00000",
            1.0,
        ),
    };
    left_blocks[1].jump_position = .{
        .enabled = true,
        .interpolation_length = try adm_time.Value.parse("0.50000"),
    };
    const right_blocks = [_]adm_xml.BlockFormat{
        try testTimedBinauralBlock(
            "RightEar",
            0x1002,
            1,
            "0.00000",
            "2.00000",
            1.0,
        ),
    };
    const block_sequences = [_][]const adm_xml.BlockFormat{
        &left_blocks,
        &right_blocks,
    };
    const timeline = try StereoGainTimeline(f32, 2).init(
        &block_sequences,
        4,
    );
    const input: [8]f32 = @splat(1.0);
    const inputs = [_][]const f32{ &input, &input };
    var left: [input.len]f32 = undefined;
    var right: [input.len]f32 = undefined;
    const outputs = [_][]f32{ &left, &right };
    try timeline.process(0, &inputs, &outputs);
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 1.0, 1.0 },
        left,
    );
    try std.testing.expectEqualDeep(
        @as([input.len]f32, @splat(1.0)),
        right,
    );
}

test "ADM binaural gain timeline rejects invalid state transactionally" {
    var left_blocks = [_]adm_xml.BlockFormat{
        try testTimedBinauralBlock(
            "LeftEar",
            0x1001,
            1,
            "0.00000",
            "1.00000",
            0.5,
        ),
        try testTimedBinauralBlock(
            "LeftEar",
            0x1001,
            2,
            "0.50000",
            "1.00000",
            1.0,
        ),
    };
    const right_blocks = [_]adm_xml.BlockFormat{
        try testTimedBinauralBlock(
            "RightEar",
            0x1002,
            1,
            "0.00000",
            "1.00000",
            1.0,
        ),
    };
    const block_sequences = [_][]const adm_xml.BlockFormat{
        &left_blocks,
        &right_blocks,
    };
    try std.testing.expectError(
        error.InvalidAdmBinauralSampleRate,
        StereoGainTimeline(f32, 2).init(&block_sequences, 0),
    );
    try std.testing.expectError(
        error.AdmBinauralBlockCapacityExceeded,
        StereoGainTimeline(f32, 1).init(&block_sequences, 48_000),
    );
    try std.testing.expectError(
        error.OverlappingAdmBinauralBlocks,
        StereoGainTimeline(f32, 2).init(&block_sequences, 48_000),
    );

    left_blocks[1].rtime =
        try adm_time.Value.parse("1.00000");
    left_blocks[1].identifier.primary = 0x0005_1002;
    try std.testing.expectError(
        error.AdmBinauralBlockIdentifierMismatch,
        StereoGainTimeline(f32, 2).init(&block_sequences, 48_000),
    );
    left_blocks[1].identifier.primary = 0x0005_1001;
    var timeline = try StereoGainTimeline(f32, 2).init(
        &block_sequences,
        48_000,
    );
    const input = [_]f32{ 1.0, 1.0 };
    const inputs = [_][]const f32{ &input, &input };
    var first = [_]f32{ 7.0, 7.0 };
    var second = [_]f32{ 7.0, 7.0 };
    const outputs = [_][]f32{ &first, &second };
    try std.testing.expectError(
        error.AdmBinauralSampleRangeOverflow,
        timeline.process(std.math.maxInt(u64), &inputs, &outputs),
    );
    try std.testing.expectEqualDeep([_]f32{ 7.0, 7.0 }, first);
    try std.testing.expectEqualDeep([_]f32{ 7.0, 7.0 }, second);

    const aliased_outputs = [_][]f32{ &first, &first };
    try std.testing.expectError(
        error.AdmBinauralAliasedBuffers,
        timeline.process(0, &inputs, &aliased_outputs),
    );
    try std.testing.expectEqualDeep([_]f32{ 7.0, 7.0 }, first);

    timeline.segment_counts[0] = 1;
    try std.testing.expect(!timeline.valid());
    try std.testing.expectEqual(@as(usize, 0), timeline.blockCount(0));
    try std.testing.expectEqual(@as(usize, 0), timeline.totalBlockCount());
    try std.testing.expectError(
        error.InvalidAdmBinauralTimelineState,
        timeline.process(0, &inputs, &outputs),
    );
    try std.testing.expectEqualDeep([_]f32{ 7.0, 7.0 }, first);
    try std.testing.expectEqualDeep([_]f32{ 7.0, 7.0 }, second);
}

test "ADM binaural stereo mixer maps current and legacy ear names" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="RightEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001">
        \\      <gain gainUnit="dB">-6.020599913279624</gain>
        \\    </audioBlockFormatBinaural>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051002" audioChannelFormatName="leftEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051002_00000001">
        \\      <gain>2</gain>
        \\    </audioBlockFormatBinaural>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    const blocks = [_]adm_xml.BlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const mixer = try StereoMixer(f32).init(&blocks);
    try std.testing.expectEqualDeep([_]u1{ 1, 0 }, mixer.input_indices);

    const right = [_]f32{ 2.0, 4.0, std.math.nan(f32) };
    const left = [_]f32{ 1.0, -3.0, 5.0 };
    const inputs = [_][]const f32{ &right, &left };
    var left_output: [left.len]f32 = undefined;
    var right_output: [right.len]f32 = undefined;
    const outputs = [_][]f32{ &left_output, &right_output };
    try mixer.process(&inputs, &outputs);
    try std.testing.expectEqualDeep(
        [_]f32{ 2.0, -6.0, 10.0 },
        left_output,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        right_output[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 2.0),
        right_output[1],
        0.000_001,
    );
    try std.testing.expectEqual(@as(f32, 0.0), right_output[2]);

    var frame: [2]f32 = undefined;
    try mixer.processSample(&.{ 6.0, 3.0 }, &frame);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), frame[0], 0.000_001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), frame[1], 0.000_001);
}

fn testTimedBinauralBlock(
    channel_name: []const u8,
    channel_suffix: u16,
    block_index: u32,
    rtime: []const u8,
    duration: []const u8,
    gain: f64,
) !adm_xml.BlockFormat {
    var xml_storage: [768]u8 = undefined;
    const encoded = try std.fmt.bufPrint(
        &xml_storage,
        "<audioFormatExtended>" ++
            "<audioChannelFormat audioChannelFormatID=\"AC_0005{X:0>4}\" " ++
            "audioChannelFormatName=\"{s}\">" ++
            "<audioBlockFormatBinaural " ++
            "audioBlockFormatID=\"AB_0005{X:0>4}_{d:0>8}\" " ++
            "rtime=\"{s}\" duration=\"{s}\">" ++
            "<gain>{d}</gain>" ++
            "</audioBlockFormatBinaural>" ++
            "</audioChannelFormat>" ++
            "</audioFormatExtended>",
        .{
            channel_suffix,
            channel_name,
            channel_suffix,
            1,
            rtime,
            duration,
            gain,
        },
    );
    const document = try adm_xml.Document.init(encoded);
    var iterator = document.blocks();
    var block = (try iterator.next()) orelse
        return error.MissingAdmBinauralBlock;
    block.identifier.secondary = block_index;
    return block;
}

test "ADM binaural stereo mixer rejects invalid plans transactionally" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="LeftEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001"/>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051002" audioChannelFormatName="RightEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051002_00000001"/>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    var blocks = [_]adm_xml.BlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const Mixer = StereoMixer(f64);
    blocks[1].channel_name = blocks[0].channel_name;
    try std.testing.expectError(
        error.DuplicateAdmBinauralEar,
        Mixer.init(&blocks),
    );
    blocks[1].channel_name.?.bytes[0] = 'R';
    blocks[1].channel_name.?.bytes[1] = 'i';
    blocks[1].channel_name.?.bytes[2] = 'g';
    blocks[1].channel_name.?.bytes[3] = 'h';
    blocks[1].channel_name.?.bytes[4] = 't';
    blocks[1].channel_name.?.bytes[5] = 'E';
    blocks[1].channel_name.?.bytes[6] = 'a';
    blocks[1].channel_name.?.bytes[7] = 'r';
    blocks[1].channel_name.?.len = 8;
    blocks[1].rtime_explicit = true;
    try std.testing.expectError(
        error.UnsupportedTimedAdmBinauralBlock,
        Mixer.init(&blocks),
    );
    blocks[1].rtime_explicit = false;
    const mixer = try Mixer.init(&blocks);

    var aliased = [_]f64{ 1.0, 2.0 };
    const inputs = [_][]const f64{ &aliased, &aliased };
    var other = [_]f64{ 7.0, 7.0 };
    const outputs = [_][]f64{ &aliased, &other };
    try std.testing.expectError(
        error.AdmBinauralAliasedBuffers,
        mixer.process(&inputs, &outputs),
    );
    try std.testing.expectEqualDeep([_]f64{ 1.0, 2.0 }, aliased);
    try std.testing.expectEqualDeep([_]f64{ 7.0, 7.0 }, other);
}
