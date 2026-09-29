const std = @import("std");
const dynamics = @import("dynamics.zig");
const linkwitz_riley = @import("linkwitz_riley.zig");

pub const Config = struct {
    sample_rate: f64,
    crossover_hz: f64,
    low: dynamics.CompressorConfig,
    high: dynamics.CompressorConfig,

    pub fn validate(self: Config) !void {
        try self.low.validate();
        try self.high.validate();
        if (!std.math.isFinite(self.sample_rate) or
            self.sample_rate < 1_000.0 or
            self.sample_rate > 768_000.0 or
            self.low.sample_rate != self.sample_rate or
            self.high.sample_rate != self.sample_rate or
            !std.math.isFinite(self.crossover_hz) or
            self.crossover_hz < 1.0 or
            self.crossover_hz >= self.sample_rate * 0.49)
            return error.InvalidMultibandCompressorConfig;
    }
};

pub const maximum_bands = 8;
pub const maximum_linked_channels = 16;

pub fn MultibandConfig(comptime band_count: usize) type {
    validateBandCount(band_count);
    return struct {
        sample_rate: f64,
        crossover_hz: [band_count - 1]f64,
        bands: [band_count]dynamics.CompressorConfig,

        pub fn validate(self: @This()) !void {
            if (!std.math.isFinite(self.sample_rate) or
                self.sample_rate < 1_000.0 or
                self.sample_rate > 768_000.0)
                return error.InvalidMultibandCompressorConfig;
            var previous: f64 = 0.0;
            for (self.crossover_hz) |frequency| {
                if (!std.math.isFinite(frequency) or
                    frequency < 1.0 or
                    frequency >= self.sample_rate * 0.49 or
                    frequency <= previous)
                    return error.InvalidMultibandCompressorConfig;
                previous = frequency;
            }
            for (self.bands) |band| {
                try band.validate();
                if (band.sample_rate != self.sample_rate)
                    return error.InvalidMultibandCompressorConfig;
            }
        }
    };
}

pub fn TwoBandCompressor(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("TwoBandCompressor supports f32 and f64 samples");

    const Crossover = linkwitz_riley.LinkwitzRileyFilter(Sample);
    const Compressor = dynamics.Compressor(Sample);

    return struct {
        const Self = @This();

        config: Config,
        crossover: Crossover,
        low: Compressor,
        high: Compressor,

        pub fn init(config: Config) !Self {
            try config.validate();
            return .{
                .config = config,
                .crossover = try Crossover.init(.{
                    .sample_rate = config.sample_rate,
                    .frequency_hz = config.crossover_hz,
                }),
                .low = try Compressor.init(config.low),
                .high = try Compressor.init(config.high),
            };
        }

        pub fn configure(
            self: *Self,
            config: Config,
            crossover_transition_samples: usize,
        ) !void {
            try config.validate();
            var next_crossover = self.crossover;
            var next_low = self.low;
            var next_high = self.high;
            try next_crossover.configure(.{
                .sample_rate = config.sample_rate,
                .frequency_hz = config.crossover_hz,
            }, crossover_transition_samples);
            try next_low.configure(config.low);
            try next_high.configure(config.high);
            self.config = config;
            self.crossover = next_crossover;
            self.low = next_low;
            self.high = next_high;
        }

        pub fn reset(self: *Self) void {
            self.crossover.reset();
            self.low.reset();
            self.high.reset();
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const split = self.crossover.processSample(input);
            const output =
                self.low.processSample(split.low) +
                self.high.processSample(split.high);
            return if (std.math.isFinite(output)) output else 0.0;
        }

        pub fn process(self: *Self, samples: []Sample) void {
            for (samples) |*sample| sample.* = self.processSample(sample.*);
        }

        pub fn lowGainReductionDb(self: *const Self) f64 {
            return self.low.gainReductionDb();
        }

        pub fn highGainReductionDb(self: *const Self) f64 {
            return self.high.gainReductionDb();
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            return self.crossover.valid() and
                self.low.valid() and
                self.high.valid();
        }
    };
}

pub fn MultibandCompressor(
    comptime Sample: type,
    comptime band_count: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("MultibandCompressor supports f32 and f64 samples");
    validateBandCount(band_count);

    const Crossover = linkwitz_riley.LinkwitzRileyFilter(Sample);
    const Compressor = dynamics.Compressor(Sample);
    const ProcessorConfig = MultibandConfig(band_count);
    const crossover_count = band_count - 1;

    return struct {
        const Self = @This();

        config: ProcessorConfig,
        splitters: [crossover_count]Crossover,
        phase_compensators: [crossover_count][crossover_count]Crossover,
        compressors: [band_count]Compressor,

        pub fn init(config: ProcessorConfig) !Self {
            try config.validate();
            var splitters: [crossover_count]Crossover = undefined;
            var phase_compensators: [crossover_count][crossover_count]Crossover = undefined;
            for (0..crossover_count) |index| {
                const crossover_config = linkwitz_riley.Config{
                    .sample_rate = config.sample_rate,
                    .frequency_hz = config.crossover_hz[index],
                };
                splitters[index] = try Crossover.init(crossover_config);
                for (0..crossover_count) |band|
                    phase_compensators[band][index] =
                        try Crossover.init(crossover_config);
            }
            var compressors: [band_count]Compressor = undefined;
            for (&compressors, config.bands) |*compressor, band|
                compressor.* = try Compressor.init(band);
            return .{
                .config = config,
                .splitters = splitters,
                .phase_compensators = phase_compensators,
                .compressors = compressors,
            };
        }

        pub fn configure(
            self: *Self,
            config: ProcessorConfig,
            crossover_transition_samples: usize,
        ) !void {
            try config.validate();
            var next = self.*;
            for (0..crossover_count) |index| {
                const crossover_config = linkwitz_riley.Config{
                    .sample_rate = config.sample_rate,
                    .frequency_hz = config.crossover_hz[index],
                };
                try next.splitters[index].configure(
                    crossover_config,
                    crossover_transition_samples,
                );
                for (0..crossover_count) |band|
                    try next.phase_compensators[band][index].configure(
                        crossover_config,
                        crossover_transition_samples,
                    );
            }
            for (&next.compressors, config.bands) |*compressor, band|
                try compressor.configure(band);
            next.config = config;
            self.* = next;
        }

        pub fn reset(self: *Self) void {
            for (&self.splitters) |*splitter| splitter.reset();
            for (&self.phase_compensators) |*row|
                for (row) |*compensator| compensator.reset();
            for (&self.compressors) |*compressor| compressor.reset();
        }

        pub fn splitBands(
            self: *Self,
            input: Sample,
        ) [band_count]Sample {
            var bands: [band_count]Sample = undefined;
            var remainder = if (std.math.isFinite(input)) input else 0.0;
            for (&self.splitters, 0..) |*splitter, index| {
                const split = splitter.processSample(remainder);
                bands[index] = split.low;
                remainder = split.high;
            }
            bands[band_count - 1] = remainder;

            for (&bands, 0..) |*band, band_index| {
                if (band_index + 1 < crossover_count) {
                    for (
                        band_index + 1..crossover_count,
                    ) |crossover_index| {
                        const compensated = self.phase_compensators[band_index][crossover_index]
                            .processSample(band.*);
                        band.* = compensated.low + compensated.high;
                    }
                }
            }
            return bands;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            var bands = self.splitBands(input);
            var output: Sample = 0.0;
            for (&bands, 0..) |*band, band_index| {
                output += self.compressors[band_index].processSample(band.*);
            }
            return if (std.math.isFinite(output)) output else 0.0;
        }

        pub fn process(self: *Self, samples: []Sample) void {
            for (samples) |*sample| sample.* = self.processSample(sample.*);
        }

        pub fn gainReductionDb(
            self: *const Self,
            band_index: usize,
        ) !f64 {
            if (band_index >= band_count)
                return error.MultibandBandIndexOutOfRange;
            return self.compressors[band_index].gainReductionDb();
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            for (self.splitters) |splitter| {
                if (!splitter.valid()) return false;
            }
            for (self.phase_compensators) |row| {
                for (row) |compensator| {
                    if (!compensator.valid()) return false;
                }
            }
            for (self.compressors) |compressor| {
                if (!compressor.valid()) return false;
            }
            return true;
        }
    };
}

pub fn LinkedMultibandCompressor(
    comptime Sample: type,
    comptime band_count: usize,
    comptime channel_count: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "LinkedMultibandCompressor supports f32 and f64 samples",
        );
    validateBandCount(band_count);
    validateChannelCount(channel_count);

    const BandProcessor = MultibandCompressor(Sample, band_count);
    const Compressor = dynamics.Compressor(Sample);
    const ProcessorConfig = MultibandConfig(band_count);

    return struct {
        const Self = @This();

        config: ProcessorConfig,
        channel_processors: [channel_count]BandProcessor,
        compressors: [band_count]Compressor,

        pub fn init(config: ProcessorConfig) !Self {
            try config.validate();
            var channel_processors: [channel_count]BandProcessor =
                undefined;
            for (&channel_processors) |*processor|
                processor.* = try BandProcessor.init(config);
            var compressors: [band_count]Compressor = undefined;
            for (&compressors, config.bands) |*compressor, band|
                compressor.* = try Compressor.init(band);
            return .{
                .config = config,
                .channel_processors = channel_processors,
                .compressors = compressors,
            };
        }

        pub fn configure(
            self: *Self,
            config: ProcessorConfig,
            crossover_transition_samples: usize,
        ) !void {
            try config.validate();
            var next = self.*;
            for (&next.channel_processors) |*processor|
                try processor.configure(
                    config,
                    crossover_transition_samples,
                );
            for (&next.compressors, config.bands) |*compressor, band|
                try compressor.configure(band);
            next.config = config;
            self.* = next;
        }

        pub fn reset(self: *Self) void {
            for (&self.channel_processors) |*processor|
                processor.reset();
            for (&self.compressors) |*compressor| compressor.reset();
        }

        pub fn processFrame(
            self: *Self,
            input: [channel_count]Sample,
        ) [channel_count]Sample {
            var separated: [band_count][channel_count]Sample =
                undefined;
            for (&self.channel_processors, 0..) |*processor, channel| {
                const bands = processor.splitBands(input[channel]);
                for (bands, 0..) |sample, band|
                    separated[band][channel] = sample;
            }
            var output: [channel_count]Sample = @splat(0.0);
            for (&separated, &self.compressors) |
                *band_frame,
                *compressor,
            | {
                compressor.processLinkedArray(
                    channel_count,
                    band_frame,
                );
                for (&output, band_frame) |*sample, band_sample|
                    sample.* += band_sample;
            }
            for (&output) |*sample| {
                if (!std.math.isFinite(sample.*)) sample.* = 0.0;
            }
            return output;
        }

        pub fn processInterleaved(
            self: *Self,
            samples: []Sample,
        ) !void {
            if (samples.len % channel_count != 0)
                return error.LinkedMultibandChannelLengthMismatch;
            var offset: usize = 0;
            while (offset < samples.len) : (offset += channel_count) {
                var frame: [channel_count]Sample = undefined;
                for (&frame, 0..) |*sample, channel|
                    sample.* = samples[offset + channel];
                const output = self.processFrame(frame);
                for (output, 0..) |sample, channel|
                    samples[offset + channel] = sample;
            }
        }

        pub fn gainReductionDb(
            self: *const Self,
            band_index: usize,
        ) !f64 {
            if (band_index >= band_count)
                return error.MultibandBandIndexOutOfRange;
            return self.compressors[band_index].gainReductionDb();
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            for (self.channel_processors) |processor| {
                if (!std.meta.eql(processor.config, self.config))
                    return false;
                for (processor.splitters) |splitter| {
                    if (!splitter.valid()) return false;
                }
                for (processor.phase_compensators) |row| {
                    for (row) |compensator| {
                        if (!compensator.valid()) return false;
                    }
                }
            }
            for (self.compressors) |compressor| {
                if (!compressor.valid()) return false;
            }
            return true;
        }
    };
}

fn validateBandCount(comptime band_count: usize) void {
    if (band_count < 2 or band_count > maximum_bands)
        @compileError("multiband dynamics supports 2 through 8 bands");
}

fn validateChannelCount(comptime channel_count: usize) void {
    if (channel_count < 1 or channel_count > maximum_linked_channels)
        @compileError(
            "linked multiband dynamics supports 1 through 16 channels",
        );
}

test "two-band compressor independently controls low and high bands" {
    const Processor = TwoBandCompressor(f64);
    const sample_rate = 48_000.0;
    var processor = try Processor.init(.{
        .sample_rate = sample_rate,
        .crossover_hz = 1_000.0,
        .low = .{
            .sample_rate = sample_rate,
            .threshold_db = -18.0,
            .ratio = 8.0,
            .attack_ms = 0.1,
            .release_ms = 20.0,
        },
        .high = .{
            .sample_rate = sample_rate,
            .threshold_db = 0.0,
            .ratio = 1.0,
            .attack_ms = 0.1,
            .release_ms = 20.0,
        },
    });
    for (0..16_384) |index| {
        const sample = @sin(
            std.math.tau *
                100.0 *
                @as(f64, @floatFromInt(index)) /
                sample_rate,
        );
        _ = processor.processSample(sample);
    }
    try std.testing.expect(processor.lowGainReductionDb() < -6.0);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        processor.highGainReductionDb(),
        0.000_001,
    );
}

test "four-band unity compression preserves magnitude across bands" {
    const Processor = MultibandCompressor(f64, 4);
    const sample_rate = 48_000.0;
    const config = MultibandConfig(4){
        .sample_rate = sample_rate,
        .crossover_hz = .{ 200.0, 1_500.0, 6_000.0 },
        .bands = @splat(.{
            .sample_rate = sample_rate,
            .threshold_db = 0.0,
            .ratio = 1.0,
        }),
    };
    for ([_]f64{ 60.0, 200.0, 700.0, 1_500.0, 3_000.0, 6_000.0, 12_000.0 }) |
        frequency,
    | {
        var processor = try Processor.init(config);
        var input_energy: f64 = 0.0;
        var output_energy: f64 = 0.0;
        for (0..24_576) |index| {
            const input = @sin(
                std.math.tau * frequency *
                    @as(f64, @floatFromInt(index)) / sample_rate,
            );
            const output = processor.processSample(input);
            if (index >= 8_192) {
                input_energy += input * input;
                output_energy += output * output;
            }
        }
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            output_energy / input_energy,
            0.004,
        );
    }
}

test "three-band compressor controls bands independently" {
    const Processor = MultibandCompressor(f64, 3);
    const sample_rate = 48_000.0;
    var processor = try Processor.init(.{
        .sample_rate = sample_rate,
        .crossover_hz = .{ 300.0, 3_000.0 },
        .bands = .{
            .{
                .sample_rate = sample_rate,
                .threshold_db = -18.0,
                .ratio = 10.0,
                .attack_ms = 0.1,
            },
            .{
                .sample_rate = sample_rate,
                .threshold_db = 0.0,
                .ratio = 1.0,
            },
            .{
                .sample_rate = sample_rate,
                .threshold_db = 0.0,
                .ratio = 1.0,
            },
        },
    });
    for (0..24_576) |index| {
        const input = @sin(
            std.math.tau * 80.0 *
                @as(f64, @floatFromInt(index)) / sample_rate,
        );
        _ = processor.processSample(input);
    }
    try std.testing.expect(try processor.gainReductionDb(0) < -8.0);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        try processor.gainReductionDb(1),
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        try processor.gainReductionDb(2),
        0.000_001,
    );
    try std.testing.expectError(
        error.MultibandBandIndexOutOfRange,
        processor.gainReductionDb(3),
    );
}

test "three-band unity impulse matches SciPy 1.17" {
    const Processor = MultibandCompressor(f64, 3);
    var processor = try Processor.init(.{
        .sample_rate = 48_000.0,
        .crossover_hz = .{ 400.0, 4_000.0 },
        .bands = @splat(.{
            .sample_rate = 48_000.0,
            .threshold_db = 0.0,
            .ratio = 1.0,
        }),
    });
    const reference = [_]f64{
        0.44350509954063211,
        -0.68642912961071156,
        -0.046364219532446425,
        0.23773680569254474,
        0.2977753008455557,
        0.24102140622899942,
        0.14174657891074194,
        0.043759967567028484,
        -0.032349737018190994,
        -0.081158762828318118,
        -0.10555879325115639,
        -0.11183944815977225,
        -0.10666693072679161,
        -0.095566387124857516,
        -0.082422871368012268,
        -0.069567588141467102,
        -0.058126597854621667,
        -0.048425852097773302,
        -0.040342960861660497,
        -0.03356389251698115,
        -0.027743462668669869,
        -0.022588111025246015,
        -0.017885184707174699,
        -0.013500883642493459,
        -0.009363652617995582,
        -0.005443916712047329,
        -0.0017360877475998092,
        0.001754777213658555,
        0.005021449484236036,
        0.008058995402679704,
        0.010866440775372426,
        0.013446763558136182,
    };
    for (reference, 0..) |expected, index| {
        const input: f64 = if (index == 0) 1.0 else 0.0;
        try std.testing.expectApproxEqAbs(
            expected,
            processor.processSample(input),
            2.0e-14,
        );
    }
}

test "multiband processing is partition independent" {
    const Processor = MultibandCompressor(f32, 3);
    const config = MultibandConfig(3){
        .sample_rate = 48_000.0,
        .crossover_hz = .{ 400.0, 4_000.0 },
        .bands = @splat(.{
            .sample_rate = 48_000.0,
            .threshold_db = -12.0,
            .ratio = 3.0,
        }),
    };
    var input: [257]f32 = undefined;
    for (&input, 0..) |*sample, index|
        sample.* = @sin(
            std.math.tau * 937.0 *
                @as(f32, @floatFromInt(index)) / 48_000.0,
        );
    var whole = try Processor.init(config);
    var whole_output = input;
    whole.process(&whole_output);
    var partitioned = try Processor.init(config);
    var partitioned_output = input;
    partitioned.process(partitioned_output[0..73]);
    partitioned.process(partitioned_output[73..191]);
    partitioned.process(partitioned_output[191..]);
    try std.testing.expectEqualSlices(
        f32,
        &whole_output,
        &partitioned_output,
    );
}

test "multiband configuration is transactional and hostile state recovers" {
    const Processor = MultibandCompressor(f32, 3);
    const config = MultibandConfig(3){
        .sample_rate = 48_000.0,
        .crossover_hz = .{ 500.0, 5_000.0 },
        .bands = @splat(.{
            .sample_rate = 48_000.0,
            .threshold_db = -12.0,
            .ratio = 2.0,
        }),
    };
    var processor = try Processor.init(config);
    var invalid = config;
    invalid.crossover_hz = .{ 5_000.0, 500.0 };
    try std.testing.expectError(
        error.InvalidMultibandCompressorConfig,
        processor.configure(invalid, 64),
    );
    try std.testing.expectEqualDeep(config, processor.config);
    processor.compressors[1].envelope = std.math.nan(f64);
    const output = processor.processSample(0.25);
    try std.testing.expect(std.math.isFinite(output));
    try std.testing.expect(processor.valid());
}

test "linked multiband compression preserves stereo image and isolation" {
    const Processor = LinkedMultibandCompressor(f64, 3, 2);
    const config = MultibandConfig(3){
        .sample_rate = 48_000.0,
        .crossover_hz = .{ 300.0, 3_000.0 },
        .bands = @splat(.{
            .sample_rate = 48_000.0,
            .threshold_db = -18.0,
            .ratio = 6.0,
            .attack_ms = 0.1,
            .release_ms = 20.0,
        }),
    };
    var processor = try Processor.init(config);
    var output: [2]f64 = undefined;
    for (0..8_192) |_|
        output = processor.processFrame(.{ 1.0, 0.1 });
    try std.testing.expectApproxEqAbs(
        @as(f64, 10.0),
        output[0] / output[1],
        0.000_001,
    );
    var reduction_detected = false;
    for (0..3) |band| {
        if (try processor.gainReductionDb(band) < -1.0)
            reduction_detected = true;
    }
    try std.testing.expect(reduction_detected);

    processor.reset();
    for (0..1_024) |index| {
        const input = @sin(
            std.math.tau * 700.0 *
                @as(f64, @floatFromInt(index)) / 48_000.0,
        );
        output = processor.processFrame(.{ input, 0.0 });
        try std.testing.expectEqual(@as(f64, 0.0), output[1]);
    }
}

test "linked multiband interleaved processing is partition independent" {
    const Processor = LinkedMultibandCompressor(f32, 4, 2);
    const config = MultibandConfig(4){
        .sample_rate = 48_000.0,
        .crossover_hz = .{ 200.0, 1_200.0, 6_000.0 },
        .bands = @splat(.{
            .sample_rate = 48_000.0,
            .threshold_db = -12.0,
            .ratio = 3.0,
        }),
    };
    var input: [514]f32 = undefined;
    for (0..257) |frame| {
        const phase = std.math.tau * 937.0 *
            @as(f32, @floatFromInt(frame)) / 48_000.0;
        input[frame * 2] = @sin(phase);
        input[frame * 2 + 1] = 0.25 * @cos(phase);
    }
    var whole = try Processor.init(config);
    var whole_output = input;
    try whole.processInterleaved(&whole_output);
    var partitioned = try Processor.init(config);
    var partitioned_output = input;
    try partitioned.processInterleaved(partitioned_output[0 .. 73 * 2]);
    try partitioned.processInterleaved(
        partitioned_output[73 * 2 .. 191 * 2],
    );
    try partitioned.processInterleaved(partitioned_output[191 * 2 ..]);
    try std.testing.expectEqualSlices(
        f32,
        &whole_output,
        &partitioned_output,
    );
    var malformed = [_]f32{ 0.1, 0.2, 0.3 };
    const retained = malformed;
    try std.testing.expectError(
        error.LinkedMultibandChannelLengthMismatch,
        partitioned.processInterleaved(&malformed),
    );
    try std.testing.expectEqualSlices(f32, &retained, &malformed);
}

test "two-band unity compression preserves crossover magnitude" {
    const Processor = TwoBandCompressor(f32);
    const sample_rate = 48_000.0;
    var processor = try Processor.init(.{
        .sample_rate = sample_rate,
        .crossover_hz = 2_000.0,
        .low = .{
            .sample_rate = sample_rate,
            .threshold_db = 0.0,
            .ratio = 1.0,
        },
        .high = .{
            .sample_rate = sample_rate,
            .threshold_db = 0.0,
            .ratio = 1.0,
        },
    });
    var input_energy: f64 = 0.0;
    var output_energy: f64 = 0.0;
    for (0..16_384) |index| {
        const input: f32 = @floatCast(@sin(
            std.math.tau *
                2_000.0 *
                @as(f64, @floatFromInt(index)) /
                sample_rate,
        ));
        const output = processor.processSample(input);
        if (index > 4_096) {
            input_energy += @as(f64, input) * input;
            output_energy += @as(f64, output) * output;
        }
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        output_energy / input_energy,
        0.002,
    );
}
