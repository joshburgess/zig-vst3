const std = @import("std");
const adm_hoa_decoder = @import("adm_hoa_decoder.zig");
const adm_xml = @import("adm_xml.zig");
const linkwitz_riley = @import("linkwitz_riley.zig");

pub const Config = struct {
    sample_rate: f64,
    crossover_hz: f64,
};

pub fn Decoder(
    comptime Sample: type,
    comptime maximum_inputs: usize,
    comptime maximum_outputs: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Dual-band HOA decoding supports f32 and f64 samples");
    if (maximum_inputs == 0)
        @compileError("Dual-band HOA decoding requires input capacity");
    if (maximum_outputs == 0)
        @compileError("Dual-band HOA decoding requires output capacity");

    const MatrixDecoder = adm_hoa_decoder.MatrixDecoder(
        Sample,
        maximum_inputs,
        maximum_outputs,
    );
    const Crossover = linkwitz_riley.LinkwitzRileyFilter(Sample);

    return struct {
        const Self = @This();

        config: Config,
        low_decoder: MatrixDecoder,
        high_decoder: MatrixDecoder,
        crossovers: [maximum_inputs]Crossover = undefined,

        pub fn init(
            blocks: []const adm_xml.BlockFormat,
            output_count: usize,
            low_output_major_coefficients: []const Sample,
            high_output_major_coefficients: []const Sample,
            config: Config,
        ) !Self {
            const low_decoder = try MatrixDecoder.init(
                blocks,
                output_count,
                low_output_major_coefficients,
            );
            const high_decoder = try MatrixDecoder.init(
                blocks,
                output_count,
                high_output_major_coefficients,
            );
            var result = Self{
                .config = config,
                .low_decoder = low_decoder,
                .high_decoder = high_decoder,
            };
            for (result.crossovers[0..blocks.len]) |*crossover| {
                crossover.* = try Crossover.init(.{
                    .sample_rate = config.sample_rate,
                    .frequency_hz = config.crossover_hz,
                });
            }
            if (!result.valid())
                return error.InvalidAdmHoaDualBandDecoder;
            return result;
        }

        pub fn configure(
            self: *Self,
            config: Config,
            transition_samples: usize,
        ) !void {
            if (!self.valid())
                return error.InvalidAdmHoaDualBandDecoder;
            var next = self.crossovers;
            for (next[0..self.low_decoder.input_count]) |*crossover| {
                try crossover.configure(.{
                    .sample_rate = config.sample_rate,
                    .frequency_hz = config.crossover_hz,
                }, transition_samples);
            }
            self.config = config;
            self.crossovers = next;
        }

        pub fn reset(self: *Self) !void {
            if (!self.valid())
                return error.InvalidAdmHoaDualBandDecoder;
            for (
                self.crossovers[0..self.low_decoder.input_count],
            ) |*crossover| {
                crossover.reset();
            }
        }

        pub fn processSample(
            self: *Self,
            inputs: []const Sample,
            outputs: []Sample,
        ) !void {
            try self.validateSampleShapes(inputs, outputs);
            var values: [maximum_outputs]Sample = @splat(0.0);
            self.renderSample(inputs, values[0..self.low_decoder.output_count]);
            @memcpy(outputs, values[0..self.low_decoder.output_count]);
        }

        pub fn process(
            self: *Self,
            inputs: []const []const Sample,
            outputs: []const []Sample,
        ) !void {
            try self.validateBlockShapes(inputs, outputs);
            const sample_count = inputs[0].len;
            var input_values: [maximum_inputs]Sample = @splat(0.0);
            var output_values: [maximum_outputs]Sample = @splat(0.0);
            for (0..sample_count) |sample_index| {
                for (
                    inputs[0..self.low_decoder.input_count],
                    0..,
                ) |input, input_index| {
                    input_values[input_index] = input[sample_index];
                }
                self.renderSample(
                    input_values[0..self.low_decoder.input_count],
                    output_values[0..self.low_decoder.output_count],
                );
                for (
                    outputs[0..self.low_decoder.output_count],
                    output_values[0..self.low_decoder.output_count],
                ) |output, value| {
                    output[sample_index] = value;
                }
            }
        }

        pub fn valid(self: *const Self) bool {
            if (!self.low_decoder.valid() or
                !self.high_decoder.valid() or
                self.low_decoder.input_count !=
                    self.high_decoder.input_count or
                self.low_decoder.output_count !=
                    self.high_decoder.output_count or
                self.low_decoder.normalization !=
                    self.high_decoder.normalization or
                self.low_decoder.nfc_reference_distance !=
                    self.high_decoder.nfc_reference_distance or
                self.low_decoder.screen_reference !=
                    self.high_decoder.screen_reference)
            {
                return false;
            }
            for (
                self.low_decoder.orders[0..self.low_decoder.input_count],
                self.low_decoder.degrees[0..self.low_decoder.input_count],
                self.high_decoder.orders[0..self.high_decoder.input_count],
                self.high_decoder.degrees[0..self.high_decoder.input_count],
                self.crossovers[0..self.low_decoder.input_count],
            ) |
                low_order,
                low_degree,
                high_order,
                high_degree,
                crossover,
            | {
                if (low_order != high_order or
                    low_degree != high_degree or
                    !crossover.valid() or
                    crossover.config.sample_rate !=
                        self.config.sample_rate or
                    crossover.config.frequency_hz !=
                        self.config.crossover_hz)
                {
                    return false;
                }
            }
            return std.math.isFinite(self.config.sample_rate) and
                std.math.isFinite(self.config.crossover_hz);
        }

        fn validateSampleShapes(
            self: *const Self,
            inputs: []const Sample,
            outputs: []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidAdmHoaDualBandDecoder;
            if (inputs.len != self.low_decoder.input_count)
                return error.AdmHoaInputCountMismatch;
            if (outputs.len != self.low_decoder.output_count)
                return error.AdmHoaOutputCountMismatch;
        }

        fn validateBlockShapes(
            self: *const Self,
            inputs: []const []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidAdmHoaDualBandDecoder;
            if (inputs.len != self.low_decoder.input_count)
                return error.AdmHoaInputCountMismatch;
            if (outputs.len != self.low_decoder.output_count)
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
        }

        fn renderSample(
            self: *Self,
            inputs: []const Sample,
            outputs: []Sample,
        ) void {
            var low_inputs: [maximum_inputs]Sample = @splat(0.0);
            var high_inputs: [maximum_inputs]Sample = @splat(0.0);
            for (
                inputs,
                self.crossovers[0..self.low_decoder.input_count],
                0..,
            ) |raw_input, *crossover, input_index| {
                const input = if (std.math.isFinite(raw_input))
                    raw_input
                else
                    0.0;
                const split = crossover.processSample(input);
                low_inputs[input_index] = split.low;
                high_inputs[input_index] = split.high;
            }
            for (outputs, 0..) |*output, output_index| {
                var value: Sample = 0.0;
                for (0..self.low_decoder.input_count) |input_index| {
                    value +=
                        low_inputs[input_index] *
                        self.low_decoder
                            .coefficients[output_index][input_index] +
                        high_inputs[input_index] *
                            self.high_decoder
                                .coefficients[output_index][input_index];
                    if (!std.math.isFinite(value)) value = 0.0;
                }
                output.* = value;
            }
        }
    };
}

fn slicesOverlap(comptime Sample: type, first: []const Sample, second: []Sample) bool {
    if (first.len == 0 or second.len == 0) return false;
    const first_start = @intFromPtr(first.ptr);
    const second_start = @intFromPtr(second.ptr);
    const first_bytes = std.math.mul(
        usize,
        first.len,
        @sizeOf(Sample),
    ) catch return true;
    const second_bytes = std.math.mul(
        usize,
        second.len,
        @sizeOf(Sample),
    ) catch return true;
    const first_end = std.math.add(
        usize,
        first_start,
        first_bytes,
    ) catch return true;
    const second_end = std.math.add(
        usize,
        second_start,
        second_bytes,
    ) catch return true;
    return first_start < second_end and second_start < first_end;
}

fn testBlocks() ![2]adm_xml.BlockFormat {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>0</order><degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041002">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041002_00000001">
        \\      <order>1</order><degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    return .{
        (try iterator.next()) orelse return error.MissingTestHoaBlock,
        (try iterator.next()) orelse return error.MissingTestHoaBlock,
    };
}

test "dual-band HOA routes low and high frequencies independently" {
    const blocks = try testBlocks();
    const DualBand = Decoder(f64, 2, 2);
    var decoder = try DualBand.init(
        blocks[0..1],
        2,
        &.{ 1.0, 0.0 },
        &.{ 0.0, 1.0 },
        .{
            .sample_rate = 48_000.0,
            .crossover_hz = 1_000.0,
        },
    );

    var low_energy: f64 = 0.0;
    var low_leakage: f64 = 0.0;
    for (0..24_000) |index| {
        const sample = @sin(
            std.math.tau *
                100.0 *
                @as(f64, @floatFromInt(index)) /
                48_000.0,
        );
        var output: [2]f64 = undefined;
        try decoder.processSample(&.{sample}, &output);
        if (index >= 12_000) {
            low_energy += output[0] * output[0];
            low_leakage += output[1] * output[1];
        }
    }
    try std.testing.expect(low_energy > low_leakage * 1_000.0);

    try decoder.reset();
    var high_energy: f64 = 0.0;
    var high_leakage: f64 = 0.0;
    for (0..24_000) |index| {
        const sample = @sin(
            std.math.tau *
                10_000.0 *
                @as(f64, @floatFromInt(index)) /
                48_000.0,
        );
        var output: [2]f64 = undefined;
        try decoder.processSample(&.{sample}, &output);
        if (index >= 12_000) {
            high_energy += output[1] * output[1];
            high_leakage += output[0] * output[0];
        }
    }
    try std.testing.expect(high_energy > high_leakage * 1_000.0);
}

test "dual-band HOA retains a consistent screen reference" {
    var blocks = try testBlocks();
    for (&blocks) |*block| block.screen_ref = true;

    const DualBand = Decoder(f32, 2, 1);
    const decoder = try DualBand.init(
        &blocks,
        1,
        &.{ 1.0, 0.5 },
        &.{ 0.75, 0.25 },
        .{
            .sample_rate = 48_000.0,
            .crossover_hz = 1_000.0,
        },
    );
    try std.testing.expect(decoder.low_decoder.screen_reference);
    try std.testing.expect(decoder.high_decoder.screen_reference);

    blocks[1].screen_ref = false;
    try std.testing.expectError(
        error.MixedAdmHoaScreenReference,
        DualBand.init(
            &blocks,
            1,
            &.{ 1.0, 0.5 },
            &.{ 0.75, 0.25 },
            .{
                .sample_rate = 48_000.0,
                .crossover_hz = 1_000.0,
            },
        ),
    );
}

test "dual-band HOA processing is partition-independent and transactional" {
    const blocks = try testBlocks();
    const DualBand = Decoder(f32, 2, 2);
    const low_coefficients = [_]f32{
        1.0,  0.25,
        -0.5, 0.75,
    };
    const high_coefficients = [_]f32{
        0.5, -0.25,
        1.0, 0.125,
    };
    var block_decoder = try DualBand.init(
        &blocks,
        2,
        &low_coefficients,
        &high_coefficients,
        .{
            .sample_rate = 48_000.0,
            .crossover_hz = 1_200.0,
        },
    );
    var sample_decoder = block_decoder;
    const first = [_]f32{
        1.0, 0.5, -0.25, std.math.nan(f32), 0.75, -1.0,
    };
    const second = [_]f32{ -0.5, 0.25, 1.0, 0.0, -0.75, 0.5 };
    const inputs = [_][]const f32{ &first, &second };
    var block_first: [first.len]f32 = undefined;
    var block_second: [first.len]f32 = undefined;
    const block_outputs = [_][]f32{ &block_first, &block_second };
    try block_decoder.process(&inputs, &block_outputs);

    var sample_first: [first.len]f32 = undefined;
    var sample_second: [first.len]f32 = undefined;
    for (0..first.len) |index| {
        var output: [2]f32 = undefined;
        try sample_decoder.processSample(
            &.{ first[index], second[index] },
            &output,
        );
        sample_first[index] = output[0];
        sample_second[index] = output[1];
    }
    try std.testing.expectEqual(block_first, sample_first);
    try std.testing.expectEqual(block_second, sample_second);
    for (block_first ++ block_second) |sample|
        try std.testing.expect(std.math.isFinite(sample));

    const before_short = block_decoder;
    var short_output: [first.len - 1]f32 = @splat(99.0);
    try std.testing.expectError(
        error.AdmHoaBufferLengthMismatch,
        block_decoder.process(
            &inputs,
            &.{ short_output[0..], block_second[0..] },
        ),
    );
    try std.testing.expectEqual(before_short, block_decoder);
    try std.testing.expectEqual(
        [_]f32{99.0} ** (first.len - 1),
        short_output,
    );

    var aliased = first;
    const before_alias = block_decoder;
    try std.testing.expectError(
        error.AdmHoaAliasedBuffers,
        block_decoder.process(
            &.{ aliased[0..], second[0..] },
            &.{ aliased[0..], block_second[0..] },
        ),
    );
    try std.testing.expectEqual(before_alias, block_decoder);
    for (first, aliased) |expected, actual| {
        if (std.math.isNan(expected))
            try std.testing.expect(std.math.isNan(actual))
        else
            try std.testing.expectEqual(expected, actual);
    }

    const before_config = block_decoder;
    try std.testing.expectError(
        error.InvalidLinkwitzRileyConfig,
        block_decoder.configure(.{
            .sample_rate = 48_000.0,
            .crossover_hz = 24_000.0,
        }, 64),
    );
    try std.testing.expectEqual(before_config, block_decoder);
    try block_decoder.configure(.{
        .sample_rate = 96_000.0,
        .crossover_hz = 2_000.0,
    }, 64);
    try std.testing.expect(block_decoder.valid());
    try block_decoder.reset();

    var hostile = block_decoder;
    hostile.low_decoder.input_count = 0;
    var retained: [2]f32 = .{ 31.0, 47.0 };
    try std.testing.expectError(
        error.InvalidAdmHoaDualBandDecoder,
        hostile.processSample(&.{ 1.0, 2.0 }, &retained),
    );
    try std.testing.expectEqual([_]f32{ 31.0, 47.0 }, retained);

    try std.testing.expectError(
        error.InvalidAdmHoaCoefficientCount,
        DualBand.init(
            &blocks,
            2,
            low_coefficients[0..3],
            &high_coefficients,
            .{
                .sample_rate = 48_000.0,
                .crossover_hz = 1_200.0,
            },
        ),
    );
}
