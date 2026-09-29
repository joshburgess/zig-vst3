const std = @import("std");
const file_reader_io = @import("../file_reader_io.zig");
const metadata = @import("metadata.zig");
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
const Summary = metadata.Summary;

pub const DecoderFormat = struct {
    version: Version,
    sample_rate: u32,
    channel_count: u2,
};

pub fn headerStateValid(header: Header) bool {
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
