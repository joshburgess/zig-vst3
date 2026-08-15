const std = @import("std");
const file_reader_io = @import("../file_reader_io.zig");
const syntax = @import("syntax.zig");
const synthesis_window_quantized =
    @import("../mp3_synthesis_window.zig").values;

const Version = syntax.Version;
const ChannelMode = syntax.ChannelMode;
const maximum_free_format_frame_bytes =
    syntax.maximum_free_format_frame_bytes;
const maximum_frame_main_data_bytes =
    syntax.maximum_frame_main_data_bytes;
const Limits = syntax.Limits;
const default_limits = syntax.default_limits;
const decoder_delay_samples = syntax.decoder_delay_samples;
const Header = syntax.Header;
const byteRangesOverlap = syntax.byteRangesOverlap;
const headersCompatible = syntax.headersCompatible;
const bitrateIndex = syntax.bitrateIndex;
const sampleRateIndex = syntax.sampleRateIndex;
const readU32 = syntax.readU32;
const GranuleChannel = syntax.GranuleChannel;
const SideInformation = syntax.SideInformation;
const MainData = syntax.MainData;
const ScaleFactorChannel = syntax.ScaleFactorChannel;
const ScaleFactors = syntax.ScaleFactors;
const ScaleFactorBands = syntax.ScaleFactorBands;
const QuantizedSpectrum = syntax.QuantizedSpectrum;
const RequantizedSpectrum = syntax.RequantizedSpectrum;
const StereoSpectrum = syntax.StereoSpectrum;
const HybridSamples = syntax.HybridSamples;
const PcmGranule = syntax.PcmGranule;
const ScaleFactorLayout = syntax.ScaleFactorLayout;
const scaleFactorLayout = syntax.scaleFactorLayout;
const validateBlockDescription = syntax.validateBlockDescription;
const mixedLongSubbands = syntax.mixedLongSubbands;
const MainDataReservoir = syntax.MainDataReservoir;
const decodeScaleFactors = syntax.decodeScaleFactors;
const scaleFactorBands = syntax.scaleFactorBands;
const huffmanRegionEnds = syntax.huffmanRegionEnds;
const decodeHuffmanChannel = syntax.decodeHuffmanChannel;
const parseSideInformation = syntax.parseSideInformation;

pub const DecoderFormat = struct {
    version: Version,
    sample_rate: u32,
    channel_count: u2,
};

fn headerStateValid(header: Header) bool {
    if (sampleRateIndex(header.version, header.sample_rate) == null)
        return false;
    if (header.free_format) return header.bitrate_kbps == 0;
    return bitrateIndex(header.version, header.bitrate_kbps) != null;
}

pub const PcmFrame = struct {
    channels: [2][1152]f32 = @splat(@splat(0)),
    channel_count: u2,
    sample_count: u16,
};

pub fn formatFromHeader(header: Header) DecoderFormat {
    return .{
        .version = header.version,
        .sample_rate = header.sample_rate,
        .channel_count = @intCast(header.channels()),
    };
}

pub const HybridSynthesis = struct {
    overlap: [32][18]f32 = @splat(@splat(0)),

    pub fn reset(self: *HybridSynthesis) void {
        self.* = .{};
    }

    pub fn valid(self: *const HybridSynthesis) bool {
        for (self.overlap) |subband| {
            for (subband) |sample| {
                if (!std.math.isFinite(sample)) return false;
            }
        }
        return true;
    }

    pub fn process(
        self: *HybridSynthesis,
        header: Header,
        description: GranuleChannel,
        spectrum: RequantizedSpectrum,
    ) !HybridSamples {
        _ = try scaleFactorBands(header);
        try validateBlockDescription(description);
        for (spectrum.lines) |line| {
            if (!std.math.isFinite(line))
                return error.InvalidMp3RequantizedSpectrum;
        }
        if (!self.valid()) return error.InvalidMp3HybridState;

        var output = HybridSamples{};
        var next_overlap: [32][18]f32 = @splat(@splat(0));
        const mixed_long_subbands =
            if (description.mixed_block)
                mixedLongSubbands(header)
            else
                0;
        for (0..32) |subband| {
            const long_mixed = subband < mixed_long_subbands;
            const block = synthesizeHybridBlock(
                description,
                long_mixed,
                spectrum.lines[subband * 18 ..][0..18],
            );
            for (0..18) |time| {
                var combined =
                    block[time] + self.overlap[subband][time];
                if (subband & 1 != 0 and time & 1 != 0)
                    combined = -combined;
                output.time_slots[time][subband] =
                    try checkedHybridSample(combined);
                next_overlap[subband][time] =
                    try checkedHybridSample(block[time + 18]);
            }
        }
        self.overlap = next_overlap;
        return output;
    }
};

pub const PolyphaseSynthesis = struct {
    history: [1024]f64 = @splat(0),
    head_block: u8 = 0,

    pub fn reset(self: *PolyphaseSynthesis) void {
        self.* = .{};
    }

    pub fn valid(self: *const PolyphaseSynthesis) bool {
        if (self.head_block >= 16) return false;
        for (self.history) |value| {
            if (!std.math.isFinite(value)) return false;
        }
        return true;
    }

    pub fn process(
        self: *PolyphaseSynthesis,
        hybrid: HybridSamples,
    ) !PcmGranule {
        if (!self.valid()) return error.InvalidMp3PolyphaseState;
        for (hybrid.time_slots) |time_slot| {
            for (time_slot) |sample| {
                if (!std.math.isFinite(sample))
                    return error.InvalidMp3HybridSamples;
            }
        }

        var next = self.*;
        var output = PcmGranule{};
        for (hybrid.time_slots, 0..) |time_slot, time| {
            next.head_block =
                (next.head_block + 15) & 15;
            const head =
                @as(usize, next.head_block) * 64;
            for (synthesis_matrix, 0..) |row, index| {
                var value: f64 = 0;
                for (row, time_slot) |coefficient, sample|
                    value += coefficient * sample;
                if (!std.math.isFinite(value))
                    return error.InvalidMp3PolyphaseSample;
                next.history[head + index] = value;
            }

            for (0..32) |sample| {
                var value: f64 = 0;
                for (0..16) |phase| {
                    const window_index = sample + 32 * phase;
                    const group = window_index / 64;
                    const offset = window_index % 64;
                    const logical_index = group * 128 +
                        if (offset < 32)
                            offset
                        else
                            offset + 64;
                    const history_index =
                        (head + logical_index) % 1024;
                    value += next.history[history_index] *
                        synthesis_window[window_index];
                }
                output.samples[time * 32 + sample] =
                    try checkedPolyphaseSample(value);
            }
        }
        self.* = next;
        return output;
    }
};

pub const FrameDecoder = struct {
    reservoir: MainDataReservoir(511) = .{},
    hybrid: [2]HybridSynthesis = @splat(.{}),
    polyphase: [2]PolyphaseSynthesis = @splat(.{}),
    format: ?DecoderFormat = null,

    pub fn reset(self: *FrameDecoder) void {
        self.* = .{};
    }

    pub fn valid(self: *const FrameDecoder) bool {
        if (!self.reservoir.valid()) return false;
        for (0..2) |channel| {
            if (!self.hybrid[channel].valid() or
                !self.polyphase[channel].valid())
                return false;
        }
        const format = self.format orelse
            return self.reservoir.length == 0 and
                std.meta.eql(self.hybrid, @as([2]HybridSynthesis, @splat(.{}))) and
                std.meta.eql(self.polyphase, @as([2]PolyphaseSynthesis, @splat(.{})));
        if (format.channel_count == 0 or
            format.channel_count > 2 or
            sampleRateIndex(format.version, format.sample_rate) == null)
            return false;
        for (format.channel_count..2) |channel| {
            if (!std.meta.eql(self.hybrid[channel], HybridSynthesis{}) or
                !std.meta.eql(self.polyphase[channel], PolyphaseSynthesis{}))
                return false;
        }
        return true;
    }

    pub fn decode(
        self: *FrameDecoder,
        frame: anytype,
    ) !PcmFrame {
        if (!self.reservoir.valid())
            return error.InvalidMp3ReservoirState;
        if (!self.valid()) return error.InvalidMp3DecoderState;
        if (try frame.crcValid()) |crc_ok| {
            if (!crc_ok) return error.InvalidMp3FrameCrc;
        }
        const format = formatFromHeader(frame.header);
        if (self.format) |active| {
            if (!std.meta.eql(active, format))
                return error.Mp3DecoderFormatChanged;
        }

        var next = self.*;
        var main_storage: [maximum_frame_main_data_bytes]u8 = undefined;
        const main_data = try next.reservoir.assemble(
            frame,
            &main_storage,
        );
        const side = try frame.sideInformation();
        const factors = try decodeScaleFactors(
            frame.header,
            side,
            main_data,
        );
        var output = PcmFrame{
            .channel_count = format.channel_count,
            .sample_count = frame.header.samplesPerFrame(),
        };
        for (0..side.granule_count) |granule| {
            var spectra: [2]RequantizedSpectrum = @splat(.{});
            for (0..side.channel_count) |channel| {
                const description =
                    side.granules[granule].channels[channel];
                const scale_factors =
                    factors.granules[granule].channels[channel];
                const quantized = try decodeHuffmanChannel(
                    frame.header,
                    description,
                    scale_factors,
                    main_data,
                );
                spectra[channel] = try requantizeChannel(
                    frame.header,
                    description,
                    scale_factors,
                    quantized,
                );
            }
            if (side.channel_count == 2) {
                spectra = (try processStereo(
                    frame.header,
                    side.granules[granule].channels,
                    factors.granules[granule].channels,
                    spectra,
                )).channels;
            }
            for (0..side.channel_count) |channel| {
                const description =
                    side.granules[granule].channels[channel];
                const reduced = try reduceAliases(
                    frame.header,
                    description,
                    spectra[channel],
                );
                const hybrid = try next.hybrid[channel].process(
                    frame.header,
                    description,
                    reduced,
                );
                const pcm = try next.polyphase[channel].process(
                    hybrid,
                );
                const start = granule * pcm.samples.len;
                @memcpy(
                    output.channels[channel][start..][0..pcm.samples.len],
                    &pcm.samples,
                );
            }
        }
        next.format = format;
        self.* = next;
        return output;
    }
};

pub const PcmRange = struct {
    start: u16,
    length: u16,
};

pub const TrimmedPcmFrame = struct {
    pcm: PcmFrame,
    audible: PcmRange,
};

pub const GaplessPlan = struct {
    encoded_samples: u64,
    leading_samples: u32,
    trailing_samples: u32,
    audible_samples: u64,

    pub fn valid(self: *const GaplessPlan) bool {
        const trimmed = std.math.add(
            u64,
            self.leading_samples,
            self.trailing_samples,
        ) catch return false;
        return trimmed <= self.encoded_samples and
            self.audible_samples == self.encoded_samples - trimmed;
    }

    pub fn fromSummary(summary: Summary) !GaplessPlan {
        var leading: u32 = 0;
        var trailing: u32 = 0;
        if (summary.first_xing) |xing| {
            if ((xing.encoder_delay == null) !=
                (xing.encoder_padding == null))
                return error.InvalidMp3GaplessMetadata;
            if (xing.encoder_delay) |delay| {
                const metadata_samples: u32 =
                    if (summary.sample_rate >= 32_000) 1152 else 576;
                const encoder_and_metadata = std.math.add(
                    u32,
                    delay,
                    metadata_samples,
                ) catch return error.InvalidMp3GaplessMetadata;
                leading = std.math.add(
                    u32,
                    encoder_and_metadata,
                    decoder_delay_samples,
                ) catch return error.InvalidMp3GaplessMetadata;
                const stored_padding = xing.encoder_padding orelse
                    return error.InvalidMp3GaplessMetadata;
                if (stored_padding < decoder_delay_samples)
                    return error.InvalidMp3GaplessMetadata;
                trailing = stored_padding - decoder_delay_samples;
            }
        } else if (summary.first_vbri != null) {
            leading = if (summary.sample_rate >= 32_000) 1152 else 576;
        }
        const trimmed = std.math.add(
            u64,
            leading,
            trailing,
        ) catch return error.InvalidMp3GaplessMetadata;
        if (trimmed > summary.sample_count)
            return error.InvalidMp3GaplessMetadata;
        return .{
            .encoded_samples = summary.sample_count,
            .leading_samples = leading,
            .trailing_samples = trailing,
            .audible_samples = summary.sample_count - trimmed,
        };
    }

    pub fn frameRange(
        self: GaplessPlan,
        sample_offset: u64,
        sample_count: u16,
    ) !PcmRange {
        if (!self.valid() or
            sample_offset > self.encoded_samples or
            sample_count > self.encoded_samples - sample_offset)
            return error.InvalidMp3GaplessPlan;
        const frame_end = sample_offset + sample_count;
        const audible_start: u64 = self.leading_samples;
        const audible_end =
            self.encoded_samples - self.trailing_samples;
        const start = @max(sample_offset, audible_start);
        const end = @min(frame_end, audible_end);
        if (end <= start) {
            return .{
                .start = if (frame_end <= audible_start)
                    sample_count
                else
                    0,
                .length = 0,
            };
        }
        return .{
            .start = @intCast(start - sample_offset),
            .length = @intCast(end - start),
        };
    }
};

pub const StreamDecoder = struct {
    decoder: FrameDecoder = .{},
    plan: GaplessPlan,
    sample_rate: u32,
    channel_count: u2,
    sample_offset: u64 = 0,

    pub fn init(summary: Summary) !StreamDecoder {
        const samples_per_frame =
            mp3SamplesPerFrameForRate(summary.sample_rate) orelse
            return error.InvalidMp3Summary;
        const encoded_samples = std.math.mul(
            u64,
            summary.frame_count,
            samples_per_frame,
        ) catch return error.InvalidMp3Summary;
        if (summary.frame_count == 0 or
            summary.sample_count != encoded_samples or
            summary.channels == 0 or
            summary.channels > 2)
            return error.InvalidMp3Summary;
        return .{
            .plan = try GaplessPlan.fromSummary(summary),
            .sample_rate = summary.sample_rate,
            .channel_count = @intCast(summary.channels),
        };
    }

    pub fn reset(self: *StreamDecoder) void {
        self.decoder.reset();
        self.sample_offset = 0;
    }

    pub fn valid(self: *const StreamDecoder) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn decode(
        self: *StreamDecoder,
        frame: anytype,
    ) !TrimmedPcmFrame {
        try self.validateState();
        if (frame.header.sample_rate != self.sample_rate or
            frame.header.channels() != self.channel_count)
            return error.Mp3DecoderFormatChanged;
        var next = self.*;
        const pcm = try next.decoder.decode(frame);
        const audible = try next.plan.frameRange(
            next.sample_offset,
            pcm.sample_count,
        );
        next.sample_offset = std.math.add(
            u64,
            next.sample_offset,
            pcm.sample_count,
        ) catch return error.Mp3SampleCountOverflow;
        self.* = next;
        return .{
            .pcm = pcm,
            .audible = audible,
        };
    }

    pub fn finish(self: StreamDecoder) !void {
        try self.validateState();
        if (self.sample_offset != self.plan.encoded_samples)
            return error.Mp3GaplessStreamIncomplete;
    }

    fn validateState(self: StreamDecoder) !void {
        if (!mp3SampleRateValid(self.sample_rate) or
            self.channel_count == 0 or
            self.channel_count > 2 or
            !self.decoder.valid() or
            self.sample_offset > self.plan.encoded_samples)
            return error.InvalidMp3StreamDecoderState;
        if (!self.plan.valid()) return error.InvalidMp3GaplessPlan;
        const samples_per_frame =
            mp3SamplesPerFrameForRate(self.sample_rate) orelse
            return error.InvalidMp3StreamDecoderState;
        if (self.sample_offset % samples_per_frame != 0)
            return error.InvalidMp3StreamDecoderState;
        if (self.decoder.format) |format| {
            if (format.sample_rate != self.sample_rate or
                format.channel_count != self.channel_count or
                self.sample_offset == 0)
                return error.InvalidMp3StreamDecoderState;
        } else if (self.sample_offset != 0) {
            return error.InvalidMp3StreamDecoderState;
        }
    }
};

pub fn mp3SampleRateValid(sample_rate: u32) bool {
    return mp3SamplesPerFrameForRate(sample_rate) != null;
}

pub fn mp3SamplesPerFrameForRate(sample_rate: u32) ?u16 {
    if (sampleRateIndex(.mpeg1, sample_rate) != null) return 1152;
    if (sampleRateIndex(.mpeg2, sample_rate) != null or
        sampleRateIndex(.mpeg25, sample_rate) != null)
        return 576;
    return null;
}

pub fn requantizeChannel(
    header: Header,
    description: GranuleChannel,
    factors: ScaleFactorChannel,
    quantized: QuantizedSpectrum,
) !RequantizedSpectrum {
    if (quantized.decoded_lines > quantized.lines.len)
        return error.InvalidMp3QuantizedSpectrum;
    for (quantized.lines[quantized.decoded_lines..]) |line| {
        if (line != 0) return error.InvalidMp3QuantizedSpectrum;
    }
    const layout = try scaleFactorLayout(
        header,
        description,
        factors,
    );
    const bands = layout.bands;
    const short_block = layout.short_block;
    const short_boundary = layout.short_boundary;
    const long_factor_count = layout.long_factor_count;

    var result = RequantizedSpectrum{};
    const global_exponent =
        (@as(f64, description.global_gain) - 210.0) * 0.25;
    const scale_multiplier: f64 =
        if (description.scalefac_scale) 1.0 else 0.5;
    const pretab = [_]u2{
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 2, 2, 3, 3, 3, 2, 0,
    };

    if (!short_block or description.mixed_block) {
        const band_count =
            if (short_block) long_factor_count else 22;
        for (0..band_count) |band| {
            const scale_factor: f64 =
                @floatFromInt(factors.values[band]);
            const preemphasis: f64 = if (factors.preflag)
                @floatFromInt(pretab[band])
            else
                0.0;
            const exponent = global_exponent -
                scale_multiplier * (scale_factor + preemphasis);
            for (bands.long_starts[band]..bands.long_starts[band + 1]) |line| result.lines[line] = try requantizeLine(
                quantized.lines[line],
                exponent,
            );
        }
    }

    if (short_block) {
        const first_short_band: usize =
            if (description.mixed_block) 3 else 0;
        var source: usize =
            if (description.mixed_block) short_boundary else 0;
        for (first_short_band..13) |band| {
            const width: usize =
                bands.short_starts[band + 1] -
                bands.short_starts[band];
            for (0..3) |window| {
                const factor_index = if (description.mixed_block)
                    long_factor_count + (band - 3) * 3 + window
                else
                    band * 3 + window;
                const scale_factor: f64 = if (factor_index <
                    factors.value_count)
                    @floatFromInt(factors.values[factor_index])
                else
                    0.0;
                const exponent = global_exponent -
                    2.0 * @as(f64, @floatFromInt(
                        description.subblock_gain[window],
                    )) -
                    scale_multiplier * scale_factor;
                for (0..width) |offset| {
                    const destination =
                        3 * (@as(usize, bands.short_starts[band]) +
                            offset) +
                        window;
                    result.lines[destination] = try requantizeLine(
                        quantized.lines[source],
                        exponent,
                    );
                    source += 1;
                }
            }
        }
        if (source != quantized.lines.len)
            return error.InvalidMp3ScaleFactorBands;
    }
    return result;
}

fn requantizeLine(value: i32, exponent: f64) !f32 {
    const magnitude: i64 =
        if (value < 0) -@as(i64, value) else value;
    if (magnitude > 8206)
        return error.InvalidMp3QuantizedValue;
    if (magnitude == 0) return 0.0;
    const scaled = std.math.pow(
        f64,
        @floatFromInt(magnitude),
        4.0 / 3.0,
    ) * std.math.exp2(exponent);
    if (!std.math.isFinite(scaled))
        return error.InvalidMp3RequantizedValue;
    const signed = if (value < 0) -scaled else scaled;
    return @floatCast(signed);
}

pub fn processStereo(
    header: Header,
    descriptions: [2]GranuleChannel,
    factors: [2]ScaleFactorChannel,
    spectra: [2]RequantizedSpectrum,
) !StereoSpectrum {
    if (header.channels() != 2)
        return error.InvalidMp3StereoChannels;
    const layouts = [2]ScaleFactorLayout{
        try scaleFactorLayout(header, descriptions[0], factors[0]),
        try scaleFactorLayout(header, descriptions[1], factors[1]),
    };
    for (spectra) |spectrum| {
        for (spectrum.lines) |line| {
            if (!std.math.isFinite(line))
                return error.InvalidMp3RequantizedSpectrum;
        }
    }

    var result = StereoSpectrum{ .channels = spectra };
    if (header.channel_mode != .joint_stereo or
        header.mode_extension == 0)
        return result;
    if (descriptions[0].window_switching !=
        descriptions[1].window_switching or
        descriptions[0].block_type != descriptions[1].block_type or
        descriptions[0].mixed_block != descriptions[1].mixed_block)
        return error.InvalidMp3StereoBlocks;

    const intensity = header.mode_extension & 1 != 0;
    const mid_side = header.mode_extension & 2 != 0;
    if (intensity) {
        if (layouts[1].short_block) {
            try processShortStereo(
                header,
                descriptions[1],
                factors[1],
                layouts[1],
                mid_side,
                &result.channels,
            );
        } else {
            try processLongStereo(
                header,
                factors[1],
                layouts[1],
                mid_side,
                &result.channels,
            );
        }
    } else if (mid_side) {
        applyMidSideRange(&result.channels, 0, 576);
    }
    return result;
}

pub fn reduceAliases(
    header: Header,
    description: GranuleChannel,
    spectrum: RequantizedSpectrum,
) !RequantizedSpectrum {
    _ = try scaleFactorBands(header);
    try validateBlockDescription(description);
    for (spectrum.lines) |line| {
        if (!std.math.isFinite(line))
            return error.InvalidMp3RequantizedSpectrum;
    }

    const subband_count: usize = if (description.block_type != 2)
        32
    else if (!description.mixed_block)
        0
    else
        mixedLongSubbands(header);
    var result = spectrum;
    var subband: usize = 1;
    while (subband < subband_count) : (subband += 1) {
        const boundary = 18 * subband;
        for (alias_cs, alias_ca, 0..) |cs, ca, index| {
            const upper = boundary - 1 - index;
            const lower = boundary + index;
            const upper_value = spectrum.lines[upper];
            const lower_value = spectrum.lines[lower];
            result.lines[upper] =
                upper_value * cs - lower_value * ca;
            result.lines[lower] =
                lower_value * cs + upper_value * ca;
        }
    }
    return result;
}

pub fn prepareAliasesForEncoding(
    header: Header,
    description: GranuleChannel,
    spectrum: RequantizedSpectrum,
) !RequantizedSpectrum {
    _ = try scaleFactorBands(header);
    try validateBlockDescription(description);
    for (spectrum.lines) |line| {
        if (!std.math.isFinite(line))
            return error.InvalidMp3RequantizedSpectrum;
    }

    const subband_count: usize = if (description.block_type != 2)
        32
    else if (!description.mixed_block)
        0
    else
        mixedLongSubbands(header);
    var result = spectrum;
    var subband: usize = 1;
    while (subband < subband_count) : (subband += 1) {
        const boundary = 18 * subband;
        for (alias_cs, alias_ca, 0..) |cs, ca, index| {
            const upper = boundary - 1 - index;
            const lower = boundary + index;
            const upper_value = spectrum.lines[upper];
            const lower_value = spectrum.lines[lower];
            result.lines[upper] =
                upper_value * cs + lower_value * ca;
            result.lines[lower] =
                lower_value * cs - upper_value * ca;
        }
    }
    return result;
}

pub const alias_cs = [_]f32{
    0.8574929257125442,
    0.8817419973177052,
    0.9496286491027328,
    0.9833145924917902,
    0.9955178160675858,
    0.9991605581781475,
    0.9998991952434471,
    0.9999931550702803,
};

pub const alias_ca = [_]f32{
    -0.5144957554275265,
    -0.47173196856497235,
    -0.31337745420390184,
    -0.18191319961098118,
    -0.09457419252642066,
    -0.04096558288530405,
    -0.01419856857247115,
    -0.0036999746737600373,
};

fn buildImdctMatrix(
    comptime input_count: usize,
) [input_count * 2][input_count]f64 {
    var result: [input_count * 2][input_count]f64 = undefined;
    const count: f64 = @floatFromInt(input_count);
    for (0..input_count * 2) |time| {
        const time_value: f64 = @floatFromInt(time);
        for (0..input_count) |frequency| {
            const frequency_value: f64 = @floatFromInt(frequency);
            result[time][frequency] = @cos(
                std.math.pi / count *
                    (time_value + 0.5 + count * 0.5) *
                    (frequency_value + 0.5),
            );
        }
    }
    return result;
}

fn buildLongWindows() [4][36]f64 {
    var result: [4][36]f64 = @splat(@splat(0));
    for (0..36) |time| {
        const position: f64 = @floatFromInt(time);
        result[0][time] = @sin(
            std.math.pi / 36.0 * (position + 0.5),
        );
        if (time < 18) {
            result[1][time] = result[0][time];
        } else if (time < 24) {
            result[1][time] = 1;
        } else if (time < 30) {
            result[1][time] = @sin(
                std.math.pi / 12.0 * (position - 17.5),
            );
        }
        if (time >= 6 and time < 12) {
            result[3][time] = @sin(
                std.math.pi / 12.0 * (position - 5.5),
            );
        } else if (time >= 12 and time < 18) {
            result[3][time] = 1;
        } else if (time >= 18) {
            result[3][time] = result[0][time];
        }
    }
    return result;
}

fn buildShortWindow() [12]f64 {
    var result: [12]f64 = undefined;
    for (0..12) |time| {
        const position: f64 = @floatFromInt(time);
        result[time] = @sin(
            std.math.pi / 12.0 * (position + 0.5),
        );
    }
    return result;
}

fn buildSynthesisMatrix() [64][32]f64 {
    @setEvalBranchQuota(4_096);
    var result: [64][32]f64 = undefined;
    for (0..64) |row| {
        const row_value: f64 = @floatFromInt(16 + row);
        for (0..32) |band| {
            const band_value: f64 = @floatFromInt(2 * band + 1);
            result[row][band] = @cos(
                row_value * band_value * std.math.pi / 64.0,
            );
        }
    }
    return result;
}

fn buildAnalysisMatrix() [32][64]f64 {
    @setEvalBranchQuota(4_096);
    var result: [32][64]f64 = undefined;
    for (0..32) |band| {
        const band_value: f64 = @floatFromInt(2 * band + 1);
        for (0..64) |phase| {
            const phase_value: f64 =
                @floatFromInt(@as(i8, @intCast(phase)) - 16);
            result[band][phase] = @cos(
                band_value * phase_value * std.math.pi / 64.0,
            );
        }
    }
    return result;
}

fn buildSynthesisWindow() [512]f64 {
    var result: [512]f64 = undefined;
    for (synthesis_window_quantized, 0..) |value, index| {
        result[index] =
            @as(f64, @floatFromInt(value)) / 65_536.0;
    }
    return result;
}

fn buildAnalysisWindow() [512]f64 {
    var result: [512]f64 = undefined;
    for (synthesis_window, 0..) |value, index|
        result[index] = value / 32.0;
    return result;
}

pub const long_imdct = buildImdctMatrix(18);
const short_imdct = buildImdctMatrix(6);
const long_windows = buildLongWindows();
const short_window = buildShortWindow();
pub const synthesis_matrix = buildSynthesisMatrix();
const synthesis_window = buildSynthesisWindow();
pub const analysis_matrix = buildAnalysisMatrix();
pub const analysis_window = buildAnalysisWindow();

fn synthesizeHybridBlock(
    description: GranuleChannel,
    long_mixed: bool,
    spectrum: *const [18]f32,
) [36]f64 {
    var result: [36]f64 = @splat(0);
    if (description.block_type == 2 and !long_mixed) {
        for (0..3) |window| {
            for (0..12) |time| {
                var transformed: f64 = 0;
                for (0..6) |frequency| {
                    transformed +=
                        spectrum[frequency * 3 + window] *
                        short_imdct[time][frequency];
                }
                result[6 + window * 6 + time] +=
                    transformed * short_window[time];
            }
        }
        return result;
    }

    const window_type: usize =
        if (long_mixed) 0 else description.block_type;
    for (0..36) |time| {
        var transformed: f64 = 0;
        for (spectrum, 0..) |sample, frequency|
            transformed += sample * long_imdct[time][frequency];
        result[time] =
            transformed * long_windows[window_type][time];
    }
    return result;
}

pub fn analyzeHybridBlock(
    description: GranuleChannel,
    long_mixed: bool,
    samples: *const [36]f32,
) [18]f64 {
    var result: [18]f64 = @splat(0);
    if (description.block_type == 2 and !long_mixed) {
        for (0..3) |window| {
            for (0..6) |frequency| {
                var transformed: f64 = 0;
                for (0..12) |time| {
                    transformed +=
                        samples[6 + window * 6 + time] *
                        short_window[time] *
                        short_imdct[time][frequency];
                }
                result[frequency * 3 + window] =
                    transformed / 3.0;
            }
        }
        return result;
    }

    const window_type: usize =
        if (long_mixed) 0 else description.block_type;
    for (0..18) |frequency| {
        var transformed: f64 = 0;
        for (samples, 0..) |sample, time| {
            transformed += sample *
                long_windows[window_type][time] *
                long_imdct[time][frequency];
        }
        result[frequency] = transformed / 9.0;
    }
    return result;
}

pub fn checkedHybridSample(value: f64) !f32 {
    if (!std.math.isFinite(value) or
        value < -std.math.floatMax(f32) or
        value > std.math.floatMax(f32))
        return error.InvalidMp3HybridSample;
    return @floatCast(value);
}

fn checkedPolyphaseSample(value: f64) !f32 {
    if (!std.math.isFinite(value) or
        value < -std.math.floatMax(f32) or
        value > std.math.floatMax(f32))
        return error.InvalidMp3PolyphaseSample;
    return @floatCast(value);
}

fn processLongStereo(
    header: Header,
    factors: ScaleFactorChannel,
    layout: ScaleFactorLayout,
    mid_side: bool,
    channels: *[2]RequantizedSpectrum,
) !void {
    var last_nonzero: ?usize = null;
    for (0..22) |band| {
        const start: usize = layout.bands.long_starts[band];
        const end: usize = layout.bands.long_starts[band + 1];
        if (containsNonzero(channels[1].lines[start..end]))
            last_nonzero = band;
    }
    for (0..22) |band| {
        const start: usize = layout.bands.long_starts[band];
        const end: usize = layout.bands.long_starts[band + 1];
        const above_last_nonzero = if (last_nonzero) |last|
            band > last
        else
            true;
        if (above_last_nonzero and
            try intensityPositionValid(header, factors, band))
        {
            try applyIntensityRange(
                header,
                factors,
                band,
                channels,
                start,
                end,
            );
        } else if (mid_side) {
            applyMidSideRange(channels, start, end);
        }
    }
}

fn processShortStereo(
    header: Header,
    description: GranuleChannel,
    factors: ScaleFactorChannel,
    layout: ScaleFactorLayout,
    mid_side: bool,
    channels: *[2]RequantizedSpectrum,
) !void {
    const first_band: usize =
        if (description.mixed_block) 3 else 0;
    if (description.mixed_block and mid_side)
        applyMidSideRange(channels, 0, layout.short_boundary);

    var last_nonzero: [3]?usize = @splat(null);
    for (first_band..13) |band| {
        const width: usize =
            layout.bands.short_starts[band + 1] -
            layout.bands.short_starts[band];
        for (0..3) |window| {
            var nonzero = false;
            for (0..width) |offset| {
                const line =
                    3 * (@as(usize, layout.bands.short_starts[band]) +
                        offset) +
                    window;
                nonzero = nonzero or channels[1].lines[line] != 0;
            }
            if (nonzero) last_nonzero[window] = band;
        }
    }

    for (first_band..13) |band| {
        const width: usize =
            layout.bands.short_starts[band + 1] -
            layout.bands.short_starts[band];
        for (0..3) |window| {
            const factor_index = if (description.mixed_block)
                layout.long_factor_count + (band - 3) * 3 + window
            else
                band * 3 + window;
            const above_last_nonzero = if (last_nonzero[window]) |last|
                band > last
            else
                true;
            const use_intensity = above_last_nonzero and
                try intensityPositionValid(
                    header,
                    factors,
                    factor_index,
                );
            for (0..width) |offset| {
                const line =
                    3 * (@as(usize, layout.bands.short_starts[band]) +
                        offset) +
                    window;
                if (use_intensity) {
                    try applyIntensityLine(
                        header,
                        factors,
                        factor_index,
                        channels,
                        line,
                    );
                } else if (mid_side) {
                    applyMidSideLine(channels, line);
                }
            }
        }
    }
}

fn intensityPositionValid(
    header: Header,
    factors: ScaleFactorChannel,
    index: usize,
) !bool {
    const position = factors.values[index];
    return switch (header.version) {
        .mpeg1 => if (position > 7)
            error.InvalidMp3IntensityPosition
        else
            position != 7,
        .mpeg2, .mpeg25 => if (position > 15)
            error.InvalidMp3IntensityPosition
        else
            !factors.intensity_max[index],
    };
}

fn applyIntensityRange(
    header: Header,
    factors: ScaleFactorChannel,
    factor_index: usize,
    channels: *[2]RequantizedSpectrum,
    start: usize,
    end: usize,
) !void {
    for (start..end) |line|
        try applyIntensityLine(
            header,
            factors,
            factor_index,
            channels,
            line,
        );
}

fn applyIntensityLine(
    header: Header,
    factors: ScaleFactorChannel,
    factor_index: usize,
    channels: *[2]RequantizedSpectrum,
    line: usize,
) !void {
    const position = factors.values[factor_index];
    const gains = switch (header.version) {
        .mpeg1 => mpeg1IntensityGains(position),
        .mpeg2, .mpeg25 => lsfIntensityGains(
            position,
            factors.intensity_scale,
        ),
    };
    const combined = channels[0].lines[line];
    channels[0].lines[line] = combined * gains[0];
    channels[1].lines[line] = combined * gains[1];
}

pub fn mpeg1IntensityGains(position: u8) [2]f32 {
    if (position == 0) return .{ 1, 0 };
    if (position == 6) return .{ 0, 1 };
    const ratio = @tan(
        @as(f32, @floatFromInt(position)) *
            std.math.pi /
            12.0,
    );
    const left = 1.0 / (1.0 + ratio);
    return .{ left, 1.0 - left };
}

pub fn lsfIntensityGains(
    position: u8,
    intensity_scale: bool,
) [2]f32 {
    if (position == 0) return .{ 1, 1 };
    const divisor: f32 = if (intensity_scale) 4 else 8;
    if (position & 1 != 0)
        return .{
            std.math.exp2(
                -@as(f32, @floatFromInt(position + 1)) / divisor,
            ),
            1,
        };
    return .{
        1,
        std.math.exp2(
            -@as(f32, @floatFromInt(position)) / divisor,
        ),
    };
}

pub fn containsNonzero(lines: []const f32) bool {
    for (lines) |line| {
        if (line != 0) return true;
    }
    return false;
}

fn applyMidSideRange(
    channels: *[2]RequantizedSpectrum,
    start: usize,
    end: usize,
) void {
    for (start..end) |line|
        applyMidSideLine(channels, line);
}

fn applyMidSideLine(
    channels: *[2]RequantizedSpectrum,
    line: usize,
) void {
    const middle = channels[0].lines[line];
    const side = channels[1].lines[line];
    const scale: f32 = 0.7071067811865476;
    channels[0].lines[line] = (middle + side) * scale;
    channels[1].lines[line] = (middle - side) * scale;
}

pub const XingKind = enum {
    variable,
    constant,
};

pub const Xing = struct {
    kind: XingKind,
    frame_count: ?u32,
    stream_bytes: ?u32,
    toc: ?[100]u8,
    quality: ?u32,
    encoder: ?[9]u8,
    encoder_delay: ?u12,
    encoder_padding: ?u12,
};

pub const Vbri = struct {
    version: u16,
    delay: u16,
    quality: u16,
    stream_bytes: u32,
    frame_count: u32,
    toc_entries: u16,
    toc_scale: u16,
    entry_bytes: u16,
    frames_per_entry: u16,
    toc: []const u8,

    /// Approximate an audio-relative byte offset for an encoded frame.
    pub fn approximateByteOffsetForFrame(
        self: Vbri,
        target_frame: u32,
    ) !u32 {
        if (self.version != 1)
            return error.UnsupportedVbriVersion;
        if (self.entry_bytes < 1 or self.entry_bytes > 4)
            return error.InvalidVbriEntrySize;
        if (self.toc_scale == 0)
            return error.InvalidVbriTocScale;
        if (self.frames_per_entry == 0)
            return error.InvalidVbriFramesPerEntry;
        if (self.frame_count == 0 or target_frame > self.frame_count)
            return error.InvalidVbriTargetFrame;
        const expected_toc_bytes = std.math.mul(
            usize,
            self.toc_entries,
            self.entry_bytes,
        ) catch return error.VbriSizeOverflow;
        if (self.toc.len != expected_toc_bytes)
            return error.InvalidVbriTocSize;
        const covered_frames = std.math.mul(
            u64,
            self.toc_entries,
            self.frames_per_entry,
        ) catch return error.VbriFrameCoverageOverflow;
        const uncovered_frames =
            @as(u64, self.frame_count) -| covered_frames;
        if (uncovered_frames > 1)
            return error.IncompleteVbriFrameCoverage;

        const target_frame_wide: u64 = target_frame;
        var cumulative_bytes: u64 = 0;
        var target_offset: ?u64 = if (target_frame == 0) 0 else null;
        for (0..self.toc_entries) |entry_index| {
            const entry_offset = entry_index * self.entry_bytes;
            var entry: u32 = 0;
            for (self.toc[entry_offset..][0..self.entry_bytes]) |byte| {
                entry = (entry << 8) | byte;
            }
            if (entry == 0) return error.InvalidVbriTocEntry;
            const segment_bytes = std.math.mul(
                u64,
                entry,
                self.toc_scale,
            ) catch return error.VbriByteOffsetOverflow;

            const segment_first_frame = std.math.mul(
                u64,
                @intCast(entry_index),
                self.frames_per_entry,
            ) catch return error.VbriFrameCoverageOverflow;
            var segment_end_frame = std.math.add(
                u64,
                segment_first_frame,
                self.frames_per_entry,
            ) catch return error.VbriFrameCoverageOverflow;
            if (entry_index + 1 == self.toc_entries and
                uncovered_frames == 1)
            {
                segment_end_frame += 1;
            }
            if (target_offset == null and
                target_frame_wide >= segment_first_frame and
                target_frame_wide < segment_end_frame)
            {
                const frame_in_segment =
                    target_frame_wide - segment_first_frame;
                const segment_frames =
                    segment_end_frame - segment_first_frame;
                const partial_bytes =
                    segment_bytes * frame_in_segment / segment_frames;
                target_offset = std.math.add(
                    u64,
                    cumulative_bytes,
                    partial_bytes,
                ) catch return error.VbriByteOffsetOverflow;
            }
            cumulative_bytes = std.math.add(
                u64,
                cumulative_bytes,
                segment_bytes,
            ) catch return error.VbriByteOffsetOverflow;
            if (cumulative_bytes > self.stream_bytes)
                return error.InvalidVbriStreamBytes;
        }
        if (target_frame == self.frame_count)
            target_offset = self.stream_bytes;
        const result = target_offset orelse
            return error.IncompleteVbriFrameCoverage;
        if (result > self.stream_bytes or result > std.math.maxInt(u32))
            return error.InvalidVbriStreamBytes;
        return @intCast(result);
    }
};

pub const VbriSummary = struct {
    version: u16,
    delay: u16,
    quality: u16,
    stream_bytes: u32,
    frame_count: u32,
    toc_entries: u16,
    toc_scale: u16,
    entry_bytes: u16,
    frames_per_entry: u16,

    fn from(vbri: Vbri) VbriSummary {
        return .{
            .version = vbri.version,
            .delay = vbri.delay,
            .quality = vbri.quality,
            .stream_bytes = vbri.stream_bytes,
            .frame_count = vbri.frame_count,
            .toc_entries = vbri.toc_entries,
            .toc_scale = vbri.toc_scale,
            .entry_bytes = vbri.entry_bytes,
            .frames_per_entry = vbri.frames_per_entry,
        };
    }
};

pub const Frame = struct {
    offset: usize,
    bytes: []const u8,
    header: Header,
    xing: ?Xing,
    vbri: ?Vbri,

    pub fn parse(encoded: []const u8, offset: usize) !Frame {
        if (offset > encoded.len or encoded.len - offset < 4)
            return error.TruncatedMp3Header;
        const header = try Header.parse(encoded[offset..]);
        const free_base = if (header.free_format)
            try inferMemoryFreeFormatBase(
                encoded,
                offset,
                encoded.len,
                header,
            )
        else
            null;
        const frame_bytes = try resolvedFrameBytes(
            header,
            free_base,
        );
        if (frame_bytes < 4 or frame_bytes > encoded.len - offset)
            return error.TruncatedMp3Frame;
        return frameAtKnownLength(
            encoded,
            offset,
            header,
            frame_bytes,
        );
    }

    /// Return null when the frame does not carry a CRC.
    pub fn crcValid(self: Frame) !?bool {
        return frameCrcValid(self.bytes, self.header);
    }

    /// Parse the complete fixed side-information region.
    pub fn sideInformation(self: Frame) !SideInformation {
        return parseSideInformation(self.bytes, self.header);
    }
};

pub const Summary = struct {
    audio_offset: usize,
    audio_bytes: usize,
    frame_count: u64,
    sample_count: u64,
    sample_rate: u32,
    channels: u8,
    first_xing: ?Xing,
    first_vbri: ?Vbri,

    pub fn durationSeconds(self: Summary) f64 {
        return @as(f64, @floatFromInt(self.sample_count)) /
            @as(f64, @floatFromInt(self.sample_rate));
    }
};

pub const SeekPoint = struct {
    frame_index: u64,
    sample_offset: u64,
    byte_offset: usize,
};

pub const FileFrame = struct {
    byte_offset: u64,
    bytes: []const u8,
    header: Header,
    xing: ?Xing,
    vbri: ?Vbri,

    /// Return null when the frame does not carry a CRC.
    pub fn crcValid(self: FileFrame) !?bool {
        return frameCrcValid(self.bytes, self.header);
    }

    /// Parse the complete fixed side-information region.
    pub fn sideInformation(self: FileFrame) !SideInformation {
        return parseSideInformation(self.bytes, self.header);
    }
};

pub const FileSummary = struct {
    audio_offset: u64,
    audio_bytes: u64,
    frame_count: u64,
    sample_count: u64,
    sample_rate: u32,
    channels: u8,
    first_xing: ?Xing,
    first_vbri: ?VbriSummary,

    pub fn durationSeconds(self: FileSummary) f64 {
        return @as(f64, @floatFromInt(self.sample_count)) /
            @as(f64, @floatFromInt(self.sample_rate));
    }
};

pub const Stream = struct {
    encoded: []const u8,
    audio_start: usize,
    audio_end: usize,
    cursor: usize,
    first_header: ?Header = null,
    frame_index: u64 = 0,
    sample_offset: u64 = 0,
    free_frame_base_bytes: ?usize = null,
    limits: Limits = default_limits,

    pub fn init(encoded: []const u8) !Stream {
        return initWithLimits(encoded, default_limits);
    }

    pub fn initWithLimits(encoded: []const u8, limits: Limits) !Stream {
        try limits.validate();
        const encoded_bytes = std.math.cast(u64, encoded.len) orelse
            return error.Mp3StreamLimitExceeded;
        if (encoded_bytes > limits.max_stream_bytes)
            return error.Mp3StreamLimitExceeded;
        const audio_start = try leadingTagBytes(encoded);
        const audio_end = trailingTagStart(encoded, audio_start);
        if (audio_end - audio_start < 4) return error.Mp3StreamHasNoFrames;
        return .{
            .encoded = encoded,
            .audio_start = audio_start,
            .audio_end = audio_end,
            .cursor = audio_start,
            .limits = limits,
        };
    }

    pub fn valid(self: *const Stream) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn next(self: *Stream) !?Frame {
        try self.validateState();
        if (self.cursor == self.audio_end) return null;
        if (self.frame_index == self.limits.max_frames)
            return error.Mp3FrameLimitExceeded;
        if (self.audio_end - self.cursor < 4)
            return error.TrailingMp3Data;
        const header = try Header.parse(self.encoded[self.cursor..]);
        const next_free_base = if (header.free_format)
            self.free_frame_base_bytes orelse
                try inferMemoryFreeFormatBase(
                    self.encoded,
                    self.cursor,
                    self.audio_end,
                    header,
                )
        else
            null;
        const frame_bytes = try resolvedFrameBytes(
            header,
            next_free_base,
        );
        if (frame_bytes > self.audio_end - self.cursor)
            return error.TruncatedMp3Frame;
        const frame = try frameAtKnownLength(
            self.encoded[0..self.audio_end],
            self.cursor,
            header,
            frame_bytes,
        );
        if (self.first_header) |first| {
            if (!headersCompatible(first, frame.header))
                return error.Mp3StreamFormatChanged;
        }
        const next_cursor = std.math.add(
            usize,
            self.cursor,
            frame.bytes.len,
        ) catch return error.Mp3ByteCountOverflow;
        const next_frame_index = std.math.add(
            u64,
            self.frame_index,
            1,
        ) catch return error.Mp3FrameCountOverflow;
        const next_sample_offset = std.math.add(
            u64,
            self.sample_offset,
            frame.header.samplesPerFrame(),
        ) catch return error.Mp3SampleCountOverflow;
        self.first_header = self.first_header orelse frame.header;
        self.free_frame_base_bytes = next_free_base;
        self.cursor = next_cursor;
        self.frame_index = next_frame_index;
        self.sample_offset = next_sample_offset;
        return frame;
    }

    /// Advances past at most `maximum_skip_bytes` to a compatible frame.
    pub fn resynchronize(
        self: *Stream,
        maximum_skip_bytes: usize,
    ) !usize {
        try self.validateState();
        if (maximum_skip_bytes == 0)
            return error.InvalidMp3ResynchronizationLimit;
        if (self.cursor >= self.audio_end -| 4)
            return error.Mp3ResynchronizationLimitReached;
        const first_candidate = std.math.add(
            usize,
            self.cursor,
            1,
        ) catch return error.Mp3ByteCountOverflow;
        const last_candidate = @min(
            self.audio_end - 4,
            std.math.add(
                usize,
                self.cursor,
                maximum_skip_bytes,
            ) catch self.audio_end - 4,
        );
        var candidate = first_candidate;
        while (candidate <= last_candidate) : (candidate += 1) {
            const header = Header.parse(
                self.encoded[candidate..self.audio_end],
            ) catch continue;
            if (self.first_header) |first| {
                if (!headersCompatible(first, header)) continue;
            }
            const next_free_base = if (header.free_format)
                self.free_frame_base_bytes orelse
                    inferMemoryFreeFormatBase(
                        self.encoded,
                        candidate,
                        self.audio_end,
                        header,
                    ) catch continue
            else
                null;
            const frame_bytes = resolvedFrameBytes(
                header,
                next_free_base,
            ) catch continue;
            if (frame_bytes > self.audio_end - candidate)
                continue;
            const candidate_frame = frameAtKnownLength(
                self.encoded[0..self.audio_end],
                candidate,
                header,
                frame_bytes,
            ) catch continue;
            if (!frameRecoveryCandidateValid(candidate_frame)) continue;
            if (self.first_header == null) {
                const following = std.math.add(
                    usize,
                    candidate,
                    frame_bytes,
                ) catch continue;
                if (following != self.audio_end) {
                    if (following > self.audio_end -| 4)
                        continue;
                    const following_header = Header.parse(
                        self.encoded[following..self.audio_end],
                    ) catch continue;
                    if (!headersCompatible(header, following_header))
                        continue;
                }
            }
            const skipped = candidate - self.cursor;
            self.cursor = candidate;
            self.free_frame_base_bytes = next_free_base;
            return skipped;
        }
        return error.Mp3ResynchronizationLimitReached;
    }

    fn validateState(self: *const Stream) !void {
        self.limits.validate() catch return error.InvalidMp3StreamState;
        const encoded_bytes = std.math.cast(u64, self.encoded.len) orelse
            return error.InvalidMp3StreamState;
        if (self.audio_start > self.audio_end or
            self.audio_end > self.encoded.len or
            self.cursor < self.audio_start or
            self.cursor > self.audio_end or
            encoded_bytes > self.limits.max_stream_bytes or
            self.frame_index > self.limits.max_frames)
        {
            return error.InvalidMp3StreamState;
        }
        const first = self.first_header orelse {
            if (self.audio_end - self.audio_start < 4 or
                self.cursor > self.audio_end - 4 or
                self.frame_index != 0 or self.sample_offset != 0)
                return error.InvalidMp3StreamState;
            if (self.free_frame_base_bytes) |base| {
                if (base < 4 or base > maximum_free_format_frame_bytes)
                    return error.InvalidMp3StreamState;
            }
            return;
        };
        if (!headerStateValid(first))
            return error.InvalidMp3StreamState;
        if (self.frame_index == 0)
            return error.InvalidMp3StreamState;
        const expected_samples = std.math.mul(
            u64,
            self.frame_index,
            first.samplesPerFrame(),
        ) catch return error.InvalidMp3StreamState;
        if (self.sample_offset != expected_samples)
            return error.InvalidMp3StreamState;
        const consumed_bytes = std.math.cast(
            u64,
            self.cursor - self.audio_start,
        ) orelse return error.InvalidMp3StreamState;
        if (!mp3FrameProgressValid(
            self.frame_index,
            consumed_bytes,
            first,
        )) return error.InvalidMp3StreamState;
        if (first.free_format) {
            const base = self.free_frame_base_bytes orelse
                return error.InvalidMp3StreamState;
            if (base < minimumFrameBytes(first) or
                base > maximum_free_format_frame_bytes)
            {
                return error.InvalidMp3StreamState;
            }
            _ = resolvedFrameBytes(first, base) catch
                return error.InvalidMp3StreamState;
        } else if (self.free_frame_base_bytes != null) {
            return error.InvalidMp3StreamState;
        }
    }

    pub fn summarize(encoded: []const u8) !Summary {
        return summarizeWithLimits(encoded, default_limits);
    }

    pub fn summarizeWithLimits(encoded: []const u8, limits: Limits) !Summary {
        var stream = try Stream.initWithLimits(encoded, limits);
        var first_xing: ?Xing = null;
        var first_vbri: ?Vbri = null;
        while (try stream.next()) |frame| {
            if (stream.frame_index == 1) {
                first_xing = frame.xing;
                first_vbri = frame.vbri;
            }
        }
        const first = stream.first_header orelse
            return error.Mp3StreamHasNoFrames;
        return .{
            .audio_offset = stream.audio_start,
            .audio_bytes = stream.audio_end - stream.audio_start,
            .frame_count = stream.frame_index,
            .sample_count = stream.sample_offset,
            .sample_rate = first.sample_rate,
            .channels = first.channels(),
            .first_xing = first_xing,
            .first_vbri = first_vbri,
        };
    }
};

pub const FileReader = struct {
    io: std.Io,
    file: std.Io.File,
    audio_start: u64,
    audio_end: u64,
    offset: u64,
    first_header: Header,
    frame_index: u64 = 0,
    sample_offset: u64 = 0,
    free_frame_base_bytes: ?usize = null,
    limits: Limits = default_limits,

    /// The caller owns the file and frame storage for the reader lifetime.
    pub fn init(io: std.Io, file: std.Io.File) !FileReader {
        return initWithLimits(io, file, default_limits);
    }

    pub fn initWithLimits(
        io: std.Io,
        file: std.Io.File,
        limits: Limits,
    ) !FileReader {
        try limits.validate();
        const file_size = (try file.stat(io)).size;
        if (file_size > limits.max_stream_bytes)
            return error.Mp3StreamLimitExceeded;
        if (file_size < 3) return error.Mp3StreamHasNoFrames;

        var prefix: [10]u8 = undefined;
        const prefix_bytes: usize = @intCast(@min(file_size, prefix.len));
        try readExactAt(io, file, 0, prefix[0..prefix_bytes]);
        const audio_start = try leadingFileTagBytes(
            prefix[0..prefix_bytes],
            file_size,
        );

        var audio_end = file_size;
        if (audio_start <= file_size and
            file_size - audio_start >= 128)
        {
            var marker: [3]u8 = undefined;
            try readExactAt(io, file, file_size - 128, &marker);
            if (std.mem.eql(u8, &marker, "TAG"))
                audio_end -= 128;
        }
        if (audio_end < audio_start or audio_end - audio_start < 4)
            return error.Mp3StreamHasNoFrames;

        var header_bytes: [4]u8 = undefined;
        try readExactAt(io, file, audio_start, &header_bytes);
        const first_header = try Header.parse(&header_bytes);
        const free_frame_base_bytes = if (first_header.free_format)
            try inferFileFreeFormatBase(
                io,
                file,
                audio_start,
                audio_end,
                first_header,
            )
        else
            null;
        return .{
            .io = io,
            .file = file,
            .audio_start = audio_start,
            .audio_end = audio_end,
            .offset = audio_start,
            .first_header = first_header,
            .free_frame_base_bytes = free_frame_base_bytes,
            .limits = limits,
        };
    }

    pub fn valid(self: *const FileReader) bool {
        self.validateState() catch return false;
        return true;
    }

    /// Returned frame slices borrow storage until the caller reuses it.
    pub fn next(self: *FileReader, storage: []u8) !?FileFrame {
        try self.validateState();
        if (self.offset == self.audio_end) return null;
        if (self.frame_index == self.limits.max_frames)
            return error.Mp3FrameLimitExceeded;
        if (self.audio_end - self.offset < 4)
            return error.TrailingMp3Data;

        var header_bytes: [4]u8 = undefined;
        try readExactAt(self.io, self.file, self.offset, &header_bytes);
        const header = try Header.parse(&header_bytes);
        if (!headersCompatible(self.first_header, header))
            return error.Mp3StreamFormatChanged;
        const frame_bytes = try resolvedFrameBytes(
            header,
            self.free_frame_base_bytes,
        );
        if (frame_bytes > self.audio_end - self.offset)
            return error.TruncatedMp3Frame;
        if (storage.len < frame_bytes)
            return error.Mp3FrameBufferTooSmall;
        const next_offset = std.math.add(
            u64,
            self.offset,
            frame_bytes,
        ) catch return error.Mp3ByteCountOverflow;
        const next_frame_index = std.math.add(
            u64,
            self.frame_index,
            1,
        ) catch return error.Mp3FrameCountOverflow;
        const next_sample_offset = std.math.add(
            u64,
            self.sample_offset,
            header.samplesPerFrame(),
        ) catch return error.Mp3SampleCountOverflow;
        try readExactAt(
            self.io,
            self.file,
            self.offset,
            storage[0..frame_bytes],
        );
        const parsed = try frameAtKnownLength(
            storage[0..frame_bytes],
            0,
            header,
            frame_bytes,
        );
        const byte_offset = self.offset;
        self.offset = next_offset;
        self.frame_index = next_frame_index;
        self.sample_offset = next_sample_offset;
        return .{
            .byte_offset = byte_offset,
            .bytes = parsed.bytes,
            .header = parsed.header,
            .xing = parsed.xing,
            .vbri = parsed.vbri,
        };
    }

    /// Stage a complete frame before advancing or changing destination.
    pub fn nextTransactional(
        self: *FileReader,
        storage: []u8,
        scratch: []u8,
    ) !?FileFrame {
        try self.validateState();
        if (byteRangesOverlap(
            @intFromPtr(storage.ptr),
            storage.len,
            @intFromPtr(scratch.ptr),
            scratch.len,
        )) return error.OverlappingMp3FileReaderBuffers;

        var staged_reader = self.*;
        const staged = try staged_reader.next(scratch) orelse return null;
        if (storage.len < staged.bytes.len)
            return error.Mp3FrameBufferTooSmall;
        var published_vbri = staged.vbri;
        if (published_vbri) |*vbri| {
            const frame_start = @intFromPtr(staged.bytes.ptr);
            const toc_start = @intFromPtr(vbri.toc.ptr);
            if (toc_start < frame_start)
                return error.InvalidVbriTocSize;
            const toc_offset = toc_start - frame_start;
            if (toc_offset > staged.bytes.len or
                vbri.toc.len > staged.bytes.len - toc_offset)
            {
                return error.InvalidVbriTocSize;
            }
            vbri.toc = storage[toc_offset..][0..vbri.toc.len];
        }
        @memcpy(storage[0..staged.bytes.len], staged.bytes);
        self.* = staged_reader;
        return .{
            .byte_offset = staged.byte_offset,
            .bytes = storage[0..staged.bytes.len],
            .header = staged.header,
            .xing = staged.xing,
            .vbri = published_vbri,
        };
    }

    /// Advances past at most `maximum_skip_bytes` to a compatible frame.
    pub fn resynchronize(
        self: *FileReader,
        maximum_skip_bytes: u64,
    ) !u64 {
        try self.validateState();
        if (maximum_skip_bytes == 0)
            return error.InvalidMp3ResynchronizationLimit;
        if (self.offset >= self.audio_end -| 4)
            return error.Mp3ResynchronizationLimitReached;
        const first_candidate = std.math.add(
            u64,
            self.offset,
            1,
        ) catch return error.Mp3ByteCountOverflow;
        const last_candidate = @min(
            self.audio_end - 4,
            std.math.add(
                u64,
                self.offset,
                maximum_skip_bytes,
            ) catch self.audio_end - 4,
        );
        var header_bytes: [4]u8 = undefined;
        var frame_storage: [maximum_free_format_frame_bytes]u8 = undefined;
        var candidate = first_candidate;
        while (candidate <= last_candidate) : (candidate += 1) {
            readExactAt(
                self.io,
                self.file,
                candidate,
                &header_bytes,
            ) catch continue;
            const header = Header.parse(&header_bytes) catch continue;
            if (!headersCompatible(self.first_header, header)) continue;
            const frame_bytes = resolvedFrameBytes(
                header,
                self.free_frame_base_bytes,
            ) catch continue;
            if (frame_bytes > self.audio_end - candidate)
                continue;
            if (frame_bytes > frame_storage.len)
                continue;
            readExactAt(
                self.io,
                self.file,
                candidate,
                frame_storage[0..frame_bytes],
            ) catch continue;
            const candidate_frame = frameAtKnownLength(
                frame_storage[0..frame_bytes],
                0,
                header,
                frame_bytes,
            ) catch continue;
            if (!frameRecoveryCandidateValid(candidate_frame)) continue;
            const skipped = candidate - self.offset;
            self.offset = candidate;
            return skipped;
        }
        return error.Mp3ResynchronizationLimitReached;
    }

    pub fn seek(self: *FileReader, point: SeekPoint) !void {
        try self.validateState();
        const byte_offset: u64 = @intCast(point.byte_offset);
        if (byte_offset < self.audio_start or
            byte_offset > self.audio_end -| 4)
            return error.InvalidMp3SeekPoint;
        const expected_sample = std.math.mul(
            u64,
            point.frame_index,
            self.first_header.samplesPerFrame(),
        ) catch return error.InvalidMp3SeekPoint;
        if (point.sample_offset != expected_sample)
            return error.InvalidMp3SeekPoint;
        if (point.frame_index > self.limits.max_frames)
            return error.InvalidMp3SeekPoint;
        if (!mp3FrameProgressValid(
            point.frame_index,
            byte_offset - self.audio_start,
            self.first_header,
        )) return error.InvalidMp3SeekPoint;
        var header_bytes: [4]u8 = undefined;
        try readExactAt(self.io, self.file, byte_offset, &header_bytes);
        const header = Header.parse(&header_bytes) catch
            return error.InvalidMp3SeekPoint;
        if (!headersCompatible(self.first_header, header))
            return error.InvalidMp3SeekPoint;
        const frame_bytes = resolvedFrameBytes(
            header,
            self.free_frame_base_bytes,
        ) catch return error.InvalidMp3SeekPoint;
        if (frame_bytes > self.audio_end - byte_offset)
            return error.InvalidMp3SeekPoint;
        var frame_storage: [maximum_free_format_frame_bytes]u8 = undefined;
        if (frame_bytes > frame_storage.len)
            return error.InvalidMp3SeekPoint;
        try readExactAt(
            self.io,
            self.file,
            byte_offset,
            frame_storage[0..frame_bytes],
        );
        const frame = frameAtKnownLength(
            frame_storage[0..frame_bytes],
            0,
            header,
            frame_bytes,
        ) catch return error.InvalidMp3SeekPoint;
        if (!frameRecoveryCandidateValid(frame))
            return error.InvalidMp3SeekPoint;
        self.offset = byte_offset;
        self.frame_index = point.frame_index;
        self.sample_offset = point.sample_offset;
    }

    fn validateState(self: *const FileReader) !void {
        self.limits.validate() catch
            return error.InvalidMp3FileReaderState;
        if (self.audio_start > self.audio_end or
            self.audio_end - self.audio_start < 4 or
            self.offset < self.audio_start or
            self.offset > self.audio_end or
            self.audio_end > self.limits.max_stream_bytes or
            self.frame_index > self.limits.max_frames)
        {
            return error.InvalidMp3FileReaderState;
        }
        if (!headerStateValid(self.first_header))
            return error.InvalidMp3FileReaderState;
        const expected_samples = std.math.mul(
            u64,
            self.frame_index,
            self.first_header.samplesPerFrame(),
        ) catch return error.InvalidMp3FileReaderState;
        if (self.sample_offset != expected_samples)
            return error.InvalidMp3FileReaderState;
        if (!mp3FrameProgressValid(
            self.frame_index,
            self.offset - self.audio_start,
            self.first_header,
        )) return error.InvalidMp3FileReaderState;
        if (self.first_header.free_format) {
            const base = self.free_frame_base_bytes orelse
                return error.InvalidMp3FileReaderState;
            if (base < minimumFrameBytes(self.first_header) or
                base > maximum_free_format_frame_bytes)
            {
                return error.InvalidMp3FileReaderState;
            }
            _ = resolvedFrameBytes(self.first_header, base) catch
                return error.InvalidMp3FileReaderState;
        } else if (self.free_frame_base_bytes != null) {
            return error.InvalidMp3FileReaderState;
        }
    }

    pub fn summarize(
        io: std.Io,
        file: std.Io.File,
        storage: []u8,
    ) !FileSummary {
        return summarizeWithLimits(
            io,
            file,
            storage,
            default_limits,
        );
    }

    pub fn summarizeWithLimits(
        io: std.Io,
        file: std.Io.File,
        storage: []u8,
        limits: Limits,
    ) !FileSummary {
        var reader = try FileReader.initWithLimits(io, file, limits);
        var first_xing: ?Xing = null;
        var first_vbri: ?VbriSummary = null;
        while (try reader.next(storage)) |frame| {
            if (reader.frame_index == 1) {
                first_xing = frame.xing;
                if (frame.vbri) |vbri|
                    first_vbri = VbriSummary.from(vbri);
            }
        }
        return .{
            .audio_offset = reader.audio_start,
            .audio_bytes = reader.audio_end - reader.audio_start,
            .frame_count = reader.frame_index,
            .sample_count = reader.sample_offset,
            .sample_rate = reader.first_header.sample_rate,
            .channels = reader.first_header.channels(),
            .first_xing = first_xing,
            .first_vbri = first_vbri,
        };
    }
};

pub fn requiredSeekPoints(encoded: []const u8, stride: u32) !usize {
    if (stride == 0) return error.InvalidMp3SeekStride;
    var stream = try Stream.init(encoded);
    var count: usize = 0;
    while (try stream.next()) |_| {
        const index = stream.frame_index - 1;
        if (index % stride == 0)
            count = std.math.add(
                usize,
                count,
                1,
            ) catch return error.Mp3SeekPointCountOverflow;
    }
    return count;
}

pub fn buildSeekIndex(
    encoded: []const u8,
    stride: u32,
    destination: []SeekPoint,
) ![]const SeekPoint {
    const destination_bytes = std.math.mul(
        usize,
        destination.len,
        @sizeOf(SeekPoint),
    ) catch return error.Mp3SeekIndexSizeOverflow;
    if (byteRangesOverlap(
        @intFromPtr(encoded.ptr),
        encoded.len,
        @intFromPtr(destination.ptr),
        destination_bytes,
    )) return error.OverlappingMp3SeekStorage;
    const required = try requiredSeekPoints(encoded, stride);
    if (destination.len < required) return error.Mp3SeekIndexTooSmall;

    var stream = try Stream.init(encoded);
    var count: usize = 0;
    while (true) {
        const frame_index = stream.frame_index;
        const sample_offset = stream.sample_offset;
        const byte_offset = stream.cursor;
        const frame = try stream.next() orelse break;
        _ = frame;
        if (frame_index % stride != 0) continue;
        destination[count] = .{
            .frame_index = frame_index,
            .sample_offset = sample_offset,
            .byte_offset = byte_offset,
        };
        count += 1;
    }
    if (count != required) return error.Mp3SeekIndexChanged;
    return destination[0..count];
}

pub fn findSeekPoint(points: []const SeekPoint, target_sample: u64) !SeekPoint {
    if (points.len == 0) return error.EmptyMp3SeekIndex;
    var selected = points[0];
    if (selected.frame_index != 0 or selected.sample_offset != 0)
        return error.InvalidMp3SeekIndex;
    var previous = selected;
    for (points[1..]) |point| {
        if (point.frame_index <= previous.frame_index or
            point.sample_offset <= previous.sample_offset or
            point.byte_offset <= previous.byte_offset)
            return error.InvalidMp3SeekIndex;
        if (point.sample_offset <= target_sample) selected = point;
        previous = point;
    }
    return selected;
}

pub fn resolvedFrameBytes(
    header: Header,
    free_base_bytes: ?usize,
) !usize {
    if (!header.free_format) return header.frameBytes();
    const base = free_base_bytes orelse
        return error.CannotInferFreeFormatMp3FrameSize;
    return std.math.add(
        usize,
        base,
        @intFromBool(header.padding),
    ) catch return error.Mp3ByteCountOverflow;
}

pub fn minimumFrameBytes(header: Header) usize {
    return 4 + @as(usize, if (header.crc_present) 2 else 0) +
        header.sideInformationBytes();
}

fn mp3FrameProgressValid(
    frame_count: u64,
    consumed_bytes: u64,
    header: Header,
) bool {
    const minimum_compatible_bytes: u64 =
        4 + @as(u64, header.sideInformationBytes());
    const minimum_consumed = std.math.mul(
        u64,
        frame_count,
        minimum_compatible_bytes,
    ) catch return false;
    return consumed_bytes >= minimum_consumed;
}

fn inferMemoryFreeFormatBase(
    encoded: []const u8,
    offset: usize,
    audio_end: usize,
    header: Header,
) !usize {
    if (!header.free_format)
        return error.InvalidFreeFormatMp3Header;
    const first_candidate = std.math.add(
        usize,
        offset,
        minimumFrameBytes(header),
    ) catch return error.Mp3ByteCountOverflow;
    const maximum_candidate = @min(
        audio_end -| 4,
        std.math.add(
            usize,
            offset,
            maximum_free_format_frame_bytes,
        ) catch std.math.maxInt(usize),
    );
    var candidate = first_candidate;
    while (candidate <= maximum_candidate) : (candidate += 1) {
        const candidate_header =
            Header.parse(encoded[candidate..audio_end]) catch continue;
        if (!headersCompatible(header, candidate_header)) continue;
        const frame_bytes = candidate - offset;
        const padding: usize = @intFromBool(header.padding);
        if (frame_bytes <= padding) continue;
        const base = frame_bytes - padding;
        if (!memoryFreeFormatFrameValid(
            encoded,
            offset,
            audio_end,
            header,
            frame_bytes,
        )) continue;
        if (try confirmsMemoryFreeFormat(
            encoded,
            candidate,
            audio_end,
            candidate_header,
            base,
        )) return base;
    }
    return error.CannotInferFreeFormatMp3FrameSize;
}

fn confirmsMemoryFreeFormat(
    encoded: []const u8,
    candidate: usize,
    audio_end: usize,
    header: Header,
    base: usize,
) !bool {
    const frame_bytes = try resolvedFrameBytes(header, base);
    if (!memoryFreeFormatFrameValid(
        encoded,
        candidate,
        audio_end,
        header,
        frame_bytes,
    )) return false;
    const next = std.math.add(
        usize,
        candidate,
        frame_bytes,
    ) catch return false;
    if (next == audio_end) return true;
    if (next > audio_end -| 4) return false;
    const next_header =
        Header.parse(encoded[next..audio_end]) catch return false;
    if (!headersCompatible(header, next_header)) return false;
    const next_frame_bytes = resolvedFrameBytes(
        next_header,
        base,
    ) catch return false;
    return memoryFreeFormatFrameValid(
        encoded,
        next,
        audio_end,
        next_header,
        next_frame_bytes,
    );
}

fn memoryFreeFormatFrameValid(
    encoded: []const u8,
    offset: usize,
    audio_end: usize,
    header: Header,
    frame_bytes: usize,
) bool {
    if (audio_end > encoded.len or
        offset > audio_end or
        frame_bytes > audio_end - offset)
        return false;
    const frame = frameAtKnownLength(
        encoded[0..audio_end],
        offset,
        header,
        frame_bytes,
    ) catch return false;
    return frameRecoveryCandidateValid(frame);
}

fn inferFileFreeFormatBase(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    audio_end: u64,
    header: Header,
) !usize {
    if (!header.free_format)
        return error.InvalidFreeFormatMp3Header;
    const first_candidate = std.math.add(
        u64,
        offset,
        minimumFrameBytes(header),
    ) catch return error.Mp3ByteCountOverflow;
    const maximum_candidate = @min(
        audio_end -| 4,
        std.math.add(
            u64,
            offset,
            maximum_free_format_frame_bytes,
        ) catch std.math.maxInt(u64),
    );
    var candidate = first_candidate;
    var header_bytes: [4]u8 = undefined;
    var frame_storage: [maximum_free_format_frame_bytes]u8 = undefined;
    while (candidate <= maximum_candidate) : (candidate += 1) {
        try readExactAt(io, file, candidate, &header_bytes);
        const candidate_header =
            Header.parse(&header_bytes) catch continue;
        if (!headersCompatible(header, candidate_header)) continue;
        const frame_bytes = std.math.cast(
            usize,
            candidate - offset,
        ) orelse return error.Mp3ByteCountOverflow;
        const padding: usize = @intFromBool(header.padding);
        if (frame_bytes <= padding) continue;
        const base = frame_bytes - padding;
        if (!try fileFreeFormatFrameValid(
            io,
            file,
            offset,
            audio_end,
            header,
            frame_bytes,
            &frame_storage,
        )) continue;
        if (try confirmsFileFreeFormat(
            io,
            file,
            candidate,
            audio_end,
            candidate_header,
            base,
            &frame_storage,
        )) return base;
    }
    return error.CannotInferFreeFormatMp3FrameSize;
}

fn confirmsFileFreeFormat(
    io: std.Io,
    file: std.Io.File,
    candidate: u64,
    audio_end: u64,
    header: Header,
    base: usize,
    frame_storage: []u8,
) !bool {
    const frame_bytes = try resolvedFrameBytes(header, base);
    if (!try fileFreeFormatFrameValid(
        io,
        file,
        candidate,
        audio_end,
        header,
        frame_bytes,
        frame_storage,
    )) return false;
    const next = std.math.add(
        u64,
        candidate,
        frame_bytes,
    ) catch return false;
    if (next == audio_end) return true;
    if (next > audio_end -| 4) return false;
    var next_bytes: [4]u8 = undefined;
    try readExactAt(io, file, next, &next_bytes);
    const next_header = Header.parse(&next_bytes) catch return false;
    if (!headersCompatible(header, next_header)) return false;
    const next_frame_bytes = resolvedFrameBytes(
        next_header,
        base,
    ) catch return false;
    return fileFreeFormatFrameValid(
        io,
        file,
        next,
        audio_end,
        next_header,
        next_frame_bytes,
        frame_storage,
    );
}

fn fileFreeFormatFrameValid(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    audio_end: u64,
    header: Header,
    frame_bytes: usize,
    storage: []u8,
) !bool {
    const frame_bytes_u64: u64 = @intCast(frame_bytes);
    if (offset > audio_end or
        frame_bytes_u64 > audio_end - offset or
        frame_bytes > storage.len)
        return false;
    try readExactAt(
        io,
        file,
        offset,
        storage[0..frame_bytes],
    );
    const frame = frameAtKnownLength(
        storage[0..frame_bytes],
        0,
        header,
        frame_bytes,
    ) catch return false;
    return frameRecoveryCandidateValid(frame);
}

pub fn frameAtKnownLength(
    encoded: []const u8,
    offset: usize,
    header: Header,
    frame_bytes: usize,
) !Frame {
    if (offset > encoded.len or
        frame_bytes < minimumFrameBytes(header) or
        frame_bytes > encoded.len - offset)
        return error.TruncatedMp3Frame;
    const bytes = encoded[offset .. offset + frame_bytes];
    return .{
        .offset = offset,
        .bytes = bytes,
        .header = header,
        .xing = try parseXing(bytes, header),
        .vbri = try parseVbri(bytes),
    };
}

fn frameCrcValid(bytes: []const u8, header: Header) !?bool {
    if (!header.crc_present) return null;
    const protected_end = std.math.add(
        usize,
        6,
        header.sideInformationBytes(),
    ) catch return error.TruncatedMp3Frame;
    if (bytes.len < protected_end)
        return error.TruncatedMp3Frame;
    const expected = readU16(bytes[4..6]);
    var crc = crc16(0xffff, bytes[2..4]);
    crc = crc16(crc, bytes[6..protected_end]);
    return crc == expected;
}

fn frameRecoveryCandidateValid(frame: Frame) bool {
    if (frameCrcValid(frame.bytes, frame.header) catch return false) |crc_valid| {
        if (!crc_valid) return false;
    }
    _ = parseSideInformation(frame.bytes, frame.header) catch return false;
    return true;
}

pub fn crc16(initial: u16, bytes: []const u8) u16 {
    var crc = initial;
    for (bytes) |byte| {
        var mask: u8 = 0x80;
        while (mask != 0) : (mask >>= 1) {
            const input_bit: u16 =
                if (byte & mask == 0) 0 else 1;
            const feedback = (crc >> 15) ^ input_bit;
            crc <<= 1;
            if (feedback != 0) crc ^= 0x8005;
        }
    }
    return crc;
}

pub fn requiredFileSeekPoints(
    io: std.Io,
    file: std.Io.File,
    frame_storage: []u8,
    stride: u32,
) !usize {
    if (stride == 0) return error.InvalidMp3SeekStride;
    var reader = try FileReader.init(io, file);
    var count: usize = 0;
    while (try reader.next(frame_storage)) |_| {
        const index = reader.frame_index - 1;
        if (index % stride == 0)
            count = std.math.add(
                usize,
                count,
                1,
            ) catch return error.Mp3SeekPointCountOverflow;
    }
    return count;
}

pub fn buildFileSeekIndex(
    io: std.Io,
    file: std.Io.File,
    frame_storage: []u8,
    stride: u32,
    destination: []SeekPoint,
) ![]const SeekPoint {
    const destination_bytes = std.math.mul(
        usize,
        destination.len,
        @sizeOf(SeekPoint),
    ) catch return error.Mp3SeekIndexSizeOverflow;
    if (byteRangesOverlap(
        @intFromPtr(frame_storage.ptr),
        frame_storage.len,
        @intFromPtr(destination.ptr),
        destination_bytes,
    )) return error.OverlappingMp3SeekStorage;
    const required = try requiredFileSeekPoints(
        io,
        file,
        frame_storage,
        stride,
    );
    if (destination.len < required) return error.Mp3SeekIndexTooSmall;

    var reader = try FileReader.init(io, file);
    var count: usize = 0;
    while (true) {
        const frame_index = reader.frame_index;
        const sample_offset = reader.sample_offset;
        const byte_offset: usize = std.math.cast(
            usize,
            reader.offset,
        ) orelse return error.Mp3FileOffsetTooLarge;
        _ = try reader.next(frame_storage) orelse break;
        if (frame_index % stride != 0) continue;
        if (count >= destination.len)
            return error.Mp3SeekIndexChanged;
        destination[count] = .{
            .frame_index = frame_index,
            .sample_offset = sample_offset,
            .byte_offset = byte_offset,
        };
        count = std.math.add(
            usize,
            count,
            1,
        ) catch return error.Mp3SeekPointCountOverflow;
    }
    if (count != required) return error.Mp3SeekIndexChanged;
    return destination[0..count];
}

/// Stage the index so file changes cannot partially replace destination.
/// Frame, destination, and index scratch storage must be pairwise disjoint.
pub fn buildFileSeekIndexTransactional(
    io: std.Io,
    file: std.Io.File,
    frame_storage: []u8,
    stride: u32,
    destination: []SeekPoint,
    index_scratch: []SeekPoint,
) ![]const SeekPoint {
    const destination_bytes = std.math.mul(
        usize,
        destination.len,
        @sizeOf(SeekPoint),
    ) catch return error.Mp3SeekIndexSizeOverflow;
    const scratch_bytes = std.math.mul(
        usize,
        index_scratch.len,
        @sizeOf(SeekPoint),
    ) catch return error.Mp3SeekIndexSizeOverflow;
    if (byteRangesOverlap(
        @intFromPtr(frame_storage.ptr),
        frame_storage.len,
        @intFromPtr(destination.ptr),
        destination_bytes,
    ) or byteRangesOverlap(
        @intFromPtr(frame_storage.ptr),
        frame_storage.len,
        @intFromPtr(index_scratch.ptr),
        scratch_bytes,
    ) or byteRangesOverlap(
        @intFromPtr(destination.ptr),
        destination_bytes,
        @intFromPtr(index_scratch.ptr),
        scratch_bytes,
    )) return error.OverlappingMp3SeekStorage;

    const staged = try buildFileSeekIndex(
        io,
        file,
        frame_storage,
        stride,
        index_scratch,
    );
    if (destination.len < staged.len)
        return error.Mp3SeekIndexTooSmall;
    @memcpy(destination[0..staged.len], staged);
    return destination[0..staged.len];
}

fn frameXingOffset(header: Header) usize {
    return 4 + header.sideInformationBytes();
}

fn isValidXingEncoderIdentifier(encoder: [9]u8) bool {
    var has_visible_byte = false;
    for (encoder) |byte| {
        if (byte < 0x20 or byte > 0x7e)
            return false;
        has_visible_byte = has_visible_byte or byte != ' ';
    }
    return has_visible_byte;
}

fn parseXing(frame: []const u8, header: Header) !?Xing {
    const offset = frameXingOffset(header);
    if (frame.len < offset + 4) return null;
    const marker = frame[offset .. offset + 4];
    const kind: XingKind = if (std.mem.eql(u8, marker, "Xing"))
        .variable
    else if (std.mem.eql(u8, marker, "Info"))
        .constant
    else
        return null;
    if (frame.len < offset + 8) return error.TruncatedXingHeader;
    const flags = readU32(frame[offset + 4 .. offset + 8]);
    if (flags & ~@as(u32, 0x7f) != 0 or
        (flags & 0x30 != 0 and flags & 0x40 == 0))
    {
        return error.InvalidXingFlags;
    }
    var cursor = offset + 8;
    var xing = Xing{
        .kind = kind,
        .frame_count = null,
        .stream_bytes = null,
        .toc = null,
        .quality = null,
        .encoder = null,
        .encoder_delay = null,
        .encoder_padding = null,
    };
    if (flags & 1 != 0) {
        xing.frame_count = try readOptionalU32(frame, &cursor);
    }
    if (flags & 2 != 0) {
        xing.stream_bytes = try readOptionalU32(frame, &cursor);
    }
    if (flags & 4 != 0) {
        if (frame.len -| cursor < 100) return error.TruncatedXingHeader;
        xing.toc = frame[cursor..][0..100].*;
        cursor += 100;
    }
    if (flags & 8 != 0) {
        xing.quality = try readOptionalU32(frame, &cursor);
    }
    if (flags & 0x10 != 0) {
        if (frame.len -| cursor < 20) return error.TruncatedXingHeader;
        cursor += 20;
    }
    if (flags & 0x20 != 0) {
        if (frame.len -| cursor < 20) return error.TruncatedXingHeader;
        cursor += 20;
    }

    if (frame.len -| cursor >= 24) {
        const encoder = frame[cursor..][0..9].*;
        xing.encoder = encoder;
        const delay_offset = cursor + 21;
        const delay_fields =
            readU24(frame[delay_offset .. delay_offset + 3]);
        if (delay_fields != 0 and
            isValidXingEncoderIdentifier(encoder))
        {
            xing.encoder_delay = @intCast(delay_fields >> 12);
            xing.encoder_padding = @intCast(delay_fields & 0xfff);
        }
    }
    return xing;
}

fn parseVbri(frame: []const u8) !?Vbri {
    const offset = 4 + 32;
    if (frame.len < offset + 4 or
        !std.mem.eql(u8, frame[offset .. offset + 4], "VBRI"))
        return null;
    if (frame.len < offset + 26) return error.TruncatedVbriHeader;
    const version = readU16(frame[offset + 4 .. offset + 6]);
    if (version != 1) return error.UnsupportedVbriVersion;
    const entry_count = readU16(frame[offset + 18 .. offset + 20]);
    const entry_bytes = readU16(frame[offset + 22 .. offset + 24]);
    if (entry_bytes < 1 or entry_bytes > 4)
        return error.InvalidVbriEntrySize;
    const toc_scale = readU16(frame[offset + 20 .. offset + 22]);
    if (toc_scale == 0)
        return error.InvalidVbriTocScale;
    const frames_per_entry =
        readU16(frame[offset + 24 .. offset + 26]);
    if (frames_per_entry == 0)
        return error.InvalidVbriFramesPerEntry;
    const toc_bytes = std.math.mul(
        usize,
        entry_count,
        entry_bytes,
    ) catch return error.VbriSizeOverflow;
    if (frame.len - (offset + 26) < toc_bytes)
        return error.TruncatedVbriToc;
    const result = Vbri{
        .version = version,
        .delay = readU16(frame[offset + 6 .. offset + 8]),
        .quality = readU16(frame[offset + 8 .. offset + 10]),
        .stream_bytes = readU32(frame[offset + 10 .. offset + 14]),
        .frame_count = readU32(frame[offset + 14 .. offset + 18]),
        .toc_entries = entry_count,
        .toc_scale = toc_scale,
        .entry_bytes = entry_bytes,
        .frames_per_entry = frames_per_entry,
        .toc = frame[offset + 26 ..][0..toc_bytes],
    };
    _ = try result.approximateByteOffsetForFrame(0);
    return result;
}

pub fn leadingTagBytes(encoded: []const u8) !usize {
    if (encoded.len < 3 or !std.mem.eql(u8, encoded[0..3], "ID3"))
        return 0;
    if (encoded.len < 10) return error.TruncatedLeadingId3Tag;
    const total = try leadingTagSize(encoded[0..10]);
    if (total > encoded.len) return error.TruncatedLeadingId3Tag;
    return total;
}

fn leadingTagSize(header: []const u8) !usize {
    const version = header[3];
    if (version < 2 or version > 4) return error.UnsupportedLeadingId3Tag;
    for (header[6..10]) |byte| {
        if (byte & 0x80 != 0) return error.InvalidLeadingId3Size;
    }
    const body_bytes =
        (@as(usize, header[6]) << 21) |
        (@as(usize, header[7]) << 14) |
        (@as(usize, header[8]) << 7) |
        header[9];
    const footer_bytes: usize =
        if (version == 4 and header[5] & 0x10 != 0) 10 else 0;
    return std.math.add(
        usize,
        10 + footer_bytes,
        body_bytes,
    ) catch return error.LeadingId3SizeOverflow;
}

fn leadingFileTagBytes(prefix: []const u8, file_size: u64) !u64 {
    if (prefix.len < 3 or !std.mem.eql(u8, prefix[0..3], "ID3"))
        return 0;
    if (prefix.len < 10) return error.TruncatedLeadingId3Tag;
    const total: u64 = try leadingTagSize(prefix[0..10]);
    if (total > file_size) return error.TruncatedLeadingId3Tag;
    return total;
}

pub fn trailingTagStart(encoded: []const u8, audio_start: usize) usize {
    if (audio_start <= encoded.len and
        encoded.len - audio_start >= 128 and
        std.mem.eql(u8, encoded[encoded.len - 128 ..][0..3], "TAG"))
        return encoded.len - 128;
    return encoded.len;
}

fn readOptionalU32(bytes: []const u8, cursor: *usize) !u32 {
    if (bytes.len -| cursor.* < 4) return error.TruncatedXingHeader;
    const value = readU32(bytes[cursor.*..][0..4]);
    cursor.* += 4;
    return value;
}

fn readU16(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readU24(bytes: []const u8) u24 {
    return (@as(u24, bytes[0]) << 16) |
        (@as(u24, bytes[1]) << 8) |
        bytes[2];
}

fn readExactAt(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    destination: []u8,
) !void {
    return file_reader_io.readExactAt(
        io,
        file,
        offset,
        destination,
        error.TruncatedMp3File,
    );
}

pub fn referencePolyphaseTimeSlot(
    history: *[1024]f64,
    time_slot: *const [32]f32,
) [32]f64 {
    var index: usize = history.len;
    while (index > 64) {
        index -= 1;
        history[index] = history[index - 64];
    }
    for (0..64) |row| {
        const row_value: f64 = @floatFromInt(16 + row);
        var value: f64 = 0;
        for (time_slot, 0..) |sample, band| {
            const band_value: f64 = @floatFromInt(2 * band + 1);
            value += sample * @cos(
                row_value * band_value * std.math.pi / 64.0,
            );
        }
        history[row] = value;
    }

    var output: [32]f64 = @splat(0);
    for (0..32) |sample| {
        for (0..16) |phase| {
            const window_index = sample + 32 * phase;
            const group = window_index / 64;
            const offset = window_index % 64;
            const history_index = group * 128 +
                if (offset < 32) offset else offset + 64;
            const window_value =
                @as(f64, @floatFromInt(
                    synthesis_window_quantized[window_index],
                )) / 65_536.0;
            output[sample] +=
                history[history_index] * window_value;
        }
    }
    return output;
}
