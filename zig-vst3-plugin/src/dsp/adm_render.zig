const std = @import("std");
const adm = @import("adm.zig");
const adm_xml = @import("adm_xml.zig");

pub const maximum_input_channels = adm_xml.max_adm_matrix_coefficients;

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
                const linear_gain = switch (coefficient.gain.unit) {
                    .linear => coefficient.gain.value,
                    .decibels => if (std.math.isInf(
                        coefficient.gain.value,
                    ) and coefficient.gain.value < 0.0)
                        0.0
                    else
                        std.math.pow(
                            f64,
                            10.0,
                            coefficient.gain.value / 20.0,
                        ),
                };
                const gain: Sample = @floatCast(linear_gain);
                if (!std.math.isFinite(gain))
                    return error.InvalidAdmRendererGain;
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
