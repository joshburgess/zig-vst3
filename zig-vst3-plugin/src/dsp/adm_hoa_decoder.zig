const std = @import("std");
const adm_xml = @import("adm_xml.zig");

pub const maximum_supported_order: u32 = 50;

pub const ScreenReferencePolicy = enum {
    reject,
    render_unchanged,
};

pub fn MatrixDecoder(
    comptime Sample: type,
    comptime maximum_inputs: usize,
    comptime maximum_outputs: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("MatrixDecoder supports f32 and f64 samples");
    if (maximum_inputs == 0)
        @compileError("MatrixDecoder requires input capacity");
    if (maximum_outputs == 0)
        @compileError("MatrixDecoder requires output capacity");

    return struct {
        const Self = @This();

        input_count: usize,
        output_count: usize,
        declared_input_count: usize,
        declared_output_count: usize,
        normalization: adm_xml.HoaNormalization,
        nfc_reference_distance: f64,
        screen_reference: bool,
        orders: [maximum_inputs]u8 = @splat(0),
        degrees: [maximum_inputs]i8 = @splat(0),
        coefficients: [maximum_outputs][maximum_inputs]Sample =
            @splat(@splat(0.0)),

        pub fn init(
            blocks: []const adm_xml.BlockFormat,
            output_count: usize,
            output_major_coefficients: []const Sample,
        ) !Self {
            if (blocks.len == 0 or blocks.len > maximum_inputs)
                return error.InvalidAdmHoaInputCount;
            if (output_count == 0 or output_count > maximum_outputs)
                return error.InvalidAdmHoaOutputCount;
            const coefficient_count = std.math.mul(
                usize,
                blocks.len,
                output_count,
            ) catch return error.InvalidAdmHoaCoefficientCount;
            if (output_major_coefficients.len != coefficient_count)
                return error.InvalidAdmHoaCoefficientCount;

            const first = blocks[0];
            try validateBlockKind(first);
            if (first.hoa_equation != null)
                return error.UnsupportedAdmHoaEquation;
            if (!std.math.isFinite(first.hoa_nfc_reference_distance) or
                first.hoa_nfc_reference_distance < 0.0)
            {
                return error.InvalidAdmHoaReferenceDistance;
            }

            var result = Self{
                .input_count = blocks.len,
                .output_count = output_count,
                .declared_input_count = blocks.len,
                .declared_output_count = output_count,
                .normalization = first.hoa_normalization,
                .nfc_reference_distance = first.hoa_nfc_reference_distance,
                .screen_reference = first.screen_ref,
            };
            for (blocks, 0..) |block, input_index| {
                try validateBlockKind(block);
                if (block.hoa_equation != null)
                    return error.UnsupportedAdmHoaEquation;
                if (block.hoa_normalization != result.normalization)
                    return error.MixedAdmHoaNormalization;
                if (!std.math.isFinite(
                    block.hoa_nfc_reference_distance,
                ) or block.hoa_nfc_reference_distance < 0.0) {
                    return error.InvalidAdmHoaReferenceDistance;
                }
                if (block.hoa_nfc_reference_distance !=
                    result.nfc_reference_distance)
                {
                    return error.MixedAdmHoaReferenceDistance;
                }
                if (block.screen_ref != result.screen_reference)
                    return error.MixedAdmHoaScreenReference;

                const order =
                    block.hoa_order orelse return error.MissingAdmHoaOrder;
                const degree =
                    block.hoa_degree orelse return error.MissingAdmHoaDegree;
                if (order > maximum_supported_order)
                    return error.UnsupportedAdmHoaOrder;
                const signed_order: i64 = @intCast(order);
                if (@as(i64, degree) < -signed_order or
                    @as(i64, degree) > signed_order)
                {
                    return error.InvalidAdmHoaDegree;
                }
                if (result.normalization == .fuma and order > 3)
                    return error.UnsupportedAdmHoaFumaOrder;
                for (
                    result.orders[0..input_index],
                    result.degrees[0..input_index],
                ) |previous_order, previous_degree| {
                    if (previous_order == order and
                        previous_degree == degree)
                    {
                        return error.DuplicateAdmHoaComponent;
                    }
                }
                result.orders[input_index] = @intCast(order);
                result.degrees[input_index] = @intCast(degree);

                const block_gain = try renderGain(Sample, block.gain);
                for (0..output_count) |output_index| {
                    const supplied =
                        output_major_coefficients[
                            output_index * blocks.len + input_index
                        ];
                    if (!std.math.isFinite(supplied))
                        return error.InvalidAdmHoaCoefficient;
                    const coefficient = supplied * block_gain;
                    if (!std.math.isFinite(coefficient))
                        return error.InvalidAdmHoaCoefficient;
                    result.coefficients[output_index][input_index] =
                        coefficient;
                }
            }
            return result;
        }

        pub fn processSample(
            self: *const Self,
            inputs: []const Sample,
            outputs: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmHoaDecoderState;
            if (inputs.len != self.input_count)
                return error.AdmHoaInputCountMismatch;
            if (outputs.len != self.output_count)
                return error.AdmHoaOutputCountMismatch;

            var values: [maximum_outputs]Sample = @splat(0.0);
            for (0..self.output_count) |output_index| {
                values[output_index] = self.decodeSample(
                    output_index,
                    inputs,
                );
            }
            @memcpy(outputs, values[0..self.output_count]);
        }

        pub fn process(
            self: *const Self,
            inputs: []const []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmHoaDecoderState;
            if (inputs.len != self.input_count)
                return error.AdmHoaInputCountMismatch;
            if (outputs.len != self.output_count)
                return error.AdmHoaOutputCountMismatch;

            const sample_count = inputs[0].len;
            for (inputs) |input| {
                if (input.len != sample_count)
                    return error.AdmHoaBufferLengthMismatch;
            }
            for (outputs, 0..) |output, output_index| {
                if (output.len != sample_count)
                    return error.AdmHoaBufferLengthMismatch;
                for (inputs) |input| {
                    if (slicesOverlap(Sample, input, output))
                        return error.AdmHoaAliasedBuffers;
                }
                for (outputs[0..output_index]) |previous| {
                    if (slicesOverlap(Sample, previous, output))
                        return error.AdmHoaAliasedBuffers;
                }
            }

            for (outputs, 0..) |output, output_index| {
                for (output, 0..) |*output_sample, sample_index| {
                    var value: Sample = 0.0;
                    for (0..self.input_count) |input_index| {
                        const raw_input =
                            inputs[input_index][sample_index];
                        const input = if (std.math.isFinite(raw_input))
                            raw_input
                        else
                            0.0;
                        value += input *
                            self.coefficients[output_index][input_index];
                        if (!std.math.isFinite(value)) value = 0.0;
                    }
                    output_sample.* = value;
                }
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.input_count == 0 or
                self.input_count > maximum_inputs or
                self.input_count != self.declared_input_count or
                self.output_count == 0 or
                self.output_count > maximum_outputs or
                self.output_count != self.declared_output_count or
                !std.math.isFinite(self.nfc_reference_distance) or
                self.nfc_reference_distance < 0.0)
            {
                return false;
            }
            for (
                self.orders[0..self.input_count],
                self.degrees[0..self.input_count],
                0..,
            ) |order, degree, input_index| {
                if (order > maximum_supported_order or
                    degree < -@as(i16, order) or
                    degree > @as(i16, order) or
                    (self.normalization == .fuma and order > 3))
                {
                    return false;
                }
                for (
                    self.orders[0..input_index],
                    self.degrees[0..input_index],
                ) |previous_order, previous_degree| {
                    if (previous_order == order and
                        previous_degree == degree)
                    {
                        return false;
                    }
                }
            }
            for (self.coefficients[0..self.output_count]) |row| {
                for (row[0..self.input_count]) |coefficient| {
                    if (!std.math.isFinite(coefficient)) return false;
                }
            }
            return true;
        }

        fn decodeSample(
            self: *const Self,
            output_index: usize,
            inputs: []const Sample,
        ) Sample {
            var value: Sample = 0.0;
            for (inputs, 0..) |raw_input, input_index| {
                const input = if (std.math.isFinite(raw_input))
                    raw_input
                else
                    0.0;
                value += input *
                    self.coefficients[output_index][input_index];
                if (!std.math.isFinite(value)) value = 0.0;
            }
            return value;
        }
    };
}

fn validateBlockKind(block: adm_xml.BlockFormat) !void {
    if (block.identifier.typeLabel() != 0x0004 or
        block.channel_identifier.typeLabel() != 0x0004)
    {
        return error.AdmHoaDecoderRequiresHoaBlock;
    }
}

fn renderGain(
    comptime Sample: type,
    gain: adm_xml.Gain,
) !Sample {
    if (std.math.isNan(gain.value))
        return error.InvalidAdmHoaBlockGain;
    const linear = switch (gain.unit) {
        .linear => gain.value,
        .decibels => if (gain.value == -std.math.inf(f64))
            0.0
        else if (!std.math.isFinite(gain.value))
            return error.InvalidAdmHoaBlockGain
        else
            std.math.pow(f64, 10.0, gain.value / 20.0),
    };
    if (!std.math.isFinite(linear))
        return error.InvalidAdmHoaBlockGain;
    const converted: Sample = @floatCast(linear);
    if (!std.math.isFinite(converted))
        return error.InvalidAdmHoaBlockGain;
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

test "HOA matrix decoder validates components and decodes blocks" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <gain>0.5</gain>
        \\      <order>0</order>
        \\      <degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\      <nfcRefDist>1</nfcRefDist>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041002">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041002_00000001">
        \\      <order>1</order>
        \\      <degree>-1</degree>
        \\      <normalization>SN3D</normalization>
        \\      <nfcRefDist>1</nfcRefDist>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    const blocks = [_]adm_xml.BlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const Decoder = MatrixDecoder(f32, 4, 2);
    const decoder = try Decoder.init(
        &blocks,
        2,
        &.{
            1.0,  2.0,
            -1.0, 0.25,
        },
    );
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(adm_xml.HoaNormalization.sn3d, decoder.normalization);
    try std.testing.expectEqualDeep([_]u8{ 0, 1 }, decoder.orders[0..2].*);
    try std.testing.expectEqualDeep([_]i8{ 0, -1 }, decoder.degrees[0..2].*);
    try std.testing.expectEqual([_]u8{ 0, 0 }, decoder.orders[2..4].*);
    try std.testing.expectEqual([_]i8{ 0, 0 }, decoder.degrees[2..4].*);

    const first = [_]f32{ 2.0, 4.0, std.math.nan(f32) };
    const second = [_]f32{ 3.0, -2.0, 8.0 };
    const inputs = [_][]const f32{ &first, &second };
    var left: [first.len]f32 = undefined;
    var right: [first.len]f32 = undefined;
    const outputs = [_][]f32{ &left, &right };
    try decoder.process(&inputs, &outputs);
    try std.testing.expectEqualDeep(
        [_]f32{ 7.0, -2.0, 16.0 },
        left,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ -0.25, -2.5, 2.0 },
        right,
    );

    var frame: [2]f32 = undefined;
    try decoder.processSample(&.{ 4.0, 2.0 }, &frame);
    try std.testing.expectEqualDeep([_]f32{ 6.0, -1.5 }, frame);
}

test "HOA matrix decoder rejects inconsistent plans transactionally" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>1</order>
        \\      <degree>0</degree>
        \\      <normalization>N3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041002">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041002_00000001">
        \\      <order>1</order>
        \\      <degree>1</degree>
        \\      <normalization>N3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    var blocks = [_]adm_xml.BlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const Decoder = MatrixDecoder(f64, 2, 2);
    try std.testing.expectError(
        error.InvalidAdmHoaCoefficientCount,
        Decoder.init(&blocks, 2, &.{ 1.0, 0.0 }),
    );
    blocks[1].hoa_degree = 0;
    try std.testing.expectError(
        error.DuplicateAdmHoaComponent,
        Decoder.init(&blocks, 1, &.{ 1.0, 1.0 }),
    );
    blocks[1].hoa_degree = 1;
    blocks[1].hoa_normalization = .sn3d;
    try std.testing.expectError(
        error.MixedAdmHoaNormalization,
        Decoder.init(&blocks, 1, &.{ 1.0, 1.0 }),
    );
    blocks[1].hoa_normalization = .n3d;
    blocks[1].hoa_nfc_reference_distance = 1.0;
    try std.testing.expectError(
        error.MixedAdmHoaReferenceDistance,
        Decoder.init(&blocks, 1, &.{ 1.0, 1.0 }),
    );
    blocks[1].hoa_nfc_reference_distance = 0.0;
    blocks[1].screen_ref = true;
    try std.testing.expectError(
        error.MixedAdmHoaScreenReference,
        Decoder.init(&blocks, 1, &.{ 1.0, 1.0 }),
    );
    blocks[1].screen_ref = false;
    blocks[1].hoa_order = 51;
    try std.testing.expectError(
        error.UnsupportedAdmHoaOrder,
        Decoder.init(&blocks, 1, &.{ 1.0, 1.0 }),
    );
    blocks[1].hoa_order = 1;
    blocks[0].hoa_equation = .{ .len = 1, .bytes = undefined };
    blocks[0].hoa_equation.?.bytes[0] = 'x';
    try std.testing.expectError(
        error.UnsupportedAdmHoaEquation,
        Decoder.init(&blocks, 1, &.{ 1.0, 1.0 }),
    );
    blocks[0].hoa_equation = null;
    blocks[0].hoa_normalization = .fuma;
    blocks[1].hoa_normalization = .fuma;
    blocks[1].hoa_order = 4;
    blocks[1].hoa_degree = 1;
    try std.testing.expectError(
        error.UnsupportedAdmHoaFumaOrder,
        Decoder.init(&blocks, 1, &.{ 1.0, 1.0 }),
    );
    blocks[0].hoa_normalization = .n3d;
    blocks[1].hoa_normalization = .n3d;
    blocks[1].hoa_order = 1;
    try std.testing.expectError(
        error.InvalidAdmHoaCoefficient,
        Decoder.init(&blocks, 1, &.{ std.math.nan(f64), 1.0 }),
    );

    const decoder = try Decoder.init(&blocks, 1, &.{ 1.0, 1.0 });
    var aliased = [_]f64{ 1.0, 2.0 };
    const inputs = [_][]const f64{ &aliased, &aliased };
    const outputs = [_][]f64{&aliased};
    try std.testing.expectError(
        error.AdmHoaAliasedBuffers,
        decoder.process(&inputs, &outputs),
    );
    try std.testing.expectEqualDeep([_]f64{ 1.0, 2.0 }, aliased);

    const CountBoundDecoder = MatrixDecoder(f64, 3, 2);
    const count_bound = try CountBoundDecoder.init(
        blocks[0..1],
        1,
        &.{1.0},
    );
    for (2..4) |forged_count| {
        var hostile = count_bound;
        hostile.input_count = forged_count;
        const hostile_before = hostile;
        var retained = [_]f64{ 31.0, 47.0 };
        try std.testing.expect(!hostile.valid());
        try std.testing.expectError(
            error.InvalidAdmHoaDecoderState,
            hostile.processSample(&.{ 1.0, 2.0 }, retained[0..1]),
        );
        try std.testing.expectEqualDeep(hostile_before, hostile);
        try std.testing.expectEqualDeep([_]f64{ 31.0, 47.0 }, retained);
    }
    var hostile_output_count = count_bound;
    hostile_output_count.output_count = 2;
    const hostile_output_count_before = hostile_output_count;
    var retained = [_]f64{ 53.0, 59.0 };
    try std.testing.expect(!hostile_output_count.valid());
    try std.testing.expectError(
        error.InvalidAdmHoaDecoderState,
        hostile_output_count.processSample(&.{1.0}, &retained),
    );
    try std.testing.expectEqualDeep(
        hostile_output_count_before,
        hostile_output_count,
    );
    try std.testing.expectEqualDeep([_]f64{ 53.0, 59.0 }, retained);
}
