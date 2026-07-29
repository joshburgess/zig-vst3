const std = @import("std");
const adm = @import("adm.zig");
const adm_xml = @import("adm_xml.zig");

pub const maximum_input_channels = adm_xml.max_adm_matrix_coefficients;
pub const maximum_output_channels: usize = 64;

pub fn StaticMatrixMixer(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("StaticMatrixMixer supports f32 and f64 samples");

    return struct {
        const Self = @This();

        input_count: usize,
        term_count: usize,
        input_indices: [maximum_input_channels]u8 = undefined,
        gains: [maximum_input_channels]Sample = undefined,

        pub fn init(
            block: *const adm_xml.BlockFormat,
            input_channels: []const adm.Identifier,
        ) !Self {
            if (block.identifier.typeLabel() != 0x0002 or
                block.channel_identifier.typeLabel() != 0x0002)
            {
                return error.AdmRendererRequiresMatrixBlock;
            }
            if (input_channels.len == 0 or
                input_channels.len > maximum_input_channels)
            {
                return error.InvalidAdmRendererInputCount;
            }
            for (input_channels, 0..) |channel, index| {
                if (channel.kind != .channel_format)
                    return error.InvalidAdmRendererInputIdentifier;
                for (input_channels[0..index]) |previous| {
                    if (channel.eql(previous))
                        return error.DuplicateAdmRendererInputIdentifier;
                }
            }

            const coefficients = block.matrixCoefficientSlice();
            if (coefficients.len == 0)
                return error.MissingAdmRendererMatrixCoefficient;
            var result = Self{
                .input_count = input_channels.len,
                .term_count = coefficients.len,
            };
            for (coefficients, 0..) |coefficient, term_index| {
                if (coefficient.gain_variable != null or
                    coefficient.phase_variable != null or
                    coefficient.delay_variable != null or
                    coefficient.phase_degrees != 0.0 or
                    coefficient.delay_milliseconds != 0.0)
                {
                    return error.UnsupportedDynamicAdmMatrixCoefficient;
                }
                const identifier = try coefficient.channelIdentifier();
                const input_index = findInputChannel(
                    input_channels,
                    identifier,
                ) orelse return error.MissingAdmRendererInputChannel;
                for (result.input_indices[0..term_index]) |previous| {
                    if (previous == input_index)
                        return error.DuplicateAdmRendererMatrixCoefficient;
                }
                const gain = try renderGain(Sample, coefficient.gain);
                result.input_indices[term_index] = @intCast(input_index);
                result.gains[term_index] = gain;
            }
            return result;
        }

        pub fn processSample(
            self: *const Self,
            inputs: []const Sample,
        ) Sample {
            if (!self.valid() or inputs.len != self.input_count)
                return 0.0;
            var output: Sample = 0.0;
            for (
                self.input_indices[0..self.term_count],
                self.gains[0..self.term_count],
            ) |input_index, gain| {
                const input = inputs[input_index];
                if (!std.math.isFinite(input)) return 0.0;
                output += input * gain;
                if (!std.math.isFinite(output)) return 0.0;
            }
            return output;
        }

        pub fn process(
            self: *const Self,
            inputs: []const []const Sample,
            output: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (inputs.len != self.input_count)
                return error.AdmRendererInputCountMismatch;
            for (inputs) |input| {
                if (input.len != output.len)
                    return error.AdmRendererBufferLengthMismatch;
                if (slicesOverlap(Sample, input, output))
                    return error.AdmRendererAliasedBuffers;
            }
            for (output, 0..) |*output_sample, sample_index| {
                var value: Sample = 0.0;
                for (
                    self.input_indices[0..self.term_count],
                    self.gains[0..self.term_count],
                ) |input_index, gain| {
                    const input = inputs[input_index][sample_index];
                    if (!std.math.isFinite(input)) {
                        value = 0.0;
                        break;
                    }
                    value += input * gain;
                    if (!std.math.isFinite(value)) {
                        value = 0.0;
                        break;
                    }
                }
                output_sample.* = value;
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.input_count == 0 or
                self.input_count > maximum_input_channels or
                self.term_count == 0 or
                self.term_count > maximum_input_channels)
            {
                return false;
            }
            for (
                self.input_indices[0..self.term_count],
                self.gains[0..self.term_count],
                0..,
            ) |input_index, gain, term_index| {
                if (input_index >= self.input_count or
                    !std.math.isFinite(gain))
                {
                    return false;
                }
                for (self.input_indices[0..term_index]) |previous| {
                    if (previous == input_index) return false;
                }
            }
            return true;
        }
    };
}

pub fn DirectSpeakerRouter(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("DirectSpeakerRouter supports f32 and f64 samples");

    return struct {
        const Self = @This();

        output_count: usize,
        output_index: u8,
        gain: Sample,

        pub fn init(
            block: *const adm_xml.BlockFormat,
            output_labels: []const []const u8,
        ) !Self {
            if (block.identifier.typeLabel() != 0x0001 or
                block.channel_identifier.typeLabel() != 0x0001)
            {
                return error.AdmRendererRequiresDirectSpeakersBlock;
            }
            if (output_labels.len == 0 or
                output_labels.len > maximum_output_channels)
            {
                return error.InvalidAdmRendererOutputCount;
            }
            for (output_labels, 0..) |label, index| {
                if (label.len == 0 or
                    label.len > adm_xml.max_adm_speaker_label_bytes or
                    !std.unicode.utf8ValidateSlice(label))
                {
                    return error.InvalidAdmRendererSpeakerLabel;
                }
                for (output_labels[0..index]) |previous| {
                    if (std.mem.eql(u8, label, previous))
                        return error.DuplicateAdmRendererSpeakerLabel;
                }
            }

            var matched_output: ?usize = null;
            for (block.speakerLabelSlice()) |speaker_label| {
                for (output_labels, 0..) |output_label, output_index| {
                    if (!std.mem.eql(
                        u8,
                        speaker_label.value(),
                        output_label,
                    )) {
                        continue;
                    }
                    if (matched_output) |previous| {
                        if (previous != output_index)
                            return error.AmbiguousAdmRendererSpeakerRoute;
                    } else {
                        matched_output = output_index;
                    }
                }
            }
            const output_index = matched_output orelse
                return error.MissingAdmRendererSpeakerRoute;
            return .{
                .output_count = output_labels.len,
                .output_index = @intCast(output_index),
                .gain = try renderGain(Sample, block.gain),
            };
        }

        pub fn processSample(
            self: *const Self,
            input: Sample,
        ) Sample {
            if (!self.valid() or !std.math.isFinite(input)) return 0.0;
            const output = input * self.gain;
            return if (std.math.isFinite(output)) output else 0.0;
        }

        pub fn mix(
            self: *const Self,
            input: []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (outputs.len != self.output_count)
                return error.AdmRendererOutputCountMismatch;
            for (outputs, 0..) |output, output_index| {
                if (output.len != input.len)
                    return error.AdmRendererBufferLengthMismatch;
                for (outputs[0..output_index]) |previous| {
                    if (slicesOverlap(Sample, previous, output))
                        return error.AdmRendererAliasedBuffers;
                }
            }
            const target = outputs[self.output_index];
            if (slicesOverlap(Sample, input, target))
                return error.AdmRendererAliasedBuffers;

            for (input, target) |input_sample, *output_sample| {
                if (!std.math.isFinite(input_sample)) continue;
                if (!std.math.isFinite(output_sample.*)) {
                    output_sample.* = 0.0;
                    continue;
                }
                const mixed = output_sample.* + input_sample * self.gain;
                output_sample.* = if (std.math.isFinite(mixed))
                    mixed
                else
                    0.0;
            }
        }

        pub fn valid(self: *const Self) bool {
            return self.output_count > 0 and
                self.output_count <= maximum_output_channels and
                self.output_index < self.output_count and
                std.math.isFinite(self.gain);
        }
    };
}

fn renderGain(
    comptime Sample: type,
    gain_value: adm_xml.Gain,
) !Sample {
    const linear_gain = switch (gain_value.unit) {
        .linear => gain_value.value,
        .decibels => if (std.math.isInf(gain_value.value) and
            gain_value.value < 0.0)
            0.0
        else
            std.math.pow(f64, 10.0, gain_value.value / 20.0),
    };
    const gain: Sample = @floatCast(linear_gain);
    if (!std.math.isFinite(gain))
        return error.InvalidAdmRendererGain;
    return gain;
}

fn findInputChannel(
    channels: []const adm.Identifier,
    target: adm.Identifier,
) ?usize {
    for (channels, 0..) |channel, index| {
        if (channel.eql(target)) return index;
    }
    return null;
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

test "ADM static matrix mixer binds identifiers and applies gains" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient gain="0.5">AC_00010001</coefficient>
        \\        <coefficient gain="-6.020599913279624" gainUnit="dB">AC_00010002</coefficient>
        \\        <coefficient gain="-inf" gainUnit="dB">AC_00010003</coefficient>
        \\      </matrix>
        \\    </audioBlockFormatMatrix>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const channels = [_]adm.Identifier{
        try adm.Identifier.parse("AC_00010001"),
        try adm.Identifier.parse("AC_00010002"),
        try adm.Identifier.parse("AC_00010003"),
    };
    const mixer = try StaticMatrixMixer(f64).init(&block, &channels);
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        mixer.processSample(&.{ 1.0, 3.0, 1000.0 }),
        0.000_000_001,
    );

    const first = [_]f64{ 2.0, -2.0, std.math.nan(f64) };
    const second = [_]f64{ 4.0, 2.0, 1.0 };
    const muted = [_]f64{ 1000.0, 1000.0, 1000.0 };
    const inputs = [_][]const f64{ &first, &second, &muted };
    var output: [3]f64 = undefined;
    try mixer.process(&inputs, &output);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        output[0],
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        output[1],
        0.000_000_001,
    );
    try std.testing.expectEqual(@as(f64, 0.0), output[2]);
}

test "ADM static matrix mixer rejects unsupported plans transactionally" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient gainVar="automation">AC_00010001</coefficient>
        \\      </matrix>
        \\    </audioBlockFormatMatrix>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const channels = [_]adm.Identifier{
        try adm.Identifier.parse("AC_00010001"),
    };
    try std.testing.expectError(
        error.UnsupportedDynamicAdmMatrixCoefficient,
        StaticMatrixMixer(f32).init(&block, &channels),
    );

    var static_block = block;
    static_block.matrix_coefficients[0].gain_variable = null;
    const mixer = try StaticMatrixMixer(f32).init(
        &static_block,
        &channels,
    );
    const input = [_]f32{ 1.0, 2.0 };
    const inputs = [_][]const f32{&input};
    var output = [_]f32{7.0};
    try std.testing.expectError(
        error.AdmRendererBufferLengthMismatch,
        mixer.process(&inputs, &output),
    );
    try std.testing.expectEqual(@as(f32, 7.0), output[0]);

    var aliased = [_]f32{ 1.0, 2.0 };
    const aliased_inputs = [_][]const f32{&aliased};
    try std.testing.expectError(
        error.AdmRendererAliasedBuffers,
        mixer.process(&aliased_inputs, &aliased),
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 2.0 },
        aliased,
    );
}

test "ADM direct speaker router mixes an exact label match" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <speakerLabel>M+000</speakerLabel>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <gain>0.5</gain>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const labels = [_][]const u8{ "M+030", "M+000", "M-030" };
    const router = try DirectSpeakerRouter(f32).init(&block, &labels);
    try std.testing.expectEqual(@as(u8, 1), router.output_index);
    try std.testing.expectEqual(
        @as(f32, 1.0),
        router.processSample(2.0),
    );

    const input = [_]f32{ 2.0, std.math.nan(f32), -4.0 };
    var left = [_]f32{ 1.0, 1.0, 1.0 };
    var center = [_]f32{ 1.0, 1.0, 1.0 };
    var right = [_]f32{ 1.0, 1.0, 1.0 };
    const outputs = [_][]f32{ &left, &center, &right };
    try router.mix(&input, &outputs);
    try std.testing.expectEqualDeep(
        [_]f32{ 2.0, 1.0, -1.0 },
        center,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 1.0, 1.0 },
        left,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 1.0, 1.0 },
        right,
    );
}

test "ADM direct speaker router rejects ambiguous and aliased routes" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <speakerLabel>M+000</speakerLabel>
        \\      <speakerLabel>M+030</speakerLabel>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    try std.testing.expectError(
        error.AmbiguousAdmRendererSpeakerRoute,
        DirectSpeakerRouter(f64).init(
            &block,
            &[_][]const u8{ "M+000", "M+030" },
        ),
    );
    try std.testing.expectError(
        error.MissingAdmRendererSpeakerRoute,
        DirectSpeakerRouter(f64).init(
            &block,
            &[_][]const u8{"M-030"},
        ),
    );

    const router = try DirectSpeakerRouter(f64).init(
        &block,
        &[_][]const u8{"M+000"},
    );
    var aliased = [_]f64{ 1.0, 2.0 };
    const outputs = [_][]f64{&aliased};
    try std.testing.expectError(
        error.AdmRendererAliasedBuffers,
        router.mix(&aliased, &outputs),
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 1.0, 2.0 },
        aliased,
    );
}
