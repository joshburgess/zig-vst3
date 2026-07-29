const std = @import("std");
const adm_xml = @import("adm_xml.zig");

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
