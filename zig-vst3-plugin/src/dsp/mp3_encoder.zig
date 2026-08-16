const std = @import("std");
const file_reader_io = @import("file_reader_io.zig");
const file_writer_io = @import("file_writer_io.zig");
const huffman_tables = @import("mp3_huffman_tables.zig");
const mp3_decoder = @import("mp3/decoder.zig");
const mp3_reader = @import("mp3/reader.zig");
const reservoir_support = @import("mp3/reservoir.zig");
const syntax = @import("mp3/syntax.zig");
const synthesis_window_quantized =
    @import("mp3_synthesis_window.zig").values;

pub const Version = syntax.Version;
pub const ChannelMode = syntax.ChannelMode;
pub const maximum_free_format_frame_bytes =
    syntax.maximum_free_format_frame_bytes;
pub const maximum_encoded_frame_bytes =
    syntax.maximum_encoded_frame_bytes;
pub const maximum_encoded_main_data_bytes =
    syntax.maximum_encoded_main_data_bytes;
pub const Limits = syntax.Limits;
pub const default_limits = syntax.default_limits;
const maximum_frame_main_data_bytes =
    syntax.maximum_frame_main_data_bytes;
const decoder_delay_samples = syntax.decoder_delay_samples;
pub const Header = syntax.Header;
const bitrate = syntax.bitrate;
const bitrateIndex = syntax.bitrateIndex;
const sampleRate = syntax.sampleRate;
const sampleRateIndex = syntax.sampleRateIndex;
const headersCompatible = syntax.headersCompatible;
const readU32 = syntax.readU32;
pub const GranuleChannel = syntax.GranuleChannel;
pub const Granule = syntax.Granule;
pub const SideInformation = syntax.SideInformation;
pub const MainData = syntax.MainData;
pub const ScaleFactorChannel = syntax.ScaleFactorChannel;
pub const ScaleFactorGranule = syntax.ScaleFactorGranule;
pub const ScaleFactors = syntax.ScaleFactors;
pub const ScaleFactorBands = syntax.ScaleFactorBands;
pub const QuantizedSpectrum = syntax.QuantizedSpectrum;
pub const RequantizedSpectrum = syntax.RequantizedSpectrum;
pub const StereoSpectrum = syntax.StereoSpectrum;
pub const HybridSamples = syntax.HybridSamples;
pub const PcmGranule = syntax.PcmGranule;
pub const EncoderScaleFactors = syntax.EncoderScaleFactors;
pub const encodeSideInformation = syntax.encodeSideInformation;
const parseSideInformation = syntax.parseSideInformation;
const scaleFactorValueCount = syntax.scaleFactorValueCount;
const scaleFactorLayout = syntax.scaleFactorLayout;
const validateBlockDescription = syntax.validateBlockDescription;
const mixedLongSubbands = syntax.mixedLongSubbands;
const ScaleFactorLayout = syntax.ScaleFactorLayout;
const quantizedMagnitude = syntax.quantizedMagnitude;
const mpeg1_scale_factor_lengths =
    syntax.mpeg1_scale_factor_lengths;
const lsfScaleFactorPlan = syntax.lsfScaleFactorPlan;
const MainDataBitWriter = syntax.MainDataBitWriter;
const MainDataBitReader = syntax.MainDataBitReader;
const byteRangesOverlap = syntax.byteRangesOverlap;
const appendMainDataBits = syntax.appendMainDataBits;
const lsf_scale_factor_counts = syntax.lsf_scale_factor_counts;
const count1_table_a = syntax.count1_table_a;
const decodeMpeg1ScaleFactorChannel =
    syntax.decodeMpeg1ScaleFactorChannel;
const decodeLsfScaleFactorChannel =
    syntax.decodeLsfScaleFactorChannel;
const decodeHuffmanPair = syntax.decodeHuffmanPair;
pub const DecoderFormat = mp3_decoder.DecoderFormat;
pub const HybridSynthesis = mp3_decoder.HybridSynthesis;
pub const PolyphaseSynthesis = mp3_decoder.PolyphaseSynthesis;
pub const FrameDecoder = mp3_decoder.FrameDecoder;
pub const PcmRange = mp3_decoder.PcmRange;
pub const TrimmedPcmFrame = mp3_decoder.TrimmedPcmFrame;
pub const GaplessPlan = mp3_decoder.GaplessPlan;
pub const StreamDecoder = mp3_decoder.StreamDecoder;
pub const requantizeChannel = mp3_decoder.requantizeChannel;
pub const processStereo = mp3_decoder.processStereo;
pub const reduceAliases = mp3_decoder.reduceAliases;
pub const prepareAliasesForEncoding =
    mp3_decoder.prepareAliasesForEncoding;
pub const XingKind = mp3_reader.XingKind;
pub const Xing = mp3_reader.Xing;
pub const Vbri = mp3_reader.Vbri;
pub const VbriSummary = mp3_reader.VbriSummary;
pub const Frame = mp3_reader.Frame;
pub const Summary = mp3_reader.Summary;
pub const SeekPoint = mp3_reader.SeekPoint;
pub const FileFrame = mp3_reader.FileFrame;
pub const FileSummary = mp3_reader.FileSummary;
pub const Stream = mp3_reader.Stream;
pub const FileReader = mp3_reader.FileReader;
pub const requiredSeekPoints = mp3_reader.requiredSeekPoints;
pub const buildSeekIndex = mp3_reader.buildSeekIndex;
pub const findSeekPoint = mp3_reader.findSeekPoint;
pub const requiredFileSeekPoints = mp3_reader.requiredFileSeekPoints;
pub const buildFileSeekIndex = mp3_reader.buildFileSeekIndex;
pub const buildFileSeekIndexTransactional =
    mp3_reader.buildFileSeekIndexTransactional;
const formatFromHeader = mp3_decoder.formatFromHeader;
const mp3SampleRateValid = mp3_decoder.mp3SampleRateValid;
const mp3SamplesPerFrameForRate =
    mp3_decoder.mp3SamplesPerFrameForRate;
const minimumFrameBytes = mp3_reader.minimumFrameBytes;
const crc16 = mp3_reader.crc16;
const referencePolyphaseTimeSlot =
    mp3_decoder.referencePolyphaseTimeSlot;
const analysis_window = mp3_decoder.analysis_window;
const analysis_matrix = mp3_decoder.analysis_matrix;
const analyzeHybridBlock = mp3_decoder.analyzeHybridBlock;
const checkedHybridSample = mp3_decoder.checkedHybridSample;
const mpeg1IntensityGains = mp3_decoder.mpeg1IntensityGains;
const lsfIntensityGains = mp3_decoder.lsfIntensityGains;
const leadingTagBytes = mp3_reader.leadingTagBytes;
const containsNonzero = mp3_decoder.containsNonzero;
const resolvedFrameBytes = mp3_reader.resolvedFrameBytes;
const alias_cs = mp3_decoder.alias_cs;
const alias_ca = mp3_decoder.alias_ca;
const long_imdct = mp3_decoder.long_imdct;
const synthesis_matrix = mp3_decoder.synthesis_matrix;
const frameAtKnownLength = mp3_reader.frameAtKnownLength;
const trailingTagStart = mp3_reader.trailingTagStart;
pub const MainDataReservoir = syntax.MainDataReservoir;
pub const decodeScaleFactors = syntax.decodeScaleFactors;
pub const scaleFactorBands = syntax.scaleFactorBands;
pub const huffmanRegionEnds = syntax.huffmanRegionEnds;
pub const EncodedHuffmanChannel = syntax.EncodedHuffmanChannel;
pub const encodeHuffmanChannel = syntax.encodeHuffmanChannel;
pub const decodeHuffmanChannel = syntax.decodeHuffmanChannel;
pub const EncodedScaleFactors = syntax.EncodedScaleFactors;
pub const encodeScaleFactors = syntax.encodeScaleFactors;
pub const ReservoirQuantizerBudget =
    reservoir_support.ReservoirQuantizerBudget;
pub const ReservoirCreditDecision =
    reservoir_support.ReservoirCreditDecision;
pub const ReservoirCreditTracker =
    reservoir_support.ReservoirCreditTracker;
pub const reservoirQuantizerBudget =
    reservoir_support.reservoirQuantizerBudget;
fn headerStateValid(header: Header) bool {
    if (sampleRateIndex(header.version, header.sample_rate) == null)
        return false;
    if (header.free_format) return header.bitrate_kbps == 0;
    return bitrateIndex(header.version, header.bitrate_kbps) != null;
}

pub const EncoderConfig = struct {
    version: Version = .mpeg1,
    bitrate_kbps: u16 = 128,
    sample_rate: u32 = 44_100,
    channel_mode: ChannelMode = .stereo,
    crc_present: bool = false,
    private: bool = false,
    mode_extension: u2 = 0,
    copyright: bool = false,
    original: bool = true,
    emphasis: u2 = 0,

    pub fn header(self: EncoderConfig, padding: bool) !Header {
        const encoded_header = Header{
            .version = self.version,
            .crc_present = self.crc_present,
            .free_format = false,
            .bitrate_kbps = self.bitrate_kbps,
            .sample_rate = self.sample_rate,
            .padding = padding,
            .private = self.private,
            .channel_mode = self.channel_mode,
            .mode_extension = self.mode_extension,
            .copyright = self.copyright,
            .original = self.original,
            .emphasis = self.emphasis,
        };
        _ = try encoded_header.encode();
        if (encoded_header.frameBytes() <
            minimumFrameBytes(encoded_header) or
            encoded_header.frameBytes() > maximum_encoded_frame_bytes)
            return error.InvalidMp3EncoderFrameSize;
        return encoded_header;
    }
};

pub const FrameEncoder = struct {
    config: EncoderConfig,
    padding_accumulator: u32 = 0,
    frames_encoded: u64 = 0,

    pub fn init(config: EncoderConfig) !FrameEncoder {
        _ = try config.header(false);
        return .{ .config = config };
    }

    pub fn reset(self: *FrameEncoder) void {
        self.padding_accumulator = 0;
        self.frames_encoded = 0;
    }

    pub fn valid(self: *const FrameEncoder) bool {
        _ = self.config.header(false) catch return false;
        return self.padding_accumulator < self.config.sample_rate;
    }

    pub fn nextFrameBytes(self: FrameEncoder) !usize {
        const next = try self.advance();
        return next.header.frameBytes();
    }

    pub fn nextFrameBytesAtBitrate(
        self: FrameEncoder,
        bitrate_kbps: u16,
    ) !usize {
        const next = try self.advanceAtBitrate(bitrate_kbps);
        return next.header.frameBytes();
    }

    pub fn encodeSilentFrame(
        self: *FrameEncoder,
        destination: []u8,
    ) ![]u8 {
        const frame = QuantizedEncoderFrame{};
        return self.encodeQuantizedFrame(&frame, destination);
    }

    pub fn encodeQuantizedFrame(
        self: *FrameEncoder,
        frame: *const QuantizedEncoderFrame,
        destination: []u8,
    ) ![]u8 {
        return self.encodeQuantizedFrameAtBitrate(
            self.config.bitrate_kbps,
            frame,
            destination,
        );
    }

    pub fn encodeQuantizedFrameAtBitrate(
        self: *FrameEncoder,
        bitrate_kbps: u16,
        frame: *const QuantizedEncoderFrame,
        destination: []u8,
    ) ![]u8 {
        const next = try self.advanceAtBitrate(bitrate_kbps);
        const frame_bytes = next.header.frameBytes();
        if (destination.len < frame_bytes)
            return error.InsufficientMp3EncoderStorage;
        var staged = try stageQuantizedFrame(next.header, frame);
        const main_data_offset = frameMainDataOffset(next.header);
        const main_data_bytes = try std.math.divCeil(
            usize,
            staged.main_data_bits,
            8,
        );
        if (main_data_bytes > frame_bytes - main_data_offset)
            return error.Mp3HuffmanBitCountOverflow;
        @memcpy(
            staged.frame[main_data_offset..][0..main_data_bytes],
            staged.main_data[0..main_data_bytes],
        );
        @memcpy(destination[0..frame_bytes], staged.frame[0..frame_bytes]);
        self.padding_accumulator = next.padding_accumulator;
        self.frames_encoded += 1;
        return destination[0..frame_bytes];
    }

    pub fn encodeQuantizedFrameParts(
        self: *FrameEncoder,
        frame: *const QuantizedEncoderFrame,
        frame_destination: []u8,
        main_data_destination: []u8,
    ) !QuantizedFrameParts {
        return self.encodeQuantizedFramePartsAtBitrate(
            self.config.bitrate_kbps,
            frame,
            frame_destination,
            main_data_destination,
        );
    }

    pub fn encodeQuantizedFramePartsAtBitrate(
        self: *FrameEncoder,
        bitrate_kbps: u16,
        frame: *const QuantizedEncoderFrame,
        frame_destination: []u8,
        main_data_destination: []u8,
    ) !QuantizedFrameParts {
        const next = try self.advanceAtBitrate(bitrate_kbps);
        const frame_bytes = next.header.frameBytes();
        if (frame_destination.len < frame_bytes)
            return error.InsufficientMp3EncoderStorage;
        if (byteRangesOverlap(
            @intFromPtr(frame_destination.ptr),
            frame_bytes,
            @intFromPtr(main_data_destination.ptr),
            main_data_destination.len,
        )) return error.OverlappingMp3EncoderStorage;
        const staged = try stageQuantizedFrame(next.header, frame);
        const main_data_bytes = try std.math.divCeil(
            usize,
            staged.main_data_bits,
            8,
        );
        if (main_data_destination.len < main_data_bytes)
            return error.InsufficientMp3MainDataStorage;
        @memcpy(
            frame_destination[0..frame_bytes],
            staged.frame[0..frame_bytes],
        );
        @memcpy(
            main_data_destination[0..main_data_bytes],
            staged.main_data[0..main_data_bytes],
        );
        self.padding_accumulator = next.padding_accumulator;
        self.frames_encoded += 1;
        return .{
            .frame = frame_destination[0..frame_bytes],
            .main_data = main_data_destination[0..main_data_bytes],
            .main_data_bits = staged.main_data_bits,
        };
    }

    fn stageQuantizedFrame(
        header: Header,
        frame: *const QuantizedEncoderFrame,
    ) !StagedQuantizedFrame {
        var staged = StagedQuantizedFrame{};
        const encoded_header = try header.encode();
        @memcpy(staged.frame[0..4], &encoded_header);
        const side_offset: usize =
            if (header.crc_present) 6 else 4;
        const side_end = side_offset +
            header.sideInformationBytes();
        const channel_count: u2 =
            @intCast(header.channels());
        const granule_count: u2 =
            if (header.version == .mpeg1) 2 else 1;
        var side = SideInformation{
            .channel_count = channel_count,
            .granule_count = granule_count,
            .main_data_begin = 0,
            .private_bits = frame.private_bits,
            .scfsi = frame.scfsi,
            .main_data_bits = 0,
        };
        if (header.version != .mpeg1 and
            !std.meta.eql(frame.scfsi, @as([2]u4, @splat(0))))
            return error.InvalidMp3EncoderScaleFactors;
        if (header.version == .mpeg1) {
            for (0..channel_count) |channel| {
                if (frame.scfsi[channel] != 0 and
                    (frame.granules[0][channel]
                        .description.block_type == 2 or
                        frame.granules[1][channel]
                            .description.block_type == 2))
                    return error.InvalidMp3EncoderScaleFactors;
            }
        }
        var main_writer = MainDataBitWriter{
            .bytes = &staged.main_data,
        };
        var scale_factor_storage: [64]u8 = undefined;
        var channel_storage: [512]u8 = undefined;
        for (0..2) |granule| {
            for (0..2) |channel| {
                const source = &frame.granules[granule][channel];
                if (granule >= granule_count or
                    channel >= channel_count)
                {
                    if (!std.meta.eql(
                        source.*,
                        QuantizedEncoderChannel{},
                    )) return error.InvalidMp3EncoderFrame;
                    continue;
                }
                if (source.description.part2_3_length != 0)
                    return error.InvalidMp3EncoderFrame;
                const encoded_factors = try encodeScaleFactors(
                    header,
                    source.description,
                    frame.scfsi[channel],
                    @intCast(granule),
                    @intCast(channel),
                    frame.granules[0][channel].scale_factors,
                    source.scale_factors,
                    &scale_factor_storage,
                );
                try appendMainDataBits(
                    &main_writer,
                    encoded_factors.main_data,
                );
                const encoded = try encodeHuffmanChannel(
                    header,
                    source.description,
                    &source.spectrum,
                    &channel_storage,
                );
                try appendMainDataBits(
                    &main_writer,
                    encoded.main_data,
                );
                var encoded_description = encoded.description;
                encoded_description.part2_3_length = std.math.add(
                    u12,
                    @intCast(encoded_factors.main_data.bit_count),
                    encoded.description.part2_3_length,
                ) catch return error.Mp3MainDataBitCountOverflow;
                side.granules[granule].channels[channel] =
                    encoded_description;
                side.main_data_bits = std.math.add(
                    u16,
                    side.main_data_bits,
                    encoded_description.part2_3_length,
                ) catch return error.Mp3MainDataBitCountOverflow;
            }
        }
        if (main_writer.bit_offset != side.main_data_bits)
            return error.InvalidMp3EncoderState;
        var side_storage: [32]u8 = undefined;
        const encoded_side = try encodeSideInformation(
            header,
            side,
            &side_storage,
        );
        @memcpy(staged.frame[side_offset..side_end], encoded_side);
        if (header.crc_present) {
            var checksum = crc16(0xffff, staged.frame[2..4]);
            checksum = crc16(
                checksum,
                staged.frame[side_offset..side_end],
            );
            staged.frame[4] = @intCast(checksum >> 8);
            staged.frame[5] = @intCast(checksum & 0xff);
        }
        staged.main_data_bits = side.main_data_bits;
        return staged;
    }

    const Advance = struct {
        header: Header,
        padding_accumulator: u32,
    };

    fn advance(self: FrameEncoder) !Advance {
        return self.advanceAtBitrate(self.config.bitrate_kbps);
    }

    fn advanceAtBitrate(
        self: FrameEncoder,
        bitrate_kbps: u16,
    ) !Advance {
        if (!self.valid()) return error.InvalidMp3EncoderState;
        var frame_config = self.config;
        frame_config.bitrate_kbps = bitrate_kbps;
        _ = try frame_config.header(false);
        if (self.frames_encoded == std.math.maxInt(u64))
            return error.Mp3EncoderFrameCountOverflow;

        const coefficient: u64 =
            if (self.config.version == .mpeg1) 144_000 else 72_000;
        const numerator = coefficient * bitrate_kbps;
        const remainder: u32 =
            @intCast(numerator % self.config.sample_rate);
        const accumulated: u64 =
            @as(u64, self.padding_accumulator) + remainder;
        const padding = accumulated >= self.config.sample_rate;
        const next_accumulator: u32 = @intCast(
            if (padding)
                accumulated - self.config.sample_rate
            else
                accumulated,
        );
        return .{
            .header = try frame_config.header(padding),
            .padding_accumulator = next_accumulator,
        };
    }
};

pub const QuantizedFrameParts = struct {
    frame: []u8,
    main_data: []u8,
    main_data_bits: u16,
};

pub const StagedQuantizedFrame = struct {
    frame: [maximum_encoded_frame_bytes]u8 = @splat(0),
    main_data: [maximum_encoded_main_data_bytes]u8 = @splat(0),
    main_data_bits: u16 = 0,
};

pub const QuantizedEncoderChannel = struct {
    description: GranuleChannel = .{},
    scale_factors: EncoderScaleFactors = .{},
    spectrum: [576]i32 = @splat(0),
};

pub const QuantizedEncoderFrame = struct {
    private_bits: u5 = 0,
    scfsi: [2]u4 = @splat(0),
    granules: [2][2]QuantizedEncoderChannel =
        @splat(@splat(.{})),
};

pub const PolyphaseAnalysis = struct {
    history: [512]f64 = @splat(0),

    pub fn reset(self: *PolyphaseAnalysis) void {
        self.* = .{};
    }

    pub fn valid(self: *const PolyphaseAnalysis) bool {
        for (self.history) |sample| {
            if (!std.math.isFinite(sample)) return false;
        }
        return true;
    }

    pub fn process(
        self: *PolyphaseAnalysis,
        pcm: PcmGranule,
    ) !HybridSamples {
        if (!self.valid())
            return error.InvalidMp3PolyphaseAnalysisState;
        for (pcm.samples) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidMp3PcmSamples;
        }

        var next = self.*;
        var output = HybridSamples{};
        for (0..18) |time| {
            var index = next.history.len;
            while (index > 32) {
                index -= 1;
                next.history[index] = next.history[index - 32];
            }
            for (0..32) |sample| {
                next.history[sample] =
                    pcm.samples[time * 32 + 31 - sample];
            }

            var polyphase: [64]f64 = @splat(0);
            for (0..64) |phase| {
                for (0..8) |block| {
                    const window_index = phase + block * 64;
                    polyphase[phase] +=
                        next.history[window_index] *
                        analysis_window[window_index];
                }
            }
            for (analysis_matrix, 0..) |row, band| {
                var value: f64 = 0;
                for (row, polyphase) |coefficient, sample|
                    value += coefficient * sample;
                output.time_slots[time][band] =
                    try checkedHybridSample(value);
            }
        }
        self.* = next;
        return output;
    }
};

pub const HybridAnalysis = struct {
    history: [32][18]f32 = @splat(@splat(0)),

    pub fn reset(self: *HybridAnalysis) void {
        self.* = .{};
    }

    pub fn valid(self: *const HybridAnalysis) bool {
        for (self.history) |subband| {
            for (subband) |sample| {
                if (!std.math.isFinite(sample)) return false;
            }
        }
        return true;
    }

    pub fn process(
        self: *HybridAnalysis,
        header: Header,
        description: GranuleChannel,
        hybrid: HybridSamples,
    ) !RequantizedSpectrum {
        if (!self.valid())
            return error.InvalidMp3HybridAnalysisState;
        _ = try scaleFactorBands(header);
        try validateBlockDescription(description);
        for (hybrid.time_slots) |time_slot| {
            for (time_slot) |sample| {
                if (!std.math.isFinite(sample))
                    return error.InvalidMp3HybridSamples;
            }
        }

        var next = self.*;
        var reduced = RequantizedSpectrum{};
        const mixed_long_subbands =
            if (description.mixed_block)
                mixedLongSubbands(header)
            else
                0;
        for (0..32) |subband| {
            var block: [36]f32 = undefined;
            @memcpy(block[0..18], &self.history[subband]);
            for (0..18) |time| {
                var sample = hybrid.time_slots[time][subband];
                if (subband & 1 != 0 and time & 1 != 0)
                    sample = -sample;
                block[18 + time] = sample;
                next.history[subband][time] = sample;
            }
            const spectrum = analyzeHybridBlock(
                description,
                subband < mixed_long_subbands,
                &block,
            );
            for (spectrum, 0..) |line, frequency| {
                reduced.lines[subband * 18 + frequency] =
                    try checkedHybridSample(line);
            }
        }
        const output = try prepareAliasesForEncoding(
            header,
            description,
            reduced,
        );
        self.* = next;
        return output;
    }
};

pub const PcmFrame = mp3_decoder.PcmFrame;

pub const EncoderAnalysis = struct {
    config: EncoderConfig,
    polyphase: [2]PolyphaseAnalysis = @splat(.{}),
    hybrid: [2]HybridAnalysis = @splat(.{}),
    format: DecoderFormat,
    frames_analyzed: u64 = 0,

    pub fn init(config: EncoderConfig) !EncoderAnalysis {
        const header = try config.header(false);
        return .{
            .config = config,
            .format = formatFromHeader(header),
        };
    }

    pub fn reset(self: *EncoderAnalysis) void {
        self.polyphase = @splat(.{});
        self.hybrid = @splat(.{});
        self.frames_analyzed = 0;
    }

    pub fn valid(self: *const EncoderAnalysis) bool {
        const header = self.config.header(false) catch return false;
        const format = formatFromHeader(header);
        if (!std.meta.eql(format, self.format)) return false;
        self.validateHistoryState(format) catch return false;
        return true;
    }

    pub fn analyze(
        self: *EncoderAnalysis,
        descriptions: [2][2]GranuleChannel,
        pcm: PcmFrame,
    ) !AnalyzedEncoderFrame {
        const header = try self.config.header(false);
        const format = formatFromHeader(header);
        if (!std.meta.eql(format, self.format))
            return error.Mp3EncoderAnalysisFormatChanged;
        try self.validateHistoryState(format);
        if (pcm.channel_count != format.channel_count or
            pcm.sample_count != header.samplesPerFrame())
            return error.InvalidMp3EncoderPcmFrame;

        const granule_count: u2 =
            if (header.version == .mpeg1) 2 else 1;
        for (0..2) |granule| {
            for (0..2) |channel| {
                if (granule >= granule_count or
                    channel >= format.channel_count)
                {
                    if (!std.meta.eql(
                        descriptions[granule][channel],
                        GranuleChannel{},
                    )) return error.InvalidMp3EncoderAnalysisFrame;
                }
            }
        }

        var next = self.*;
        var output = AnalyzedEncoderFrame{
            .channel_count = format.channel_count,
            .granule_count = granule_count,
        };
        for (0..granule_count) |granule| {
            for (0..format.channel_count) |channel| {
                var samples = PcmGranule{};
                const start = granule * samples.samples.len;
                @memcpy(
                    &samples.samples,
                    pcm.channels[channel][start..][0..samples.samples.len],
                );
                const hybrid_samples =
                    try next.polyphase[channel].process(samples);
                output.granules[granule][channel] = .{
                    .description = descriptions[granule][channel],
                    .spectrum = try next.hybrid[channel].process(
                        header,
                        descriptions[granule][channel],
                        hybrid_samples,
                    ),
                };
            }
        }
        next.frames_analyzed = std.math.add(
            u64,
            next.frames_analyzed,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        self.* = next;
        return output;
    }

    fn validateHistoryState(
        self: *const EncoderAnalysis,
        format: DecoderFormat,
    ) !void {
        for (0..2) |channel| {
            if (!self.polyphase[channel].valid() or
                !self.hybrid[channel].valid())
                return error.InvalidMp3EncoderAnalysisState;
            if ((self.frames_analyzed == 0 or
                channel >= format.channel_count) and
                (!std.meta.eql(self.polyphase[channel], PolyphaseAnalysis{}) or
                    !std.meta.eql(self.hybrid[channel], HybridAnalysis{})))
                return error.InvalidMp3EncoderAnalysisState;
        }
    }
};

pub const AnalyzedEncoderChannel = struct {
    description: GranuleChannel = .{},
    spectrum: RequantizedSpectrum = .{},
    intensity_positions: [39]u8 = @splat(0),
    intensity_enabled: [39]bool = @splat(false),
};

pub const AnalyzedEncoderFrame = struct {
    channel_count: u2,
    granule_count: u2,
    granules: [2][2]AnalyzedEncoderChannel =
        @splat(@splat(.{})),
};

pub fn prepareEncoderStereo(
    header: Header,
    analyzed: AnalyzedEncoderFrame,
) !AnalyzedEncoderFrame {
    try validateAnalyzedEncoderFrame(header, analyzed);
    const channel_count: u2 = @intCast(header.channels());
    const granule_count: u2 =
        if (header.version == .mpeg1) 2 else 1;
    if (channel_count != 2 or
        header.channel_mode != .joint_stereo or
        header.mode_extension == 0)
        return analyzed;

    var result = analyzed;
    const scale: f32 = 1.0 / @sqrt(2.0);
    const intensity = header.mode_extension & 1 != 0;
    const mid_side = header.mode_extension & 2 != 0;
    for (0..granule_count) |granule| {
        const left = analyzed.granules[granule][0];
        const right = analyzed.granules[granule][1];
        if (!std.meta.eql(left.description, right.description))
            return error.InvalidMp3EncoderStereoBlocks;
        for (left.spectrum.lines, right.spectrum.lines) |
            left_line,
            right_line,
        | {
            if (!std.math.isFinite(left_line) or
                !std.math.isFinite(right_line))
                return error.InvalidMp3RequantizedSpectrum;
        }
        var ordered = [2][576]f32{
            try orderEncoderSpectrum(
                header,
                left.description,
                left.spectrum,
            ),
            try orderEncoderSpectrum(
                header,
                right.description,
                right.spectrum,
            ),
        };
        const layout = try encoderBandLayout(
            header,
            right.description,
        );
        const intensity_start =
            encoderIntensityStartBand(right.description, layout);
        var intensity_description = right.description;
        intensity_description.scalefac_compress =
            if (header.version == .mpeg1) 13 else 358;
        const intensity_widths = try encoderScaleFactorWidths(
            header,
            intensity_description,
            true,
        );
        for (0..layout.band_count) |band| {
            const start: usize = layout.starts[band];
            const end: usize = layout.starts[band + 1];
            if (intensity and band >= intensity_start) {
                const position = try selectEncoderIntensityPosition(
                    header,
                    intensity_widths[band],
                    ordered[0][start..end],
                    ordered[1][start..end],
                );
                if (position) |selected| {
                    const gains = encoderIntensityGains(
                        header,
                        selected,
                    );
                    for (
                        ordered[0][start..end],
                        ordered[1][start..end],
                    ) |*left_line, *right_line| {
                        const denominator =
                            gains[0] * gains[0] +
                            gains[1] * gains[1];
                        const combined =
                            (gains[0] * left_line.* +
                                gains[1] * right_line.*) /
                            denominator;
                        if (!std.math.isFinite(combined))
                            return error.InvalidMp3EncoderStereoSpectrum;
                        left_line.* = combined;
                        right_line.* = 0;
                    }
                    result.granules[granule][1]
                        .intensity_positions[band] = selected;
                    result.granules[granule][1]
                        .intensity_enabled[band] = true;
                    continue;
                }
                @memset(ordered[0][start..end], 0);
                @memset(ordered[1][start..end], 0);
                continue;
            }
            if (mid_side) {
                for (
                    ordered[0][start..end],
                    ordered[1][start..end],
                ) |*left_line, *right_line| {
                    const middle =
                        (left_line.* + right_line.*) * scale;
                    const side =
                        (left_line.* - right_line.*) * scale;
                    if (!std.math.isFinite(middle) or
                        !std.math.isFinite(side))
                        return error.InvalidMp3EncoderStereoSpectrum;
                    left_line.* = middle;
                    right_line.* = side;
                }
            }
        }
        result.granules[granule][0].spectrum =
            try restoreEncoderSpectrumOrder(
                header,
                left.description,
                ordered[0],
            );
        result.granules[granule][1].spectrum =
            try restoreEncoderSpectrumOrder(
                header,
                right.description,
                ordered[1],
            );
    }
    return result;
}

pub fn encoderIntensityStartBand(
    description: GranuleChannel,
    layout: EncoderBandLayout,
) usize {
    if (description.block_type != 2) return 14;
    if (!description.mixed_block) return 24;
    return layout.band_count - 15;
}

pub fn selectEncoderIntensityPosition(
    header: Header,
    width: u4,
    left: []const f32,
    right: []const f32,
) !?u8 {
    if (left.len != right.len)
        return error.InvalidMp3ScaleFactorBands;
    if (width == 0 and header.version != .mpeg1)
        return null;
    const maximum: u8 = if (width == 0)
        0
    else
        @intCast((@as(u16, 1) << width) - 1);
    const last_position: u8 = switch (header.version) {
        .mpeg1 => @min(maximum, 6),
        .mpeg2, .mpeg25 => @min(maximum - 1, 6),
    };
    var best_position: u8 = 0;
    var best_error = std.math.inf(f64);
    var position: u8 = 0;
    while (position <= last_position) : (position += 1) {
        const gains = encoderIntensityGains(header, position);
        const denominator =
            @as(f64, gains[0]) * gains[0] +
            @as(f64, gains[1]) * gains[1];
        var error_energy: f64 = 0;
        for (left, right) |left_line, right_line| {
            if (!std.math.isFinite(left_line) or
                !std.math.isFinite(right_line))
                return error.InvalidMp3RequantizedSpectrum;
            const combined =
                (@as(f64, gains[0]) * left_line +
                    @as(f64, gains[1]) * right_line) /
                denominator;
            const left_error = combined * gains[0] - left_line;
            const right_error = combined * gains[1] - right_line;
            error_energy +=
                left_error * left_error +
                right_error * right_error;
        }
        if (!std.math.isFinite(error_energy))
            return error.InvalidMp3EncoderStereoSpectrum;
        if (error_energy < best_error) {
            best_error = error_energy;
            best_position = position;
        }
    }
    return best_position;
}

pub fn encoderIntensityGains(
    header: Header,
    position: u8,
) [2]f32 {
    return switch (header.version) {
        .mpeg1 => mpeg1IntensityGains(position),
        .mpeg2, .mpeg25 => lsfIntensityGains(position, false),
    };
}

pub fn validateAnalyzedEncoderFrame(
    header: Header,
    analyzed: AnalyzedEncoderFrame,
) !void {
    const channel_count: u2 = @intCast(header.channels());
    const granule_count: u2 =
        if (header.version == .mpeg1) 2 else 1;
    if (analyzed.channel_count != channel_count or
        analyzed.granule_count != granule_count)
        return error.InvalidMp3EncoderAnalysisFrame;
    for (0..2) |granule| {
        for (0..2) |channel| {
            if ((granule >= granule_count or
                channel >= channel_count) and
                !std.meta.eql(
                    analyzed.granules[granule][channel],
                    AnalyzedEncoderChannel{},
                ))
                return error.InvalidMp3EncoderAnalysisFrame;
        }
    }
}

pub const EncoderBlockClassifier = struct {
    short_active: [2]bool = @splat(false),
    attack_ratio: f32 = 8.0,

    pub fn reset(self: *EncoderBlockClassifier) void {
        self.short_active = @splat(false);
    }

    pub fn valid(self: *const EncoderBlockClassifier) bool {
        return std.math.isFinite(self.attack_ratio) and
            self.attack_ratio > 1.0;
    }

    pub fn classify(
        self: *EncoderBlockClassifier,
        header: Header,
        pcm: PcmFrame,
    ) ![2][2]GranuleChannel {
        if (!self.valid())
            return error.InvalidMp3EncoderAttackRatio;
        const channel_count: u2 = @intCast(header.channels());
        const granule_count: u2 =
            if (header.version == .mpeg1) 2 else 1;
        if (pcm.channel_count != channel_count or
            pcm.sample_count != header.samplesPerFrame())
            return error.InvalidMp3EncoderPcmFrame;

        var result: [2][2]GranuleChannel = @splat(@splat(.{}));
        var next_short = self.short_active;
        for (0..granule_count) |granule| {
            var attacks: [2]bool = @splat(false);
            for (0..channel_count) |channel| {
                const start = granule * 576;
                attacks[channel] = try hasEncoderAttack(
                    pcm.channels[channel][start..][0..576],
                    self.attack_ratio,
                );
            }
            if (header.channel_mode == .joint_stereo) {
                const attack = attacks[0] or attacks[1];
                attacks = @splat(attack);
                const active = next_short[0] or next_short[1];
                next_short = @splat(active);
            }
            for (0..channel_count) |channel| {
                const was_short = next_short[channel];
                result[granule][channel] = if (attacks[channel])
                    if (was_short)
                        .{
                            .window_switching = true,
                            .block_type = 2,
                        }
                    else
                        .{
                            .window_switching = true,
                            .block_type = 1,
                        }
                else if (was_short)
                    .{
                        .window_switching = true,
                        .block_type = 3,
                    }
                else
                    .{};
                next_short[channel] = attacks[channel];
            }
        }
        self.short_active = next_short;
        return result;
    }
};

pub fn hasEncoderAttack(samples: []const f32, attack_ratio: f32) !bool {
    var previous_energy: f64 = 0.0;
    for (0..6) |partition| {
        var energy: f64 = 0.0;
        for (samples[partition * 96 ..][0..96]) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidMp3EncoderPcmSample;
            energy += @as(f64, sample) * @as(f64, sample);
        }
        if (partition != 0 and
            energy > @max(previous_energy, 1.0e-12) *
                attack_ratio)
            return true;
        previous_energy = @max(previous_energy * 0.25, energy);
    }
    return false;
}

pub const EncoderPsychoacousticConfig = struct {
    absolute_threshold: f32 = 1.0e-9,
    masking_ratio: f32 = 0.005,
    adjacent_masking_ratio: f32 = 0.001,
    tonal_masking_reduction: f32 = 0.0,
    forward_masking_ratio: f32 = 0.0,

    pub const production = EncoderPsychoacousticConfig{
        .tonal_masking_reduction = 0.5,
        .forward_masking_ratio = 0.01,
    };
};

pub const EncoderPsychoacousticChannel = struct {
    energy: [39]f32 = @splat(0),
    threshold: [39]f32 = @splat(0),
    tonality: [39]f32 = @splat(0),
    band_count: u6 = 0,
};

pub const EncoderPsychoacousticModel = struct {
    config: EncoderPsychoacousticConfig = .{},

    pub fn analyze(
        self: EncoderPsychoacousticModel,
        header: Header,
        channel: AnalyzedEncoderChannel,
    ) !EncoderPsychoacousticChannel {
        return self.analyzeWithHistory(header, channel, null);
    }

    pub fn analyzeWithHistory(
        self: EncoderPsychoacousticModel,
        header: Header,
        channel: AnalyzedEncoderChannel,
        previous: ?EncoderPsychoacousticChannel,
    ) !EncoderPsychoacousticChannel {
        try validateEncoderPsychoacousticConfig(self.config);
        const ordered = try orderEncoderSpectrum(
            header,
            channel.description,
            channel.spectrum,
        );
        const layout = try encoderBandLayout(
            header,
            channel.description,
        );
        var result = EncoderPsychoacousticChannel{
            .band_count = layout.band_count,
        };
        for (0..layout.band_count) |band| {
            var energy: f64 = 0;
            var logarithmic_energy: f64 = 0;
            const lines =
                ordered[layout.starts[band]..layout.starts[band + 1]];
            for (lines) |line| {
                if (!std.math.isFinite(line))
                    return error.InvalidMp3RequantizedSpectrum;
                const line_energy =
                    @as(f64, line) * @as(f64, line);
                energy += line_energy;
                logarithmic_energy +=
                    @log(@max(line_energy, 1.0e-30));
            }
            result.energy[band] = @floatCast(energy);
            const arithmetic_mean =
                energy / @as(f64, @floatFromInt(lines.len));
            const flatness = if (arithmetic_mean <= 1.0e-30)
                1.0
            else
                @min(
                    @exp(
                        logarithmic_energy /
                            @as(f64, @floatFromInt(lines.len)),
                    ) / arithmetic_mean,
                    1.0,
                );
            result.tonality[band] = @floatCast(1.0 - flatness);
        }
        if (previous) |history|
            try validatePsychoacousticHistory(
                history,
                history.band_count,
            );
        for (0..layout.band_count) |band| {
            const line_count: f64 = @floatFromInt(
                layout.starts[band + 1] - layout.starts[band],
            );
            const tonal_scale =
                1.0 -
                @as(f64, result.tonality[band]) *
                    self.config.tonal_masking_reduction;
            var threshold =
                @as(f64, self.config.absolute_threshold) *
                line_count +
                @as(f64, result.energy[band]) *
                    self.config.masking_ratio *
                    tonal_scale;
            if (band != 0)
                threshold +=
                    @as(f64, result.energy[band - 1]) *
                    self.config.adjacent_masking_ratio;
            if (band + 1 < layout.band_count)
                threshold +=
                    @as(f64, result.energy[band + 1]) *
                    self.config.adjacent_masking_ratio;
            if (previous) |history| {
                if (history.band_count == layout.band_count) {
                    threshold = @max(
                        threshold,
                        @as(f64, history.energy[band]) *
                            self.config.forward_masking_ratio,
                    );
                }
            }
            if (!std.math.isFinite(threshold))
                return error.InvalidMp3PsychoacousticEnergy;
            result.threshold[band] = @floatCast(threshold);
        }
        return result;
    }
};

pub const EncoderPsychoacousticTimeline = struct {
    model: EncoderPsychoacousticModel = .{},
    previous: [2]EncoderPsychoacousticChannel = @splat(.{}),
    history_present: [2]bool = @splat(false),

    pub fn reset(self: *EncoderPsychoacousticTimeline) void {
        self.previous = @splat(.{});
        self.history_present = @splat(false);
    }

    pub fn valid(self: *const EncoderPsychoacousticTimeline) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn analyzeFrame(
        self: *EncoderPsychoacousticTimeline,
        header: Header,
        analyzed: AnalyzedEncoderFrame,
    ) ![2][2]EncoderPsychoacousticChannel {
        try validateAnalyzedEncoderFrame(header, analyzed);
        try self.validateState();
        var next = self.*;
        var result: [2][2]EncoderPsychoacousticChannel =
            @splat(@splat(.{}));
        const channel_count: u2 = @intCast(header.channels());
        const granule_count: u2 =
            if (header.version == .mpeg1) 2 else 1;
        for (0..granule_count) |granule| {
            for (0..channel_count) |channel| {
                result[granule][channel] =
                    try next.model.analyzeWithHistory(
                        header,
                        analyzed.granules[granule][channel],
                        if (next.history_present[channel])
                            next.previous[channel]
                        else
                            null,
                    );
                next.previous[channel] = result[granule][channel];
                next.history_present[channel] = true;
            }
        }
        self.* = next;
        return result;
    }

    fn validateState(self: EncoderPsychoacousticTimeline) !void {
        try validateEncoderPsychoacousticConfig(self.model.config);
        if (self.history_present[1] and !self.history_present[0])
            return error.InvalidMp3PsychoacousticHistory;
        for (0..2) |channel| {
            if (!self.history_present[channel]) {
                if (!std.meta.eql(
                    self.previous[channel],
                    EncoderPsychoacousticChannel{},
                ))
                    return error.InvalidMp3PsychoacousticHistory;
                continue;
            }
            try validatePsychoacousticHistory(
                self.previous[channel],
                self.previous[channel].band_count,
            );
        }
    }
};

pub fn validatePsychoacousticHistory(
    history: EncoderPsychoacousticChannel,
    expected_band_count: u6,
) !void {
    if (history.band_count != expected_band_count or
        expected_band_count == 0 or
        expected_band_count > 39)
        return error.InvalidMp3PsychoacousticHistory;
    for (0..expected_band_count) |band| {
        if (!std.math.isFinite(history.energy[band]) or
            history.energy[band] < 0 or
            !std.math.isFinite(history.threshold[band]) or
            history.threshold[band] <= 0 or
            !std.math.isFinite(history.tonality[band]) or
            history.tonality[band] < 0 or
            history.tonality[band] > 1)
            return error.InvalidMp3PsychoacousticHistory;
    }
    for (expected_band_count..39) |band| {
        if (history.energy[band] != 0 or
            history.threshold[band] != 0 or
            history.tonality[band] != 0)
            return error.InvalidMp3PsychoacousticHistory;
    }
}

pub fn validateEncoderPsychoacousticConfig(
    config: EncoderPsychoacousticConfig,
) !void {
    if (!std.math.isFinite(config.absolute_threshold) or
        config.absolute_threshold <= 0 or
        !std.math.isFinite(config.masking_ratio) or
        config.masking_ratio < 0 or
        config.masking_ratio > 1 or
        !std.math.isFinite(config.adjacent_masking_ratio) or
        config.adjacent_masking_ratio < 0 or
        config.adjacent_masking_ratio > 1 or
        !std.math.isFinite(config.tonal_masking_reduction) or
        config.tonal_masking_reduction < 0 or
        config.tonal_masking_reduction > 1 or
        !std.math.isFinite(config.forward_masking_ratio) or
        config.forward_masking_ratio < 0 or
        config.forward_masking_ratio > 1)
        return error.InvalidMp3EncoderPsychoacousticConfig;
}

pub const EncoderQuantizer = struct {
    psychoacoustics: EncoderPsychoacousticModel = .{},

    pub fn quantize(
        header: Header,
        analyzed: AnalyzedEncoderFrame,
    ) !QuantizedEncoderFrame {
        return (EncoderQuantizer{}).process(header, analyzed);
    }

    pub fn process(
        self: EncoderQuantizer,
        header: Header,
        analyzed: AnalyzedEncoderFrame,
    ) !QuantizedEncoderFrame {
        var timeline = EncoderPsychoacousticTimeline{
            .model = self.psychoacoustics,
        };
        const psychoacoustics =
            try timeline.analyzeFrame(header, analyzed);
        return self.processWithMasking(
            header,
            analyzed,
            psychoacoustics,
        );
    }

    pub fn processWithMasking(
        self: EncoderQuantizer,
        header: Header,
        analyzed: AnalyzedEncoderFrame,
        psychoacoustics: [2][2]EncoderPsychoacousticChannel,
    ) !QuantizedEncoderFrame {
        return self.processWithReservoirMasking(
            header,
            analyzed,
            psychoacoustics,
            0,
        );
    }

    pub fn processWithReservoirMasking(
        self: EncoderQuantizer,
        header: Header,
        analyzed: AnalyzedEncoderFrame,
        psychoacoustics: [2][2]EncoderPsychoacousticChannel,
        available_history_bytes: u16,
    ) !QuantizedEncoderFrame {
        try validateEncoderPsychoacousticConfig(
            self.psychoacoustics.config,
        );
        const channel_count: u2 = @intCast(header.channels());
        const granule_count: u2 =
            if (header.version == .mpeg1) 2 else 1;
        try validateAnalyzedEncoderFrame(header, analyzed);
        for (0..2) |granule| {
            for (0..2) |channel| {
                if (granule >= granule_count or
                    channel >= channel_count)
                {
                    if (!std.meta.eql(
                        psychoacoustics[granule][channel],
                        EncoderPsychoacousticChannel{},
                    ))
                        return error.InvalidMp3PsychoacousticBands;
                    continue;
                }
                const layout = try encoderBandLayout(
                    header,
                    analyzed.granules[granule][channel].description,
                );
                try validatePsychoacousticHistory(
                    psychoacoustics[granule][channel],
                    layout.band_count,
                );
            }
        }
        const budget = try reservoirQuantizerBudget(
            header,
            available_history_bytes,
        );
        const available_bits = budget.logical_bits;
        const active_channels =
            @as(usize, channel_count) * granule_count;
        var weights: [2][2]f64 = @splat(@splat(0));
        var total_weight: f64 = 0;
        for (0..granule_count) |granule| {
            for (0..channel_count) |channel| {
                var energy: f64 = 0;
                for (psychoacoustics[granule][channel]
                    .energy[0..psychoacoustics[granule][channel].band_count]) |band_energy|
                    energy += band_energy;
                weights[granule][channel] = @sqrt(energy);
                total_weight += weights[granule][channel];
            }
        }
        if (!std.math.isFinite(total_weight))
            return error.InvalidMp3PsychoacousticEnergy;
        const minimum_budget =
            available_bits / (active_channels * 4);
        const flexible_bits =
            available_bits - minimum_budget * active_channels;

        var result = QuantizedEncoderFrame{};
        for (0..granule_count) |granule| {
            for (0..channel_count) |channel| {
                const weighted_budget: usize =
                    if (total_weight == 0)
                        flexible_bits / active_channels
                    else
                        @intFromFloat(@floor(
                            @as(f64, @floatFromInt(flexible_bits)) *
                                weights[granule][channel] /
                                total_weight,
                        ));
                result.granules[granule][channel] =
                    try quantizeEncoderChannel(
                        header,
                        analyzed.granules[granule][channel],
                        psychoacoustics[granule][channel],
                        @min(
                            minimum_budget + weighted_budget,
                            std.math.maxInt(u12),
                        ),
                        @intCast(granule),
                        @intCast(channel),
                    );
            }
        }
        return result;
    }
};

pub const PcmEncoder = struct {
    frames: FrameEncoder,
    analysis: EncoderAnalysis,
    classifier: EncoderBlockClassifier = .{},
    masking: EncoderPsychoacousticTimeline = .{},

    pub fn init(config: EncoderConfig) !PcmEncoder {
        return initWithPsychoacoustics(config, .{});
    }

    pub fn initWithPsychoacoustics(
        config: EncoderConfig,
        psychoacoustics: EncoderPsychoacousticConfig,
    ) !PcmEncoder {
        const header = try config.header(false);
        try validatePcmEncoderStereo(header);
        try validateEncoderPsychoacousticConfig(psychoacoustics);
        return .{
            .frames = try FrameEncoder.init(config),
            .analysis = try EncoderAnalysis.init(config),
            .masking = .{
                .model = .{ .config = psychoacoustics },
            },
        };
    }

    pub fn reset(self: *PcmEncoder) void {
        self.frames.reset();
        self.analysis.reset();
        self.classifier.reset();
        self.masking.reset();
    }

    pub fn valid(self: *const PcmEncoder) bool {
        if (!self.frames.valid() or
            !self.analysis.valid() or
            !self.classifier.valid() or
            !self.masking.valid() or
            !std.meta.eql(self.frames.config, self.analysis.config) or
            self.frames.frames_encoded != self.analysis.frames_analyzed)
            return false;
        const header = self.frames.config.header(false) catch return false;
        validatePcmEncoderStereo(header) catch return false;
        for (0..2) |channel| {
            const expected = self.frames.frames_encoded != 0 and
                channel < header.channels();
            if (self.masking.history_present[channel] != expected)
                return false;
        }
        return true;
    }

    pub fn encode(
        self: *PcmEncoder,
        pcm: PcmFrame,
        destination: []u8,
    ) ![]u8 {
        if (!self.valid()) return error.InvalidMp3PcmEncoderState;
        var next = self.*;
        const header = try next.frames.config.header(false);
        try validatePcmEncoderStereo(header);
        const descriptions = try next.classifier.classify(
            header,
            pcm,
        );
        const analyzed = try prepareEncoderStereo(
            header,
            try next.analysis.analyze(
                descriptions,
                pcm,
            ),
        );
        const psychoacoustics =
            try next.masking.analyzeFrame(header, analyzed);
        const quantized = try (EncoderQuantizer{
            .psychoacoustics = next.masking.model,
        }).processWithMasking(
            header,
            analyzed,
            psychoacoustics,
        );
        const encoded = try next.frames.encodeQuantizedFrame(
            &quantized,
            destination,
        );
        self.* = next;
        return encoded;
    }

    pub fn encodeReservoirParts(
        self: *PcmEncoder,
        pcm: PcmFrame,
        available_history_bytes: u16,
        frame_destination: []u8,
        main_data_destination: []u8,
    ) !QuantizedFrameParts {
        if (!self.valid()) return error.InvalidMp3PcmEncoderState;
        var next = self.*;
        const header = try next.frames.config.header(false);
        try validatePcmEncoderStereo(header);
        const descriptions = try next.classifier.classify(
            header,
            pcm,
        );
        const analyzed = try prepareEncoderStereo(
            header,
            try next.analysis.analyze(
                descriptions,
                pcm,
            ),
        );
        const psychoacoustics =
            try next.masking.analyzeFrame(header, analyzed);
        const quantized = try (EncoderQuantizer{
            .psychoacoustics = next.masking.model,
        }).processWithReservoirMasking(
            header,
            analyzed,
            psychoacoustics,
            available_history_bytes,
        );
        const encoded = try next.frames.encodeQuantizedFrameParts(
            &quantized,
            frame_destination,
            main_data_destination,
        );
        self.* = next;
        return encoded;
    }
};

pub const PcmReservoirBatchResult = struct {
    stream: []u8,
    frame_count: u64,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
};

pub fn requiredPcmReservoirBatchFrameBytes(
    config: EncoderConfig,
    frame_count: usize,
) !usize {
    var frames = try FrameEncoder.init(config);
    var total: usize = 0;
    for (0..frame_count) |_| {
        const advanced = try frames.advance();
        total = std.math.add(
            usize,
            total,
            advanced.header.frameBytes(),
        ) catch return error.Mp3ReservoirSizeOverflow;
        frames.padding_accumulator = advanced.padding_accumulator;
        frames.frames_encoded = std.math.add(
            u64,
            frames.frames_encoded,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
    }
    return total;
}

pub fn encodePcmReservoirBatch(
    config: EncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
) !PcmReservoirBatchResult {
    const header = try config.header(false);
    var credit = try ReservoirCreditTracker.init(
        header,
        maximum_history_bytes,
    );
    const frame_bytes = try requiredPcmReservoirBatchFrameBytes(
        config,
        pcm_frames.len,
    );
    if (destination.len < frame_bytes)
        return error.InsufficientMp3EncoderStorage;
    if (frame_scratch.len < frame_bytes or
        pack_scratch.len < frame_bytes)
        return error.Mp3ReservoirEncodedScratchTooSmall;
    const ranges = [_]struct { start: usize, length: usize }{
        .{ .start = @intFromPtr(destination.ptr), .length = frame_bytes },
        .{ .start = @intFromPtr(frame_scratch.ptr), .length = frame_bytes },
        .{ .start = @intFromPtr(pack_scratch.ptr), .length = frame_bytes },
        .{
            .start = @intFromPtr(main_data_scratch.ptr),
            .length = main_data_scratch.len,
        },
    };
    for (0..ranges.len) |left| {
        for (left + 1..ranges.len) |right| {
            if (byteRangesOverlap(
                ranges[left].start,
                ranges[left].length,
                ranges[right].start,
                ranges[right].length,
            )) return error.OverlappingMp3ReservoirStorage;
        }
    }
    const pcm_bytes = std.mem.sliceAsBytes(pcm_frames);
    if (byteRangesOverlap(
        @intFromPtr(pcm_bytes.ptr),
        pcm_bytes.len,
        @intFromPtr(frame_scratch.ptr),
        frame_bytes,
    ) or byteRangesOverlap(
        @intFromPtr(pcm_bytes.ptr),
        pcm_bytes.len,
        @intFromPtr(main_data_scratch.ptr),
        main_data_scratch.len,
    )) return error.OverlappingMp3ReservoirStorage;
    if (pcm_frames.len == 0) return .{
        .stream = destination[0..0],
        .frame_count = 0,
        .logical_main_data_bits = 0,
        .borrowed_bytes = 0,
        .maximum_backpointer = 0,
        .retained_history_bytes = 0,
    };

    var encoder = try PcmEncoder.init(config);
    var frame_cursor: usize = 0;
    var main_data_cursor: usize = 0;
    var logical_main_data_bits: u64 = 0;
    for (pcm_frames) |pcm| {
        const parts = try encoder.encodeReservoirParts(
            pcm,
            credit.available_history_bytes,
            frame_scratch[frame_cursor..],
            main_data_scratch[main_data_cursor..],
        );
        const encoded_frame = try Frame.parse(parts.frame, 0);
        _ = try credit.commit(
            encoded_frame.header,
            parts.main_data_bits,
        );
        frame_cursor += parts.frame.len;
        main_data_cursor += parts.main_data.len;
        logical_main_data_bits = std.math.add(
            u64,
            logical_main_data_bits,
            parts.main_data_bits,
        ) catch return error.Mp3MainDataBitCountOverflow;
    }
    if (frame_cursor != frame_bytes)
        return error.InvalidMp3ReservoirEncoderState;
    const packing_result = try packMainDataReservoir(
        frame_scratch[0..frame_cursor],
        main_data_scratch[0..main_data_cursor],
        maximum_history_bytes,
        pack_scratch[0..frame_cursor],
    );
    @memcpy(destination[0..frame_cursor], frame_scratch[0..frame_cursor]);
    return .{
        .stream = destination[0..frame_cursor],
        .frame_count = packing_result.frame_count,
        .logical_main_data_bits = logical_main_data_bits,
        .borrowed_bytes = packing_result.borrowed_bytes,
        .maximum_backpointer = packing_result.maximum_backpointer,
        .retained_history_bytes = credit.available_history_bytes,
    };
}

pub fn requiredPcmAdaptiveReservoirStorage(
    config: EncoderConfig,
    maximum_history_bytes: u16,
) !usize {
    const header = try config.header(false);
    _ = try ReservoirCreditTracker.init(
        header,
        maximum_history_bytes,
    );
    const minimum_capacity = header.frameBytes() -
        frameMainDataOffset(header);
    if (minimum_capacity == 0)
        return error.InvalidMp3EncoderFrameSize;
    const retained_frames = std.math.add(
        usize,
        try std.math.divCeil(
            usize,
            maximum_history_bytes,
            minimum_capacity,
        ),
        1,
    ) catch return error.Mp3ReservoirSizeOverflow;
    const maximum_frame_bytes = std.math.add(
        usize,
        header.frameBytes(),
        1,
    ) catch return error.Mp3ReservoirSizeOverflow;
    return std.math.mul(
        usize,
        retained_frames,
        maximum_frame_bytes,
    ) catch error.Mp3ReservoirSizeOverflow;
}

pub const PcmAdaptiveReservoirAppend = struct {
    frames: []u8,
    frame_count: u16,
    borrowed_bytes: u16,
    retained_history_bytes: u16,
};

pub const PcmAdaptiveReservoirFinish = struct {
    frames: []u8,
    frame_count: u64,
    byte_count: u64,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
};

pub const PcmAdaptiveReservoirStreamEncoder = struct {
    encoder: PcmEncoder,
    credit: ReservoirCreditTracker,
    pending_storage: []u8,
    pending_length: usize = 0,
    physical_main_data_bytes: u64 = 0,
    published_main_data_bytes: u64 = 0,
    packed_main_data_end: u64 = 0,
    frames_received: u64 = 0,
    frames_emitted: u64 = 0,
    independent_frames: u8 = 0,
    byte_count: u64 = 0,
    logical_main_data_bits: u64 = 0,
    borrowed_bytes: u64 = 0,
    maximum_backpointer: u16 = 0,
    finalized: bool = false,

    /// Keep `pending_storage` stable until the encoder is no longer used.
    pub fn init(
        config: EncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
    ) !PcmAdaptiveReservoirStreamEncoder {
        const required = try requiredPcmAdaptiveReservoirStorage(
            config,
            maximum_history_bytes,
        );
        if (pending_storage.len < required)
            return error.Mp3AdaptiveReservoirStorageTooSmall;
        const header = try config.header(false);
        @memset(pending_storage, 0);
        return .{
            .encoder = try PcmEncoder.init(config),
            .credit = try ReservoirCreditTracker.init(
                header,
                maximum_history_bytes,
            ),
            .pending_storage = pending_storage,
        };
    }

    pub fn reset(self: *PcmAdaptiveReservoirStreamEncoder) void {
        self.encoder.reset();
        self.credit.reset();
        @memset(self.pending_storage, 0);
        self.pending_length = 0;
        self.physical_main_data_bytes = 0;
        self.published_main_data_bytes = 0;
        self.packed_main_data_end = 0;
        self.frames_received = 0;
        self.frames_emitted = 0;
        self.independent_frames = 0;
        self.byte_count = 0;
        self.logical_main_data_bits = 0;
        self.borrowed_bytes = 0;
        self.maximum_backpointer = 0;
        self.finalized = false;
    }

    pub fn valid(self: *const PcmAdaptiveReservoirStreamEncoder) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn append(
        self: *PcmAdaptiveReservoirStreamEncoder,
        pcm: PcmFrame,
        destination: []u8,
        pending_scratch: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
    ) !PcmAdaptiveReservoirAppend {
        try self.validateState();
        if (self.finalized)
            return error.Mp3AdaptiveReservoirEncoderFinalized;
        try validateAdaptiveReservoirStorage(
            self.pending_storage,
            destination,
            pending_scratch,
            frame_scratch,
            main_data_scratch,
        );

        var next = self.*;
        const parts = try next.encoder.encodeReservoirParts(
            pcm,
            next.credit.available_history_bytes,
            frame_scratch,
            main_data_scratch,
        );
        const frame = try Frame.parse(parts.frame, 0);
        const decision = try next.credit.commit(
            frame.header,
            parts.main_data_bits,
        );
        const staged_length = std.math.add(
            usize,
            self.pending_length,
            parts.frame.len,
        ) catch return error.Mp3ReservoirSizeOverflow;
        if (staged_length > self.pending_storage.len or
            staged_length > pending_scratch.len)
            return error.Mp3AdaptiveReservoirStorageTooSmall;
        @memcpy(
            pending_scratch[0..self.pending_length],
            self.pending_storage[0..self.pending_length],
        );
        @memcpy(
            pending_scratch[self.pending_length..staged_length],
            parts.frame,
        );

        const logical_start = @max(
            next.packed_main_data_end,
            next.physical_main_data_bytes -|
                next.credit.maximum_history_bytes,
        );
        if (logical_start > next.physical_main_data_bytes or
            logical_start < next.published_main_data_bytes)
            return error.InvalidMp3AdaptiveReservoirState;
        const backpointer_bytes =
            next.physical_main_data_bytes - logical_start;
        if (backpointer_bytes > std.math.maxInt(u16))
            return error.InvalidMp3AdaptiveReservoirState;
        const relative_logical_start = logical_start -
            next.published_main_data_bytes;
        if (relative_logical_start > std.math.maxInt(usize))
            return error.Mp3ReservoirSizeOverflow;
        var writer = ReservoirMainDataWriter{
            .encoded = pending_scratch[0..staged_length],
        };
        try writer.seekTo(@intCast(relative_logical_start));
        try writer.write(parts.main_data);
        setFrameMainDataBegin(
            pending_scratch[self.pending_length..staged_length],
            frame.header,
            @intCast(backpointer_bytes),
        );

        next.packed_main_data_end = std.math.add(
            u64,
            logical_start,
            decision.logical_bytes,
        ) catch return error.Mp3ReservoirSizeOverflow;
        next.physical_main_data_bytes = std.math.add(
            u64,
            next.physical_main_data_bytes,
            decision.physical_bytes,
        ) catch return error.Mp3ReservoirSizeOverflow;
        next.frames_received = std.math.add(
            u64,
            next.frames_received,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        next.byte_count = std.math.add(
            u64,
            next.byte_count,
            parts.frame.len,
        ) catch return error.Mp3ByteCountOverflow;
        next.logical_main_data_bits = std.math.add(
            u64,
            next.logical_main_data_bits,
            parts.main_data_bits,
        ) catch return error.Mp3MainDataBitCountOverflow;
        next.borrowed_bytes = std.math.add(
            u64,
            next.borrowed_bytes,
            backpointer_bytes,
        ) catch return error.Mp3ReservoirByteCountOverflow;
        next.maximum_backpointer = @max(
            next.maximum_backpointer,
            @as(u16, @intCast(backpointer_bytes)),
        );

        const safe_main_data_end =
            next.physical_main_data_bytes -|
            next.credit.maximum_history_bytes;
        var frame_offset: usize = 0;
        var emitted_bytes: usize = 0;
        var emitted_frames: u16 = 0;
        var emitted_main_data_bytes: u64 = 0;
        var main_data_cursor = next.published_main_data_bytes;
        while (frame_offset < staged_length) {
            const pending_frame = try Frame.parse(
                pending_scratch[0..staged_length],
                frame_offset,
            );
            const capacity = pending_frame.bytes.len -
                frameMainDataOffset(pending_frame.header);
            const frame_main_data_end = std.math.add(
                u64,
                main_data_cursor,
                capacity,
            ) catch return error.Mp3ReservoirSizeOverflow;
            if (frame_main_data_end > safe_main_data_end) break;
            emitted_bytes += pending_frame.bytes.len;
            emitted_frames = std.math.add(
                u16,
                emitted_frames,
                1,
            ) catch return error.Mp3EncoderFrameCountOverflow;
            emitted_main_data_bytes = std.math.add(
                u64,
                emitted_main_data_bytes,
                capacity,
            ) catch return error.Mp3ReservoirSizeOverflow;
            main_data_cursor = frame_main_data_end;
            frame_offset += pending_frame.bytes.len;
        }
        if (destination.len < emitted_bytes)
            return error.InsufficientMp3EncoderStorage;
        const remaining = staged_length - emitted_bytes;
        const next_published_main_data_bytes = std.math.add(
            u64,
            next.published_main_data_bytes,
            emitted_main_data_bytes,
        ) catch return error.Mp3ReservoirSizeOverflow;
        const next_frames_emitted = std.math.add(
            u64,
            next.frames_emitted,
            emitted_frames,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const old_pending_length = self.pending_length;
        @memcpy(
            destination[0..emitted_bytes],
            pending_scratch[0..emitted_bytes],
        );
        std.mem.copyForwards(
            u8,
            self.pending_storage[0..remaining],
            pending_scratch[emitted_bytes..staged_length],
        );
        if (remaining < old_pending_length)
            @memset(
                self.pending_storage[remaining..old_pending_length],
                0,
            );
        next.pending_length = remaining;
        next.published_main_data_bytes =
            next_published_main_data_bytes;
        next.frames_emitted = next_frames_emitted;
        self.* = next;
        return .{
            .frames = destination[0..emitted_bytes],
            .frame_count = emitted_frames,
            .borrowed_bytes = @intCast(backpointer_bytes),
            .retained_history_bytes = decision.next_history_bytes,
        };
    }

    pub fn finish(
        self: *PcmAdaptiveReservoirStreamEncoder,
        destination: []u8,
    ) !PcmAdaptiveReservoirFinish {
        try self.validateState();
        var emitted_bytes: usize = 0;
        if (!self.finalized) {
            if (byteRangesOverlap(
                @intFromPtr(self.pending_storage.ptr),
                self.pending_storage.len,
                @intFromPtr(destination.ptr),
                destination.len,
            )) return error.OverlappingMp3ReservoirStorage;
            if (destination.len < self.pending_length)
                return error.InsufficientMp3EncoderStorage;
            @memcpy(
                destination[0..self.pending_length],
                self.pending_storage[0..self.pending_length],
            );
            emitted_bytes = self.pending_length;
            @memset(
                self.pending_storage[0..self.pending_length],
                0,
            );
            self.pending_length = 0;
            self.published_main_data_bytes =
                self.physical_main_data_bytes;
            self.frames_emitted = self.frames_received;
            self.finalized = true;
        }
        return .{
            .frames = destination[0..emitted_bytes],
            .frame_count = self.frames_received,
            .byte_count = self.byte_count,
            .logical_main_data_bits = self.logical_main_data_bits,
            .borrowed_bytes = self.borrowed_bytes,
            .maximum_backpointer = self.maximum_backpointer,
            .retained_history_bytes = self.credit.available_history_bytes,
        };
    }

    fn validateState(
        self: PcmAdaptiveReservoirStreamEncoder,
    ) !void {
        if (!self.encoder.valid() or !self.credit.valid() or
            self.pending_length > self.pending_storage.len or
            self.independent_frames > 1 or
            self.frames_received < self.independent_frames or
            self.frames_emitted < self.independent_frames or
            self.credit.frames_committed !=
                self.frames_received - self.independent_frames or
            self.encoder.frames.frames_encoded != self.frames_received or
            self.frames_emitted > self.frames_received or
            self.physical_main_data_bytes <
                self.published_main_data_bytes or
            self.packed_main_data_end >
                self.physical_main_data_bytes or
            self.maximum_backpointer >
                self.credit.maximum_history_bytes or
            !reservoirBorrowedBytesValid(
                self.credit.version,
                self.credit.frames_committed,
                self.borrowed_bytes,
            ) or
            (self.finalized and
                (self.pending_length != 0 or
                    self.frames_emitted != self.frames_received or
                    self.published_main_data_bytes !=
                        self.physical_main_data_bytes)))
            return error.InvalidMp3AdaptiveReservoirState;
        const header = self.encoder.frames.config.header(false) catch
            return error.InvalidMp3AdaptiveReservoirState;
        const reservoir_frame_count =
            self.frames_received - self.independent_frames;
        const expected_byte_count = @as(u128, self.physical_main_data_bytes) +
            @as(u128, reservoir_frame_count) *
                frameMainDataOffset(header) +
            @as(u128, self.independent_frames) * header.frameBytes();
        if (expected_byte_count != self.byte_count)
            return error.InvalidMp3AdaptiveReservoirState;
        if (self.credit.version != header.version or
            self.credit.sample_rate != header.sample_rate or
            self.credit.channel_count != header.channels())
            return error.InvalidMp3AdaptiveReservoirState;
        const retained_credit = @min(
            self.physical_main_data_bytes -
                self.packed_main_data_end,
            self.credit.maximum_history_bytes,
        );
        if (retained_credit != self.credit.available_history_bytes)
            return error.InvalidMp3AdaptiveReservoirState;

        var pending_offset: usize = 0;
        var pending_frames: u64 = 0;
        var pending_main_data_bytes: u64 = 0;
        while (pending_offset < self.pending_length) {
            const frame = Frame.parse(
                self.pending_storage[0..self.pending_length],
                pending_offset,
            ) catch return error.InvalidMp3AdaptiveReservoirState;
            const expected = self.encoder.frames.config
                .header(frame.header.padding) catch
                return error.InvalidMp3AdaptiveReservoirState;
            if (!std.meta.eql(expected, frame.header))
                return error.InvalidMp3AdaptiveReservoirState;
            const side = frame.sideInformation() catch
                return error.InvalidMp3AdaptiveReservoirState;
            if (side.main_data_begin >
                self.credit.maximum_history_bytes)
                return error.InvalidMp3AdaptiveReservoirState;
            pending_frames = std.math.add(
                u64,
                pending_frames,
                1,
            ) catch return error.InvalidMp3AdaptiveReservoirState;
            pending_main_data_bytes = std.math.add(
                u64,
                pending_main_data_bytes,
                frame.bytes.len - frameMainDataOffset(frame.header),
            ) catch return error.InvalidMp3AdaptiveReservoirState;
            pending_offset += frame.bytes.len;
        }
        if (pending_offset != self.pending_length or
            pending_frames != self.frames_received - self.frames_emitted or
            pending_main_data_bytes !=
                self.physical_main_data_bytes -
                    self.published_main_data_bytes)
            return error.InvalidMp3AdaptiveReservoirState;
        if (!self.finalized and
            self.published_main_data_bytes >
                self.physical_main_data_bytes -|
                    self.credit.maximum_history_bytes)
            return error.InvalidMp3AdaptiveReservoirState;
    }
};

pub const PcmAdaptiveReservoirGaplessFinish = struct {
    frames: []u8,
    summary: EncoderStreamSummary,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
};

pub const PcmAdaptiveReservoirGaplessStreamEncoder = struct {
    stream: PcmAdaptiveReservoirStreamEncoder,
    input_samples: u64 = 0,
    metadata_encoder: [9]u8 = default_xing_encoder_identifier,
    metadata_started: bool = false,

    /// Keep `pending_storage` stable until the encoder is no longer used.
    pub fn init(
        config: EncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
    ) !PcmAdaptiveReservoirGaplessStreamEncoder {
        return .{
            .stream = try PcmAdaptiveReservoirStreamEncoder.init(
                config,
                maximum_history_bytes,
                pending_storage,
            ),
        };
    }

    pub fn reset(self: *PcmAdaptiveReservoirGaplessStreamEncoder) void {
        self.stream.reset();
        self.input_samples = 0;
        self.metadata_encoder = default_xing_encoder_identifier;
        self.metadata_started = false;
    }

    pub fn valid(
        self: *const PcmAdaptiveReservoirGaplessStreamEncoder,
    ) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn startMetadata(
        self: *PcmAdaptiveReservoirGaplessStreamEncoder,
        destination: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
    ) ![]u8 {
        return self.startMetadataWithEncoder(
            default_xing_encoder_identifier,
            destination,
            frame_scratch,
            main_data_scratch,
        );
    }

    pub fn startMetadataWithEncoder(
        self: *PcmAdaptiveReservoirGaplessStreamEncoder,
        encoder: [9]u8,
        destination: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
    ) ![]u8 {
        try self.validate();
        try validateXingEncoderIdentifier(encoder);
        if (self.metadata_started)
            return error.Mp3EncoderMetadataAlreadyStarted;
        try validateAdaptiveGaplessStartStorage(
            self.stream.pending_storage,
            destination,
            frame_scratch,
            main_data_scratch,
        );
        const header = try self.stream.encoder.frames.config.header(false);
        var metadata_storage: [maximum_encoded_frame_bytes]u8 = undefined;
        const placeholder = try encodeInfoFrameFields(
            header,
            0,
            0,
            0,
            0,
            encoder,
            &metadata_storage,
        );
        if (destination.len < placeholder.len)
            return error.InsufficientMp3EncoderStorage;

        var next = self.*;
        const discarded = try next.stream.encoder.encodeReservoirParts(
            .{
                .channel_count = @intCast(header.channels()),
                .sample_count = header.samplesPerFrame(),
            },
            0,
            frame_scratch,
            main_data_scratch,
        );
        if (discarded.frame.len != placeholder.len)
            return error.InvalidMp3AdaptiveReservoirState;
        next.stream.frames_received = 1;
        next.stream.frames_emitted = 1;
        next.stream.independent_frames = 1;
        next.stream.byte_count = placeholder.len;
        next.metadata_encoder = encoder;
        next.metadata_started = true;
        try next.validate();
        @memcpy(destination[0..placeholder.len], placeholder);
        self.* = next;
        return destination[0..placeholder.len];
    }

    pub fn append(
        self: *PcmAdaptiveReservoirGaplessStreamEncoder,
        pcm: PcmFrame,
        destination: []u8,
        pending_scratch: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
    ) !PcmAdaptiveReservoirAppend {
        try self.validate();
        if (!self.metadata_started)
            return error.Mp3EncoderMetadataNotStarted;
        const next_input_samples = std.math.add(
            u64,
            self.input_samples,
            pcm.sample_count,
        ) catch return error.Mp3SampleCountOverflow;
        const appended = try self.stream.append(
            pcm,
            destination,
            pending_scratch,
            frame_scratch,
            main_data_scratch,
        );
        self.input_samples = next_input_samples;
        return appended;
    }

    /// All six work and output slices must be disjoint. Failure preserves the
    /// encoder, pending bytes, and destination.
    pub fn finish(
        self: *PcmAdaptiveReservoirGaplessStreamEncoder,
        destination: []u8,
        pending_scratch: []u8,
        rollback_storage: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
        output_scratch: []u8,
    ) !PcmAdaptiveReservoirGaplessFinish {
        try self.validate();
        if (!self.metadata_started)
            return error.Mp3EncoderMetadataNotStarted;
        if (self.stream.finalized)
            return self.finishResult(destination[0..0]);
        try validateAdaptiveGaplessFinishStorage(
            self.stream.pending_storage,
            destination,
            pending_scratch,
            rollback_storage,
            frame_scratch,
            main_data_scratch,
            output_scratch,
        );
        if (rollback_storage.len < self.stream.pending_storage.len)
            return error.Mp3AdaptiveReservoirRollbackStorageTooSmall;

        const header = try self.stream.encoder.frames.config.header(false);
        const flush_frames = try adaptiveGaplessFlushFrames(header);
        const final_frame_count = std.math.add(
            u64,
            self.stream.frames_received,
            flush_frames,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const byte_state = try encoderByteState(
            self.stream.encoder.frames.config,
            final_frame_count,
        );
        if (byte_state.byte_count < self.stream.byte_count)
            return error.InvalidMp3AdaptiveReservoirState;
        const flush_bytes = byte_state.byte_count - self.stream.byte_count;
        const output_bytes_u64 = std.math.add(
            u64,
            self.stream.pending_length,
            flush_bytes,
        ) catch return error.Mp3ByteCountOverflow;
        const output_bytes = std.math.cast(usize, output_bytes_u64) orelse
            return error.Mp3ByteCountOverflow;
        if (destination.len < output_bytes or
            output_scratch.len < output_bytes)
            return error.InsufficientMp3EncoderStorage;

        @memcpy(
            rollback_storage[0..self.stream.pending_storage.len],
            self.stream.pending_storage,
        );
        errdefer @memcpy(
            self.stream.pending_storage,
            rollback_storage[0..self.stream.pending_storage.len],
        );

        var next = self.*;
        var cursor: usize = 0;
        const silence = PcmFrame{
            .channel_count = @intCast(header.channels()),
            .sample_count = header.samplesPerFrame(),
        };
        for (0..flush_frames) |_| {
            const appended = try next.stream.append(
                silence,
                output_scratch[cursor..output_bytes],
                pending_scratch,
                frame_scratch,
                main_data_scratch,
            );
            cursor += appended.frames.len;
        }
        const finished = try next.stream.finish(
            output_scratch[cursor..output_bytes],
        );
        cursor += finished.frames.len;
        if (cursor != output_bytes)
            return error.InvalidMp3AdaptiveReservoirState;
        const result = try next.finishResult(destination[0..output_bytes]);
        @memcpy(destination[0..output_bytes], output_scratch[0..output_bytes]);
        self.* = next;
        return result;
    }

    pub fn summary(
        self: PcmAdaptiveReservoirGaplessStreamEncoder,
    ) !EncoderStreamSummary {
        try self.validate();
        if (!self.stream.finalized)
            return error.Mp3EncoderStreamIncomplete;
        return self.summaryUnchecked();
    }

    fn summaryUnchecked(
        self: PcmAdaptiveReservoirGaplessStreamEncoder,
    ) !EncoderStreamSummary {
        const reservoir_frames = std.math.cast(
            usize,
            self.stream.credit.frames_committed,
        ) orelse return error.Mp3EncoderFrameCountOverflow;
        const byte_count = std.math.cast(
            usize,
            self.stream.byte_count,
        ) orelse return error.Mp3ByteCountOverflow;
        return adaptiveGaplessSummary(
            reservoir_frames,
            self.input_samples,
            try self.stream.encoder.frames.config.header(false),
            byte_count,
        );
    }

    pub fn metadataFrame(
        self: PcmAdaptiveReservoirGaplessStreamEncoder,
        destination: []u8,
    ) ![]u8 {
        return encodeInfoFrameWithEncoder(
            self.stream.encoder.frames.config,
            try self.summary(),
            self.metadata_encoder,
            destination,
        );
    }

    fn finishResult(
        self: PcmAdaptiveReservoirGaplessStreamEncoder,
        frames: []u8,
    ) !PcmAdaptiveReservoirGaplessFinish {
        return .{
            .frames = frames,
            .summary = try self.summary(),
            .logical_main_data_bits = self.stream.logical_main_data_bits,
            .borrowed_bytes = self.stream.borrowed_bytes,
            .maximum_backpointer = self.stream.maximum_backpointer,
            .retained_history_bytes = self.stream.credit.available_history_bytes,
        };
    }

    fn validate(
        self: PcmAdaptiveReservoirGaplessStreamEncoder,
    ) !void {
        self.stream.validateState() catch
            return error.InvalidMp3AdaptiveReservoirGaplessState;
        if (!isValidXingEncoderIdentifier(self.metadata_encoder) or
            self.metadata_started != (self.stream.independent_frames == 1))
            return error.InvalidMp3AdaptiveReservoirGaplessState;
        if (!self.metadata_started) {
            if (self.input_samples != 0 or
                self.stream.frames_received != 0)
                return error.InvalidMp3AdaptiveReservoirGaplessState;
            return;
        }
        const header = self.stream.encoder.frames.config.header(false) catch
            return error.InvalidMp3AdaptiveReservoirGaplessState;
        const flush_frames: u64 = if (self.stream.finalized)
            adaptiveGaplessFlushFrames(header) catch
                return error.InvalidMp3AdaptiveReservoirGaplessState
        else
            0;
        if (self.stream.credit.frames_committed < flush_frames)
            return error.InvalidMp3AdaptiveReservoirGaplessState;
        const input_frames = self.stream.credit.frames_committed - flush_frames;
        const expected_input = std.math.mul(
            u64,
            input_frames,
            header.samplesPerFrame(),
        ) catch return error.InvalidMp3AdaptiveReservoirGaplessState;
        if (self.input_samples != expected_input)
            return error.InvalidMp3AdaptiveReservoirGaplessState;
        if (self.stream.finalized)
            _ = self.summaryUnchecked() catch
                return error.InvalidMp3AdaptiveReservoirGaplessState;
    }
};

pub const Mp3StorageRange = struct { start: usize, length: usize };

pub fn validateAdaptiveGaplessStartStorage(
    pending: []const u8,
    destination: []const u8,
    frame_scratch: []const u8,
    main_data_scratch: []const u8,
) !void {
    const ranges = [_]Mp3StorageRange{
        .{ .start = @intFromPtr(pending.ptr), .length = pending.len },
        .{ .start = @intFromPtr(destination.ptr), .length = destination.len },
        .{ .start = @intFromPtr(frame_scratch.ptr), .length = frame_scratch.len },
        .{ .start = @intFromPtr(main_data_scratch.ptr), .length = main_data_scratch.len },
    };
    try validateDisjointMp3Storage(&ranges);
}

pub fn validateAdaptiveGaplessFinishStorage(
    pending: []const u8,
    destination: []const u8,
    pending_scratch: []const u8,
    rollback_storage: []const u8,
    frame_scratch: []const u8,
    main_data_scratch: []const u8,
    output_scratch: []const u8,
) !void {
    const ranges = [_]Mp3StorageRange{
        .{ .start = @intFromPtr(pending.ptr), .length = pending.len },
        .{ .start = @intFromPtr(destination.ptr), .length = destination.len },
        .{ .start = @intFromPtr(pending_scratch.ptr), .length = pending_scratch.len },
        .{ .start = @intFromPtr(rollback_storage.ptr), .length = rollback_storage.len },
        .{ .start = @intFromPtr(frame_scratch.ptr), .length = frame_scratch.len },
        .{ .start = @intFromPtr(main_data_scratch.ptr), .length = main_data_scratch.len },
        .{ .start = @intFromPtr(output_scratch.ptr), .length = output_scratch.len },
    };
    try validateDisjointMp3Storage(&ranges);
}

pub fn validateDisjointMp3Storage(
    ranges: []const Mp3StorageRange,
) !void {
    for (0..ranges.len) |left| {
        for (left + 1..ranges.len) |right| {
            if (byteRangesOverlap(
                ranges[left].start,
                ranges[left].length,
                ranges[right].start,
                ranges[right].length,
            )) return error.OverlappingMp3ReservoirStorage;
        }
    }
}

pub fn validateAdaptiveReservoirStorage(
    pending: []const u8,
    destination: []const u8,
    pending_scratch: []const u8,
    frame_scratch: []const u8,
    main_data_scratch: []const u8,
) !void {
    const ranges = [_]struct { start: usize, length: usize }{
        .{ .start = @intFromPtr(pending.ptr), .length = pending.len },
        .{ .start = @intFromPtr(destination.ptr), .length = destination.len },
        .{
            .start = @intFromPtr(pending_scratch.ptr),
            .length = pending_scratch.len,
        },
        .{
            .start = @intFromPtr(frame_scratch.ptr),
            .length = frame_scratch.len,
        },
        .{
            .start = @intFromPtr(main_data_scratch.ptr),
            .length = main_data_scratch.len,
        },
    };
    for (0..ranges.len) |left| {
        for (left + 1..ranges.len) |right| {
            if (byteRangesOverlap(
                ranges[left].start,
                ranges[left].length,
                ranges[right].start,
                ranges[right].length,
            )) return error.OverlappingMp3ReservoirStorage;
        }
    }
}

pub const PcmAdaptiveReservoirFileSummary = struct {
    frame_count: u64,
    byte_count: u64,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
    file_end: u64,
};

pub const PcmAdaptiveReservoirFileEncoder = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    stream: PcmAdaptiveReservoirStreamEncoder,
    pending_scratch: []u8,
    rollback_storage: []u8,
    frame_scratch: []u8,
    main_data_scratch: []u8,
    output_storage: []u8,
    audio_offset: u64 = 0,
    committed_bytes: u64 = 0,
    failed: bool = false,
    finalized: bool = false,

    /// All storage slices must remain stable for the encoder lifetime.
    pub fn init(
        io: std.Io,
        file: std.Io.File,
        config: EncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
        pending_scratch: []u8,
        rollback_storage: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
        output_storage: []u8,
    ) !PcmAdaptiveReservoirFileEncoder {
        return initAtWithOperations(
            io,
            file,
            config,
            maximum_history_bytes,
            pending_storage,
            pending_scratch,
            rollback_storage,
            frame_scratch,
            main_data_scratch,
            output_storage,
            0,
            .{},
        );
    }

    pub fn initAtWithOperations(
        io: std.Io,
        file: std.Io.File,
        config: EncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
        pending_scratch: []u8,
        rollback_storage: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
        output_storage: []u8,
        audio_offset: u64,
        operations: file_writer_io.Operations,
    ) !PcmAdaptiveReservoirFileEncoder {
        const required = try requiredPcmAdaptiveReservoirStorage(
            config,
            maximum_history_bytes,
        );
        try validateAdaptiveReservoirFileStorage(
            pending_storage,
            pending_scratch,
            rollback_storage,
            frame_scratch,
            main_data_scratch,
            output_storage,
            required,
        );
        return .{
            .io = io,
            .file = file,
            .operations = operations,
            .stream = try PcmAdaptiveReservoirStreamEncoder.init(
                config,
                maximum_history_bytes,
                pending_storage,
            ),
            .pending_scratch = pending_scratch,
            .rollback_storage = rollback_storage,
            .frame_scratch = frame_scratch,
            .main_data_scratch = main_data_scratch,
            .output_storage = output_storage,
            .audio_offset = audio_offset,
        };
    }

    pub fn valid(self: *const PcmAdaptiveReservoirFileEncoder) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn append(
        self: *PcmAdaptiveReservoirFileEncoder,
        pcm: PcmFrame,
    ) !PcmAdaptiveReservoirAppend {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3AdaptiveReservoirFileEncoderState;
        const write_offset = try fileEncoderOffset(
            self.audio_offset,
            self.committed_bytes,
        );
        const before = self.stream;
        @memcpy(
            self.rollback_storage[0..before.pending_storage.len],
            before.pending_storage,
        );
        const appended = try self.stream.append(
            pcm,
            self.output_storage,
            self.pending_scratch,
            self.frame_scratch,
            self.main_data_scratch,
        );
        const next_committed = std.math.add(
            u64,
            self.committed_bytes,
            appended.frames.len,
        ) catch {
            self.restoreStream(before);
            return error.Mp3ByteCountOverflow;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            write_offset,
            appended.frames,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next_committed;
        return appended;
    }

    pub fn finalize(
        self: *PcmAdaptiveReservoirFileEncoder,
    ) !PcmAdaptiveReservoirFileSummary {
        try self.validate();
        if (self.finalized) return self.summary();
        if (self.failed)
            return error.InvalidMp3AdaptiveReservoirFileEncoderState;
        const write_offset = try fileEncoderOffset(
            self.audio_offset,
            self.committed_bytes,
        );
        const before = self.stream;
        @memcpy(
            self.rollback_storage[0..before.pending_storage.len],
            before.pending_storage,
        );
        const finished = try self.stream.finish(self.output_storage);
        const next_committed = std.math.add(
            u64,
            self.committed_bytes,
            finished.frames.len,
        ) catch {
            self.restoreStream(before);
            return error.Mp3ByteCountOverflow;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            write_offset,
            finished.frames,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.operations.sync(self.io, self.file) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next_committed;
        self.finalized = true;
        return self.summary();
    }

    pub fn recover(
        self: *PcmAdaptiveReservoirFileEncoder,
    ) !void {
        try self.validate();
        if (self.finalized)
            return error.InvalidMp3AdaptiveReservoirFileEncoderState;
        try file_writer_io.Checkpoint.exact(
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        ).restore(self.operations, self.io, self.file);
        self.failed = false;
    }

    fn restoreStream(
        self: *PcmAdaptiveReservoirFileEncoder,
        before: PcmAdaptiveReservoirStreamEncoder,
    ) void {
        @memcpy(
            before.pending_storage,
            self.rollback_storage[0..before.pending_storage.len],
        );
        self.stream = before;
    }

    fn summary(
        self: PcmAdaptiveReservoirFileEncoder,
    ) !PcmAdaptiveReservoirFileSummary {
        return .{
            .frame_count = self.stream.frames_received,
            .byte_count = self.stream.byte_count,
            .logical_main_data_bits = self.stream.logical_main_data_bits,
            .borrowed_bytes = self.stream.borrowed_bytes,
            .maximum_backpointer = self.stream.maximum_backpointer,
            .retained_history_bytes = self.stream.credit.available_history_bytes,
            .file_end = try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        };
    }

    fn validate(self: PcmAdaptiveReservoirFileEncoder) !void {
        if (!self.stream.valid() or
            self.finalized != self.stream.finalized or
            self.stream.byte_count < self.stream.pending_length or
            self.committed_bytes !=
                self.stream.byte_count - self.stream.pending_length)
            return error.InvalidMp3AdaptiveReservoirFileEncoderState;
        try validateAdaptiveReservoirFileStorage(
            self.stream.pending_storage,
            self.pending_scratch,
            self.rollback_storage,
            self.frame_scratch,
            self.main_data_scratch,
            self.output_storage,
            self.stream.pending_storage.len,
        );
    }
};

pub const PcmAdaptiveReservoirGaplessFileSummary = struct {
    stream: EncoderStreamSummary,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
    file_end: u64,
};

pub const PcmAdaptiveReservoirGaplessFileEncoder = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    stream: PcmAdaptiveReservoirGaplessStreamEncoder,
    pending_scratch: []u8,
    rollback_storage: []u8,
    frame_scratch: []u8,
    main_data_scratch: []u8,
    output_storage: []u8,
    finish_storage: []u8,
    audio_offset: u64 = 0,
    committed_bytes: u64 = 0,
    failed: bool = false,
    finalized: bool = false,

    /// All storage slices must remain stable for the encoder lifetime.
    pub fn init(
        io: std.Io,
        file: std.Io.File,
        config: EncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
        pending_scratch: []u8,
        rollback_storage: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
        output_storage: []u8,
        finish_storage: []u8,
    ) !PcmAdaptiveReservoirGaplessFileEncoder {
        return initAtWithOperations(
            io,
            file,
            config,
            maximum_history_bytes,
            pending_storage,
            pending_scratch,
            rollback_storage,
            frame_scratch,
            main_data_scratch,
            output_storage,
            finish_storage,
            0,
            .{},
        );
    }

    pub fn initAtWithOperations(
        io: std.Io,
        file: std.Io.File,
        config: EncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
        pending_scratch: []u8,
        rollback_storage: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
        output_storage: []u8,
        finish_storage: []u8,
        audio_offset: u64,
        operations: file_writer_io.Operations,
    ) !PcmAdaptiveReservoirGaplessFileEncoder {
        const required = try requiredPcmAdaptiveReservoirStorage(
            config,
            maximum_history_bytes,
        );
        const finish_required = try requiredAdaptiveGaplessFileFinishStorage(
            try config.header(false),
            required,
        );
        try validateAdaptiveGaplessFileStorage(
            pending_storage,
            pending_scratch,
            rollback_storage,
            frame_scratch,
            main_data_scratch,
            output_storage,
            finish_storage,
            required,
            finish_required,
        );
        return .{
            .io = io,
            .file = file,
            .operations = operations,
            .stream = try PcmAdaptiveReservoirGaplessStreamEncoder.init(
                config,
                maximum_history_bytes,
                pending_storage,
            ),
            .pending_scratch = pending_scratch,
            .rollback_storage = rollback_storage,
            .frame_scratch = frame_scratch,
            .main_data_scratch = main_data_scratch,
            .output_storage = output_storage,
            .finish_storage = finish_storage,
            .audio_offset = audio_offset,
        };
    }

    pub fn valid(
        self: *const PcmAdaptiveReservoirGaplessFileEncoder,
    ) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn startMetadata(
        self: *PcmAdaptiveReservoirGaplessFileEncoder,
    ) ![]u8 {
        return self.startMetadataWithEncoder(
            default_xing_encoder_identifier,
        );
    }

    pub fn startMetadataWithEncoder(
        self: *PcmAdaptiveReservoirGaplessFileEncoder,
        encoder: [9]u8,
    ) ![]u8 {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3AdaptiveReservoirGaplessFileEncoderState;
        const before = self.stream;
        @memcpy(
            self.rollback_storage[0..before.stream.pending_storage.len],
            before.stream.pending_storage,
        );
        const metadata = try self.stream.startMetadataWithEncoder(
            encoder,
            self.output_storage,
            self.frame_scratch,
            self.main_data_scratch,
        );
        const next_committed = std.math.add(
            u64,
            self.committed_bytes,
            metadata.len,
        ) catch {
            self.restoreStream(before);
            return error.Mp3ByteCountOverflow;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            self.audio_offset,
            metadata,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next_committed;
        return metadata;
    }

    pub fn append(
        self: *PcmAdaptiveReservoirGaplessFileEncoder,
        pcm: PcmFrame,
    ) !PcmAdaptiveReservoirAppend {
        try self.validate();
        if (self.failed or self.finalized or !self.stream.metadata_started)
            return error.InvalidMp3AdaptiveReservoirGaplessFileEncoderState;
        const write_offset = try fileEncoderOffset(
            self.audio_offset,
            self.committed_bytes,
        );
        const before = self.stream;
        @memcpy(
            self.rollback_storage[0..before.stream.pending_storage.len],
            before.stream.pending_storage,
        );
        const appended = try self.stream.append(
            pcm,
            self.output_storage,
            self.pending_scratch,
            self.frame_scratch,
            self.main_data_scratch,
        );
        const next_committed = std.math.add(
            u64,
            self.committed_bytes,
            appended.frames.len,
        ) catch {
            self.restoreStream(before);
            return error.Mp3ByteCountOverflow;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            write_offset,
            appended.frames,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next_committed;
        return appended;
    }

    pub fn finalize(
        self: *PcmAdaptiveReservoirGaplessFileEncoder,
    ) !PcmAdaptiveReservoirGaplessFileSummary {
        try self.validate();
        if (self.finalized) return self.summary();
        if (self.failed or !self.stream.metadata_started)
            return error.InvalidMp3AdaptiveReservoirGaplessFileEncoderState;
        const write_offset = try fileEncoderOffset(
            self.audio_offset,
            self.committed_bytes,
        );
        const before = self.stream;
        const finished = try self.stream.finish(
            self.output_storage,
            self.pending_scratch,
            self.rollback_storage,
            self.frame_scratch,
            self.main_data_scratch,
            self.finish_storage,
        );
        const next_committed = std.math.add(
            u64,
            self.committed_bytes,
            finished.frames.len,
        ) catch {
            self.restoreStream(before);
            return error.Mp3ByteCountOverflow;
        };
        const metadata = self.stream.metadataFrame(self.frame_scratch) catch |failure| {
            self.restoreStream(before);
            return failure;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            write_offset,
            finished.frames,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            self.audio_offset,
            metadata,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.operations.sync(self.io, self.file) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next_committed;
        self.finalized = true;
        return self.summary();
    }

    pub fn recover(
        self: *PcmAdaptiveReservoirGaplessFileEncoder,
    ) !void {
        try self.validate();
        if (self.finalized)
            return error.InvalidMp3AdaptiveReservoirGaplessFileEncoderState;
        try file_writer_io.Checkpoint.exact(
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        ).restore(self.operations, self.io, self.file);
        if (self.stream.metadata_started) {
            const metadata = try self.placeholderMetadata();
            try self.operations.writeAt(
                self.io,
                self.file,
                self.audio_offset,
                metadata,
            );
        }
        self.failed = false;
    }

    fn placeholderMetadata(
        self: PcmAdaptiveReservoirGaplessFileEncoder,
    ) ![]u8 {
        const header = try self.stream.stream.encoder.frames.config.header(false);
        return encodeInfoFrameFields(
            header,
            0,
            0,
            0,
            0,
            self.stream.metadata_encoder,
            self.output_storage,
        );
    }

    fn restoreStream(
        self: *PcmAdaptiveReservoirGaplessFileEncoder,
        before: PcmAdaptiveReservoirGaplessStreamEncoder,
    ) void {
        @memcpy(
            before.stream.pending_storage,
            self.rollback_storage[0..before.stream.pending_storage.len],
        );
        self.stream = before;
    }

    fn summary(
        self: PcmAdaptiveReservoirGaplessFileEncoder,
    ) !PcmAdaptiveReservoirGaplessFileSummary {
        return .{
            .stream = try self.stream.summary(),
            .logical_main_data_bits = self.stream.stream.logical_main_data_bits,
            .borrowed_bytes = self.stream.stream.borrowed_bytes,
            .maximum_backpointer = self.stream.stream.maximum_backpointer,
            .retained_history_bytes = self.stream.stream.credit.available_history_bytes,
            .file_end = try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        };
    }

    fn validate(self: PcmAdaptiveReservoirGaplessFileEncoder) !void {
        if (!self.stream.valid() or
            self.finalized != self.stream.stream.finalized or
            self.stream.stream.byte_count < self.stream.stream.pending_length or
            self.committed_bytes !=
                self.stream.stream.byte_count -
                    self.stream.stream.pending_length)
            return error.InvalidMp3AdaptiveReservoirGaplessFileEncoderState;
        const required = requiredPcmAdaptiveReservoirStorage(
            self.stream.stream.encoder.frames.config,
            self.stream.stream.credit.maximum_history_bytes,
        ) catch return error.InvalidMp3AdaptiveReservoirGaplessFileEncoderState;
        const finish_required = try requiredAdaptiveGaplessFileFinishStorage(
            self.stream.stream.encoder.frames.config.header(false) catch
                return error.InvalidMp3AdaptiveReservoirGaplessFileEncoderState,
            required,
        );
        try validateAdaptiveGaplessFileStorage(
            self.stream.stream.pending_storage,
            self.pending_scratch,
            self.rollback_storage,
            self.frame_scratch,
            self.main_data_scratch,
            self.output_storage,
            self.finish_storage,
            required,
            finish_required,
        );
    }
};

pub fn requiredAdaptiveGaplessFileFinishStorage(
    header: Header,
    pending_bytes: usize,
) !usize {
    const flush_bytes = std.math.mul(
        usize,
        try adaptiveGaplessFlushFrames(header),
        maximum_encoded_frame_bytes,
    ) catch return error.Mp3ByteCountOverflow;
    return std.math.add(
        usize,
        pending_bytes,
        flush_bytes,
    ) catch return error.Mp3ByteCountOverflow;
}

pub fn validateAdaptiveGaplessFileStorage(
    pending_storage: []const u8,
    pending_scratch: []const u8,
    rollback_storage: []const u8,
    frame_scratch: []const u8,
    main_data_scratch: []const u8,
    output_storage: []const u8,
    finish_storage: []const u8,
    required: usize,
    finish_required: usize,
) !void {
    if (pending_storage.len < required or
        pending_scratch.len < pending_storage.len or
        rollback_storage.len < pending_storage.len or
        frame_scratch.len < maximum_encoded_frame_bytes or
        main_data_scratch.len < maximum_encoded_main_data_bytes or
        output_storage.len < finish_required or
        finish_storage.len < finish_required)
        return error.Mp3AdaptiveReservoirStorageTooSmall;
    const ranges = [_]Mp3StorageRange{
        .{ .start = @intFromPtr(pending_storage.ptr), .length = pending_storage.len },
        .{ .start = @intFromPtr(pending_scratch.ptr), .length = pending_scratch.len },
        .{ .start = @intFromPtr(rollback_storage.ptr), .length = rollback_storage.len },
        .{ .start = @intFromPtr(frame_scratch.ptr), .length = frame_scratch.len },
        .{ .start = @intFromPtr(main_data_scratch.ptr), .length = main_data_scratch.len },
        .{ .start = @intFromPtr(output_storage.ptr), .length = output_storage.len },
        .{ .start = @intFromPtr(finish_storage.ptr), .length = finish_storage.len },
    };
    try validateDisjointMp3Storage(&ranges);
}

pub fn validateAdaptiveReservoirFileStorage(
    pending_storage: []const u8,
    pending_scratch: []const u8,
    rollback_storage: []const u8,
    frame_scratch: []const u8,
    main_data_scratch: []const u8,
    output_storage: []const u8,
    required: usize,
) !void {
    if (pending_storage.len < required or
        pending_scratch.len < pending_storage.len or
        rollback_storage.len < pending_storage.len or
        frame_scratch.len < maximum_encoded_frame_bytes or
        main_data_scratch.len < maximum_encoded_main_data_bytes or
        output_storage.len < pending_storage.len)
        return error.Mp3AdaptiveReservoirStorageTooSmall;
    const ranges = [_]struct { start: usize, length: usize }{
        .{ .start = @intFromPtr(pending_storage.ptr), .length = pending_storage.len },
        .{ .start = @intFromPtr(pending_scratch.ptr), .length = pending_scratch.len },
        .{ .start = @intFromPtr(rollback_storage.ptr), .length = rollback_storage.len },
        .{ .start = @intFromPtr(frame_scratch.ptr), .length = frame_scratch.len },
        .{ .start = @intFromPtr(main_data_scratch.ptr), .length = main_data_scratch.len },
        .{ .start = @intFromPtr(output_storage.ptr), .length = output_storage.len },
    };
    for (0..ranges.len) |left| {
        for (left + 1..ranges.len) |right| {
            if (byteRangesOverlap(
                ranges[left].start,
                ranges[left].length,
                ranges[right].start,
                ranges[right].length,
            )) return error.OverlappingMp3ReservoirStorage;
        }
    }
}

pub const VbrEncoderConfig = struct {
    template: EncoderConfig = .{},
    minimum_bitrate_index: u4 = 1,
    maximum_bitrate_index: u4 = 14,
    maximum_noise_to_mask_ratio: f32 = 1.0,
    psychoacoustics: EncoderPsychoacousticConfig = .{},

    fn validate(self: VbrEncoderConfig) !EncoderConfig {
        if (self.minimum_bitrate_index == 0 or
            self.maximum_bitrate_index == 0 or
            self.minimum_bitrate_index == 15 or
            self.maximum_bitrate_index == 15 or
            self.minimum_bitrate_index >
                self.maximum_bitrate_index or
            !std.math.isFinite(
                self.maximum_noise_to_mask_ratio,
            ) or
            self.maximum_noise_to_mask_ratio <= 0)
            return error.InvalidMp3VbrEncoderConfig;
        validateEncoderPsychoacousticConfig(
            self.psychoacoustics,
        ) catch return error.InvalidMp3VbrEncoderConfig;
        var maximum_config = self.template;
        maximum_config.bitrate_kbps = bitrate(
            self.template.version,
            self.maximum_bitrate_index,
        );
        const maximum_header =
            maximum_config.header(false) catch
                return error.InvalidMp3VbrEncoderConfig;
        validatePcmEncoderStereo(maximum_header) catch
            return error.InvalidMp3VbrEncoderConfig;
        return maximum_config;
    }
};

pub const VbrPcmFrame = struct {
    frame: []u8,
    header: Header,
    bitrate_index: u4,
    maximum_noise_to_mask_ratio: f32,
    quality_met: bool,
};

pub const VbrPcmFrameParts = struct {
    parts: QuantizedFrameParts,
    header: Header,
    bitrate_index: u4,
    maximum_noise_to_mask_ratio: f32,
    quality_met: bool,
};

pub const VbrPcmEncoder = struct {
    config: VbrEncoderConfig,
    frames: FrameEncoder,
    analysis: EncoderAnalysis,
    classifier: EncoderBlockClassifier = .{},
    masking: EncoderPsychoacousticTimeline,
    bitrate_histogram: [16]u64 = @splat(0),
    padding_frames: u64 = 0,
    byte_count: u64 = 0,

    pub fn init(config: VbrEncoderConfig) !VbrPcmEncoder {
        const maximum_config = try config.validate();
        return .{
            .config = config,
            .frames = try FrameEncoder.init(maximum_config),
            .analysis = try EncoderAnalysis.init(maximum_config),
            .masking = .{
                .model = .{
                    .config = config.psychoacoustics,
                },
            },
        };
    }

    pub fn reset(self: *VbrPcmEncoder) void {
        self.frames.reset();
        self.analysis.reset();
        self.classifier.reset();
        self.masking.reset();
        self.bitrate_histogram = @splat(0);
        self.padding_frames = 0;
        self.byte_count = 0;
    }

    pub fn valid(self: *const VbrPcmEncoder) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn encode(
        self: *VbrPcmEncoder,
        pcm: PcmFrame,
        destination: []u8,
    ) !VbrPcmFrame {
        return self.encodeSelection(pcm, destination, null);
    }

    pub fn encodeAtBitrateIndex(
        self: *VbrPcmEncoder,
        pcm: PcmFrame,
        destination: []u8,
        bitrate_index: u4,
    ) !VbrPcmFrame {
        if (bitrate_index < self.config.minimum_bitrate_index or
            bitrate_index > self.config.maximum_bitrate_index)
            return error.Mp3VbrBitrateOutsidePolicy;
        return self.encodeSelection(
            pcm,
            destination,
            bitrate_index,
        );
    }

    pub fn encodeReservoirParts(
        self: *VbrPcmEncoder,
        pcm: PcmFrame,
        available_history_bytes: u16,
        frame_destination: []u8,
        main_data_destination: []u8,
    ) !VbrPcmFrameParts {
        const selected = try self.select(
            pcm,
            null,
            available_history_bytes,
        );
        var next = selected.next;
        const parts = try next.frames
            .encodeQuantizedFramePartsAtBitrate(
            selected.header.bitrate_kbps,
            &selected.quantized,
            frame_destination,
            main_data_destination,
        );
        try next.recordSelection(
            selected.header,
            selected.bitrate_index,
            parts.frame.len,
        );
        self.* = next;
        return .{
            .parts = parts,
            .header = selected.header,
            .bitrate_index = selected.bitrate_index,
            .maximum_noise_to_mask_ratio = selected.maximum_noise_to_mask_ratio,
            .quality_met = selected.quality_met,
        };
    }

    fn encodeSelection(
        self: *VbrPcmEncoder,
        pcm: PcmFrame,
        destination: []u8,
        forced_bitrate_index: ?u4,
    ) !VbrPcmFrame {
        const selected = try self.select(pcm, forced_bitrate_index, 0);
        var next = selected.next;
        const encoded = try next.frames
            .encodeQuantizedFrameAtBitrate(
            selected.header.bitrate_kbps,
            &selected.quantized,
            destination,
        );
        try next.recordSelection(
            selected.header,
            selected.bitrate_index,
            encoded.len,
        );
        self.* = next;
        return .{
            .frame = encoded,
            .header = selected.header,
            .bitrate_index = selected.bitrate_index,
            .maximum_noise_to_mask_ratio = selected.maximum_noise_to_mask_ratio,
            .quality_met = selected.quality_met,
        };
    }

    const Selection = struct {
        next: VbrPcmEncoder,
        quantized: QuantizedEncoderFrame,
        header: Header,
        bitrate_index: u4,
        maximum_noise_to_mask_ratio: f32,
        quality_met: bool,
    };

    fn select(
        self: VbrPcmEncoder,
        pcm: PcmFrame,
        forced_bitrate_index: ?u4,
        available_history_bytes: u16,
    ) !Selection {
        try self.validateState();
        if (self.byte_count >
            std.math.maxInt(u64) - maximum_encoded_frame_bytes)
            return error.Mp3ByteCountOverflow;
        var next = self;
        const analysis_header =
            try next.frames.config.header(false);
        const descriptions = try next.classifier.classify(
            analysis_header,
            pcm,
        );
        const analyzed = try prepareEncoderStereo(
            analysis_header,
            try next.analysis.analyze(descriptions, pcm),
        );
        var next_masking = next.masking;
        const psychoacoustics = try next_masking.analyzeFrame(
            analysis_header,
            analyzed,
        );

        var selected_frame: ?QuantizedEncoderFrame = null;
        var selected_header: Header = undefined;
        var selected_index: u4 = 0;
        var selected_ratio: f32 = 0;
        var selected_quality = false;
        const first_index = forced_bitrate_index orelse
            self.config.minimum_bitrate_index;
        const last_index = forced_bitrate_index orelse
            self.config.maximum_bitrate_index;
        var index: u5 = first_index;
        while (index <= last_index) : (index += 1) {
            const bitrate_index: u4 = @intCast(index);
            const bitrate_kbps = bitrate(
                self.config.template.version,
                bitrate_index,
            );
            const advanced = next.frames.advanceAtBitrate(
                bitrate_kbps,
            ) catch |failure| switch (failure) {
                error.InvalidMp3EncoderFrameSize => continue,
                else => return failure,
            };
            const quantized = (EncoderQuantizer{
                .psychoacoustics = next.masking.model,
            }).processWithReservoirMasking(
                advanced.header,
                analyzed,
                psychoacoustics,
                available_history_bytes,
            ) catch |failure| switch (failure) {
                error.Mp3EncoderBitBudgetTooSmall => continue,
                else => return failure,
            };
            const ratio = try encoderNoiseToMaskRatio(
                advanced.header,
                analyzed,
                quantized,
                psychoacoustics,
            );
            selected_frame = quantized;
            selected_header = advanced.header;
            selected_index = bitrate_index;
            selected_ratio = ratio;
            selected_quality =
                ratio <= self.config.maximum_noise_to_mask_ratio;
            if (selected_quality or forced_bitrate_index != null)
                break;
        }
        next.masking = next_masking;
        return .{
            .next = next,
            .quantized = selected_frame orelse
                return error.Mp3EncoderBitBudgetTooSmall,
            .header = selected_header,
            .bitrate_index = selected_index,
            .maximum_noise_to_mask_ratio = selected_ratio,
            .quality_met = selected_quality,
        };
    }

    fn recordSelection(
        self: *VbrPcmEncoder,
        header: Header,
        bitrate_index: u4,
        encoded_bytes: usize,
    ) !void {
        self.bitrate_histogram[bitrate_index] = std.math.add(
            u64,
            self.bitrate_histogram[bitrate_index],
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        if (header.padding)
            self.padding_frames = std.math.add(
                u64,
                self.padding_frames,
                1,
            ) catch return error.Mp3EncoderFrameCountOverflow;
        self.byte_count = std.math.add(
            u64,
            self.byte_count,
            encoded_bytes,
        ) catch return error.Mp3ByteCountOverflow;
    }

    fn validateState(self: VbrPcmEncoder) !void {
        const maximum_config = self.config.validate() catch
            return error.InvalidMp3VbrEncoderState;
        if (!self.frames.valid() or
            !self.analysis.valid() or
            !self.classifier.valid() or
            !self.masking.valid() or
            !std.meta.eql(self.frames.config, maximum_config) or
            !std.meta.eql(self.analysis.config, maximum_config) or
            self.frames.frames_encoded !=
                self.analysis.frames_analyzed or
            self.frames.padding_accumulator >=
                maximum_config.sample_rate or
            self.padding_frames > self.frames.frames_encoded or
            self.bitrate_histogram[0] != 0 or
            self.bitrate_histogram[15] != 0)
            return error.InvalidMp3VbrEncoderState;

        var frame_count: u64 = 0;
        var byte_count: u128 = self.padding_frames;
        for (1..15) |index| {
            const count = self.bitrate_histogram[index];
            frame_count = std.math.add(
                u64,
                frame_count,
                count,
            ) catch return error.InvalidMp3VbrEncoderState;
            if (count == 0) continue;
            if (index < self.config.minimum_bitrate_index or
                index > self.config.maximum_bitrate_index)
                return error.InvalidMp3VbrEncoderState;
            var frame_config = self.config.template;
            frame_config.bitrate_kbps = bitrate(
                self.config.template.version,
                @intCast(index),
            );
            const header = frame_config.header(false) catch
                return error.InvalidMp3VbrEncoderState;
            byte_count += @as(u128, count) *
                header.frameBytes();
        }
        if (frame_count != self.frames.frames_encoded or
            byte_count != self.byte_count)
            return error.InvalidMp3VbrEncoderState;
        if (!std.meta.eql(
            self.masking.model.config,
            self.config.psychoacoustics,
        ))
            return error.InvalidMp3VbrEncoderState;
    }
};

pub const VbrPcmReservoirBatchResult = struct {
    stream: []u8,
    frame_count: u64,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
    bitrate_histogram: [16]u64,
    quality_misses: u64,
    maximum_noise_to_mask_ratio: f32,
};

pub fn encodeVbrPcmReservoirBatch(
    config: VbrEncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
) !VbrPcmReservoirBatchResult {
    const maximum_config = try config.validate();
    const header = try maximum_config.header(false);
    var credit = try ReservoirCreditTracker.init(
        header,
        maximum_history_bytes,
    );
    const maximum_frame_bytes =
        try requiredPcmReservoirBatchFrameBytes(
            maximum_config,
            pcm_frames.len,
        );
    if (destination.len < maximum_frame_bytes)
        return error.InsufficientMp3EncoderStorage;
    if (frame_scratch.len < maximum_frame_bytes or
        pack_scratch.len < maximum_frame_bytes)
        return error.Mp3ReservoirEncodedScratchTooSmall;
    const ranges = [_]struct { start: usize, length: usize }{
        .{
            .start = @intFromPtr(destination.ptr),
            .length = maximum_frame_bytes,
        },
        .{
            .start = @intFromPtr(frame_scratch.ptr),
            .length = maximum_frame_bytes,
        },
        .{
            .start = @intFromPtr(pack_scratch.ptr),
            .length = maximum_frame_bytes,
        },
        .{
            .start = @intFromPtr(main_data_scratch.ptr),
            .length = main_data_scratch.len,
        },
    };
    for (0..ranges.len) |left| {
        for (left + 1..ranges.len) |right| {
            if (byteRangesOverlap(
                ranges[left].start,
                ranges[left].length,
                ranges[right].start,
                ranges[right].length,
            )) return error.OverlappingMp3ReservoirStorage;
        }
    }
    const pcm_bytes = std.mem.sliceAsBytes(pcm_frames);
    if (byteRangesOverlap(
        @intFromPtr(pcm_bytes.ptr),
        pcm_bytes.len,
        @intFromPtr(frame_scratch.ptr),
        maximum_frame_bytes,
    ) or byteRangesOverlap(
        @intFromPtr(pcm_bytes.ptr),
        pcm_bytes.len,
        @intFromPtr(main_data_scratch.ptr),
        main_data_scratch.len,
    )) return error.OverlappingMp3ReservoirStorage;
    if (pcm_frames.len == 0) return .{
        .stream = destination[0..0],
        .frame_count = 0,
        .logical_main_data_bits = 0,
        .borrowed_bytes = 0,
        .maximum_backpointer = 0,
        .retained_history_bytes = 0,
        .bitrate_histogram = @splat(0),
        .quality_misses = 0,
        .maximum_noise_to_mask_ratio = 0,
    };

    var encoder = try VbrPcmEncoder.init(config);
    var frame_cursor: usize = 0;
    var main_data_cursor: usize = 0;
    var logical_main_data_bits: u64 = 0;
    var quality_misses: u64 = 0;
    var maximum_noise_to_mask_ratio: f32 = 0;
    for (pcm_frames) |pcm| {
        const selected = try encoder.encodeReservoirParts(
            pcm,
            credit.available_history_bytes,
            frame_scratch[frame_cursor..],
            main_data_scratch[main_data_cursor..],
        );
        _ = try credit.commit(
            selected.header,
            selected.parts.main_data_bits,
        );
        frame_cursor += selected.parts.frame.len;
        main_data_cursor += selected.parts.main_data.len;
        logical_main_data_bits = std.math.add(
            u64,
            logical_main_data_bits,
            selected.parts.main_data_bits,
        ) catch return error.Mp3MainDataBitCountOverflow;
        quality_misses = std.math.add(
            u64,
            quality_misses,
            @intFromBool(!selected.quality_met),
        ) catch return error.Mp3EncoderFrameCountOverflow;
        maximum_noise_to_mask_ratio = @max(
            maximum_noise_to_mask_ratio,
            selected.maximum_noise_to_mask_ratio,
        );
    }
    const packing_result = try packMainDataReservoir(
        frame_scratch[0..frame_cursor],
        main_data_scratch[0..main_data_cursor],
        maximum_history_bytes,
        pack_scratch[0..frame_cursor],
    );
    @memcpy(destination[0..frame_cursor], frame_scratch[0..frame_cursor]);
    return .{
        .stream = destination[0..frame_cursor],
        .frame_count = packing_result.frame_count,
        .logical_main_data_bits = logical_main_data_bits,
        .borrowed_bytes = packing_result.borrowed_bytes,
        .maximum_backpointer = packing_result.maximum_backpointer,
        .retained_history_bytes = credit.available_history_bytes,
        .bitrate_histogram = encoder.bitrate_histogram,
        .quality_misses = quality_misses,
        .maximum_noise_to_mask_ratio = maximum_noise_to_mask_ratio,
    };
}

pub const PcmReservoirGaplessBatchResult = struct {
    stream: []u8,
    summary: EncoderStreamSummary,
    metadata_bytes: u16,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
};

pub const VbrPcmReservoirGaplessBatchResult = struct {
    stream: []u8,
    summary: EncoderStreamSummary,
    metadata_bytes: u16,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
    bitrate_histogram: [16]u64,
    quality_misses: u64,
    maximum_noise_to_mask_ratio: f32,
};

pub fn encodePcmReservoirGaplessBatch(
    config: EncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    encoder_identifier: [9]u8,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    metadata_scratch: []u8,
) !PcmReservoirGaplessBatchResult {
    const header = try config.header(false);
    const flush_frames = try adaptiveGaplessFlushFrames(header);
    const reservoir_frames = std.math.add(
        usize,
        pcm_frames.len,
        flush_frames,
    ) catch return error.Mp3EncoderFrameCountOverflow;
    const storage = try validateGaplessReservoirBatchStorage(
        config,
        pcm_frames,
        reservoir_frames,
        header.frameBytes(),
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
        metadata_scratch,
    );
    var encoder = try PcmEncoder.init(config);
    const silence = PcmFrame{
        .channel_count = @intCast(header.channels()),
        .sample_count = header.samplesPerFrame(),
    };
    const reserved = try encoder.encode(silence, metadata_scratch);
    if (reserved.len != header.frameBytes())
        return error.InvalidMp3EncoderState;

    var credit = try ReservoirCreditTracker.init(
        header,
        maximum_history_bytes,
    );
    var frame_cursor: usize = 0;
    var main_data_cursor: usize = 0;
    var logical_main_data_bits: u64 = 0;
    var input_samples: u64 = 0;
    for (pcm_frames) |pcm| {
        input_samples = std.math.add(
            u64,
            input_samples,
            pcm.sample_count,
        ) catch return error.Mp3SampleCountOverflow;
        const parts = try encoder.encodeReservoirParts(
            pcm,
            credit.available_history_bytes,
            frame_scratch[frame_cursor..],
            main_data_scratch[main_data_cursor..],
        );
        const frame = try Frame.parse(parts.frame, 0);
        _ = try credit.commit(frame.header, parts.main_data_bits);
        frame_cursor += parts.frame.len;
        main_data_cursor += parts.main_data.len;
        logical_main_data_bits = std.math.add(
            u64,
            logical_main_data_bits,
            parts.main_data_bits,
        ) catch return error.Mp3MainDataBitCountOverflow;
    }
    for (0..flush_frames) |_| {
        const parts = try encoder.encodeReservoirParts(
            silence,
            credit.available_history_bytes,
            frame_scratch[frame_cursor..],
            main_data_scratch[main_data_cursor..],
        );
        const frame = try Frame.parse(parts.frame, 0);
        _ = try credit.commit(frame.header, parts.main_data_bits);
        frame_cursor += parts.frame.len;
        main_data_cursor += parts.main_data.len;
        logical_main_data_bits = std.math.add(
            u64,
            logical_main_data_bits,
            parts.main_data_bits,
        ) catch return error.Mp3MainDataBitCountOverflow;
    }
    const packing = try packMainDataReservoir(
        frame_scratch[0..frame_cursor],
        main_data_scratch[0..main_data_cursor],
        maximum_history_bytes,
        pack_scratch[0..frame_cursor],
    );
    const stream_bytes = std.math.add(
        usize,
        reserved.len,
        frame_cursor,
    ) catch return error.Mp3EncoderMetadataByteCountOverflow;
    if (stream_bytes > storage.destination_bytes)
        return error.InsufficientMp3EncoderStorage;
    const summary = try adaptiveGaplessSummary(
        reservoir_frames,
        input_samples,
        header,
        stream_bytes,
    );
    const metadata = try encodeInfoFrameWithEncoder(
        config,
        summary,
        encoder_identifier,
        metadata_scratch,
    );
    if (metadata.len != reserved.len)
        return error.InvalidMp3EncoderState;
    @memcpy(destination[0..metadata.len], metadata);
    @memcpy(
        destination[metadata.len..stream_bytes],
        frame_scratch[0..frame_cursor],
    );
    return .{
        .stream = destination[0..stream_bytes],
        .summary = summary,
        .metadata_bytes = @intCast(metadata.len),
        .logical_main_data_bits = logical_main_data_bits,
        .borrowed_bytes = packing.borrowed_bytes,
        .maximum_backpointer = packing.maximum_backpointer,
        .retained_history_bytes = credit.available_history_bytes,
    };
}

pub fn encodeVbrPcmReservoirGaplessBatch(
    config: VbrEncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    quality: ?u32,
    encoder_identifier: [9]u8,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    metadata_scratch: []u8,
) !VbrPcmReservoirGaplessBatchResult {
    const maximum_config = try config.validate();
    var metadata_config = config.template;
    metadata_config.bitrate_kbps = bitrate(
        metadata_config.version,
        config.maximum_bitrate_index,
    );
    const metadata_header = try metadata_config.header(false);
    const flush_frames = try adaptiveGaplessFlushFrames(metadata_header);
    const reservoir_frames = std.math.add(
        usize,
        pcm_frames.len,
        flush_frames,
    ) catch return error.Mp3EncoderFrameCountOverflow;
    const storage = try validateGaplessReservoirBatchStorage(
        maximum_config,
        pcm_frames,
        reservoir_frames,
        metadata_header.frameBytes(),
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
        metadata_scratch,
    );
    var encoder = try VbrPcmEncoder.init(config);
    const silence = PcmFrame{
        .channel_count = @intCast(metadata_header.channels()),
        .sample_count = metadata_header.samplesPerFrame(),
    };
    const reserved = try encoder.encodeAtBitrateIndex(
        silence,
        metadata_scratch,
        config.maximum_bitrate_index,
    );
    if (!std.meta.eql(reserved.header, metadata_header) or
        reserved.frame.len != metadata_header.frameBytes())
        return error.InvalidMp3VbrEncoderState;

    var credit = try ReservoirCreditTracker.init(
        metadata_header,
        maximum_history_bytes,
    );
    var frame_cursor: usize = 0;
    var main_data_cursor: usize = 0;
    var logical_main_data_bits: u64 = 0;
    var input_samples: u64 = 0;
    var quality_misses: u64 = 0;
    var maximum_noise_to_mask_ratio: f32 = 0;
    for (pcm_frames) |pcm| {
        input_samples = std.math.add(
            u64,
            input_samples,
            pcm.sample_count,
        ) catch return error.Mp3SampleCountOverflow;
        const selected = try encoder.encodeReservoirParts(
            pcm,
            credit.available_history_bytes,
            frame_scratch[frame_cursor..],
            main_data_scratch[main_data_cursor..],
        );
        _ = try credit.commit(
            selected.header,
            selected.parts.main_data_bits,
        );
        frame_cursor += selected.parts.frame.len;
        main_data_cursor += selected.parts.main_data.len;
        logical_main_data_bits = std.math.add(
            u64,
            logical_main_data_bits,
            selected.parts.main_data_bits,
        ) catch return error.Mp3MainDataBitCountOverflow;
        quality_misses = std.math.add(
            u64,
            quality_misses,
            @intFromBool(!selected.quality_met),
        ) catch return error.Mp3EncoderFrameCountOverflow;
        maximum_noise_to_mask_ratio = @max(
            maximum_noise_to_mask_ratio,
            selected.maximum_noise_to_mask_ratio,
        );
    }
    for (0..flush_frames) |_| {
        const selected = try encoder.encodeReservoirParts(
            silence,
            credit.available_history_bytes,
            frame_scratch[frame_cursor..],
            main_data_scratch[main_data_cursor..],
        );
        _ = try credit.commit(
            selected.header,
            selected.parts.main_data_bits,
        );
        frame_cursor += selected.parts.frame.len;
        main_data_cursor += selected.parts.main_data.len;
        logical_main_data_bits = std.math.add(
            u64,
            logical_main_data_bits,
            selected.parts.main_data_bits,
        ) catch return error.Mp3MainDataBitCountOverflow;
        quality_misses = std.math.add(
            u64,
            quality_misses,
            @intFromBool(!selected.quality_met),
        ) catch return error.Mp3EncoderFrameCountOverflow;
        maximum_noise_to_mask_ratio = @max(
            maximum_noise_to_mask_ratio,
            selected.maximum_noise_to_mask_ratio,
        );
    }
    const packing = try packMainDataReservoir(
        frame_scratch[0..frame_cursor],
        main_data_scratch[0..main_data_cursor],
        maximum_history_bytes,
        pack_scratch[0..frame_cursor],
    );
    const stream_bytes = std.math.add(
        usize,
        reserved.frame.len,
        frame_cursor,
    ) catch return error.Mp3EncoderMetadataByteCountOverflow;
    if (stream_bytes > storage.destination_bytes)
        return error.InsufficientMp3EncoderStorage;
    const summary = try adaptiveGaplessSummary(
        reservoir_frames,
        input_samples,
        metadata_header,
        stream_bytes,
    );
    if (summary.byte_count != encoder.byte_count)
        return error.InvalidMp3VbrEncoderState;
    const toc = try reservoirBatchXingToc(
        frame_scratch[0..frame_cursor],
        reserved.frame.len,
        @intCast(summary.frame_count),
        @intCast(summary.byte_count),
    );
    const metadata = try encodeXingFrameFields(
        metadata_header,
        .{
            .kind = .variable,
            .frame_count = @intCast(summary.frame_count),
            .stream_bytes = @intCast(summary.byte_count),
            .toc = toc,
            .quality = quality,
            .encoder_delay = try storedXingEncoderDelay(
                metadata_header,
                summary.encoder_delay,
            ),
            .encoder_padding = try storedXingEncoderPadding(
                summary.end_padding,
            ),
            .encoder = encoder_identifier,
        },
        metadata_scratch,
    );
    if (metadata.len != reserved.frame.len)
        return error.InvalidMp3VbrEncoderState;
    @memcpy(destination[0..metadata.len], metadata);
    @memcpy(
        destination[metadata.len..stream_bytes],
        frame_scratch[0..frame_cursor],
    );
    return .{
        .stream = destination[0..stream_bytes],
        .summary = summary,
        .metadata_bytes = @intCast(metadata.len),
        .logical_main_data_bits = logical_main_data_bits,
        .borrowed_bytes = packing.borrowed_bytes,
        .maximum_backpointer = packing.maximum_backpointer,
        .retained_history_bytes = credit.available_history_bytes,
        .bitrate_histogram = encoder.bitrate_histogram,
        .quality_misses = quality_misses,
        .maximum_noise_to_mask_ratio = maximum_noise_to_mask_ratio,
    };
}

pub const GaplessReservoirBatchStorage = struct {
    destination_bytes: usize,
};

pub fn validateGaplessReservoirBatchStorage(
    maximum_config: EncoderConfig,
    pcm_frames: []const PcmFrame,
    reservoir_frame_count: usize,
    metadata_bytes: usize,
    destination: []const u8,
    frame_scratch: []const u8,
    pack_scratch: []const u8,
    main_data_scratch: []const u8,
    metadata_scratch: []const u8,
) !GaplessReservoirBatchStorage {
    const complete_frame_count = std.math.add(
        usize,
        reservoir_frame_count,
        1,
    ) catch return error.Mp3EncoderFrameCountOverflow;
    const complete_frame_bytes = try requiredPcmReservoirBatchFrameBytes(
        maximum_config,
        complete_frame_count,
    );
    if (complete_frame_bytes < metadata_bytes)
        return error.InvalidMp3EncoderFrameSize;
    const frame_bytes = complete_frame_bytes - metadata_bytes;
    const destination_bytes = complete_frame_bytes;
    if (destination.len < destination_bytes)
        return error.InsufficientMp3EncoderStorage;
    if (frame_scratch.len < frame_bytes or
        pack_scratch.len < frame_bytes)
        return error.Mp3ReservoirEncodedScratchTooSmall;
    if (metadata_scratch.len < metadata_bytes)
        return error.InsufficientMp3EncoderStorage;
    const ranges = [_]struct { start: usize, length: usize }{
        .{ .start = @intFromPtr(destination.ptr), .length = destination_bytes },
        .{ .start = @intFromPtr(frame_scratch.ptr), .length = frame_bytes },
        .{ .start = @intFromPtr(pack_scratch.ptr), .length = frame_bytes },
        .{ .start = @intFromPtr(main_data_scratch.ptr), .length = main_data_scratch.len },
        .{ .start = @intFromPtr(metadata_scratch.ptr), .length = metadata_bytes },
    };
    for (0..ranges.len) |left| {
        for (left + 1..ranges.len) |right| {
            if (byteRangesOverlap(
                ranges[left].start,
                ranges[left].length,
                ranges[right].start,
                ranges[right].length,
            )) return error.OverlappingMp3ReservoirStorage;
        }
    }
    const pcm_bytes = std.mem.sliceAsBytes(pcm_frames);
    inline for (.{
        frame_scratch[0..frame_bytes],
        main_data_scratch,
        metadata_scratch[0..metadata_bytes],
    }) |scratch| {
        if (byteRangesOverlap(
            @intFromPtr(pcm_bytes.ptr),
            pcm_bytes.len,
            @intFromPtr(scratch.ptr),
            scratch.len,
        )) return error.OverlappingMp3ReservoirStorage;
    }
    return .{ .destination_bytes = destination_bytes };
}

pub fn adaptiveGaplessFlushFrames(header: Header) !usize {
    return std.math.divCeil(
        usize,
        encoder_analysis_delay,
        header.samplesPerFrame(),
    ) catch error.Mp3SampleCountOverflow;
}

pub fn adaptiveGaplessSummary(
    reservoir_frame_count: usize,
    input_samples: u64,
    header: Header,
    byte_count: usize,
) !EncoderStreamSummary {
    const frame_count = std.math.add(
        u64,
        reservoir_frame_count,
        1,
    ) catch return error.Mp3EncoderFrameCountOverflow;
    const encoded_samples = std.math.mul(
        u64,
        frame_count,
        header.samplesPerFrame(),
    ) catch return error.Mp3SampleCountOverflow;
    const encoder_delay = std.math.add(
        u16,
        encoder_analysis_delay,
        header.samplesPerFrame(),
    ) catch return error.Mp3SampleCountOverflow;
    const retained_samples = std.math.add(
        u64,
        input_samples,
        encoder_delay,
    ) catch return error.Mp3SampleCountOverflow;
    if (encoded_samples < retained_samples)
        return error.Mp3EncoderStreamIncomplete;
    const end_padding = encoded_samples - retained_samples;
    if (end_padding > std.math.maxInt(u12))
        return error.Mp3EncoderPaddingOverflow;
    return .{
        .frame_count = frame_count,
        .input_samples = input_samples,
        .encoded_samples = encoded_samples,
        .byte_count = byte_count,
        .encoder_delay = encoder_delay,
        .end_padding = @intCast(end_padding),
    };
}

pub fn requiredVbrPcmAdaptiveReservoirStorage(
    config: VbrEncoderConfig,
    maximum_history_bytes: u16,
) !usize {
    const maximum_config = try config.validate();
    const maximum_header = try maximum_config.header(false);
    _ = try ReservoirCreditTracker.init(
        maximum_header,
        maximum_history_bytes,
    );
    var minimum_config = config.template;
    minimum_config.bitrate_kbps = bitrate(
        minimum_config.version,
        config.minimum_bitrate_index,
    );
    const minimum_header = try minimum_config.header(false);
    const minimum_capacity = minimum_header.frameBytes() -
        frameMainDataOffset(minimum_header);
    if (minimum_capacity == 0)
        return error.InvalidMp3EncoderFrameSize;
    const retained_frames = std.math.add(
        usize,
        try std.math.divCeil(
            usize,
            maximum_history_bytes,
            minimum_capacity,
        ),
        1,
    ) catch return error.Mp3ReservoirSizeOverflow;
    const maximum_frame_bytes = std.math.add(
        usize,
        maximum_header.frameBytes(),
        1,
    ) catch return error.Mp3ReservoirSizeOverflow;
    return std.math.mul(
        usize,
        retained_frames,
        maximum_frame_bytes,
    ) catch error.Mp3ReservoirSizeOverflow;
}

pub fn requiredPcmAdaptiveReservoirGaplessFileFinishStorage(
    config: EncoderConfig,
    maximum_history_bytes: u16,
) !usize {
    const pending_bytes = try requiredPcmAdaptiveReservoirStorage(
        config,
        maximum_history_bytes,
    );
    return requiredAdaptiveGaplessFileFinishStorage(
        try config.header(false),
        pending_bytes,
    );
}

pub fn requiredVbrPcmAdaptiveReservoirGaplessFileFinishStorage(
    config: VbrEncoderConfig,
    maximum_history_bytes: u16,
) !usize {
    const pending_bytes = try requiredVbrPcmAdaptiveReservoirStorage(
        config,
        maximum_history_bytes,
    );
    const maximum_config = try config.validate();
    return requiredAdaptiveGaplessFileFinishStorage(
        try maximum_config.header(false),
        pending_bytes,
    );
}

pub fn requiredVbrPcmAdaptiveReservoirGaplessFrameOffsets(
    config: VbrEncoderConfig,
    input_frame_count: usize,
) !usize {
    const maximum_config = try config.validate();
    const header = try maximum_config.header(false);
    const audio_frames = std.math.add(
        usize,
        input_frame_count,
        try adaptiveGaplessFlushFrames(header),
    ) catch return error.Mp3EncoderFrameCountOverflow;
    return std.math.add(
        usize,
        audio_frames,
        1,
    ) catch return error.Mp3EncoderFrameCountOverflow;
}

pub const VbrPcmAdaptiveReservoirAppend = struct {
    frames: []u8,
    frame_count: u16,
    selection: VbrPcmReservoirSelection,
    borrowed_bytes: u16,
    retained_history_bytes: u16,
};

pub const VbrPcmAdaptiveReservoirFinish = struct {
    frames: []u8,
    frame_count: u64,
    byte_count: u64,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
    bitrate_histogram: [16]u64,
    quality_misses: u64,
    maximum_noise_to_mask_ratio: f32,
};

pub const VbrPcmAdaptiveReservoirStreamEncoder = struct {
    encoder: VbrPcmEncoder,
    credit: ReservoirCreditTracker,
    pending_storage: []u8,
    pending_length: usize = 0,
    physical_main_data_bytes: u64 = 0,
    published_main_data_bytes: u64 = 0,
    packed_main_data_end: u64 = 0,
    frames_received: u64 = 0,
    frames_emitted: u64 = 0,
    independent_frames: u8 = 0,
    logical_main_data_bits: u64 = 0,
    borrowed_bytes: u64 = 0,
    maximum_backpointer: u16 = 0,
    quality_misses: u64 = 0,
    maximum_noise_to_mask_ratio: f32 = 0,
    finalized: bool = false,

    /// Keep `pending_storage` stable until the encoder is no longer used.
    pub fn init(
        config: VbrEncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
    ) !VbrPcmAdaptiveReservoirStreamEncoder {
        const required = try requiredVbrPcmAdaptiveReservoirStorage(
            config,
            maximum_history_bytes,
        );
        if (pending_storage.len < required)
            return error.Mp3AdaptiveReservoirStorageTooSmall;
        const maximum_config = try config.validate();
        const header = try maximum_config.header(false);
        @memset(pending_storage, 0);
        return .{
            .encoder = try VbrPcmEncoder.init(config),
            .credit = try ReservoirCreditTracker.init(
                header,
                maximum_history_bytes,
            ),
            .pending_storage = pending_storage,
        };
    }

    pub fn reset(
        self: *VbrPcmAdaptiveReservoirStreamEncoder,
    ) void {
        self.encoder.reset();
        self.credit.reset();
        @memset(self.pending_storage, 0);
        self.pending_length = 0;
        self.physical_main_data_bytes = 0;
        self.published_main_data_bytes = 0;
        self.packed_main_data_end = 0;
        self.frames_received = 0;
        self.frames_emitted = 0;
        self.independent_frames = 0;
        self.logical_main_data_bits = 0;
        self.borrowed_bytes = 0;
        self.maximum_backpointer = 0;
        self.quality_misses = 0;
        self.maximum_noise_to_mask_ratio = 0;
        self.finalized = false;
    }

    pub fn valid(
        self: *const VbrPcmAdaptiveReservoirStreamEncoder,
    ) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn append(
        self: *VbrPcmAdaptiveReservoirStreamEncoder,
        pcm: PcmFrame,
        destination: []u8,
        pending_scratch: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
    ) !VbrPcmAdaptiveReservoirAppend {
        try self.validateState();
        if (self.finalized)
            return error.Mp3VbrAdaptiveReservoirEncoderFinalized;
        try validateAdaptiveReservoirStorage(
            self.pending_storage,
            destination,
            pending_scratch,
            frame_scratch,
            main_data_scratch,
        );

        var next = self.*;
        const selected = try next.encoder.encodeReservoirParts(
            pcm,
            next.credit.available_history_bytes,
            frame_scratch,
            main_data_scratch,
        );
        const decision = try next.credit.commit(
            selected.header,
            selected.parts.main_data_bits,
        );
        const staged_length = std.math.add(
            usize,
            self.pending_length,
            selected.parts.frame.len,
        ) catch return error.Mp3ReservoirSizeOverflow;
        if (staged_length > self.pending_storage.len or
            staged_length > pending_scratch.len)
            return error.Mp3AdaptiveReservoirStorageTooSmall;
        @memcpy(
            pending_scratch[0..self.pending_length],
            self.pending_storage[0..self.pending_length],
        );
        @memcpy(
            pending_scratch[self.pending_length..staged_length],
            selected.parts.frame,
        );

        const logical_start = @max(
            next.packed_main_data_end,
            next.physical_main_data_bytes -|
                next.credit.maximum_history_bytes,
        );
        if (logical_start > next.physical_main_data_bytes or
            logical_start < next.published_main_data_bytes)
            return error.InvalidMp3VbrAdaptiveReservoirState;
        const backpointer_bytes =
            next.physical_main_data_bytes - logical_start;
        if (backpointer_bytes > std.math.maxInt(u16))
            return error.InvalidMp3VbrAdaptiveReservoirState;
        const relative_logical_start = logical_start -
            next.published_main_data_bytes;
        if (relative_logical_start > std.math.maxInt(usize))
            return error.Mp3ReservoirSizeOverflow;
        var writer = ReservoirMainDataWriter{
            .encoded = pending_scratch[0..staged_length],
        };
        try writer.seekTo(@intCast(relative_logical_start));
        try writer.write(selected.parts.main_data);
        setFrameMainDataBegin(
            pending_scratch[self.pending_length..staged_length],
            selected.header,
            @intCast(backpointer_bytes),
        );

        next.packed_main_data_end = std.math.add(
            u64,
            logical_start,
            decision.logical_bytes,
        ) catch return error.Mp3ReservoirSizeOverflow;
        next.physical_main_data_bytes = std.math.add(
            u64,
            next.physical_main_data_bytes,
            decision.physical_bytes,
        ) catch return error.Mp3ReservoirSizeOverflow;
        next.frames_received = std.math.add(
            u64,
            next.frames_received,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        next.logical_main_data_bits = std.math.add(
            u64,
            next.logical_main_data_bits,
            selected.parts.main_data_bits,
        ) catch return error.Mp3MainDataBitCountOverflow;
        next.borrowed_bytes = std.math.add(
            u64,
            next.borrowed_bytes,
            backpointer_bytes,
        ) catch return error.Mp3ReservoirByteCountOverflow;
        next.maximum_backpointer = @max(
            next.maximum_backpointer,
            @as(u16, @intCast(backpointer_bytes)),
        );
        next.quality_misses = std.math.add(
            u64,
            next.quality_misses,
            @intFromBool(!selected.quality_met),
        ) catch return error.Mp3EncoderFrameCountOverflow;
        next.maximum_noise_to_mask_ratio = @max(
            next.maximum_noise_to_mask_ratio,
            selected.maximum_noise_to_mask_ratio,
        );

        const safe_main_data_end =
            next.physical_main_data_bytes -|
            next.credit.maximum_history_bytes;
        var frame_offset: usize = 0;
        var emitted_bytes: usize = 0;
        var emitted_frames: u16 = 0;
        var emitted_main_data_bytes: u64 = 0;
        var main_data_cursor = next.published_main_data_bytes;
        while (frame_offset < staged_length) {
            const pending_frame = try Frame.parse(
                pending_scratch[0..staged_length],
                frame_offset,
            );
            const capacity = pending_frame.bytes.len -
                frameMainDataOffset(pending_frame.header);
            const frame_main_data_end = std.math.add(
                u64,
                main_data_cursor,
                capacity,
            ) catch return error.Mp3ReservoirSizeOverflow;
            if (frame_main_data_end > safe_main_data_end) break;
            emitted_bytes += pending_frame.bytes.len;
            emitted_frames = std.math.add(
                u16,
                emitted_frames,
                1,
            ) catch return error.Mp3EncoderFrameCountOverflow;
            emitted_main_data_bytes = std.math.add(
                u64,
                emitted_main_data_bytes,
                capacity,
            ) catch return error.Mp3ReservoirSizeOverflow;
            main_data_cursor = frame_main_data_end;
            frame_offset += pending_frame.bytes.len;
        }
        if (destination.len < emitted_bytes)
            return error.InsufficientMp3EncoderStorage;
        const remaining = staged_length - emitted_bytes;
        const next_published_main_data_bytes = std.math.add(
            u64,
            next.published_main_data_bytes,
            emitted_main_data_bytes,
        ) catch return error.Mp3ReservoirSizeOverflow;
        const next_frames_emitted = std.math.add(
            u64,
            next.frames_emitted,
            emitted_frames,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const old_pending_length = self.pending_length;
        @memcpy(
            destination[0..emitted_bytes],
            pending_scratch[0..emitted_bytes],
        );
        std.mem.copyForwards(
            u8,
            self.pending_storage[0..remaining],
            pending_scratch[emitted_bytes..staged_length],
        );
        if (remaining < old_pending_length)
            @memset(
                self.pending_storage[remaining..old_pending_length],
                0,
            );
        next.pending_length = remaining;
        next.published_main_data_bytes =
            next_published_main_data_bytes;
        next.frames_emitted = next_frames_emitted;
        self.* = next;
        return .{
            .frames = destination[0..emitted_bytes],
            .frame_count = emitted_frames,
            .selection = .{
                .header = selected.header,
                .bitrate_index = selected.bitrate_index,
                .maximum_noise_to_mask_ratio = selected.maximum_noise_to_mask_ratio,
                .quality_met = selected.quality_met,
            },
            .borrowed_bytes = @intCast(backpointer_bytes),
            .retained_history_bytes = decision.next_history_bytes,
        };
    }

    pub fn finish(
        self: *VbrPcmAdaptiveReservoirStreamEncoder,
        destination: []u8,
    ) !VbrPcmAdaptiveReservoirFinish {
        try self.validateState();
        var emitted_bytes: usize = 0;
        if (!self.finalized) {
            if (byteRangesOverlap(
                @intFromPtr(self.pending_storage.ptr),
                self.pending_storage.len,
                @intFromPtr(destination.ptr),
                destination.len,
            )) return error.OverlappingMp3ReservoirStorage;
            if (destination.len < self.pending_length)
                return error.InsufficientMp3EncoderStorage;
            @memcpy(
                destination[0..self.pending_length],
                self.pending_storage[0..self.pending_length],
            );
            emitted_bytes = self.pending_length;
            @memset(
                self.pending_storage[0..self.pending_length],
                0,
            );
            self.pending_length = 0;
            self.published_main_data_bytes =
                self.physical_main_data_bytes;
            self.frames_emitted = self.frames_received;
            self.finalized = true;
        }
        return .{
            .frames = destination[0..emitted_bytes],
            .frame_count = self.frames_received,
            .byte_count = self.encoder.byte_count,
            .logical_main_data_bits = self.logical_main_data_bits,
            .borrowed_bytes = self.borrowed_bytes,
            .maximum_backpointer = self.maximum_backpointer,
            .retained_history_bytes = self.credit.available_history_bytes,
            .bitrate_histogram = self.encoder.bitrate_histogram,
            .quality_misses = self.quality_misses,
            .maximum_noise_to_mask_ratio = self.maximum_noise_to_mask_ratio,
        };
    }

    fn validateState(
        self: VbrPcmAdaptiveReservoirStreamEncoder,
    ) !void {
        if (!self.encoder.valid() or !self.credit.valid() or
            self.pending_length > self.pending_storage.len or
            self.independent_frames > 1 or
            self.frames_received < self.independent_frames or
            self.frames_emitted < self.independent_frames or
            self.credit.frames_committed !=
                self.frames_received - self.independent_frames or
            self.encoder.frames.frames_encoded != self.frames_received or
            self.frames_emitted > self.frames_received or
            self.physical_main_data_bytes <
                self.published_main_data_bytes or
            self.packed_main_data_end >
                self.physical_main_data_bytes or
            self.maximum_backpointer >
                self.credit.maximum_history_bytes or
            self.quality_misses > self.frames_received or
            !std.math.isFinite(self.maximum_noise_to_mask_ratio) or
            self.maximum_noise_to_mask_ratio < 0 or
            !reservoirBorrowedBytesValid(
                self.credit.version,
                self.credit.frames_committed,
                self.borrowed_bytes,
            ) or
            (self.finalized and
                (self.pending_length != 0 or
                    self.frames_emitted != self.frames_received or
                    self.published_main_data_bytes !=
                        self.physical_main_data_bytes)))
            return error.InvalidMp3VbrAdaptiveReservoirState;
        const maximum_config = self.encoder.config.validate() catch
            return error.InvalidMp3VbrAdaptiveReservoirState;
        const header = maximum_config.header(false) catch
            return error.InvalidMp3VbrAdaptiveReservoirState;
        if (self.credit.version != header.version or
            self.credit.sample_rate != header.sample_rate or
            self.credit.channel_count != header.channels())
            return error.InvalidMp3VbrAdaptiveReservoirState;
        const retained_credit = @min(
            self.physical_main_data_bytes -
                self.packed_main_data_end,
            self.credit.maximum_history_bytes,
        );
        if (retained_credit != self.credit.available_history_bytes)
            return error.InvalidMp3VbrAdaptiveReservoirState;

        var pending_offset: usize = 0;
        var pending_frames: u64 = 0;
        var pending_main_data_bytes: u64 = 0;
        while (pending_offset < self.pending_length) {
            const frame = Frame.parse(
                self.pending_storage[0..self.pending_length],
                pending_offset,
            ) catch return error.InvalidMp3VbrAdaptiveReservoirState;
            const index = bitrateIndex(
                frame.header.version,
                frame.header.bitrate_kbps,
            ) orelse return error.InvalidMp3VbrAdaptiveReservoirState;
            if (index < self.encoder.config.minimum_bitrate_index or
                index > self.encoder.config.maximum_bitrate_index)
                return error.InvalidMp3VbrAdaptiveReservoirState;
            var expected_config = self.encoder.config.template;
            expected_config.bitrate_kbps = frame.header.bitrate_kbps;
            const expected = expected_config
                .header(frame.header.padding) catch
                return error.InvalidMp3VbrAdaptiveReservoirState;
            if (!std.meta.eql(expected, frame.header))
                return error.InvalidMp3VbrAdaptiveReservoirState;
            const side = frame.sideInformation() catch
                return error.InvalidMp3VbrAdaptiveReservoirState;
            if (side.main_data_begin >
                self.credit.maximum_history_bytes)
                return error.InvalidMp3VbrAdaptiveReservoirState;
            pending_frames = std.math.add(
                u64,
                pending_frames,
                1,
            ) catch return error.InvalidMp3VbrAdaptiveReservoirState;
            pending_main_data_bytes = std.math.add(
                u64,
                pending_main_data_bytes,
                frame.bytes.len - frameMainDataOffset(frame.header),
            ) catch return error.InvalidMp3VbrAdaptiveReservoirState;
            pending_offset += frame.bytes.len;
        }
        if (pending_offset != self.pending_length or
            pending_frames != self.frames_received - self.frames_emitted or
            pending_main_data_bytes !=
                self.physical_main_data_bytes -
                    self.published_main_data_bytes)
            return error.InvalidMp3VbrAdaptiveReservoirState;
        if (!self.finalized and
            self.published_main_data_bytes >
                self.physical_main_data_bytes -|
                    self.credit.maximum_history_bytes)
            return error.InvalidMp3VbrAdaptiveReservoirState;
    }
};

pub const VbrPcmAdaptiveReservoirGaplessFinish = struct {
    frames: []u8,
    summary: EncoderStreamSummary,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
    bitrate_histogram: [16]u64,
    quality_misses: u64,
    maximum_noise_to_mask_ratio: f32,
};

pub const VbrPcmAdaptiveReservoirGaplessStreamEncoder = struct {
    stream: VbrPcmAdaptiveReservoirStreamEncoder,
    input_samples: u64 = 0,
    metadata_encoder: [9]u8 = default_xing_encoder_identifier,
    metadata_started: bool = false,

    /// Keep `pending_storage` stable until the encoder is no longer used.
    pub fn init(
        config: VbrEncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
    ) !VbrPcmAdaptiveReservoirGaplessStreamEncoder {
        return .{
            .stream = try VbrPcmAdaptiveReservoirStreamEncoder.init(
                config,
                maximum_history_bytes,
                pending_storage,
            ),
        };
    }

    pub fn reset(self: *VbrPcmAdaptiveReservoirGaplessStreamEncoder) void {
        self.stream.reset();
        self.input_samples = 0;
        self.metadata_encoder = default_xing_encoder_identifier;
        self.metadata_started = false;
    }

    pub fn valid(
        self: *const VbrPcmAdaptiveReservoirGaplessStreamEncoder,
    ) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn startMetadata(
        self: *VbrPcmAdaptiveReservoirGaplessStreamEncoder,
        destination: []u8,
        frame_scratch: []u8,
    ) ![]u8 {
        return self.startMetadataWithEncoder(
            default_xing_encoder_identifier,
            destination,
            frame_scratch,
        );
    }

    pub fn startMetadataWithEncoder(
        self: *VbrPcmAdaptiveReservoirGaplessStreamEncoder,
        encoder: [9]u8,
        destination: []u8,
        frame_scratch: []u8,
    ) ![]u8 {
        try self.validate();
        try validateXingEncoderIdentifier(encoder);
        if (self.metadata_started)
            return error.Mp3EncoderMetadataAlreadyStarted;
        const ranges = [_]Mp3StorageRange{
            .{
                .start = @intFromPtr(self.stream.pending_storage.ptr),
                .length = self.stream.pending_storage.len,
            },
            .{ .start = @intFromPtr(destination.ptr), .length = destination.len },
            .{ .start = @intFromPtr(frame_scratch.ptr), .length = frame_scratch.len },
        };
        try validateDisjointMp3Storage(&ranges);

        var metadata_config = self.stream.encoder.config.template;
        const bitrate_index = self.stream.encoder.config.maximum_bitrate_index;
        metadata_config.bitrate_kbps = bitrate(
            metadata_config.version,
            bitrate_index,
        );
        const header = try metadata_config.header(false);
        var metadata_storage: [maximum_encoded_frame_bytes]u8 = undefined;
        const placeholder = try encodeXingFrameFields(
            header,
            .{
                .kind = .variable,
                .frame_count = 0,
                .stream_bytes = 0,
                .toc = @splat(0),
                .quality = 0,
                .encoder_delay = 0,
                .encoder_padding = 0,
                .encoder = encoder,
            },
            &metadata_storage,
        );
        if (destination.len < placeholder.len)
            return error.InsufficientMp3EncoderStorage;

        var next = self.*;
        const discarded = try next.stream.encoder.encodeAtBitrateIndex(
            .{
                .channel_count = @intCast(header.channels()),
                .sample_count = header.samplesPerFrame(),
            },
            frame_scratch,
            bitrate_index,
        );
        if (!std.meta.eql(discarded.header, header) or
            discarded.frame.len != placeholder.len)
            return error.InvalidMp3VbrAdaptiveReservoirState;
        next.stream.frames_received = 1;
        next.stream.frames_emitted = 1;
        next.stream.independent_frames = 1;
        next.metadata_encoder = encoder;
        next.metadata_started = true;
        try next.validate();
        @memcpy(destination[0..placeholder.len], placeholder);
        self.* = next;
        return destination[0..placeholder.len];
    }

    pub fn append(
        self: *VbrPcmAdaptiveReservoirGaplessStreamEncoder,
        pcm: PcmFrame,
        destination: []u8,
        pending_scratch: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
    ) !VbrPcmAdaptiveReservoirAppend {
        try self.validate();
        if (!self.metadata_started)
            return error.Mp3EncoderMetadataNotStarted;
        const next_input_samples = std.math.add(
            u64,
            self.input_samples,
            pcm.sample_count,
        ) catch return error.Mp3SampleCountOverflow;
        const appended = try self.stream.append(
            pcm,
            destination,
            pending_scratch,
            frame_scratch,
            main_data_scratch,
        );
        self.input_samples = next_input_samples;
        return appended;
    }

    /// All six work and output slices must be disjoint. Failure preserves the
    /// encoder, pending bytes, and destination.
    pub fn finish(
        self: *VbrPcmAdaptiveReservoirGaplessStreamEncoder,
        destination: []u8,
        pending_scratch: []u8,
        rollback_storage: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
        output_scratch: []u8,
    ) !VbrPcmAdaptiveReservoirGaplessFinish {
        try self.validate();
        if (!self.metadata_started)
            return error.Mp3EncoderMetadataNotStarted;
        if (self.stream.finalized)
            return self.finishResult(destination[0..0]);
        try validateAdaptiveGaplessFinishStorage(
            self.stream.pending_storage,
            destination,
            pending_scratch,
            rollback_storage,
            frame_scratch,
            main_data_scratch,
            output_scratch,
        );
        if (rollback_storage.len < self.stream.pending_storage.len)
            return error.Mp3AdaptiveReservoirRollbackStorageTooSmall;

        var metadata_config = self.stream.encoder.config.template;
        metadata_config.bitrate_kbps = bitrate(
            metadata_config.version,
            self.stream.encoder.config.maximum_bitrate_index,
        );
        const header = try metadata_config.header(false);
        const flush_frames = try adaptiveGaplessFlushFrames(header);
        const maximum_flush_bytes = std.math.mul(
            usize,
            flush_frames,
            maximum_encoded_frame_bytes,
        ) catch return error.Mp3ByteCountOverflow;
        const required_output = std.math.add(
            usize,
            self.stream.pending_length,
            maximum_flush_bytes,
        ) catch return error.Mp3ByteCountOverflow;
        if (output_scratch.len < required_output)
            return error.InsufficientMp3EncoderStorage;

        @memcpy(
            rollback_storage[0..self.stream.pending_storage.len],
            self.stream.pending_storage,
        );
        errdefer @memcpy(
            self.stream.pending_storage,
            rollback_storage[0..self.stream.pending_storage.len],
        );

        var next = self.*;
        var cursor: usize = 0;
        const silence = PcmFrame{
            .channel_count = @intCast(header.channels()),
            .sample_count = header.samplesPerFrame(),
        };
        for (0..flush_frames) |_| {
            const appended = try next.stream.append(
                silence,
                output_scratch[cursor..],
                pending_scratch,
                frame_scratch,
                main_data_scratch,
            );
            cursor += appended.frames.len;
        }
        const finished = try next.stream.finish(output_scratch[cursor..]);
        cursor += finished.frames.len;
        if (destination.len < cursor)
            return error.InsufficientMp3EncoderStorage;
        const result = try next.finishResult(destination[0..cursor]);
        @memcpy(destination[0..cursor], output_scratch[0..cursor]);
        self.* = next;
        return result;
    }

    pub fn summary(
        self: VbrPcmAdaptiveReservoirGaplessStreamEncoder,
    ) !EncoderStreamSummary {
        try self.validate();
        if (!self.stream.finalized)
            return error.Mp3EncoderStreamIncomplete;
        return self.summaryUnchecked();
    }

    fn summaryUnchecked(
        self: VbrPcmAdaptiveReservoirGaplessStreamEncoder,
    ) !EncoderStreamSummary {
        const reservoir_frames = std.math.cast(
            usize,
            self.stream.credit.frames_committed,
        ) orelse return error.Mp3EncoderFrameCountOverflow;
        const byte_count = std.math.cast(
            usize,
            self.stream.encoder.byte_count,
        ) orelse return error.Mp3ByteCountOverflow;
        var metadata_config = self.stream.encoder.config.template;
        metadata_config.bitrate_kbps = bitrate(
            metadata_config.version,
            self.stream.encoder.config.maximum_bitrate_index,
        );
        return adaptiveGaplessSummary(
            reservoir_frames,
            self.input_samples,
            try metadata_config.header(false),
            byte_count,
        );
    }

    pub fn metadataFrame(
        self: VbrPcmAdaptiveReservoirGaplessStreamEncoder,
        quality: ?u32,
        encoded: []const u8,
        destination: []u8,
    ) ![]u8 {
        const stream_summary = try self.summary();
        if (encoded.len != stream_summary.byte_count)
            return error.InvalidMp3EncoderMetadataCounts;
        const first = try Frame.parse(encoded, 0);
        if (first.xing == null or first.bytes.len >= encoded.len)
            return error.MissingReservedMp3MetadataFrame;
        const toc = try reservoirBatchXingToc(
            encoded[first.bytes.len..],
            first.bytes.len,
            std.math.cast(u32, stream_summary.frame_count) orelse
                return error.Mp3EncoderMetadataFrameCountOverflow,
            std.math.cast(u32, stream_summary.byte_count) orelse
                return error.Mp3EncoderMetadataByteCountOverflow,
        );
        return encodeXingFrameFields(
            first.header,
            .{
                .kind = .variable,
                .frame_count = @intCast(stream_summary.frame_count),
                .stream_bytes = @intCast(stream_summary.byte_count),
                .toc = toc,
                .quality = quality,
                .encoder_delay = try storedXingEncoderDelay(
                    first.header,
                    stream_summary.encoder_delay,
                ),
                .encoder_padding = try storedXingEncoderPadding(
                    stream_summary.end_padding,
                ),
                .encoder = self.metadata_encoder,
            },
            destination,
        );
    }

    fn finishResult(
        self: VbrPcmAdaptiveReservoirGaplessStreamEncoder,
        frames: []u8,
    ) !VbrPcmAdaptiveReservoirGaplessFinish {
        return .{
            .frames = frames,
            .summary = try self.summary(),
            .logical_main_data_bits = self.stream.logical_main_data_bits,
            .borrowed_bytes = self.stream.borrowed_bytes,
            .maximum_backpointer = self.stream.maximum_backpointer,
            .retained_history_bytes = self.stream.credit.available_history_bytes,
            .bitrate_histogram = self.stream.encoder.bitrate_histogram,
            .quality_misses = self.stream.quality_misses,
            .maximum_noise_to_mask_ratio = self.stream.maximum_noise_to_mask_ratio,
        };
    }

    fn validate(
        self: VbrPcmAdaptiveReservoirGaplessStreamEncoder,
    ) !void {
        self.stream.validateState() catch
            return error.InvalidMp3VbrAdaptiveReservoirGaplessState;
        if (!isValidXingEncoderIdentifier(self.metadata_encoder) or
            self.metadata_started != (self.stream.independent_frames == 1))
            return error.InvalidMp3VbrAdaptiveReservoirGaplessState;
        if (!self.metadata_started) {
            if (self.input_samples != 0 or
                self.stream.frames_received != 0)
                return error.InvalidMp3VbrAdaptiveReservoirGaplessState;
            return;
        }
        var metadata_config = self.stream.encoder.config.template;
        metadata_config.bitrate_kbps = bitrate(
            metadata_config.version,
            self.stream.encoder.config.maximum_bitrate_index,
        );
        const header = metadata_config.header(false) catch
            return error.InvalidMp3VbrAdaptiveReservoirGaplessState;
        const flush_frames: u64 = if (self.stream.finalized)
            adaptiveGaplessFlushFrames(header) catch
                return error.InvalidMp3VbrAdaptiveReservoirGaplessState
        else
            0;
        if (self.stream.credit.frames_committed < flush_frames or
            self.stream.quality_misses > self.stream.credit.frames_committed)
            return error.InvalidMp3VbrAdaptiveReservoirGaplessState;
        const input_frames = self.stream.credit.frames_committed - flush_frames;
        const expected_input = std.math.mul(
            u64,
            input_frames,
            header.samplesPerFrame(),
        ) catch return error.InvalidMp3VbrAdaptiveReservoirGaplessState;
        if (self.input_samples != expected_input)
            return error.InvalidMp3VbrAdaptiveReservoirGaplessState;
        if (self.stream.finalized)
            _ = self.summaryUnchecked() catch
                return error.InvalidMp3VbrAdaptiveReservoirGaplessState;
    }
};

pub const VbrPcmAdaptiveReservoirFileSummary = struct {
    frame_count: u64,
    byte_count: u64,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
    bitrate_histogram: [16]u64,
    quality_misses: u64,
    maximum_noise_to_mask_ratio: f32,
    file_end: u64,
};

pub const VbrPcmAdaptiveReservoirFileEncoder = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    stream: VbrPcmAdaptiveReservoirStreamEncoder,
    pending_scratch: []u8,
    rollback_storage: []u8,
    frame_scratch: []u8,
    main_data_scratch: []u8,
    output_storage: []u8,
    audio_offset: u64 = 0,
    committed_bytes: u64 = 0,
    failed: bool = false,
    finalized: bool = false,

    /// All storage slices must remain stable for the encoder lifetime.
    pub fn init(
        io: std.Io,
        file: std.Io.File,
        config: VbrEncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
        pending_scratch: []u8,
        rollback_storage: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
        output_storage: []u8,
    ) !VbrPcmAdaptiveReservoirFileEncoder {
        return initAtWithOperations(
            io,
            file,
            config,
            maximum_history_bytes,
            pending_storage,
            pending_scratch,
            rollback_storage,
            frame_scratch,
            main_data_scratch,
            output_storage,
            0,
            .{},
        );
    }

    pub fn initAtWithOperations(
        io: std.Io,
        file: std.Io.File,
        config: VbrEncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
        pending_scratch: []u8,
        rollback_storage: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
        output_storage: []u8,
        audio_offset: u64,
        operations: file_writer_io.Operations,
    ) !VbrPcmAdaptiveReservoirFileEncoder {
        const required = try requiredVbrPcmAdaptiveReservoirStorage(
            config,
            maximum_history_bytes,
        );
        try validateAdaptiveReservoirFileStorage(
            pending_storage,
            pending_scratch,
            rollback_storage,
            frame_scratch,
            main_data_scratch,
            output_storage,
            required,
        );
        return .{
            .io = io,
            .file = file,
            .operations = operations,
            .stream = try VbrPcmAdaptiveReservoirStreamEncoder.init(
                config,
                maximum_history_bytes,
                pending_storage,
            ),
            .pending_scratch = pending_scratch,
            .rollback_storage = rollback_storage,
            .frame_scratch = frame_scratch,
            .main_data_scratch = main_data_scratch,
            .output_storage = output_storage,
            .audio_offset = audio_offset,
        };
    }

    pub fn valid(self: *const VbrPcmAdaptiveReservoirFileEncoder) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn append(
        self: *VbrPcmAdaptiveReservoirFileEncoder,
        pcm: PcmFrame,
    ) !VbrPcmAdaptiveReservoirAppend {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3VbrAdaptiveReservoirFileEncoderState;
        const write_offset = try fileEncoderOffset(
            self.audio_offset,
            self.committed_bytes,
        );
        const before = self.stream;
        @memcpy(
            self.rollback_storage[0..before.pending_storage.len],
            before.pending_storage,
        );
        const appended = try self.stream.append(
            pcm,
            self.output_storage,
            self.pending_scratch,
            self.frame_scratch,
            self.main_data_scratch,
        );
        const next_committed = std.math.add(
            u64,
            self.committed_bytes,
            appended.frames.len,
        ) catch {
            self.restoreStream(before);
            return error.Mp3ByteCountOverflow;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            write_offset,
            appended.frames,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next_committed;
        return appended;
    }

    pub fn finalize(
        self: *VbrPcmAdaptiveReservoirFileEncoder,
    ) !VbrPcmAdaptiveReservoirFileSummary {
        try self.validate();
        if (self.finalized) return self.summary();
        if (self.failed)
            return error.InvalidMp3VbrAdaptiveReservoirFileEncoderState;
        const write_offset = try fileEncoderOffset(
            self.audio_offset,
            self.committed_bytes,
        );
        const before = self.stream;
        @memcpy(
            self.rollback_storage[0..before.pending_storage.len],
            before.pending_storage,
        );
        const finished = try self.stream.finish(self.output_storage);
        const next_committed = std.math.add(
            u64,
            self.committed_bytes,
            finished.frames.len,
        ) catch {
            self.restoreStream(before);
            return error.Mp3ByteCountOverflow;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            write_offset,
            finished.frames,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.operations.sync(self.io, self.file) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next_committed;
        self.finalized = true;
        return self.summary();
    }

    pub fn recover(
        self: *VbrPcmAdaptiveReservoirFileEncoder,
    ) !void {
        try self.validate();
        if (self.finalized)
            return error.InvalidMp3VbrAdaptiveReservoirFileEncoderState;
        try file_writer_io.Checkpoint.exact(
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        ).restore(self.operations, self.io, self.file);
        self.failed = false;
    }

    fn restoreStream(
        self: *VbrPcmAdaptiveReservoirFileEncoder,
        before: VbrPcmAdaptiveReservoirStreamEncoder,
    ) void {
        @memcpy(
            before.pending_storage,
            self.rollback_storage[0..before.pending_storage.len],
        );
        self.stream = before;
    }

    fn summary(
        self: VbrPcmAdaptiveReservoirFileEncoder,
    ) !VbrPcmAdaptiveReservoirFileSummary {
        return .{
            .frame_count = self.stream.frames_received,
            .byte_count = self.stream.encoder.byte_count,
            .logical_main_data_bits = self.stream.logical_main_data_bits,
            .borrowed_bytes = self.stream.borrowed_bytes,
            .maximum_backpointer = self.stream.maximum_backpointer,
            .retained_history_bytes = self.stream.credit.available_history_bytes,
            .bitrate_histogram = self.stream.encoder.bitrate_histogram,
            .quality_misses = self.stream.quality_misses,
            .maximum_noise_to_mask_ratio = self.stream.maximum_noise_to_mask_ratio,
            .file_end = try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        };
    }

    fn validate(self: VbrPcmAdaptiveReservoirFileEncoder) !void {
        if (!self.stream.valid() or
            self.finalized != self.stream.finalized or
            self.stream.encoder.byte_count < self.stream.pending_length or
            self.committed_bytes !=
                self.stream.encoder.byte_count - self.stream.pending_length)
            return error.InvalidMp3VbrAdaptiveReservoirFileEncoderState;
        try validateAdaptiveReservoirFileStorage(
            self.stream.pending_storage,
            self.pending_scratch,
            self.rollback_storage,
            self.frame_scratch,
            self.main_data_scratch,
            self.output_storage,
            self.stream.pending_storage.len,
        );
    }
};

pub const VbrPcmAdaptiveReservoirGaplessFileSummary = struct {
    stream: EncoderStreamSummary,
    logical_main_data_bits: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
    retained_history_bytes: u16,
    bitrate_histogram: [16]u64,
    quality_misses: u64,
    maximum_noise_to_mask_ratio: f32,
    file_end: u64,
};

pub const VbrPcmAdaptiveReservoirGaplessFileEncoder = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    stream: VbrPcmAdaptiveReservoirGaplessStreamEncoder,
    pending_scratch: []u8,
    rollback_storage: []u8,
    frame_scratch: []u8,
    main_data_scratch: []u8,
    output_storage: []u8,
    finish_storage: []u8,
    frame_offsets: []u64,
    audio_offset: u64 = 0,
    committed_bytes: u64 = 0,
    indexed_frames: usize = 0,
    failed: bool = false,
    finalized: bool = false,

    /// Keep byte storage stable. Replace frame offsets only through
    /// `replaceFrameOffsetStorage`.
    pub fn init(
        io: std.Io,
        file: std.Io.File,
        config: VbrEncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
        pending_scratch: []u8,
        rollback_storage: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
        output_storage: []u8,
        finish_storage: []u8,
        frame_offsets: []u64,
    ) !VbrPcmAdaptiveReservoirGaplessFileEncoder {
        return initAtWithOperations(
            io,
            file,
            config,
            maximum_history_bytes,
            pending_storage,
            pending_scratch,
            rollback_storage,
            frame_scratch,
            main_data_scratch,
            output_storage,
            finish_storage,
            frame_offsets,
            0,
            .{},
        );
    }

    pub fn initAtWithOperations(
        io: std.Io,
        file: std.Io.File,
        config: VbrEncoderConfig,
        maximum_history_bytes: u16,
        pending_storage: []u8,
        pending_scratch: []u8,
        rollback_storage: []u8,
        frame_scratch: []u8,
        main_data_scratch: []u8,
        output_storage: []u8,
        finish_storage: []u8,
        frame_offsets: []u64,
        audio_offset: u64,
        operations: file_writer_io.Operations,
    ) !VbrPcmAdaptiveReservoirGaplessFileEncoder {
        const required = try requiredVbrPcmAdaptiveReservoirStorage(
            config,
            maximum_history_bytes,
        );
        var metadata_config = config.template;
        metadata_config.bitrate_kbps = bitrate(
            metadata_config.version,
            config.maximum_bitrate_index,
        );
        const finish_required = try requiredAdaptiveGaplessFileFinishStorage(
            try metadata_config.header(false),
            required,
        );
        try validateAdaptiveGaplessFileStorage(
            pending_storage,
            pending_scratch,
            rollback_storage,
            frame_scratch,
            main_data_scratch,
            output_storage,
            finish_storage,
            required,
            finish_required,
        );
        if (frame_offsets.len == 0)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        try validateMp3FrameOffsetStorage(
            frame_offsets,
            &.{
                pending_storage,
                pending_scratch,
                rollback_storage,
                frame_scratch,
                main_data_scratch,
                output_storage,
                finish_storage,
            },
        );
        return .{
            .io = io,
            .file = file,
            .operations = operations,
            .stream = try VbrPcmAdaptiveReservoirGaplessStreamEncoder.init(
                config,
                maximum_history_bytes,
                pending_storage,
            ),
            .pending_scratch = pending_scratch,
            .rollback_storage = rollback_storage,
            .frame_scratch = frame_scratch,
            .main_data_scratch = main_data_scratch,
            .output_storage = output_storage,
            .finish_storage = finish_storage,
            .frame_offsets = frame_offsets,
            .audio_offset = audio_offset,
        };
    }

    pub fn valid(
        self: *const VbrPcmAdaptiveReservoirGaplessFileEncoder,
    ) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn startMetadata(
        self: *VbrPcmAdaptiveReservoirGaplessFileEncoder,
    ) ![]u8 {
        return self.startMetadataWithEncoder(
            default_xing_encoder_identifier,
        );
    }

    pub fn startMetadataWithEncoder(
        self: *VbrPcmAdaptiveReservoirGaplessFileEncoder,
        encoder: [9]u8,
    ) ![]u8 {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3VbrAdaptiveReservoirGaplessFileEncoderState;
        const before = self.stream;
        @memcpy(
            self.rollback_storage[0..before.stream.pending_storage.len],
            before.stream.pending_storage,
        );
        const metadata = try self.stream.startMetadataWithEncoder(
            encoder,
            self.output_storage,
            self.frame_scratch,
        );
        const next_committed = std.math.add(
            u64,
            self.committed_bytes,
            metadata.len,
        ) catch {
            self.restoreStream(before);
            return error.Mp3ByteCountOverflow;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            self.audio_offset,
            metadata,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.frame_offsets[0] = 0;
        self.indexed_frames = 1;
        self.committed_bytes = next_committed;
        return metadata;
    }

    pub fn append(
        self: *VbrPcmAdaptiveReservoirGaplessFileEncoder,
        pcm: PcmFrame,
    ) !VbrPcmAdaptiveReservoirAppend {
        try self.validate();
        if (self.failed or self.finalized or !self.stream.metadata_started)
            return error.InvalidMp3VbrAdaptiveReservoirGaplessFileEncoderState;
        const write_offset = try fileEncoderOffset(
            self.audio_offset,
            self.committed_bytes,
        );
        const before = self.stream;
        @memcpy(
            self.rollback_storage[0..before.stream.pending_storage.len],
            before.stream.pending_storage,
        );
        const appended = try self.stream.append(
            pcm,
            self.output_storage,
            self.pending_scratch,
            self.frame_scratch,
            self.main_data_scratch,
        );
        const next_indexed = recordMp3FileFrameOffsets(
            appended.frames,
            self.committed_bytes,
            self.frame_offsets,
            self.indexed_frames,
        ) catch |failure| {
            self.restoreStream(before);
            return failure;
        };
        const next_committed = std.math.add(
            u64,
            self.committed_bytes,
            appended.frames.len,
        ) catch {
            self.restoreStream(before);
            return error.Mp3ByteCountOverflow;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            write_offset,
            appended.frames,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.indexed_frames = next_indexed;
        self.committed_bytes = next_committed;
        return appended;
    }

    pub fn finalize(
        self: *VbrPcmAdaptiveReservoirGaplessFileEncoder,
        quality: ?u32,
    ) !VbrPcmAdaptiveReservoirGaplessFileSummary {
        try self.validate();
        if (self.finalized) return self.summary();
        if (self.failed or !self.stream.metadata_started)
            return error.InvalidMp3VbrAdaptiveReservoirGaplessFileEncoderState;
        const write_offset = try fileEncoderOffset(
            self.audio_offset,
            self.committed_bytes,
        );
        const before = self.stream;
        const finished = try self.stream.finish(
            self.output_storage,
            self.pending_scratch,
            self.rollback_storage,
            self.frame_scratch,
            self.main_data_scratch,
            self.finish_storage,
        );
        const next_indexed = recordMp3FileFrameOffsets(
            finished.frames,
            self.committed_bytes,
            self.frame_offsets,
            self.indexed_frames,
        ) catch |failure| {
            self.restoreStream(before);
            return failure;
        };
        const next_committed = std.math.add(
            u64,
            self.committed_bytes,
            finished.frames.len,
        ) catch {
            self.restoreStream(before);
            return error.Mp3ByteCountOverflow;
        };
        const metadata = self.finalMetadata(
            quality,
            next_indexed,
            next_committed,
        ) catch |failure| {
            self.restoreStream(before);
            return failure;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            write_offset,
            finished.frames,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.operations.writeAt(
            self.io,
            self.file,
            self.audio_offset,
            metadata,
        ) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.operations.sync(self.io, self.file) catch |failure| {
            self.restoreStream(before);
            self.failed = true;
            return failure;
        };
        self.indexed_frames = next_indexed;
        self.committed_bytes = next_committed;
        self.finalized = true;
        return self.summary();
    }

    pub fn recover(
        self: *VbrPcmAdaptiveReservoirGaplessFileEncoder,
    ) !void {
        try self.validate();
        if (self.finalized)
            return error.InvalidMp3VbrAdaptiveReservoirGaplessFileEncoderState;
        try file_writer_io.Checkpoint.exact(
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        ).restore(self.operations, self.io, self.file);
        if (self.stream.metadata_started) {
            const metadata = try self.placeholderMetadata();
            try self.operations.writeAt(
                self.io,
                self.file,
                self.audio_offset,
                metadata,
            );
        }
        self.failed = false;
    }

    pub fn replaceFrameOffsetStorage(
        self: *VbrPcmAdaptiveReservoirGaplessFileEncoder,
        storage: []u64,
    ) !void {
        try self.validate();
        if (storage.len < self.indexed_frames)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        try validateMp3FrameOffsetStorage(
            storage,
            &.{
                self.stream.stream.pending_storage,
                self.pending_scratch,
                self.rollback_storage,
                self.frame_scratch,
                self.main_data_scratch,
                self.output_storage,
                self.finish_storage,
            },
        );
        if (storage.ptr != self.frame_offsets.ptr and
            try mp3FrameOffsetSlicesOverlap(storage, self.frame_offsets))
            return error.OverlappingMp3VbrStorage;
        if (storage.ptr != self.frame_offsets.ptr)
            @memcpy(
                storage[0..self.indexed_frames],
                self.frame_offsets[0..self.indexed_frames],
            );
        var next = self.*;
        next.frame_offsets = storage;
        try next.validate();
        self.* = next;
    }

    fn metadataHeader(
        self: VbrPcmAdaptiveReservoirGaplessFileEncoder,
    ) !Header {
        var config = self.stream.stream.encoder.config.template;
        config.bitrate_kbps = bitrate(
            config.version,
            self.stream.stream.encoder.config.maximum_bitrate_index,
        );
        return config.header(false);
    }

    fn placeholderMetadata(
        self: VbrPcmAdaptiveReservoirGaplessFileEncoder,
    ) ![]u8 {
        return encodeXingFrameFields(
            try self.metadataHeader(),
            .{
                .kind = .variable,
                .frame_count = 0,
                .stream_bytes = 0,
                .toc = @splat(0),
                .quality = 0,
                .encoder_delay = 0,
                .encoder_padding = 0,
                .encoder = self.stream.metadata_encoder,
            },
            self.output_storage,
        );
    }

    fn finalMetadata(
        self: VbrPcmAdaptiveReservoirGaplessFileEncoder,
        quality: ?u32,
        frame_count: usize,
        byte_count: u64,
    ) ![]u8 {
        const stream_summary = try self.stream.summary();
        if (frame_count != stream_summary.frame_count or
            byte_count != stream_summary.byte_count)
            return error.InvalidMp3EncoderMetadataCounts;
        const frame_count_u32 = std.math.cast(u32, frame_count) orelse
            return error.Mp3EncoderMetadataFrameCountOverflow;
        const byte_count_u32 = std.math.cast(u32, byte_count) orelse
            return error.Mp3EncoderMetadataByteCountOverflow;
        return encodeXingFrameFields(
            try self.metadataHeader(),
            .{
                .kind = .variable,
                .frame_count = frame_count_u32,
                .stream_bytes = byte_count_u32,
                .toc = try xingTocFromFrameOffsets(
                    self.frame_offsets[0..frame_count],
                    byte_count_u32,
                ),
                .quality = quality,
                .encoder_delay = try storedXingEncoderDelay(
                    try self.metadataHeader(),
                    stream_summary.encoder_delay,
                ),
                .encoder_padding = try storedXingEncoderPadding(
                    stream_summary.end_padding,
                ),
                .encoder = self.stream.metadata_encoder,
            },
            self.frame_scratch,
        );
    }

    fn restoreStream(
        self: *VbrPcmAdaptiveReservoirGaplessFileEncoder,
        before: VbrPcmAdaptiveReservoirGaplessStreamEncoder,
    ) void {
        @memcpy(
            before.stream.pending_storage,
            self.rollback_storage[0..before.stream.pending_storage.len],
        );
        self.stream = before;
    }

    fn summary(
        self: VbrPcmAdaptiveReservoirGaplessFileEncoder,
    ) !VbrPcmAdaptiveReservoirGaplessFileSummary {
        return .{
            .stream = try self.stream.summary(),
            .logical_main_data_bits = self.stream.stream.logical_main_data_bits,
            .borrowed_bytes = self.stream.stream.borrowed_bytes,
            .maximum_backpointer = self.stream.stream.maximum_backpointer,
            .retained_history_bytes = self.stream.stream.credit.available_history_bytes,
            .bitrate_histogram = self.stream.stream.encoder.bitrate_histogram,
            .quality_misses = self.stream.stream.quality_misses,
            .maximum_noise_to_mask_ratio = self.stream.stream.maximum_noise_to_mask_ratio,
            .file_end = try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        };
    }

    fn validate(self: VbrPcmAdaptiveReservoirGaplessFileEncoder) !void {
        if (!self.stream.valid() or
            self.finalized != self.stream.stream.finalized or
            self.stream.stream.encoder.byte_count <
                self.stream.stream.pending_length or
            self.committed_bytes !=
                self.stream.stream.encoder.byte_count -
                    self.stream.stream.pending_length or
            self.indexed_frames != self.stream.stream.frames_emitted or
            self.indexed_frames > self.frame_offsets.len)
            return error.InvalidMp3VbrAdaptiveReservoirGaplessFileEncoderState;
        validateIndexedMp3FrameOffsets(
            self.frame_offsets[0..self.indexed_frames],
            self.committed_bytes,
        ) catch
            return error.InvalidMp3VbrAdaptiveReservoirGaplessFileEncoderState;
        validateIndexedVbrFrameSpans(
            self.stream.stream.encoder.config,
            self.frame_offsets[0..self.indexed_frames],
            self.committed_bytes,
        ) catch
            return error.InvalidMp3VbrAdaptiveReservoirGaplessFileEncoderState;
        const required = requiredVbrPcmAdaptiveReservoirStorage(
            self.stream.stream.encoder.config,
            self.stream.stream.credit.maximum_history_bytes,
        ) catch return error.InvalidMp3VbrAdaptiveReservoirGaplessFileEncoderState;
        const finish_required = try requiredAdaptiveGaplessFileFinishStorage(
            self.metadataHeader() catch
                return error.InvalidMp3VbrAdaptiveReservoirGaplessFileEncoderState,
            required,
        );
        try validateAdaptiveGaplessFileStorage(
            self.stream.stream.pending_storage,
            self.pending_scratch,
            self.rollback_storage,
            self.frame_scratch,
            self.main_data_scratch,
            self.output_storage,
            self.finish_storage,
            required,
            finish_required,
        );
        try validateMp3FrameOffsetStorage(
            self.frame_offsets,
            &.{
                self.stream.stream.pending_storage,
                self.pending_scratch,
                self.rollback_storage,
                self.frame_scratch,
                self.main_data_scratch,
                self.output_storage,
                self.finish_storage,
            },
        );
    }
};

pub fn validateMp3FrameOffsetStorage(
    frame_offsets: []const u64,
    byte_storage: []const []const u8,
) !void {
    const offset_bytes = std.math.mul(
        usize,
        frame_offsets.len,
        @sizeOf(u64),
    ) catch return error.OverlappingMp3VbrStorage;
    for (byte_storage) |storage| {
        if (byteRangesOverlap(
            @intFromPtr(frame_offsets.ptr),
            offset_bytes,
            @intFromPtr(storage.ptr),
            storage.len,
        )) return error.OverlappingMp3VbrStorage;
    }
}

pub fn mp3FrameOffsetSlicesOverlap(
    left: []const u64,
    right: []const u64,
) !bool {
    const left_bytes = std.math.mul(
        usize,
        left.len,
        @sizeOf(u64),
    ) catch return error.OverlappingMp3VbrStorage;
    const right_bytes = std.math.mul(
        usize,
        right.len,
        @sizeOf(u64),
    ) catch return error.OverlappingMp3VbrStorage;
    return byteRangesOverlap(
        @intFromPtr(left.ptr),
        left_bytes,
        @intFromPtr(right.ptr),
        right_bytes,
    );
}

pub fn validateIndexedMp3FrameOffsets(
    frame_offsets: []const u64,
    committed_bytes: u64,
) !void {
    if (frame_offsets.len == 0) {
        if (committed_bytes != 0)
            return error.InvalidMp3VbrFrameOffsets;
        return;
    }
    if (frame_offsets[0] != 0 or committed_bytes == 0)
        return error.InvalidMp3VbrFrameOffsets;
    var previous: u64 = 0;
    for (frame_offsets[1..]) |offset| {
        if (offset <= previous or offset >= committed_bytes)
            return error.InvalidMp3VbrFrameOffsets;
        previous = offset;
    }
}

pub fn validateIndexedVbrFrameSpans(
    config: VbrEncoderConfig,
    frame_offsets: []const u64,
    committed_bytes: u64,
) !void {
    if (frame_offsets.len == 0) return;
    const maximum_config = try config.validate();
    const metadata_bytes = (try maximum_config.header(false)).frameBytes();
    const first_end = if (frame_offsets.len == 1)
        committed_bytes
    else
        frame_offsets[1];
    if (first_end != metadata_bytes)
        return error.InvalidMp3VbrFrameOffsets;

    for (frame_offsets[1..], 1..) |offset, index| {
        const end = if (index + 1 == frame_offsets.len)
            committed_bytes
        else
            frame_offsets[index + 1];
        const frame_bytes = end - offset;
        var bitrate_index: u5 = config.minimum_bitrate_index;
        var matched = false;
        while (bitrate_index <= config.maximum_bitrate_index) : (bitrate_index += 1) {
            var frame_config = config.template;
            frame_config.bitrate_kbps = bitrate(
                frame_config.version,
                @intCast(bitrate_index),
            );
            if ((try frame_config.header(false)).frameBytes() == frame_bytes or
                (try frame_config.header(true)).frameBytes() == frame_bytes)
            {
                matched = true;
                break;
            }
        }
        if (!matched) return error.InvalidMp3VbrFrameOffsets;
    }
}

pub fn recordMp3FileFrameOffsets(
    encoded: []const u8,
    base_offset: u64,
    frame_offsets: []u64,
    start_index: usize,
) !usize {
    if (encoded.len == 0) return start_index;
    var stream = try Stream.init(encoded);
    var index = start_index;
    while (try stream.next()) |frame| {
        if (index >= frame_offsets.len)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        frame_offsets[index] = std.math.add(
            u64,
            base_offset,
            frame.offset,
        ) catch return error.Mp3ByteCountOverflow;
        index += 1;
    }
    return index;
}

pub fn xingTocFromFrameOffsets(
    frame_offsets: []const u64,
    stream_bytes: u32,
) ![100]u8 {
    if (frame_offsets.len == 0 or stream_bytes == 0)
        return error.InvalidMp3EncoderMetadataCounts;
    var toc: [100]u8 = undefined;
    for (&toc, 0..) |*entry, percent| {
        const selected = @min(
            (@as(u64, percent) * frame_offsets.len) / 100,
            frame_offsets.len - 1,
        );
        const scaled = (@as(u128, frame_offsets[selected]) * 256) /
            stream_bytes;
        entry.* = @intCast(@min(scaled, 255));
    }
    return toc;
}

pub const PcmReservoirBatchFileResult = struct {
    batch: PcmReservoirBatchResult,
    metadata_bytes: u16 = 0,
    file_end: u64,
};

pub const VbrPcmReservoirBatchFileResult = struct {
    batch: VbrPcmReservoirBatchResult,
    metadata_bytes: u16 = 0,
    file_end: u64,
};

pub const PcmReservoirGaplessBatchFileResult = struct {
    batch: PcmReservoirGaplessBatchResult,
    file_end: u64,
};

pub const VbrPcmReservoirGaplessBatchFileResult = struct {
    batch: VbrPcmReservoirGaplessBatchResult,
    file_end: u64,
};

pub fn writePcmReservoirGaplessBatchFile(
    io: std.Io,
    file: std.Io.File,
    config: EncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    encoder_identifier: [9]u8,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    metadata_scratch: []u8,
) !PcmReservoirGaplessBatchFileResult {
    return writePcmReservoirGaplessBatchFileWithOperations(
        io,
        file,
        config,
        pcm_frames,
        maximum_history_bytes,
        audio_offset,
        encoder_identifier,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
        metadata_scratch,
        .{},
    );
}

pub fn writePcmReservoirGaplessBatchFileWithOperations(
    io: std.Io,
    file: std.Io.File,
    config: EncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    encoder_identifier: [9]u8,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    metadata_scratch: []u8,
    operations: file_writer_io.Operations,
) !PcmReservoirGaplessBatchFileResult {
    const batch = try encodePcmReservoirGaplessBatch(
        config,
        pcm_frames,
        maximum_history_bytes,
        encoder_identifier,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
        metadata_scratch,
    );
    return .{
        .batch = batch,
        .file_end = try writeReservoirBatchBytes(
            io,
            file,
            audio_offset,
            batch.stream,
            operations,
        ),
    };
}

pub fn writeVbrPcmReservoirGaplessBatchFile(
    io: std.Io,
    file: std.Io.File,
    config: VbrEncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    quality: ?u32,
    encoder_identifier: [9]u8,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    metadata_scratch: []u8,
) !VbrPcmReservoirGaplessBatchFileResult {
    return writeVbrPcmReservoirGaplessBatchFileWithOperations(
        io,
        file,
        config,
        pcm_frames,
        maximum_history_bytes,
        audio_offset,
        quality,
        encoder_identifier,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
        metadata_scratch,
        .{},
    );
}

pub fn writeVbrPcmReservoirGaplessBatchFileWithOperations(
    io: std.Io,
    file: std.Io.File,
    config: VbrEncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    quality: ?u32,
    encoder_identifier: [9]u8,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    metadata_scratch: []u8,
    operations: file_writer_io.Operations,
) !VbrPcmReservoirGaplessBatchFileResult {
    const batch = try encodeVbrPcmReservoirGaplessBatch(
        config,
        pcm_frames,
        maximum_history_bytes,
        quality,
        encoder_identifier,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
        metadata_scratch,
    );
    return .{
        .batch = batch,
        .file_end = try writeReservoirBatchBytes(
            io,
            file,
            audio_offset,
            batch.stream,
            operations,
        ),
    };
}

pub fn writePcmReservoirBatchFile(
    io: std.Io,
    file: std.Io.File,
    config: EncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
) !PcmReservoirBatchFileResult {
    return writePcmReservoirBatchFileWithOperations(
        io,
        file,
        config,
        pcm_frames,
        maximum_history_bytes,
        audio_offset,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
        .{},
    );
}

pub fn writePcmReservoirBatchFileWithOperations(
    io: std.Io,
    file: std.Io.File,
    config: EncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    operations: file_writer_io.Operations,
) !PcmReservoirBatchFileResult {
    const batch = try encodePcmReservoirBatch(
        config,
        pcm_frames,
        maximum_history_bytes,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
    );
    return .{
        .batch = batch,
        .file_end = try writeReservoirBatchBytes(
            io,
            file,
            audio_offset,
            batch.stream,
            operations,
        ),
    };
}

pub fn writeVbrPcmReservoirBatchFile(
    io: std.Io,
    file: std.Io.File,
    config: VbrEncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
) !VbrPcmReservoirBatchFileResult {
    return writeVbrPcmReservoirBatchFileWithOperations(
        io,
        file,
        config,
        pcm_frames,
        maximum_history_bytes,
        audio_offset,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
        .{},
    );
}

pub fn writeVbrPcmReservoirBatchFileWithOperations(
    io: std.Io,
    file: std.Io.File,
    config: VbrEncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    operations: file_writer_io.Operations,
) !VbrPcmReservoirBatchFileResult {
    const batch = try encodeVbrPcmReservoirBatch(
        config,
        pcm_frames,
        maximum_history_bytes,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
    );
    return .{
        .batch = batch,
        .file_end = try writeReservoirBatchBytes(
            io,
            file,
            audio_offset,
            batch.stream,
            operations,
        ),
    };
}

/// Prepends Info counts without asserting encoder delay or end padding.
pub fn writePcmReservoirBatchFileWithInfo(
    io: std.Io,
    file: std.Io.File,
    config: EncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    encoder: [9]u8,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    metadata_scratch: []u8,
) !PcmReservoirBatchFileResult {
    return writePcmReservoirBatchFileWithInfoAndOperations(
        io,
        file,
        config,
        pcm_frames,
        maximum_history_bytes,
        audio_offset,
        encoder,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
        metadata_scratch,
        .{},
    );
}

pub fn writePcmReservoirBatchFileWithInfoAndOperations(
    io: std.Io,
    file: std.Io.File,
    config: EncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    encoder: [9]u8,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    metadata_scratch: []u8,
    operations: file_writer_io.Operations,
) !PcmReservoirBatchFileResult {
    const batch = try encodePcmReservoirBatch(
        config,
        pcm_frames,
        maximum_history_bytes,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
    );
    const header = try config.header(false);
    const frame_count = std.math.add(
        u64,
        batch.frame_count,
        1,
    ) catch return error.Mp3EncoderMetadataFrameCountOverflow;
    if (frame_count > std.math.maxInt(u32))
        return error.Mp3EncoderMetadataFrameCountOverflow;
    const stream_bytes = std.math.add(
        usize,
        header.frameBytes(),
        batch.stream.len,
    ) catch return error.Mp3EncoderMetadataByteCountOverflow;
    if (stream_bytes > std.math.maxInt(u32))
        return error.Mp3EncoderMetadataByteCountOverflow;
    const metadata = try encodeXingFrameFields(
        header,
        .{
            .kind = .constant,
            .frame_count = @intCast(frame_count),
            .stream_bytes = @intCast(stream_bytes),
            .encoder_delay = 0,
            .encoder_padding = 0,
            .encoder = encoder,
        },
        metadata_scratch,
    );
    return .{
        .batch = batch,
        .metadata_bytes = @intCast(metadata.len),
        .file_end = try writeReservoirBatchFileBytes(
            io,
            file,
            audio_offset,
            metadata,
            batch.stream,
            operations,
        ),
    };
}

/// Prepends Xing counts and a seek table without asserting gapless trims.
pub fn writeVbrPcmReservoirBatchFileWithXing(
    io: std.Io,
    file: std.Io.File,
    config: VbrEncoderConfig,
    pcm_frames: []const PcmFrame,
    maximum_history_bytes: u16,
    audio_offset: u64,
    quality: ?u32,
    encoder: [9]u8,
    destination: []u8,
    frame_scratch: []u8,
    pack_scratch: []u8,
    main_data_scratch: []u8,
    metadata_scratch: []u8,
) !VbrPcmReservoirBatchFileResult {
    const batch = try encodeVbrPcmReservoirBatch(
        config,
        pcm_frames,
        maximum_history_bytes,
        destination,
        frame_scratch,
        pack_scratch,
        main_data_scratch,
    );
    const frame_count = std.math.add(
        u64,
        batch.frame_count,
        1,
    ) catch return error.Mp3EncoderMetadataFrameCountOverflow;
    if (frame_count > std.math.maxInt(u32))
        return error.Mp3EncoderMetadataFrameCountOverflow;
    var metadata_config = config.template;
    metadata_config.bitrate_kbps = bitrate(
        metadata_config.version,
        config.maximum_bitrate_index,
    );
    const header = try metadata_config.header(false);
    const stream_bytes = std.math.add(
        usize,
        header.frameBytes(),
        batch.stream.len,
    ) catch return error.Mp3EncoderMetadataByteCountOverflow;
    if (stream_bytes > std.math.maxInt(u32))
        return error.Mp3EncoderMetadataByteCountOverflow;
    const toc = try reservoirBatchXingToc(
        batch.stream,
        header.frameBytes(),
        @intCast(frame_count),
        @intCast(stream_bytes),
    );
    const metadata = try encodeXingFrameFields(
        header,
        .{
            .kind = .variable,
            .frame_count = @intCast(frame_count),
            .stream_bytes = @intCast(stream_bytes),
            .toc = toc,
            .quality = quality,
            .encoder_delay = 0,
            .encoder_padding = 0,
            .encoder = encoder,
        },
        metadata_scratch,
    );
    return .{
        .batch = batch,
        .metadata_bytes = @intCast(metadata.len),
        .file_end = try writeReservoirBatchFileBytes(
            io,
            file,
            audio_offset,
            metadata,
            batch.stream,
            .{},
        ),
    };
}

pub fn reservoirBatchXingToc(
    encoded: []const u8,
    metadata_bytes: usize,
    frame_count: u32,
    stream_bytes: u32,
) ![100]u8 {
    if (frame_count == 0 or stream_bytes == 0)
        return error.InvalidMp3EncoderMetadataCounts;
    var toc: [100]u8 = undefined;
    var stream = try Stream.init(encoded);
    var audio_offset: usize = 0;
    var percent: usize = 0;
    for (0..frame_count) |frame_index| {
        const offset = if (frame_index == 0)
            0
        else
            try std.math.add(
                usize,
                metadata_bytes,
                audio_offset,
            );
        while (percent < toc.len) {
            const selected = @min(
                (@as(u64, percent) * frame_count) / 100,
                frame_count - 1,
            );
            if (selected != frame_index) break;
            const scaled = (@as(u128, offset) * 256) /
                stream_bytes;
            toc[percent] = @intCast(@min(scaled, 255));
            percent += 1;
        }
        if (frame_index != 0) {
            const frame = (try stream.next()) orelse
                return error.InvalidMp3EncoderMetadataCounts;
            audio_offset = std.math.add(
                usize,
                audio_offset,
                frame.bytes.len,
            ) catch return error.Mp3ByteCountOverflow;
        }
    }
    if (percent != toc.len or
        audio_offset != encoded.len or
        try stream.next() != null)
        return error.InvalidMp3EncoderMetadataCounts;
    return toc;
}

pub fn writeReservoirBatchBytes(
    io: std.Io,
    file: std.Io.File,
    audio_offset: u64,
    encoded: []const u8,
    operations: file_writer_io.Operations,
) !u64 {
    return writeReservoirBatchFileBytes(
        io,
        file,
        audio_offset,
        &.{},
        encoded,
        operations,
    );
}

pub fn writeReservoirBatchFileBytes(
    io: std.Io,
    file: std.Io.File,
    audio_offset: u64,
    metadata: []const u8,
    encoded: []const u8,
    operations: file_writer_io.Operations,
) !u64 {
    const metadata_end = try fileEncoderOffset(
        audio_offset,
        metadata.len,
    );
    const file_end = try fileEncoderOffset(
        metadata_end,
        encoded.len,
    );
    const checkpoint = file_writer_io.Checkpoint.exact(audio_offset);
    try checkpoint.restore(operations, io, file);
    if (metadata.len != 0)
        operations.writeAt(io, file, audio_offset, metadata) catch |failure| {
            checkpoint.restore(operations, io, file) catch |restore_failure|
                return restore_failure;
            return failure;
        };
    if (encoded.len != 0)
        operations.writeAt(io, file, metadata_end, encoded) catch |failure| {
            checkpoint.restore(operations, io, file) catch |restore_failure|
                return restore_failure;
            return failure;
        };
    operations.setLength(io, file, file_end) catch |failure| {
        checkpoint.restore(operations, io, file) catch |restore_failure|
            return restore_failure;
        return failure;
    };
    operations.sync(io, file) catch |failure| {
        checkpoint.restore(operations, io, file) catch |restore_failure|
            return restore_failure;
        return failure;
    };
    return file_end;
}

pub fn encoderNoiseToMaskRatio(
    header: Header,
    analyzed: AnalyzedEncoderFrame,
    quantized: QuantizedEncoderFrame,
    psychoacoustics: [2][2]EncoderPsychoacousticChannel,
) !f32 {
    try validateAnalyzedEncoderFrame(header, analyzed);
    const channel_count: u2 = @intCast(header.channels());
    const granule_count: u2 =
        if (header.version == .mpeg1) 2 else 1;
    var maximum_ratio: f64 = 0;
    for (0..granule_count) |granule| {
        for (0..channel_count) |channel| {
            const source = analyzed.granules[granule][channel];
            const encoded = quantized.granules[granule][channel];
            const ordered = try orderEncoderSpectrum(
                header,
                source.description,
                source.spectrum,
            );
            const layout = try encoderBandLayout(
                header,
                source.description,
            );
            const psychoacoustic =
                psychoacoustics[granule][channel];
            const expected_factors = scaleFactorValueCount(
                header,
                encoded.description,
            );
            if (encoded.scale_factors.value_count !=
                expected_factors)
                return error.InvalidMp3VbrQuantizationEvidence;
            for (0..layout.band_count) |band| {
                const factor = if (band < expected_factors)
                    encoded.scale_factors.values[band]
                else
                    0;
                const exponent =
                    (@as(f64, @floatFromInt(
                        encoded.description.global_gain,
                    )) - 210.0) * 0.25 -
                    0.5 * @as(f64, @floatFromInt(factor));
                const step = std.math.exp2(exponent);
                var noise: f64 = 0;
                for (
                    ordered[layout.starts[band]..layout.starts[band + 1]],
                    encoded.spectrum[layout.starts[band]..layout.starts[band + 1]],
                ) |line, value| {
                    const magnitude: u32 = @intCast(
                        if (value < 0) -value else value,
                    );
                    const reconstructed = std.math.pow(
                        f64,
                        @floatFromInt(magnitude),
                        4.0 / 3.0,
                    ) * step;
                    const difference = reconstructed -
                        @abs(@as(f64, line));
                    noise += difference * difference;
                }
                const threshold =
                    psychoacoustic.threshold[band];
                const ratio = noise / threshold;
                if (!std.math.isFinite(ratio))
                    return error.InvalidMp3VbrQuantizationEvidence;
                maximum_ratio = @max(maximum_ratio, ratio);
            }
        }
    }
    if (maximum_ratio > std.math.floatMax(f32))
        return error.InvalidMp3VbrQuantizationEvidence;
    return @floatCast(maximum_ratio);
}

pub const VbrPcmStreamFinish = struct {
    frames: []u8,
    summary: EncoderStreamSummary,
    quality_misses: u64,
    maximum_noise_to_mask_ratio: f32,
};

pub const VbrPcmStreamEncoder = struct {
    encoder: VbrPcmEncoder,
    frame_offsets: []u64,
    input_samples: u64 = 0,
    quality_misses: u64 = 0,
    maximum_noise_to_mask_ratio: f32 = 0,
    metadata_encoder: [9]u8 = default_xing_encoder_identifier,
    metadata_started: bool = false,
    finalized: bool = false,

    pub fn init(
        config: VbrEncoderConfig,
        frame_offsets: []u64,
    ) !VbrPcmStreamEncoder {
        return .{
            .encoder = try VbrPcmEncoder.init(config),
            .frame_offsets = frame_offsets,
        };
    }

    pub fn valid(self: *const VbrPcmStreamEncoder) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn append(
        self: *VbrPcmStreamEncoder,
        pcm: PcmFrame,
        destination: []u8,
    ) !VbrPcmFrame {
        try self.validate();
        if (self.finalized)
            return error.Mp3VbrEncoderFinalized;
        try self.validateDestination(destination);
        const frame_index = self.encoder.frames.frames_encoded;
        if (frame_index >= self.frame_offsets.len)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        const next_input_samples = std.math.add(
            u64,
            self.input_samples,
            pcm.sample_count,
        ) catch return error.Mp3SampleCountOverflow;

        var next = self.*;
        const result = try next.encoder.encode(
            pcm,
            destination,
        );
        const frame_offset = self.encoder.byte_count;
        const next_quality_misses = std.math.add(
            u64,
            self.quality_misses,
            @intFromBool(!result.quality_met),
        ) catch return error.Mp3EncoderFrameCountOverflow;
        self.frame_offsets[frame_index] = frame_offset;
        next.input_samples = next_input_samples;
        next.quality_misses = next_quality_misses;
        next.maximum_noise_to_mask_ratio = @max(
            self.maximum_noise_to_mask_ratio,
            result.maximum_noise_to_mask_ratio,
        );
        self.* = next;
        return result;
    }

    pub fn startXingMetadata(
        self: *VbrPcmStreamEncoder,
        destination: []u8,
    ) ![]u8 {
        return self.startXingMetadataWithEncoder(
            default_xing_encoder_identifier,
            destination,
        );
    }

    pub fn startXingMetadataWithEncoder(
        self: *VbrPcmStreamEncoder,
        encoder: [9]u8,
        destination: []u8,
    ) ![]u8 {
        try self.validate();
        try validateXingEncoderIdentifier(encoder);
        if (self.finalized)
            return error.Mp3VbrEncoderFinalized;
        if (self.metadata_started or
            self.encoder.frames.frames_encoded != 0 or
            self.input_samples != 0)
            return error.Mp3EncoderMetadataAlreadyStarted;
        try self.validateDestination(destination);
        if (self.frame_offsets.len == 0)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        const bitrate_index =
            self.encoder.config.maximum_bitrate_index;
        const bitrate_kbps = bitrate(
            self.encoder.config.template.version,
            bitrate_index,
        );
        const header = (try self.encoder.frames
            .advanceAtBitrate(bitrate_kbps)).header;
        var metadata_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        const placeholder = try encodeXingFrameFields(
            header,
            .{
                .kind = .variable,
                .frame_count = 0,
                .stream_bytes = 0,
                .toc = @splat(0),
                .quality = 0,
                .encoder_delay = 0,
                .encoder_padding = 0,
                .encoder = encoder,
            },
            &metadata_storage,
        );

        var next = self.*;
        const encoded = try next.encoder.encodeAtBitrateIndex(
            .{
                .channel_count = @intCast(header.channels()),
                .sample_count = header.samplesPerFrame(),
            },
            destination,
            bitrate_index,
        );
        if (!std.meta.eql(encoded.header, header) or
            encoded.frame.len != placeholder.len)
            return error.InvalidMp3VbrEncoderState;
        self.frame_offsets[0] = 0;
        @memcpy(destination[0..placeholder.len], placeholder);
        next.metadata_started = true;
        next.metadata_encoder = encoder;
        self.* = next;
        return destination[0..placeholder.len];
    }

    pub fn finish(
        self: *VbrPcmStreamEncoder,
        destination: []u8,
    ) !VbrPcmStreamFinish {
        try self.validate();
        if (self.finalized)
            return .{
                .frames = destination[0..0],
                .summary = try self.summary(),
                .quality_misses = self.quality_misses,
                .maximum_noise_to_mask_ratio = self.maximum_noise_to_mask_ratio,
            };
        try self.validateDestination(destination);
        const header = try self.encoder.frames.config
            .header(false);
        const flush_frames = std.math.divCeil(
            u16,
            encoder_analysis_delay,
            header.samplesPerFrame(),
        ) catch return error.Mp3SampleCountOverflow;
        const first_frame = self.encoder.frames.frames_encoded;
        if (first_frame + flush_frames >
            self.frame_offsets.len)
            return error.Mp3VbrFrameIndexStorageTooSmall;

        var staged: [maximum_encoded_frame_bytes * 2]u8 =
            undefined;
        var staged_bytes: usize = 0;
        var offsets: [2]u64 = undefined;
        var next = self.*;
        var next_quality_misses = self.quality_misses;
        var next_maximum_ratio =
            self.maximum_noise_to_mask_ratio;
        const silence = PcmFrame{
            .channel_count = @intCast(header.channels()),
            .sample_count = header.samplesPerFrame(),
        };
        for (0..flush_frames) |flush_index| {
            offsets[flush_index] = next.encoder.byte_count;
            const encoded = try next.encoder.encode(
                silence,
                staged[staged_bytes..],
            );
            staged_bytes += encoded.frame.len;
            next_quality_misses = std.math.add(
                u64,
                next_quality_misses,
                @intFromBool(!encoded.quality_met),
            ) catch return error.Mp3EncoderFrameCountOverflow;
            next_maximum_ratio = @max(
                next_maximum_ratio,
                encoded.maximum_noise_to_mask_ratio,
            );
        }
        if (destination.len < staged_bytes)
            return error.InsufficientMp3EncoderStorage;
        next.quality_misses = next_quality_misses;
        next.maximum_noise_to_mask_ratio =
            next_maximum_ratio;
        next.finalized = true;
        const finished_summary = try next.summaryValidated();
        for (0..flush_frames) |flush_index|
            self.frame_offsets[first_frame + flush_index] =
                offsets[flush_index];
        @memcpy(
            destination[0..staged_bytes],
            staged[0..staged_bytes],
        );
        self.* = next;
        return .{
            .frames = destination[0..staged_bytes],
            .summary = finished_summary,
            .quality_misses = next_quality_misses,
            .maximum_noise_to_mask_ratio = next_maximum_ratio,
        };
    }

    pub fn summary(
        self: VbrPcmStreamEncoder,
    ) !EncoderStreamSummary {
        try self.validate();
        return self.summaryValidated();
    }

    fn summaryValidated(
        self: VbrPcmStreamEncoder,
    ) !EncoderStreamSummary {
        if (!self.finalized)
            return error.Mp3EncoderStreamIncomplete;
        const header = try self.encoder.frames.config
            .header(false);
        const frame_count = self.encoder.frames.frames_encoded;
        const encoded_samples = std.math.mul(
            u64,
            frame_count,
            header.samplesPerFrame(),
        ) catch return error.Mp3SampleCountOverflow;
        const metadata_delay = if (self.metadata_started)
            header.samplesPerFrame()
        else
            0;
        const total_delay = std.math.add(
            u16,
            encoder_analysis_delay,
            metadata_delay,
        ) catch return error.Mp3SampleCountOverflow;
        const retained_samples = std.math.add(
            u64,
            self.input_samples,
            total_delay,
        ) catch return error.Mp3SampleCountOverflow;
        if (encoded_samples < retained_samples)
            return error.Mp3EncoderStreamIncomplete;
        const padding = encoded_samples - retained_samples;
        if (padding > std.math.maxInt(u12))
            return error.Mp3EncoderPaddingOverflow;
        return .{
            .frame_count = frame_count,
            .input_samples = self.input_samples,
            .encoded_samples = encoded_samples,
            .byte_count = self.encoder.byte_count,
            .encoder_delay = total_delay,
            .end_padding = @intCast(padding),
        };
    }

    pub fn xingMetadataFrame(
        self: VbrPcmStreamEncoder,
        quality: ?u32,
        destination: []u8,
    ) ![]u8 {
        try self.validate();
        if (!self.metadata_started)
            return error.Mp3EncoderMetadataNotStarted;
        try self.validateDestination(destination);
        const stream_summary = try self.summary();
        if (stream_summary.frame_count >
            std.math.maxInt(u32))
            return error.Mp3EncoderMetadataFrameCountOverflow;
        if (stream_summary.byte_count >
            std.math.maxInt(u32))
            return error.Mp3EncoderMetadataByteCountOverflow;
        var toc: [100]u8 = undefined;
        for (&toc, 0..) |*entry, percent| {
            const frame_index = @min(
                @as(u64, @intCast(
                    (@as(u128, percent) *
                        stream_summary.frame_count) / 100,
                )),
                stream_summary.frame_count - 1,
            );
            const offset = self.frame_offsets[frame_index];
            const scaled = (@as(u128, offset) * 256) /
                stream_summary.byte_count;
            entry.* = @intCast(@min(scaled, 255));
        }
        var metadata_config = self.encoder.config.template;
        metadata_config.bitrate_kbps = bitrate(
            metadata_config.version,
            self.encoder.config.maximum_bitrate_index,
        );
        return encodeXingFrameFields(
            try metadata_config.header(false),
            .{
                .kind = .variable,
                .frame_count = @intCast(stream_summary.frame_count),
                .stream_bytes = @intCast(stream_summary.byte_count),
                .toc = toc,
                .quality = quality,
                .encoder_delay = try storedXingEncoderDelay(
                    try metadata_config.header(false),
                    stream_summary.encoder_delay,
                ),
                .encoder_padding = try storedXingEncoderPadding(
                    stream_summary.end_padding,
                ),
                .encoder = self.metadata_encoder,
            },
            destination,
        );
    }

    fn validate(
        self: VbrPcmStreamEncoder,
    ) !void {
        self.encoder.validateState() catch
            return error.InvalidMp3VbrStreamState;
        if (!isValidXingEncoderIdentifier(self.metadata_encoder))
            return error.InvalidMp3VbrStreamState;
        const frame_count = self.encoder.frames.frames_encoded;
        if (frame_count > self.frame_offsets.len or
            self.quality_misses > frame_count or
            !std.math.isFinite(
                self.maximum_noise_to_mask_ratio,
            ) or
            self.maximum_noise_to_mask_ratio < 0)
            return error.InvalidMp3VbrStreamState;
        if (frame_count == 0) {
            if (self.encoder.byte_count != 0 or
                self.metadata_started or self.finalized or
                self.input_samples != 0 or
                self.quality_misses != 0 or
                self.maximum_noise_to_mask_ratio != 0)
                return error.InvalidMp3VbrStreamState;
            return;
        }
        if (self.frame_offsets[0] != 0)
            return error.InvalidMp3VbrStreamState;
        for (1..frame_count) |index| {
            if (self.frame_offsets[index] <=
                self.frame_offsets[index - 1])
                return error.InvalidMp3VbrStreamState;
        }
        if (self.frame_offsets[frame_count - 1] >=
            self.encoder.byte_count)
            return error.InvalidMp3VbrStreamState;

        const header = self.encoder.frames.config
            .header(false) catch
            return error.InvalidMp3VbrStreamState;
        const flush_frames: u64 = if (self.finalized)
            std.math.divCeil(
                u64,
                encoder_analysis_delay,
                header.samplesPerFrame(),
            ) catch return error.InvalidMp3VbrStreamState
        else
            0;
        const metadata_frames: u64 =
            @intFromBool(self.metadata_started);
        if (frame_count < flush_frames + metadata_frames)
            return error.InvalidMp3VbrStreamState;
        const expected_input = std.math.mul(
            u64,
            frame_count - flush_frames - metadata_frames,
            header.samplesPerFrame(),
        ) catch return error.InvalidMp3VbrStreamState;
        if (self.input_samples != expected_input)
            return error.InvalidMp3VbrStreamState;
    }

    fn validateDestination(
        self: VbrPcmStreamEncoder,
        destination: []u8,
    ) !void {
        const offset_bytes = std.math.mul(
            usize,
            self.frame_offsets.len,
            @sizeOf(u64),
        ) catch std.math.maxInt(usize);
        if (byteRangesOverlap(
            @intFromPtr(self.frame_offsets.ptr),
            offset_bytes,
            @intFromPtr(destination.ptr),
            destination.len,
        )) return error.OverlappingMp3VbrStorage;
    }
};

pub const ReservoirRepackRequirements = struct {
    frame_count: u64,
    payload_bytes: usize,
    main_data_bytes: usize,
};

pub const ReservoirRepackResult = struct {
    frame_count: u64,
    borrowed_bytes: u64,
    maximum_backpointer: u16,
};

pub fn reservoirRepackRequirements(
    encoded: []const u8,
) !ReservoirRepackRequirements {
    return reservoirPackingRequirements(encoded, true);
}

pub fn reservoirPackingRequirements(
    encoded: []const u8,
    require_physical_payload: bool,
) !ReservoirRepackRequirements {
    var offset: usize = 0;
    var frame_count: u64 = 0;
    var payload_bytes: usize = 0;
    var main_data_bytes: usize = 0;
    var first_header: ?Header = null;
    while (offset < encoded.len) {
        const frame = try Frame.parse(encoded, offset);
        if (frame.header.free_format)
            return error.UnsupportedFreeFormatMp3;
        if (frame.xing != null or frame.vbri != null)
            return error.Mp3ReservoirMetadataFrameUnsupported;
        if (first_header) |first| {
            if (!headersCompatible(first, frame.header))
                return error.Mp3ReservoirFormatChanged;
        } else {
            first_header = frame.header;
        }
        const side = try frame.sideInformation();
        if (side.main_data_begin != 0)
            return error.Mp3ReservoirAlreadyPacked;
        const main_offset = frameMainDataOffset(frame.header);
        if (main_offset > frame.bytes.len)
            return error.TruncatedMp3Frame;
        const required = std.math.divCeil(
            usize,
            side.main_data_bits,
            8,
        ) catch return error.Mp3ReservoirSizeOverflow;
        const capacity = frame.bytes.len - main_offset;
        if (require_physical_payload and required > capacity)
            return error.InvalidMp3ReservoirEncoderState;
        payload_bytes = std.math.add(
            usize,
            payload_bytes,
            required,
        ) catch return error.Mp3ReservoirSizeOverflow;
        main_data_bytes = std.math.add(
            usize,
            main_data_bytes,
            capacity,
        ) catch return error.Mp3ReservoirSizeOverflow;
        frame_count = std.math.add(
            u64,
            frame_count,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        offset = std.math.add(
            usize,
            offset,
            frame.bytes.len,
        ) catch return error.Mp3ReservoirSizeOverflow;
    }
    if (first_header == null) return error.Mp3StreamHasNoFrames;
    return .{
        .frame_count = frame_count,
        .payload_bytes = payload_bytes,
        .main_data_bytes = main_data_bytes,
    };
}

pub fn repackMainDataReservoir(
    encoded: []u8,
    maximum_history_bytes: u16,
    encoded_scratch: []u8,
    payload_scratch: []u8,
) !ReservoirRepackResult {
    const requirements = try reservoirRepackRequirements(encoded);
    if (encoded_scratch.len < encoded.len)
        return error.Mp3ReservoirEncodedScratchTooSmall;
    if (payload_scratch.len < requirements.payload_bytes)
        return error.Mp3ReservoirPayloadScratchTooSmall;
    const encoded_start = @intFromPtr(encoded.ptr);
    const staged_start = @intFromPtr(encoded_scratch.ptr);
    const payload_start = @intFromPtr(payload_scratch.ptr);
    if (byteRangesOverlap(
        encoded_start,
        encoded.len,
        staged_start,
        encoded.len,
    ) or byteRangesOverlap(
        encoded_start,
        encoded.len,
        payload_start,
        requirements.payload_bytes,
    ) or byteRangesOverlap(
        staged_start,
        encoded.len,
        payload_start,
        requirements.payload_bytes,
    )) return error.OverlappingMp3ReservoirStorage;

    var offset: usize = 0;
    var payload_cursor: usize = 0;
    while (offset < encoded.len) {
        const frame = try Frame.parse(encoded, offset);
        const side = try frame.sideInformation();
        const main_offset = frameMainDataOffset(frame.header);
        const required = try std.math.divCeil(
            usize,
            side.main_data_bits,
            8,
        );
        @memcpy(
            payload_scratch[payload_cursor..][0..required],
            frame.bytes[main_offset..][0..required],
        );
        payload_cursor += required;
        offset += frame.bytes.len;
    }

    return packMainDataReservoirStaged(
        encoded,
        maximum_history_bytes,
        payload_scratch[0..requirements.payload_bytes],
        encoded_scratch,
        requirements,
    );
}

pub fn packMainDataReservoir(
    encoded_frames: []u8,
    logical_main_data: []const u8,
    maximum_history_bytes: u16,
    encoded_scratch: []u8,
) !ReservoirRepackResult {
    const requirements = try reservoirPackingRequirements(
        encoded_frames,
        false,
    );
    if (logical_main_data.len != requirements.payload_bytes)
        return error.InvalidMp3LogicalMainDataLength;
    if (encoded_scratch.len < encoded_frames.len)
        return error.Mp3ReservoirEncodedScratchTooSmall;
    if (byteRangesOverlap(
        @intFromPtr(encoded_frames.ptr),
        encoded_frames.len,
        @intFromPtr(logical_main_data.ptr),
        logical_main_data.len,
    ) or byteRangesOverlap(
        @intFromPtr(encoded_frames.ptr),
        encoded_frames.len,
        @intFromPtr(encoded_scratch.ptr),
        encoded_frames.len,
    ) or byteRangesOverlap(
        @intFromPtr(logical_main_data.ptr),
        logical_main_data.len,
        @intFromPtr(encoded_scratch.ptr),
        encoded_frames.len,
    )) return error.OverlappingMp3ReservoirStorage;
    return packMainDataReservoirStaged(
        encoded_frames,
        maximum_history_bytes,
        logical_main_data,
        encoded_scratch,
        requirements,
    );
}

pub fn packMainDataReservoirStaged(
    encoded: []u8,
    maximum_history_bytes: u16,
    logical_main_data: []const u8,
    encoded_scratch: []u8,
    requirements: ReservoirRepackRequirements,
) !ReservoirRepackResult {
    const active_version = (try Frame.parse(encoded, 0)).header.version;
    const format_limit: u16 =
        if (active_version == .mpeg1) 511 else 255;
    if (maximum_history_bytes > format_limit)
        return error.InvalidMp3ReservoirHistoryLimit;

    const staged = encoded_scratch[0..encoded.len];
    @memcpy(staged, encoded);
    var offset: usize = 0;
    while (offset < staged.len) {
        const frame = try Frame.parse(staged, offset);
        const main_offset = frameMainDataOffset(frame.header);
        @memset(staged[offset + main_offset ..][0 .. frame.bytes.len - main_offset], 0);
        offset += frame.bytes.len;
    }

    var writer = ReservoirMainDataWriter{ .encoded = staged };
    var physical_start: usize = 0;
    var packed_end: usize = 0;
    var payload_cursor: usize = 0;
    var borrowed_bytes: u64 = 0;
    var maximum_backpointer: u16 = 0;
    offset = 0;
    while (offset < staged.len) {
        const frame = try Frame.parse(staged, offset);
        const side = try frame.sideInformation();
        const main_offset = frameMainDataOffset(frame.header);
        const capacity = frame.bytes.len - main_offset;
        const required = try std.math.divCeil(
            usize,
            side.main_data_bits,
            8,
        );
        const earliest = physical_start -| maximum_history_bytes;
        const logical_start = @max(packed_end, earliest);
        if (logical_start > physical_start)
            return error.InvalidMp3ReservoirEncoderState;
        const backpointer: u16 = if (required == 0)
            0
        else
            @intCast(physical_start - logical_start);
        try writer.seekTo(logical_start);
        try writer.write(
            logical_main_data[payload_cursor..][0..required],
        );
        setFrameMainDataBegin(
            staged[offset..][0..frame.bytes.len],
            frame.header,
            backpointer,
        );
        packed_end = std.math.add(
            usize,
            logical_start,
            required,
        ) catch return error.Mp3ReservoirSizeOverflow;
        payload_cursor += required;
        physical_start = std.math.add(
            usize,
            physical_start,
            capacity,
        ) catch return error.Mp3ReservoirSizeOverflow;
        borrowed_bytes = std.math.add(
            u64,
            borrowed_bytes,
            backpointer,
        ) catch return error.Mp3ReservoirByteCountOverflow;
        maximum_backpointer = @max(
            maximum_backpointer,
            backpointer,
        );
        offset += frame.bytes.len;
    }
    if (payload_cursor != requirements.payload_bytes or
        physical_start != requirements.main_data_bytes)
        return error.InvalidMp3ReservoirEncoderState;
    @memcpy(encoded, staged);
    return .{
        .frame_count = requirements.frame_count,
        .borrowed_bytes = borrowed_bytes,
        .maximum_backpointer = maximum_backpointer,
    };
}

pub const ReservoirMainDataWriter = struct {
    encoded: []u8,
    next_frame_offset: usize = 0,
    region_cursor: usize = 0,
    region_end: usize = 0,
    position: usize = 0,

    fn seekTo(self: *ReservoirMainDataWriter, target: usize) !void {
        if (target < self.position)
            return error.InvalidMp3ReservoirEncoderState;
        try self.advance(target - self.position);
    }

    fn write(self: *ReservoirMainDataWriter, bytes: []const u8) !void {
        var source_offset: usize = 0;
        while (source_offset < bytes.len) {
            try self.ensureRegion();
            const copied = @min(
                bytes.len - source_offset,
                self.region_end - self.region_cursor,
            );
            @memcpy(
                self.encoded[self.region_cursor..][0..copied],
                bytes[source_offset..][0..copied],
            );
            self.region_cursor += copied;
            self.position += copied;
            source_offset += copied;
        }
    }

    fn advance(self: *ReservoirMainDataWriter, count: usize) !void {
        var remaining = count;
        while (remaining != 0) {
            try self.ensureRegion();
            const advanced = @min(
                remaining,
                self.region_end - self.region_cursor,
            );
            self.region_cursor += advanced;
            self.position += advanced;
            remaining -= advanced;
        }
    }

    fn ensureRegion(self: *ReservoirMainDataWriter) !void {
        while (self.region_cursor == self.region_end) {
            if (self.next_frame_offset == self.encoded.len)
                return error.InvalidMp3ReservoirEncoderState;
            const frame = try Frame.parse(
                self.encoded,
                self.next_frame_offset,
            );
            const main_offset = frameMainDataOffset(frame.header);
            self.region_cursor = self.next_frame_offset + main_offset;
            self.region_end = self.next_frame_offset + frame.bytes.len;
            self.next_frame_offset = self.region_end;
        }
    }
};

pub fn setFrameMainDataBegin(
    frame: []u8,
    header: Header,
    main_data_begin: u16,
) void {
    const side_offset: usize = if (header.crc_present) 6 else 4;
    if (header.version == .mpeg1) {
        frame[side_offset] = @intCast(main_data_begin >> 1);
        frame[side_offset + 1] =
            (frame[side_offset + 1] & 0x7f) |
            @as(u8, @intCast(main_data_begin & 1)) << 7;
    } else {
        frame[side_offset] = @intCast(main_data_begin);
    }
    if (header.crc_present) {
        const side_end = side_offset + header.sideInformationBytes();
        var checksum = crc16(0xffff, frame[2..4]);
        checksum = crc16(checksum, frame[side_offset..side_end]);
        frame[4] = @intCast(checksum >> 8);
        frame[5] = @intCast(checksum & 0xff);
    }
}

pub const PcmReservoirAppend = struct {
    frame: ?[]u8,
    borrowed_bytes: u16,
};

pub const PcmReservoirEncoder = struct {
    encoder: PcmEncoder,
    pending: [maximum_encoded_frame_bytes]u8 = @splat(0),
    pending_length: u16 = 0,
    frames_received: u64 = 0,
    frames_emitted: u64 = 0,
    borrowed_bytes: u64 = 0,
    finalized: bool = false,

    pub fn init(config: EncoderConfig) !PcmReservoirEncoder {
        return .{ .encoder = try PcmEncoder.init(config) };
    }

    pub fn reset(self: *PcmReservoirEncoder) void {
        self.encoder.reset();
        self.pending = @splat(0);
        self.pending_length = 0;
        self.frames_received = 0;
        self.frames_emitted = 0;
        self.borrowed_bytes = 0;
        self.finalized = false;
    }

    pub fn valid(self: *const PcmReservoirEncoder) bool {
        self.validateState() catch return false;
        return true;
    }

    /// Retain one frame so the following frame may use its spare main data.
    pub fn append(
        self: *PcmReservoirEncoder,
        pcm: PcmFrame,
        destination: []u8,
    ) !PcmReservoirAppend {
        try self.validateState();
        if (self.finalized)
            return error.Mp3ReservoirEncoderFinalized;
        const pending_length: usize = self.pending_length;
        if (pending_length != 0 and
            destination.len < pending_length)
            return error.InsufficientMp3EncoderStorage;
        const next_received = std.math.add(
            u64,
            self.frames_received,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const next_emitted = if (pending_length != 0)
            std.math.add(
                u64,
                self.frames_emitted,
                1,
            ) catch return error.Mp3EncoderFrameCountOverflow
        else
            self.frames_emitted;

        var next = self.*;
        var encoded_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        const encoded = try next.encoder.encode(
            pcm,
            &encoded_storage,
        );
        var finalized_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        var borrowed: u16 = 0;
        if (pending_length != 0) {
            @memcpy(
                finalized_storage[0..pending_length],
                self.pending[0..pending_length],
            );
            borrowed = try borrowMainData(
                finalized_storage[0..pending_length],
                encoded_storage[0..encoded.len],
            );
            next.borrowed_bytes = std.math.add(
                u64,
                self.borrowed_bytes,
                borrowed,
            ) catch return error.Mp3ReservoirByteCountOverflow;
        }
        @memcpy(
            next.pending[0..encoded.len],
            encoded_storage[0..encoded.len],
        );
        next.pending_length = @intCast(encoded.len);
        next.frames_received = next_received;
        next.frames_emitted = next_emitted;
        if (pending_length != 0)
            @memcpy(
                destination[0..pending_length],
                finalized_storage[0..pending_length],
            );
        self.* = next;
        return .{
            .frame = if (pending_length == 0)
                null
            else
                destination[0..pending_length],
            .borrowed_bytes = borrowed,
        };
    }

    fn appendIndependent(
        self: *PcmReservoirEncoder,
        pcm: PcmFrame,
        destination: []u8,
    ) ![]u8 {
        try self.validateState();
        if (self.finalized)
            return error.Mp3ReservoirEncoderFinalized;
        if (self.pending_length != 0)
            return error.InvalidMp3ReservoirEncoderState;
        const next_received = std.math.add(
            u64,
            self.frames_received,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const next_emitted = std.math.add(
            u64,
            self.frames_emitted,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        var next = self.*;
        const encoded = try next.encoder.encode(
            pcm,
            destination,
        );
        next.frames_received = next_received;
        next.frames_emitted = next_emitted;
        self.* = next;
        return encoded;
    }

    pub fn finish(
        self: *PcmReservoirEncoder,
        destination: []u8,
    ) !?[]u8 {
        try self.validateState();
        if (self.finalized) return null;
        const pending_length: usize = self.pending_length;
        if (destination.len < pending_length)
            return error.InsufficientMp3EncoderStorage;
        const next_emitted = if (pending_length != 0)
            std.math.add(
                u64,
                self.frames_emitted,
                1,
            ) catch return error.Mp3EncoderFrameCountOverflow
        else
            self.frames_emitted;
        if (pending_length != 0)
            @memcpy(
                destination[0..pending_length],
                self.pending[0..pending_length],
            );
        self.pending_length = 0;
        self.frames_emitted = next_emitted;
        self.finalized = true;
        return if (pending_length == 0)
            null
        else
            destination[0..pending_length];
    }

    fn validateState(self: PcmReservoirEncoder) !void {
        const has_pending = self.pending_length != 0;
        if (!self.encoder.valid() or
            self.pending_length > self.pending.len or
            self.encoder.frames.frames_encoded !=
                self.frames_received or
            self.encoder.analysis.frames_analyzed !=
                self.frames_received or
            self.frames_emitted > self.frames_received or
            self.frames_received - self.frames_emitted !=
                @intFromBool(has_pending) or
            (self.finalized and has_pending) or
            !reservoirBorrowedBytesValid(
                self.encoder.frames.config.version,
                self.frames_received,
                self.borrowed_bytes,
            ))
            return error.InvalidMp3ReservoirEncoderState;
        if (has_pending) {
            const bytes =
                self.pending[0..self.pending_length];
            const frame = validatePendingReservoirFrame(bytes) catch
                return error.InvalidMp3ReservoirEncoderState;
            const side = frame.sideInformation() catch
                return error.InvalidMp3ReservoirEncoderState;
            const expected = self.encoder.frames.config
                .header(frame.header.padding) catch
                return error.InvalidMp3ReservoirEncoderState;
            if (!std.meta.eql(expected, frame.header) or
                frame.bytes.len != bytes.len or
                !reservoirPendingBorrowedBytesValid(
                    frame.header.version,
                    self.frames_received,
                    self.borrowed_bytes,
                    side.main_data_begin,
                ))
                return error.InvalidMp3ReservoirEncoderState;
        }
    }
};

pub const VbrPcmReservoirSelection = struct {
    header: Header,
    bitrate_index: u4,
    maximum_noise_to_mask_ratio: f32,
    quality_met: bool,
};

pub const VbrPcmReservoirAppend = struct {
    frame: ?[]u8,
    selection: VbrPcmReservoirSelection,
    borrowed_bytes: u16,
};

pub const VbrPcmReservoirEncoder = struct {
    encoder: VbrPcmEncoder,
    pending: [maximum_encoded_frame_bytes]u8 = @splat(0),
    pending_length: u16 = 0,
    frames_received: u64 = 0,
    frames_emitted: u64 = 0,
    borrowed_bytes: u64 = 0,
    finalized: bool = false,

    pub fn init(
        config: VbrEncoderConfig,
    ) !VbrPcmReservoirEncoder {
        return .{ .encoder = try VbrPcmEncoder.init(config) };
    }

    pub fn reset(self: *VbrPcmReservoirEncoder) void {
        self.encoder.reset();
        self.pending = @splat(0);
        self.pending_length = 0;
        self.frames_received = 0;
        self.frames_emitted = 0;
        self.borrowed_bytes = 0;
        self.finalized = false;
    }

    pub fn valid(self: *const VbrPcmReservoirEncoder) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn append(
        self: *VbrPcmReservoirEncoder,
        pcm: PcmFrame,
        destination: []u8,
    ) !VbrPcmReservoirAppend {
        return self.appendSelection(pcm, destination, null);
    }

    pub fn appendAtBitrateIndex(
        self: *VbrPcmReservoirEncoder,
        pcm: PcmFrame,
        destination: []u8,
        bitrate_index: u4,
    ) !VbrPcmReservoirAppend {
        return self.appendSelection(
            pcm,
            destination,
            bitrate_index,
        );
    }

    fn appendSelection(
        self: *VbrPcmReservoirEncoder,
        pcm: PcmFrame,
        destination: []u8,
        forced_bitrate_index: ?u4,
    ) !VbrPcmReservoirAppend {
        try self.validateState();
        if (self.finalized)
            return error.Mp3VbrReservoirEncoderFinalized;
        const pending_length: usize = self.pending_length;
        if (pending_length != 0 and
            destination.len < pending_length)
            return error.InsufficientMp3EncoderStorage;
        const next_received = std.math.add(
            u64,
            self.frames_received,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const next_emitted = if (pending_length != 0)
            std.math.add(
                u64,
                self.frames_emitted,
                1,
            ) catch return error.Mp3EncoderFrameCountOverflow
        else
            self.frames_emitted;

        var next = self.*;
        var encoded_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        const selected = if (forced_bitrate_index) |index|
            try next.encoder.encodeAtBitrateIndex(
                pcm,
                &encoded_storage,
                index,
            )
        else
            try next.encoder.encode(pcm, &encoded_storage);
        var finalized_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        var borrowed: u16 = 0;
        if (pending_length != 0) {
            @memcpy(
                finalized_storage[0..pending_length],
                self.pending[0..pending_length],
            );
            borrowed = try borrowMainData(
                finalized_storage[0..pending_length],
                encoded_storage[0..selected.frame.len],
            );
            next.borrowed_bytes = std.math.add(
                u64,
                self.borrowed_bytes,
                borrowed,
            ) catch return error.Mp3ReservoirByteCountOverflow;
        }
        @memcpy(
            next.pending[0..selected.frame.len],
            encoded_storage[0..selected.frame.len],
        );
        next.pending_length = @intCast(selected.frame.len);
        next.frames_received = next_received;
        next.frames_emitted = next_emitted;
        if (pending_length != 0)
            @memcpy(
                destination[0..pending_length],
                finalized_storage[0..pending_length],
            );
        self.* = next;
        return .{
            .frame = if (pending_length == 0)
                null
            else
                destination[0..pending_length],
            .selection = .{
                .header = selected.header,
                .bitrate_index = selected.bitrate_index,
                .maximum_noise_to_mask_ratio = selected.maximum_noise_to_mask_ratio,
                .quality_met = selected.quality_met,
            },
            .borrowed_bytes = borrowed,
        };
    }

    pub fn finish(
        self: *VbrPcmReservoirEncoder,
        destination: []u8,
    ) !?[]u8 {
        try self.validateState();
        if (self.finalized) return null;
        const pending_length: usize = self.pending_length;
        if (destination.len < pending_length)
            return error.InsufficientMp3EncoderStorage;
        const next_emitted = if (pending_length != 0)
            std.math.add(
                u64,
                self.frames_emitted,
                1,
            ) catch return error.Mp3EncoderFrameCountOverflow
        else
            self.frames_emitted;
        if (pending_length != 0)
            @memcpy(
                destination[0..pending_length],
                self.pending[0..pending_length],
            );
        self.pending_length = 0;
        self.frames_emitted = next_emitted;
        self.finalized = true;
        return if (pending_length == 0)
            null
        else
            destination[0..pending_length];
    }

    fn validateState(self: VbrPcmReservoirEncoder) !void {
        self.encoder.validateState() catch
            return error.InvalidMp3VbrReservoirEncoderState;
        const has_pending = self.pending_length != 0;
        if (self.pending_length > self.pending.len or
            self.encoder.frames.frames_encoded !=
                self.frames_received or
            self.encoder.analysis.frames_analyzed !=
                self.frames_received or
            self.frames_emitted > self.frames_received or
            self.frames_received - self.frames_emitted !=
                @intFromBool(has_pending) or
            (self.finalized and has_pending) or
            !reservoirBorrowedBytesValid(
                self.encoder.config.template.version,
                self.frames_received,
                self.borrowed_bytes,
            ))
            return error.InvalidMp3VbrReservoirEncoderState;
        if (has_pending) {
            const bytes =
                self.pending[0..self.pending_length];
            const frame = validatePendingReservoirFrame(bytes) catch
                return error.InvalidMp3VbrReservoirEncoderState;
            const side = frame.sideInformation() catch
                return error.InvalidMp3VbrReservoirEncoderState;
            var expected_config = self.encoder.config.template;
            expected_config.bitrate_kbps =
                frame.header.bitrate_kbps;
            const expected = expected_config
                .header(frame.header.padding) catch
                return error.InvalidMp3VbrReservoirEncoderState;
            const index = bitrateIndex(
                frame.header.version,
                frame.header.bitrate_kbps,
            ) orelse
                return error.InvalidMp3VbrReservoirEncoderState;
            if (!std.meta.eql(expected, frame.header) or
                frame.bytes.len != bytes.len or
                index < self.encoder.config.minimum_bitrate_index or
                index > self.encoder.config.maximum_bitrate_index or
                !reservoirPendingBorrowedBytesValid(
                    frame.header.version,
                    self.frames_received,
                    self.borrowed_bytes,
                    side.main_data_begin,
                ))
                return error.InvalidMp3VbrReservoirEncoderState;
        }
    }
};

pub const VbrPcmReservoirStreamFinish = struct {
    frames: []u8,
    summary: EncoderStreamSummary,
    quality_misses: u64,
    maximum_noise_to_mask_ratio: f32,
    borrowed_bytes: u64,
};

pub const VbrPcmReservoirStreamEncoder = struct {
    encoder: VbrPcmStreamEncoder,
    pending: [maximum_encoded_frame_bytes]u8 = @splat(0),
    pending_length: u16 = 0,
    frames_emitted: u64 = 0,
    borrowed_bytes: u64 = 0,

    pub fn init(
        config: VbrEncoderConfig,
        frame_offsets: []u64,
    ) !VbrPcmReservoirStreamEncoder {
        return .{
            .encoder = try VbrPcmStreamEncoder.init(
                config,
                frame_offsets,
            ),
        };
    }

    pub fn valid(self: *const VbrPcmReservoirStreamEncoder) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn append(
        self: *VbrPcmReservoirStreamEncoder,
        pcm: PcmFrame,
        destination: []u8,
    ) !VbrPcmReservoirAppend {
        try self.validate();
        if (self.encoder.finalized)
            return error.Mp3VbrReservoirEncoderFinalized;
        try self.encoder.validateDestination(destination);
        const pending_length: usize = self.pending_length;
        if (pending_length != 0 and
            destination.len < pending_length)
            return error.InsufficientMp3EncoderStorage;

        var next = self.*;
        var encoded_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        const selected = try next.encoder.append(
            pcm,
            &encoded_storage,
        );
        var finalized_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        const borrowed = try next.retainSelectedFrame(
            self.pending[0..pending_length],
            selected.frame,
            &finalized_storage,
        );
        if (pending_length != 0) {
            next.frames_emitted = std.math.add(
                u64,
                self.frames_emitted,
                1,
            ) catch return error.Mp3EncoderFrameCountOverflow;
            @memcpy(
                destination[0..pending_length],
                finalized_storage[0..pending_length],
            );
        }
        self.* = next;
        return .{
            .frame = if (pending_length == 0)
                null
            else
                destination[0..pending_length],
            .selection = .{
                .header = selected.header,
                .bitrate_index = selected.bitrate_index,
                .maximum_noise_to_mask_ratio = selected.maximum_noise_to_mask_ratio,
                .quality_met = selected.quality_met,
            },
            .borrowed_bytes = borrowed,
        };
    }

    pub fn startXingMetadata(
        self: *VbrPcmReservoirStreamEncoder,
        destination: []u8,
    ) ![]u8 {
        return self.startXingMetadataWithEncoder(
            default_xing_encoder_identifier,
            destination,
        );
    }

    pub fn startXingMetadataWithEncoder(
        self: *VbrPcmReservoirStreamEncoder,
        encoder: [9]u8,
        destination: []u8,
    ) ![]u8 {
        try self.validate();
        if (self.pending_length != 0)
            return error.InvalidMp3VbrReservoirStreamState;
        var next = self.*;
        const frame = try next.encoder.startXingMetadataWithEncoder(
            encoder,
            destination,
        );
        next.frames_emitted = std.math.add(
            u64,
            self.frames_emitted,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        self.* = next;
        return frame;
    }

    pub fn finish(
        self: *VbrPcmReservoirStreamEncoder,
        destination: []u8,
    ) !VbrPcmReservoirStreamFinish {
        try self.validate();
        if (self.encoder.finalized)
            return .{
                .frames = destination[0..0],
                .summary = try self.encoder.summary(),
                .quality_misses = self.encoder.quality_misses,
                .maximum_noise_to_mask_ratio = self.encoder.maximum_noise_to_mask_ratio,
                .borrowed_bytes = self.borrowed_bytes,
            };
        try self.encoder.validateDestination(destination);

        var selected_storage: [maximum_encoded_frame_bytes * 2]u8 = undefined;
        var next = self.*;
        const selected_finish = try next.encoder.finish(
            &selected_storage,
        );
        var staged: [maximum_encoded_frame_bytes * 3]u8 = undefined;
        var staged_length: usize = 0;
        var cursor: usize = 0;
        while (cursor < selected_finish.frames.len) {
            const frame = try Frame.parse(
                selected_finish.frames,
                cursor,
            );
            const current_length = frame.bytes.len;
            var current: [maximum_encoded_frame_bytes]u8 =
                undefined;
            @memcpy(
                current[0..current_length],
                frame.bytes,
            );
            const pending_length: usize = next.pending_length;
            var finalized: [maximum_encoded_frame_bytes]u8 = undefined;
            _ = try next.retainSelectedFrame(
                next.pending[0..pending_length],
                current[0..current_length],
                &finalized,
            );
            if (pending_length != 0) {
                @memcpy(
                    staged[staged_length..][0..pending_length],
                    finalized[0..pending_length],
                );
                staged_length += pending_length;
                next.frames_emitted = std.math.add(
                    u64,
                    next.frames_emitted,
                    1,
                ) catch return error.Mp3EncoderFrameCountOverflow;
            }
            cursor += current_length;
        }
        const pending_length: usize = next.pending_length;
        if (pending_length != 0) {
            @memcpy(
                staged[staged_length..][0..pending_length],
                next.pending[0..pending_length],
            );
            staged_length += pending_length;
            next.pending_length = 0;
            next.frames_emitted = std.math.add(
                u64,
                next.frames_emitted,
                1,
            ) catch return error.Mp3EncoderFrameCountOverflow;
        }
        if (destination.len < staged_length)
            return error.InsufficientMp3EncoderStorage;
        try next.validate();
        @memcpy(destination[0..staged_length], staged[0..staged_length]);
        self.* = next;
        return .{
            .frames = destination[0..staged_length],
            .summary = selected_finish.summary,
            .quality_misses = selected_finish.quality_misses,
            .maximum_noise_to_mask_ratio = selected_finish.maximum_noise_to_mask_ratio,
            .borrowed_bytes = next.borrowed_bytes,
        };
    }

    pub fn summary(
        self: VbrPcmReservoirStreamEncoder,
    ) !EncoderStreamSummary {
        try self.validate();
        return self.encoder.summary();
    }

    pub fn xingMetadataFrame(
        self: VbrPcmReservoirStreamEncoder,
        quality: ?u32,
        destination: []u8,
    ) ![]u8 {
        try self.validate();
        return self.encoder.xingMetadataFrame(
            quality,
            destination,
        );
    }

    fn retainSelectedFrame(
        self: *VbrPcmReservoirStreamEncoder,
        previous: []const u8,
        current: []u8,
        finalized: []u8,
    ) !u16 {
        if (previous.len != 0)
            @memcpy(finalized[0..previous.len], previous);
        const borrowed = if (previous.len == 0)
            0
        else
            try borrowMainData(
                finalized[0..previous.len],
                current,
            );
        if (current.len > self.pending.len)
            return error.InvalidMp3VbrReservoirStreamState;
        @memcpy(self.pending[0..current.len], current);
        self.pending_length = @intCast(current.len);
        self.borrowed_bytes = std.math.add(
            u64,
            self.borrowed_bytes,
            borrowed,
        ) catch return error.Mp3ReservoirByteCountOverflow;
        return borrowed;
    }

    fn validate(
        self: VbrPcmReservoirStreamEncoder,
    ) !void {
        self.encoder.validate() catch
            return error.InvalidMp3VbrReservoirStreamState;
        const frame_count =
            self.encoder.encoder.frames.frames_encoded;
        const has_pending = self.pending_length != 0;
        if (self.pending_length > self.pending.len or
            self.frames_emitted > frame_count or
            frame_count - self.frames_emitted !=
                @intFromBool(has_pending) or
            (self.encoder.finalized and has_pending) or
            !reservoirBorrowedBytesValid(
                self.encoder.encoder.config.template.version,
                frame_count,
                self.borrowed_bytes,
            ))
            return error.InvalidMp3VbrReservoirStreamState;
        if (has_pending) {
            const frame = validatePendingReservoirFrame(
                self.pending[0..self.pending_length],
            ) catch
                return error.InvalidMp3VbrReservoirStreamState;
            const side = frame.sideInformation() catch
                return error.InvalidMp3VbrReservoirStreamState;
            var expected_config =
                self.encoder.encoder.config.template;
            expected_config.bitrate_kbps =
                frame.header.bitrate_kbps;
            const expected = expected_config
                .header(frame.header.padding) catch
                return error.InvalidMp3VbrReservoirStreamState;
            const index = bitrateIndex(
                frame.header.version,
                frame.header.bitrate_kbps,
            ) orelse
                return error.InvalidMp3VbrReservoirStreamState;
            if (!std.meta.eql(expected, frame.header) or
                frame.bytes.len != self.pending_length or
                index < self.encoder.encoder.config
                    .minimum_bitrate_index or
                index > self.encoder.encoder.config
                    .maximum_bitrate_index or
                !reservoirPendingBorrowedBytesValid(
                    frame.header.version,
                    frame_count,
                    self.borrowed_bytes,
                    side.main_data_begin,
                ))
                return error.InvalidMp3VbrReservoirStreamState;
        }
    }
};

pub fn validatePendingReservoirFrame(
    bytes: []const u8,
) !Frame {
    const frame = try Frame.parse(bytes, 0);
    if (frame.bytes.len != bytes.len)
        return error.InvalidMp3ReservoirEncoderState;
    const side = try frame.sideInformation();
    const required =
        (@as(usize, side.main_data_bits) + 7) / 8;
    const history: usize = side.main_data_begin;
    const main_offset = frameMainDataOffset(frame.header);
    if (history > required or
        main_offset > bytes.len or
        required - history > bytes.len - main_offset)
        return error.InvalidMp3ReservoirEncoderState;
    if (frame.header.crc_present and
        try frame.crcValid() != true)
        return error.InvalidMp3ReservoirEncoderState;
    return frame;
}

pub fn reservoirBorrowedBytesValid(
    version: Version,
    frame_count: u64,
    borrowed_bytes: u64,
) bool {
    const borrowable_frames = frame_count -| 1;
    const maximum_per_frame: u64 =
        if (version == .mpeg1) 511 else 255;
    const maximum = std.math.mul(
        u64,
        borrowable_frames,
        maximum_per_frame,
    ) catch return true;
    return borrowed_bytes <= maximum;
}

pub fn reservoirPendingBorrowedBytesValid(
    version: Version,
    frame_count: u64,
    borrowed_bytes: u64,
    pending_borrowed_bytes: u16,
) bool {
    if (frame_count == 0 or
        borrowed_bytes < pending_borrowed_bytes)
        return false;
    return reservoirBorrowedBytesValid(
        version,
        frame_count - 1,
        borrowed_bytes - pending_borrowed_bytes,
    );
}

pub fn borrowMainData(
    previous: []u8,
    current: []u8,
) !u16 {
    const previous_frame = try Frame.parse(previous, 0);
    const current_frame = try Frame.parse(current, 0);
    if (!headersCompatible(
        previous_frame.header,
        current_frame.header,
    ) or
        previous_frame.bytes.len != previous.len or
        current_frame.bytes.len != current.len)
        return error.Mp3ReservoirFormatChanged;
    const previous_side = try previous_frame.sideInformation();
    var current_side = try current_frame.sideInformation();
    if (current_side.main_data_begin != 0)
        return error.InvalidMp3ReservoirEncoderState;
    const previous_offset =
        frameMainDataOffset(previous_frame.header);
    const current_offset =
        frameMainDataOffset(current_frame.header);
    if (previous_offset > previous.len or
        current_offset > current.len)
        return error.TruncatedMp3Frame;
    const previous_main = previous[previous_offset..];
    const current_main = current[current_offset..];
    const previous_required =
        (@as(usize, previous_side.main_data_bits) + 7) / 8;
    const previous_history: usize =
        previous_side.main_data_begin;
    if (previous_history > previous_required)
        return error.InvalidMp3ReservoirEncoderState;
    const previous_physical =
        previous_required - previous_history;
    if (previous_physical > previous_main.len)
        return error.InvalidMp3ReservoirEncoderState;
    const current_required =
        (@as(usize, current_side.main_data_bits) + 7) / 8;
    if (current_required > current_main.len)
        return error.InvalidMp3ReservoirEncoderState;
    const maximum_history: usize =
        if (current_frame.header.version == .mpeg1)
            511
        else
            255;
    const borrowed = @min(
        current_required,
        previous_main.len - previous_physical,
        maximum_history,
    );
    if (borrowed == 0) return 0;

    const previous_tail =
        previous_main[previous_main.len - borrowed ..];
    @memcpy(previous_tail, current_main[0..borrowed]);
    const retained = current_required - borrowed;
    std.mem.copyForwards(
        u8,
        current_main[0..retained],
        current_main[borrowed..current_required],
    );
    @memset(current_main[retained..], 0);
    current_side.main_data_begin = @intCast(borrowed);
    var side_storage: [32]u8 = undefined;
    const encoded_side = try encodeSideInformation(
        current_frame.header,
        current_side,
        &side_storage,
    );
    const side_offset: usize =
        if (current_frame.header.crc_present) 6 else 4;
    @memcpy(
        current[side_offset..][0..encoded_side.len],
        encoded_side,
    );
    if (current_frame.header.crc_present) {
        const side_end = side_offset + encoded_side.len;
        var checksum = crc16(0xffff, current[2..4]);
        checksum = crc16(
            checksum,
            current[side_offset..side_end],
        );
        current[4] = @intCast(checksum >> 8);
        current[5] = @intCast(checksum & 0xff);
    }
    return @intCast(borrowed);
}

pub fn frameMainDataOffset(header: Header) usize {
    return (if (header.crc_present) @as(usize, 6) else 4) +
        header.sideInformationBytes();
}

pub fn frameXingOffset(header: Header) usize {
    return 4 + header.sideInformationBytes();
}

pub const PcmReservoirStreamFinish = struct {
    frames: []u8,
    summary: EncoderStreamSummary,
    borrowed_bytes: u64,
};

pub const PcmReservoirStreamEncoder = struct {
    encoder: PcmReservoirEncoder,
    frame_count: u64 = 0,
    input_samples: u64 = 0,
    byte_count: u64 = 0,
    metadata_encoder: [9]u8 = default_xing_encoder_identifier,
    metadata_started: bool = false,
    finalized: bool = false,

    pub fn init(
        config: EncoderConfig,
    ) !PcmReservoirStreamEncoder {
        return .{
            .encoder = try PcmReservoirEncoder.init(config),
        };
    }

    pub fn valid(self: *const PcmReservoirStreamEncoder) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn append(
        self: *PcmReservoirStreamEncoder,
        pcm: PcmFrame,
        destination: []u8,
    ) !PcmReservoirAppend {
        try self.validate();
        if (self.finalized)
            return error.Mp3ReservoirEncoderFinalized;
        const next_frame_count = std.math.add(
            u64,
            self.frame_count,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const next_input_samples = std.math.add(
            u64,
            self.input_samples,
            pcm.sample_count,
        ) catch return error.Mp3SampleCountOverflow;
        var next = self.*;
        const result = try next.encoder.append(
            pcm,
            destination,
        );
        const byte_state = try encoderByteState(
            next.encoder.encoder.frames.config,
            next_frame_count,
        );
        next.frame_count = next_frame_count;
        next.input_samples = next_input_samples;
        next.byte_count = byte_state.byte_count;
        self.* = next;
        return result;
    }

    /// Reserve an independent first frame before any reservoir-backed append.
    pub fn startGaplessMetadata(
        self: *PcmReservoirStreamEncoder,
        destination: []u8,
    ) ![]u8 {
        return self.startGaplessMetadataWithEncoder(
            default_xing_encoder_identifier,
            destination,
        );
    }

    pub fn startGaplessMetadataWithEncoder(
        self: *PcmReservoirStreamEncoder,
        encoder: [9]u8,
        destination: []u8,
    ) ![]u8 {
        try self.validate();
        try validateXingEncoderIdentifier(encoder);
        if (self.finalized)
            return error.Mp3ReservoirEncoderFinalized;
        if (self.metadata_started or self.frame_count != 0 or
            self.input_samples != 0 or self.byte_count != 0)
            return error.Mp3EncoderMetadataAlreadyStarted;
        const header = try self.encoder.encoder.frames
            .config.header(false);
        var staged: [maximum_encoded_frame_bytes]u8 =
            undefined;
        const placeholder = try encodeInfoFrameFields(
            header,
            0,
            0,
            0,
            0,
            encoder,
            &staged,
        );
        if (destination.len < placeholder.len)
            return error.InsufficientMp3EncoderStorage;
        var next = self.*;
        const discarded = try next.encoder.appendIndependent(
            .{
                .channel_count = @intCast(header.channels()),
                .sample_count = header.samplesPerFrame(),
            },
            destination,
        );
        if (discarded.len != placeholder.len)
            return error.InvalidMp3EncoderState;
        next.frame_count = 1;
        next.byte_count = placeholder.len;
        next.metadata_started = true;
        next.metadata_encoder = encoder;
        @memcpy(
            destination[0..placeholder.len],
            placeholder,
        );
        self.* = next;
        return destination[0..placeholder.len];
    }

    pub fn finish(
        self: *PcmReservoirStreamEncoder,
        destination: []u8,
    ) !PcmReservoirStreamFinish {
        try self.validate();
        if (self.finalized)
            return .{
                .frames = destination[0..0],
                .summary = try self.summary(),
                .borrowed_bytes = self.encoder.borrowed_bytes,
            };
        const header = try self.encoder.encoder.frames
            .config.header(false);
        const flush_frames = std.math.divCeil(
            u16,
            encoder_analysis_delay,
            header.samplesPerFrame(),
        ) catch return error.Mp3SampleCountOverflow;
        var staged: [maximum_encoded_frame_bytes * 3]u8 =
            undefined;
        var staged_bytes: usize = 0;
        var next = self.*;
        const silence = PcmFrame{
            .channel_count = @intCast(header.channels()),
            .sample_count = header.samplesPerFrame(),
        };
        for (0..flush_frames) |_| {
            const appended = try next.encoder.append(
                silence,
                staged[staged_bytes..],
            );
            if (appended.frame) |frame|
                staged_bytes += frame.len;
        }
        if (try next.encoder.finish(
            staged[staged_bytes..],
        )) |frame| staged_bytes += frame.len;
        if (destination.len < staged_bytes)
            return error.InsufficientMp3EncoderStorage;
        next.frame_count = std.math.add(
            u64,
            self.frame_count,
            flush_frames,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const byte_state = try encoderByteState(
            next.encoder.encoder.frames.config,
            next.frame_count,
        );
        next.byte_count = byte_state.byte_count;
        next.finalized = true;
        const finished_summary = try next.summary();
        @memcpy(
            destination[0..staged_bytes],
            staged[0..staged_bytes],
        );
        self.* = next;
        return .{
            .frames = destination[0..staged_bytes],
            .summary = finished_summary,
            .borrowed_bytes = next.encoder.borrowed_bytes,
        };
    }

    pub fn summary(
        self: PcmReservoirStreamEncoder,
    ) !EncoderStreamSummary {
        try self.validate();
        if (!self.finalized)
            return error.Mp3EncoderStreamIncomplete;
        const header = try self.encoder.encoder.frames
            .config.header(false);
        const encoded_samples = std.math.mul(
            u64,
            self.frame_count,
            header.samplesPerFrame(),
        ) catch return error.Mp3SampleCountOverflow;
        const metadata_delay = if (self.metadata_started)
            header.samplesPerFrame()
        else
            0;
        const total_delay = std.math.add(
            u16,
            encoder_analysis_delay,
            metadata_delay,
        ) catch return error.Mp3SampleCountOverflow;
        const retained_samples = std.math.add(
            u64,
            self.input_samples,
            total_delay,
        ) catch return error.Mp3SampleCountOverflow;
        if (encoded_samples < retained_samples)
            return error.Mp3EncoderStreamIncomplete;
        const padding = encoded_samples - retained_samples;
        if (padding > std.math.maxInt(u12))
            return error.Mp3EncoderPaddingOverflow;
        return .{
            .frame_count = self.frame_count,
            .input_samples = self.input_samples,
            .encoded_samples = encoded_samples,
            .byte_count = self.byte_count,
            .encoder_delay = total_delay,
            .end_padding = @intCast(padding),
        };
    }

    pub fn gaplessMetadataFrame(
        self: PcmReservoirStreamEncoder,
        destination: []u8,
    ) ![]u8 {
        try self.validate();
        if (!self.metadata_started)
            return error.Mp3EncoderMetadataNotStarted;
        if (!self.finalized)
            return error.Mp3EncoderStreamIncomplete;
        return encodeInfoFrameWithEncoder(
            self.encoder.encoder.frames.config,
            try self.summary(),
            self.metadata_encoder,
            destination,
        );
    }

    fn validate(self: PcmReservoirStreamEncoder) !void {
        self.encoder.validateState() catch
            return error.InvalidMp3ReservoirStreamState;
        if (!isValidXingEncoderIdentifier(self.metadata_encoder))
            return error.InvalidMp3ReservoirStreamState;
        if (self.encoder.frames_received != self.frame_count or
            self.finalized != self.encoder.finalized)
            return error.InvalidMp3ReservoirStreamState;
        const header = self.encoder.encoder.frames.config
            .header(false) catch
            return error.InvalidMp3ReservoirStreamState;
        const byte_state = encoderByteState(
            self.encoder.encoder.frames.config,
            self.frame_count,
        ) catch return error.InvalidMp3ReservoirStreamState;
        if (self.byte_count != byte_state.byte_count or
            self.encoder.encoder.frames.padding_accumulator !=
                byte_state.padding_accumulator)
            return error.InvalidMp3ReservoirStreamState;
        const flush_frames: u64 = if (self.finalized)
            std.math.divCeil(
                u64,
                encoder_analysis_delay,
                header.samplesPerFrame(),
            ) catch return error.InvalidMp3ReservoirStreamState
        else
            0;
        if (self.frame_count < flush_frames)
            return error.InvalidMp3ReservoirStreamState;
        const metadata_frames: u64 =
            @intFromBool(self.metadata_started);
        if (self.frame_count < flush_frames + metadata_frames)
            return error.InvalidMp3ReservoirStreamState;
        const expected_input = std.math.mul(
            u64,
            self.frame_count - flush_frames - metadata_frames,
            header.samplesPerFrame(),
        ) catch return error.InvalidMp3ReservoirStreamState;
        if (self.input_samples != expected_input)
            return error.InvalidMp3ReservoirStreamState;
    }
};

pub const EncoderStreamSummary = struct {
    frame_count: u64,
    input_samples: u64,
    encoded_samples: u64,
    byte_count: u64,
    encoder_delay: u16,
    end_padding: u16,
};

pub const PcmStreamFinish = struct {
    frames: []u8,
    summary: EncoderStreamSummary,
};

pub const PcmStreamEncoder = struct {
    encoder: PcmEncoder,
    frame_count: u64 = 0,
    input_samples: u64 = 0,
    byte_count: u64 = 0,
    metadata_encoder: [9]u8 = default_xing_encoder_identifier,
    metadata_started: bool = false,
    finalized: bool = false,

    pub fn init(config: EncoderConfig) !PcmStreamEncoder {
        return .{ .encoder = try PcmEncoder.init(config) };
    }

    pub fn valid(self: *const PcmStreamEncoder) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn append(
        self: *PcmStreamEncoder,
        pcm: PcmFrame,
        destination: []u8,
    ) ![]u8 {
        try self.validate();
        if (self.finalized)
            return error.Mp3EncoderStreamFinalized;
        const next_frame_count = std.math.add(
            u64,
            self.frame_count,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const next_input_samples = std.math.add(
            u64,
            self.input_samples,
            pcm.sample_count,
        ) catch return error.Mp3SampleCountOverflow;
        const frame_bytes = try self.encoder.frames.nextFrameBytes();
        const next_byte_count = std.math.add(
            u64,
            self.byte_count,
            frame_bytes,
        ) catch return error.Mp3ByteCountOverflow;
        var next = self.*;
        const encoded = try next.encoder.encode(
            pcm,
            destination,
        );
        if (encoded.len != frame_bytes)
            return error.InvalidMp3EncoderState;
        next.frame_count = next_frame_count;
        next.input_samples = next_input_samples;
        next.byte_count = next_byte_count;
        self.* = next;
        return encoded;
    }

    /// Reserve the first frame before any PCM append.
    /// Replace its returned bytes with `gaplessMetadataFrame` after finishing.
    pub fn startGaplessMetadata(
        self: *PcmStreamEncoder,
        destination: []u8,
    ) ![]u8 {
        return self.startGaplessMetadataWithEncoder(
            default_xing_encoder_identifier,
            destination,
        );
    }

    pub fn startGaplessMetadataWithEncoder(
        self: *PcmStreamEncoder,
        encoder: [9]u8,
        destination: []u8,
    ) ![]u8 {
        try self.validate();
        try validateXingEncoderIdentifier(encoder);
        if (self.finalized)
            return error.Mp3EncoderStreamFinalized;
        if (self.metadata_started or self.frame_count != 0 or
            self.input_samples != 0 or self.byte_count != 0)
            return error.Mp3EncoderMetadataAlreadyStarted;
        const header = try self.encoder.frames.config.header(false);
        var staged: [maximum_encoded_frame_bytes]u8 = undefined;
        const placeholder = try encodeInfoFrameFields(
            header,
            0,
            0,
            0,
            0,
            encoder,
            &staged,
        );
        if (destination.len < placeholder.len)
            return error.InsufficientMp3EncoderStorage;

        var next = self.*;
        const discarded = try next.encoder.encode(
            .{
                .channel_count = @intCast(header.channels()),
                .sample_count = header.samplesPerFrame(),
            },
            destination,
        );
        if (discarded.len != placeholder.len)
            return error.InvalidMp3EncoderState;
        next.frame_count = 1;
        next.byte_count = placeholder.len;
        next.metadata_started = true;
        next.metadata_encoder = encoder;
        @memcpy(destination[0..placeholder.len], placeholder);
        self.* = next;
        return destination[0..placeholder.len];
    }

    pub fn finish(
        self: *PcmStreamEncoder,
        destination: []u8,
    ) !PcmStreamFinish {
        try self.validate();
        if (self.finalized)
            return .{
                .frames = destination[0..0],
                .summary = try self.summary(),
            };
        const header = try self.encoder.frames.config.header(false);
        const samples_per_frame: u16 = header.samplesPerFrame();
        const flush_frames = std.math.divCeil(
            u16,
            encoder_analysis_delay,
            samples_per_frame,
        ) catch return error.Mp3SampleCountOverflow;
        var staged: [maximum_encoded_frame_bytes * 2]u8 = undefined;
        var staged_bytes: usize = 0;
        var next = self.*;
        const silence = PcmFrame{
            .channel_count = @intCast(header.channels()),
            .sample_count = samples_per_frame,
        };
        for (0..flush_frames) |_| {
            const encoded = try next.encoder.encode(
                silence,
                staged[staged_bytes..],
            );
            staged_bytes += encoded.len;
        }
        if (destination.len < staged_bytes)
            return error.InsufficientMp3EncoderStorage;
        next.frame_count = std.math.add(
            u64,
            self.frame_count,
            flush_frames,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        next.byte_count = std.math.add(
            u64,
            self.byte_count,
            staged_bytes,
        ) catch return error.Mp3ByteCountOverflow;
        next.finalized = true;
        const finished_summary = try next.summary();
        @memcpy(destination[0..staged_bytes], staged[0..staged_bytes]);
        self.* = next;
        return .{
            .frames = destination[0..staged_bytes],
            .summary = finished_summary,
        };
    }

    pub fn summary(self: PcmStreamEncoder) !EncoderStreamSummary {
        try self.validate();
        return self.summaryUnchecked();
    }

    /// Rebuild the reserved first frame with final stream counts.
    pub fn gaplessMetadataFrame(
        self: PcmStreamEncoder,
        destination: []u8,
    ) ![]u8 {
        try self.validate();
        if (!self.metadata_started)
            return error.Mp3EncoderMetadataNotStarted;
        if (!self.finalized)
            return error.Mp3EncoderStreamIncomplete;
        return encodeInfoFrameWithEncoder(
            self.encoder.frames.config,
            try self.summaryUnchecked(),
            self.metadata_encoder,
            destination,
        );
    }

    fn validate(self: PcmStreamEncoder) !void {
        if (!self.encoder.valid() or
            !isValidXingEncoderIdentifier(self.metadata_encoder))
            return error.InvalidMp3EncoderStreamState;
        if (self.encoder.frames.frames_encoded != self.frame_count or
            self.encoder.analysis.frames_analyzed != self.frame_count)
            return error.InvalidMp3EncoderStreamState;
        const header = self.encoder.frames.config.header(false) catch
            return error.InvalidMp3EncoderStreamState;
        const byte_state = encoderByteState(
            self.encoder.frames.config,
            self.frame_count,
        ) catch return error.InvalidMp3EncoderStreamState;
        if (self.byte_count != byte_state.byte_count or
            self.encoder.frames.padding_accumulator !=
                byte_state.padding_accumulator)
            return error.InvalidMp3EncoderStreamState;
        const flush_frames: u64 = if (self.finalized)
            std.math.divCeil(
                u64,
                encoder_analysis_delay,
                header.samplesPerFrame(),
            ) catch return error.InvalidMp3EncoderStreamState
        else
            0;
        if (self.frame_count < flush_frames)
            return error.InvalidMp3EncoderStreamState;
        const metadata_frames: u64 =
            @intFromBool(self.metadata_started);
        if (self.frame_count < flush_frames + metadata_frames)
            return error.InvalidMp3EncoderStreamState;
        const expected_input = std.math.mul(
            u64,
            self.frame_count - flush_frames - metadata_frames,
            header.samplesPerFrame(),
        ) catch return error.InvalidMp3EncoderStreamState;
        if (self.input_samples != expected_input)
            return error.InvalidMp3EncoderStreamState;
        if (self.finalized) {
            _ = self.summaryUnchecked() catch
                return error.InvalidMp3EncoderStreamState;
        }
    }

    fn summaryUnchecked(
        self: PcmStreamEncoder,
    ) !EncoderStreamSummary {
        const header = try self.encoder.frames.config.header(false);
        const encoded_samples = try std.math.mul(
            u64,
            self.frame_count,
            header.samplesPerFrame(),
        );
        const metadata_delay = if (self.metadata_started)
            header.samplesPerFrame()
        else
            0;
        const total_delay = try std.math.add(
            u16,
            encoder_analysis_delay,
            metadata_delay,
        );
        const retained_samples = try std.math.add(
            u64,
            self.input_samples,
            total_delay,
        );
        if (encoded_samples < retained_samples)
            return error.Mp3EncoderStreamIncomplete;
        const padding = encoded_samples - retained_samples;
        if (padding > std.math.maxInt(u12))
            return error.Mp3EncoderPaddingOverflow;
        return .{
            .frame_count = self.frame_count,
            .input_samples = self.input_samples,
            .encoded_samples = encoded_samples,
            .byte_count = self.byte_count,
            .encoder_delay = total_delay,
            .end_padding = @intCast(padding),
        };
    }
};

/// Encode a constant-rate Info frame from final stream counts.
pub fn encodeInfoFrame(
    config: EncoderConfig,
    summary: EncoderStreamSummary,
    destination: []u8,
) ![]u8 {
    return encodeInfoFrameWithEncoder(
        config,
        summary,
        default_xing_encoder_identifier,
        destination,
    );
}

/// Reject blank or non-printable identifiers without changing `destination`.
pub fn encodeInfoFrameWithEncoder(
    config: EncoderConfig,
    summary: EncoderStreamSummary,
    encoder: [9]u8,
    destination: []u8,
) ![]u8 {
    if (summary.frame_count > std.math.maxInt(u32))
        return error.Mp3EncoderMetadataFrameCountOverflow;
    if (summary.byte_count > std.math.maxInt(u32))
        return error.Mp3EncoderMetadataByteCountOverflow;
    const header = try config.header(false);
    return encodeInfoFrameFields(
        header,
        @intCast(summary.frame_count),
        @intCast(summary.byte_count),
        try storedXingEncoderDelay(header, summary.encoder_delay),
        try storedXingEncoderPadding(summary.end_padding),
        encoder,
        destination,
    );
}

pub fn storedXingEncoderDelay(header: Header, total_delay: u16) !u12 {
    const stored_offset = std.math.add(
        u16,
        header.samplesPerFrame(),
        decoder_delay_samples,
    ) catch return error.Mp3EncoderMetadataDelayUnderflow;
    if (total_delay < stored_offset)
        return error.Mp3EncoderMetadataDelayUnderflow;
    const stored = total_delay - stored_offset;
    if (stored > std.math.maxInt(u12))
        return error.Mp3EncoderMetadataGaplessOverflow;
    return @intCast(stored);
}

pub fn storedXingEncoderPadding(end_padding: u16) !u12 {
    const stored = std.math.add(
        u16,
        end_padding,
        decoder_delay_samples,
    ) catch return error.Mp3EncoderMetadataGaplessOverflow;
    if (stored > std.math.maxInt(u12))
        return error.Mp3EncoderMetadataGaplessOverflow;
    return @intCast(stored);
}

pub const default_xing_encoder_identifier: [9]u8 = "zig-vst3 ".*;

pub const XingEncoderMetadata = struct {
    kind: XingKind,
    frame_count: u32,
    stream_bytes: u32,
    toc: ?[100]u8 = null,
    quality: ?u32 = null,
    encoder_delay: u12,
    encoder_padding: u12,
    encoder: [9]u8 = default_xing_encoder_identifier,
};

pub const VbriEncoderMetadata = struct {
    delay: u16 = 0,
    quality: u16,
    stream_bytes: u32,
    frame_count: u32,
    toc_scale: u16,
    entry_bytes: u16,
    frames_per_entry: u16,
    toc: []const u8,
};

pub fn encodeXingFrame(
    header: Header,
    metadata: XingEncoderMetadata,
    destination: []u8,
) ![]u8 {
    return encodeXingFrameFields(
        header,
        metadata,
        destination,
    );
}

pub fn encodeVbriFrame(
    header: Header,
    metadata: VbriEncoderMetadata,
    destination: []u8,
) ![]u8 {
    if (header.crc_present)
        return error.UnsupportedProtectedVbriFrame;
    if (metadata.entry_bytes < 1 or
        metadata.entry_bytes > 4)
        return error.InvalidVbriEntrySize;
    if (metadata.toc_scale == 0)
        return error.InvalidVbriTocScale;
    if (metadata.frames_per_entry == 0)
        return error.InvalidVbriFramesPerEntry;
    if (metadata.toc.len % metadata.entry_bytes != 0)
        return error.InvalidVbriTocSize;
    const entry_count = metadata.toc.len /
        metadata.entry_bytes;
    if (entry_count > std.math.maxInt(u16))
        return error.VbriEntryCountOverflow;
    _ = try (Vbri{
        .version = 1,
        .delay = metadata.delay,
        .quality = metadata.quality,
        .stream_bytes = metadata.stream_bytes,
        .frame_count = metadata.frame_count,
        .toc_entries = @intCast(entry_count),
        .toc_scale = metadata.toc_scale,
        .entry_bytes = metadata.entry_bytes,
        .frames_per_entry = metadata.frames_per_entry,
        .toc = metadata.toc,
    }).approximateByteOffsetForFrame(0);
    const metadata_offset: usize = 36;
    const metadata_bytes = std.math.add(
        usize,
        26,
        metadata.toc.len,
    ) catch return error.VbriSizeOverflow;
    const encoded_header = try header.encode();
    const frame_bytes = header.frameBytes();
    if (frame_bytes < metadata_offset + metadata_bytes)
        return error.Mp3EncoderMetadataFrameTooSmall;
    if (destination.len < frame_bytes)
        return error.InsufficientMp3EncoderStorage;

    var staged: [maximum_encoded_frame_bytes]u8 = @splat(0);
    @memcpy(staged[0..4], &encoded_header);
    @memcpy(
        staged[metadata_offset..][0..4],
        "VBRI",
    );
    std.mem.writeInt(
        u16,
        staged[metadata_offset + 4 ..][0..2],
        1,
        .big,
    );
    std.mem.writeInt(
        u16,
        staged[metadata_offset + 6 ..][0..2],
        metadata.delay,
        .big,
    );
    std.mem.writeInt(
        u16,
        staged[metadata_offset + 8 ..][0..2],
        metadata.quality,
        .big,
    );
    std.mem.writeInt(
        u32,
        staged[metadata_offset + 10 ..][0..4],
        metadata.stream_bytes,
        .big,
    );
    std.mem.writeInt(
        u32,
        staged[metadata_offset + 14 ..][0..4],
        metadata.frame_count,
        .big,
    );
    std.mem.writeInt(
        u16,
        staged[metadata_offset + 18 ..][0..2],
        @intCast(entry_count),
        .big,
    );
    std.mem.writeInt(
        u16,
        staged[metadata_offset + 20 ..][0..2],
        metadata.toc_scale,
        .big,
    );
    std.mem.writeInt(
        u16,
        staged[metadata_offset + 22 ..][0..2],
        metadata.entry_bytes,
        .big,
    );
    std.mem.writeInt(
        u16,
        staged[metadata_offset + 24 ..][0..2],
        metadata.frames_per_entry,
        .big,
    );
    @memcpy(
        staged[metadata_offset + 26 ..][0..metadata.toc.len],
        metadata.toc,
    );
    @memcpy(destination[0..frame_bytes], staged[0..frame_bytes]);
    return destination[0..frame_bytes];
}

pub fn requiredVbriTocBytes(
    frame_count: u32,
    frames_per_entry: u16,
    entry_bytes: u16,
) !usize {
    if (frames_per_entry == 0)
        return error.InvalidVbriFramesPerEntry;
    if (entry_bytes < 1 or entry_bytes > 4)
        return error.InvalidVbriEntrySize;
    const entries = std.math.divCeil(
        u32,
        frame_count,
        frames_per_entry,
    ) catch return error.VbriSizeOverflow;
    if (entries > std.math.maxInt(u16))
        return error.VbriEntryCountOverflow;
    return std.math.mul(
        usize,
        @intCast(entries),
        @intCast(entry_bytes),
    ) catch error.VbriSizeOverflow;
}

pub fn buildVbriToc(
    frame_offsets: []const u64,
    frame_count: u32,
    stream_bytes: u32,
    frames_per_entry: u16,
    toc_scale: u16,
    entry_bytes: u16,
    destination: []u8,
) ![]u8 {
    if (toc_scale == 0)
        return error.InvalidVbriTocScale;
    const required = try requiredVbriTocBytes(
        frame_count,
        frames_per_entry,
        entry_bytes,
    );
    const frame_count_usize: usize = frame_count;
    const frames_per_entry_usize: usize =
        frames_per_entry;
    const entry_bytes_usize: usize = entry_bytes;
    if (frame_offsets.len < frame_count_usize)
        return error.Mp3VbrFrameIndexStorageTooSmall;
    const offset_bytes = std.math.mul(
        usize,
        frame_count_usize,
        @sizeOf(u64),
    ) catch return error.OverlappingMp3VbrStorage;
    if (byteRangesOverlap(
        @intFromPtr(frame_offsets.ptr),
        offset_bytes,
        @intFromPtr(destination.ptr),
        destination.len,
    )) return error.OverlappingMp3VbrStorage;
    if (destination.len < required)
        return error.InsufficientVbriTocStorage;
    if (frame_count == 0) return destination[0..0];
    if (frame_offsets[0] != 0)
        return error.InvalidMp3VbrFrameOffsets;
    for (
        frame_offsets[0..frame_count_usize],
        0..,
    ) |offset, index| {
        if (offset >= stream_bytes or
            (index != 0 and
                offset <= frame_offsets[index - 1]))
            return error.InvalidMp3VbrFrameOffsets;
    }

    const maximum_value: u64 =
        (@as(u64, 1) << @intCast(entry_bytes * 8)) - 1;
    const entry_count = required / entry_bytes_usize;
    for (0..entry_count) |entry| {
        const first = entry * frames_per_entry_usize;
        const following = @min(
            first + frames_per_entry_usize,
            frame_count_usize,
        );
        const end: u64 = if (following == frame_count_usize)
            stream_bytes
        else
            frame_offsets[following];
        const segment_bytes = end - frame_offsets[first];
        if (segment_bytes % toc_scale != 0)
            return error.InexactVbriTocScale;
        if (segment_bytes / toc_scale > maximum_value)
            return error.VbriTocEntryOverflow;
    }

    for (0..entry_count) |entry| {
        const first = entry * frames_per_entry_usize;
        const following = @min(
            first + frames_per_entry_usize,
            frame_count_usize,
        );
        const end: u64 = if (following == frame_count_usize)
            stream_bytes
        else
            frame_offsets[following];
        var value = (end - frame_offsets[first]) /
            toc_scale;
        const output = destination[entry * entry_bytes_usize ..][0..entry_bytes_usize];
        var index = output.len;
        while (index != 0) {
            index -= 1;
            output[index] = @intCast(value & 0xff);
            value >>= 8;
        }
    }
    return destination[0..required];
}

pub const VbriStreamMetadataResult = struct {
    audio_offset: u64,
    frame_count: u32,
    stream_bytes: u32,
    metadata_frame_bytes: u16,
    toc_bytes: u16,
};

/// Replace a reserved first audio frame only after the complete stream and
/// caller-owned VBRI work storage have been validated.
pub fn finalizeVbriStreamMetadata(
    encoded: []u8,
    quality: u16,
    frames_per_entry: u16,
    toc_scale: u16,
    entry_bytes: u16,
    frame_offsets: []u64,
    toc_storage: []u8,
) !VbriStreamMetadataResult {
    const summary = try Stream.summarize(encoded);
    const frame_count = std.math.cast(u32, summary.frame_count) orelse
        return error.Mp3FrameCountOverflow;
    const stream_bytes = std.math.cast(u32, summary.audio_bytes) orelse
        return error.Mp3ByteCountOverflow;
    if (frame_count == 0) return error.Mp3StreamHasNoFrames;
    if (frame_offsets.len < frame_count)
        return error.Mp3VbrFrameIndexStorageTooSmall;
    const required_toc = try requiredVbriTocBytes(
        frame_count,
        frames_per_entry,
        entry_bytes,
    );
    if (toc_storage.len < required_toc)
        return error.InsufficientVbriTocStorage;

    const offset_bytes = std.math.mul(
        usize,
        frame_count,
        @sizeOf(u64),
    ) catch return error.OverlappingMp3VbrStorage;
    const ranges = [_]struct { start: usize, length: usize }{
        .{ .start = @intFromPtr(encoded.ptr), .length = encoded.len },
        .{ .start = @intFromPtr(frame_offsets.ptr), .length = offset_bytes },
        .{ .start = @intFromPtr(toc_storage.ptr), .length = required_toc },
    };
    for (0..ranges.len) |left| {
        for (left + 1..ranges.len) |right| {
            if (byteRangesOverlap(
                ranges[left].start,
                ranges[left].length,
                ranges[right].start,
                ranges[right].length,
            )) return error.OverlappingMp3VbrStorage;
        }
    }

    var stream = try Stream.init(encoded);
    var metadata_frame: ?Frame = null;
    var index: usize = 0;
    while (try stream.next()) |frame| {
        if (index >= frame_count)
            return error.UnexpectedMp3FrameCount;
        if (metadata_frame == null) metadata_frame = frame;
        frame_offsets[index] = frame.offset - summary.audio_offset;
        index += 1;
    }
    if (index != frame_count)
        return error.UnexpectedMp3FrameCount;
    const first = metadata_frame orelse
        return error.Mp3StreamHasNoFrames;
    if (first.xing == null and first.vbri == null)
        return error.MissingReservedMp3MetadataFrame;

    const toc = try buildVbriToc(
        frame_offsets,
        frame_count,
        stream_bytes,
        frames_per_entry,
        toc_scale,
        entry_bytes,
        toc_storage,
    );
    var staged: [maximum_encoded_frame_bytes]u8 = undefined;
    const metadata = try encodeVbriFrame(
        first.header,
        .{
            .quality = quality,
            .stream_bytes = stream_bytes,
            .frame_count = frame_count,
            .toc_scale = toc_scale,
            .entry_bytes = entry_bytes,
            .frames_per_entry = frames_per_entry,
            .toc = toc,
        },
        &staged,
    );
    @memcpy(encoded[first.offset..][0..metadata.len], metadata);
    return .{
        .audio_offset = summary.audio_offset,
        .frame_count = frame_count,
        .stream_bytes = stream_bytes,
        .metadata_frame_bytes = @intCast(metadata.len),
        .toc_bytes = @intCast(toc.len),
    };
}

pub fn encodeInfoFrameFields(
    header: Header,
    frame_count: u32,
    stream_bytes: u32,
    encoder_delay: u12,
    encoder_padding: u12,
    encoder: [9]u8,
    destination: []u8,
) ![]u8 {
    return encodeXingFrameFields(
        header,
        .{
            .kind = .constant,
            .frame_count = frame_count,
            .stream_bytes = stream_bytes,
            .encoder_delay = encoder_delay,
            .encoder_padding = encoder_padding,
            .encoder = encoder,
        },
        destination,
    );
}

pub fn encodeXingFrameFields(
    header: Header,
    metadata: XingEncoderMetadata,
    destination: []u8,
) ![]u8 {
    try validateXingEncoderIdentifier(metadata.encoder);
    const frame_bytes = header.frameBytes();
    const side_offset: usize = if (header.crc_present) 6 else 4;
    const metadata_offset = frameXingOffset(header);
    const optional_bytes: usize =
        @as(usize, @intFromBool(metadata.toc != null)) * 100 +
        @as(usize, @intFromBool(metadata.quality != null)) * 4;
    const metadata_bytes = 40 + optional_bytes;
    if (frame_bytes < metadata_offset + metadata_bytes)
        return error.Mp3EncoderMetadataFrameTooSmall;
    if (destination.len < frame_bytes)
        return error.InsufficientMp3EncoderStorage;

    var staged: [maximum_encoded_frame_bytes]u8 = @splat(0);
    const encoded_header = try header.encode();
    @memcpy(staged[0..4], &encoded_header);
    @memcpy(
        staged[metadata_offset..][0..4],
        if (metadata.kind == .variable) "Xing" else "Info",
    );
    const flags: u32 = 3 |
        (@as(u32, @intFromBool(metadata.toc != null)) << 2) |
        (@as(u32, @intFromBool(metadata.quality != null)) << 3);
    std.mem.writeInt(
        u32,
        staged[metadata_offset + 4 ..][0..4],
        flags,
        .big,
    );
    std.mem.writeInt(
        u32,
        staged[metadata_offset + 8 ..][0..4],
        metadata.frame_count,
        .big,
    );
    std.mem.writeInt(
        u32,
        staged[metadata_offset + 12 ..][0..4],
        metadata.stream_bytes,
        .big,
    );
    var cursor = metadata_offset + 16;
    if (metadata.toc) |toc| {
        @memcpy(staged[cursor..][0..100], &toc);
        cursor += 100;
    }
    if (metadata.quality) |quality| {
        std.mem.writeInt(
            u32,
            staged[cursor..][0..4],
            quality,
            .big,
        );
        cursor += 4;
    }
    @memcpy(
        staged[cursor..][0..9],
        &metadata.encoder,
    );
    const gapless =
        (@as(u24, metadata.encoder_delay) << 12) |
        metadata.encoder_padding;
    staged[cursor + 21] = @intCast(gapless >> 16);
    staged[cursor + 22] =
        @intCast((gapless >> 8) & 0xff);
    staged[cursor + 23] =
        @intCast(gapless & 0xff);
    if (header.crc_present) {
        const side_end =
            side_offset + header.sideInformationBytes();
        var checksum = crc16(0xffff, staged[2..4]);
        checksum = crc16(
            checksum,
            staged[side_offset..side_end],
        );
        staged[4] = @intCast(checksum >> 8);
        staged[5] = @intCast(checksum & 0xff);
    }
    @memcpy(destination[0..frame_bytes], staged[0..frame_bytes]);
    return destination[0..frame_bytes];
}

pub fn validateXingEncoderIdentifier(encoder: [9]u8) !void {
    if (!isValidXingEncoderIdentifier(encoder))
        return error.InvalidMp3EncoderIdentifier;
}

pub fn isValidXingEncoderIdentifier(encoder: [9]u8) bool {
    var has_visible_byte = false;
    for (encoder) |byte| {
        if (byte < 0x20 or byte > 0x7e)
            return false;
        has_visible_byte = has_visible_byte or byte != ' ';
    }
    return has_visible_byte;
}

pub const EncoderByteState = struct {
    byte_count: u64,
    padding_accumulator: u32,
};

pub fn encoderByteState(
    config: EncoderConfig,
    frame_count: u64,
) !EncoderByteState {
    const header = try config.header(false);
    const coefficient: u64 =
        if (config.version == .mpeg1) 144_000 else 72_000;
    const numerator = coefficient * config.bitrate_kbps;
    const remainder: u32 =
        @intCast(numerator % config.sample_rate);
    const accumulated =
        @as(u128, frame_count) * remainder;
    const padding_count =
        accumulated / config.sample_rate;
    const base_bytes =
        @as(u128, frame_count) * header.frameBytes();
    const total_bytes = base_bytes + padding_count;
    if (total_bytes > std.math.maxInt(u64))
        return error.Mp3ByteCountOverflow;
    return .{
        .byte_count = @intCast(total_bytes),
        .padding_accumulator = @intCast(
            accumulated % config.sample_rate,
        ),
    };
}

/// Replaces the file with one complete ID3v2 prefix.
pub fn writeId3v2FilePrefix(
    io: std.Io,
    file: std.Io.File,
    encoded_tag: []const u8,
) !u64 {
    return writeId3v2FilePrefixWithOperations(
        io,
        file,
        encoded_tag,
        .{},
    );
}

pub fn writeId3v2FilePrefixWithOperations(
    io: std.Io,
    file: std.Io.File,
    encoded_tag: []const u8,
    operations: file_writer_io.Operations,
) !u64 {
    const tag_bytes = try leadingTagBytes(encoded_tag);
    if (tag_bytes == 0 or tag_bytes != encoded_tag.len)
        return error.InvalidMp3Id3v2Prefix;
    const file_bytes: u64 = tag_bytes;
    try operations.setLength(io, file, 0);
    try operations.writeAt(io, file, 0, encoded_tag);
    return file_bytes;
}

/// Replaces any prior tail and appends one complete ID3v1 record.
pub fn appendId3v1FileTail(
    io: std.Io,
    file: std.Io.File,
    audio_offset: u64,
    audio_bytes: u64,
    encoded_tag: []const u8,
) !u64 {
    return appendId3v1FileTailWithOperations(
        io,
        file,
        audio_offset,
        audio_bytes,
        encoded_tag,
        .{},
    );
}

pub fn appendId3v1FileTailWithOperations(
    io: std.Io,
    file: std.Io.File,
    audio_offset: u64,
    audio_bytes: u64,
    encoded_tag: []const u8,
    operations: file_writer_io.Operations,
) !u64 {
    if (encoded_tag.len != 128 or
        !std.mem.eql(u8, encoded_tag[0..3], "TAG"))
        return error.InvalidMp3Id3v1Tail;
    const audio_end = try fileEncoderOffset(
        audio_offset,
        audio_bytes,
    );
    const file_end = try fileEncoderOffset(
        audio_end,
        encoded_tag.len,
    );
    try operations.setLength(io, file, audio_end);
    try operations.writeAt(
        io,
        file,
        audio_end,
        encoded_tag,
    );
    operations.sync(io, file) catch |failure| return failure;
    return file_end;
}

pub const PcmFileEncoder = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    stream: PcmStreamEncoder,
    frame_storage: []u8,
    audio_offset: u64 = 0,
    committed_bytes: u64 = 0,
    failed: bool = false,
    finalized: bool = false,

    /// The caller owns the file and frame storage for the encoder lifetime.
    pub fn init(
        io: std.Io,
        file: std.Io.File,
        config: EncoderConfig,
        frame_storage: []u8,
    ) !PcmFileEncoder {
        return initPcmFileEncoder(
            io,
            file,
            config,
            frame_storage,
            0,
            .{},
        );
    }

    /// Preserves the file prefix and starts MP3 audio at `audio_offset`.
    pub fn initAt(
        io: std.Io,
        file: std.Io.File,
        config: EncoderConfig,
        frame_storage: []u8,
        audio_offset: u64,
    ) !PcmFileEncoder {
        return initPcmFileEncoder(
            io,
            file,
            config,
            frame_storage,
            audio_offset,
            .{},
        );
    }

    pub fn initWithOperations(
        io: std.Io,
        file: std.Io.File,
        config: EncoderConfig,
        frame_storage: []u8,
        operations: file_writer_io.Operations,
    ) !PcmFileEncoder {
        return initPcmFileEncoder(
            io,
            file,
            config,
            frame_storage,
            0,
            operations,
        );
    }

    pub fn valid(self: *const PcmFileEncoder) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn append(
        self: *PcmFileEncoder,
        pcm: PcmFrame,
    ) !void {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3FileEncoderState;
        var next = self.stream;
        const encoded = try next.append(
            pcm,
            self.frame_storage,
        );
        self.operations.writeAt(
            self.io,
            self.file,
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
            encoded,
        ) catch |failure| {
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next.byte_count;
        self.stream = next;
    }

    /// Reserve an Info frame that finalization patches with gapless counts.
    pub fn startGaplessMetadata(
        self: *PcmFileEncoder,
    ) !void {
        return self.startGaplessMetadataWithEncoder(
            default_xing_encoder_identifier,
        );
    }

    pub fn startGaplessMetadataWithEncoder(
        self: *PcmFileEncoder,
        encoder: [9]u8,
    ) !void {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3FileEncoderState;
        var next = self.stream;
        const encoded = try next.startGaplessMetadataWithEncoder(
            encoder,
            self.frame_storage,
        );
        self.operations.writeAt(
            self.io,
            self.file,
            self.audio_offset,
            encoded,
        ) catch |failure| {
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next.byte_count;
        self.stream = next;
    }

    pub fn finalize(
        self: *PcmFileEncoder,
    ) !EncoderStreamSummary {
        try self.validate();
        if (self.finalized)
            return self.stream.summary();
        if (self.failed)
            return error.InvalidMp3FileEncoderState;
        var next = self.stream;
        const finished = try next.finish(self.frame_storage);
        var metadata_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        const metadata = if (next.metadata_started)
            try next.gaplessMetadataFrame(&metadata_storage)
        else
            metadata_storage[0..0];
        self.operations.writeAt(
            self.io,
            self.file,
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
            finished.frames,
        ) catch |failure| {
            self.failed = true;
            return failure;
        };
        if (metadata.len != 0) {
            self.operations.writeAt(
                self.io,
                self.file,
                self.audio_offset,
                metadata,
            ) catch |failure| {
                self.failed = true;
                return failure;
            };
        }
        self.operations.sync(self.io, self.file) catch |failure| {
            self.failed = true;
            return failure;
        };
        self.committed_bytes = finished.summary.byte_count;
        self.stream = next;
        self.finalized = true;
        return finished.summary;
    }

    pub fn recover(self: *PcmFileEncoder) !void {
        try self.validate();
        if (self.finalized)
            return error.InvalidMp3FileEncoderState;
        try file_writer_io.Checkpoint.exact(
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        ).restore(
            self.operations,
            self.io,
            self.file,
        );
        if (self.stream.metadata_started) {
            const header = try self.stream.encoder.frames
                .config.header(false);
            const placeholder = try encodeInfoFrameFields(
                header,
                0,
                0,
                0,
                0,
                self.stream.metadata_encoder,
                self.frame_storage,
            );
            try self.operations.writeAt(
                self.io,
                self.file,
                self.audio_offset,
                placeholder,
            );
        }
        self.failed = false;
    }

    fn validate(self: PcmFileEncoder) !void {
        if (self.frame_storage.len <
            maximum_encoded_frame_bytes * 2 or
            self.committed_bytes != self.stream.byte_count or
            self.finalized != self.stream.finalized)
            return error.InvalidMp3FileEncoderState;
        try self.stream.validate();
    }
};

pub const VbrPcmFileSummary = struct {
    stream: EncoderStreamSummary,
    quality_misses: u64,
    maximum_noise_to_mask_ratio: f32,
};

pub const VbrPcmFileEncoder = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    stream: VbrPcmStreamEncoder,
    frame_storage: []u8,
    audio_offset: u64 = 0,
    committed_bytes: u64 = 0,
    metadata_quality: ?u32 = null,
    failed: bool = false,
    finalized: bool = false,

    pub fn init(
        io: std.Io,
        file: std.Io.File,
        config: VbrEncoderConfig,
        frame_storage: []u8,
        frame_offsets: []u64,
    ) !VbrPcmFileEncoder {
        return initVbrPcmFileEncoder(
            io,
            file,
            config,
            frame_storage,
            frame_offsets,
            0,
            .{},
        );
    }

    /// Preserves the file prefix and starts MP3 audio at `audio_offset`.
    pub fn initAt(
        io: std.Io,
        file: std.Io.File,
        config: VbrEncoderConfig,
        frame_storage: []u8,
        frame_offsets: []u64,
        audio_offset: u64,
    ) !VbrPcmFileEncoder {
        return initVbrPcmFileEncoder(
            io,
            file,
            config,
            frame_storage,
            frame_offsets,
            audio_offset,
            .{},
        );
    }

    pub fn initWithOperations(
        io: std.Io,
        file: std.Io.File,
        config: VbrEncoderConfig,
        frame_storage: []u8,
        frame_offsets: []u64,
        operations: file_writer_io.Operations,
    ) !VbrPcmFileEncoder {
        return initVbrPcmFileEncoder(
            io,
            file,
            config,
            frame_storage,
            frame_offsets,
            0,
            operations,
        );
    }

    pub fn valid(self: *const VbrPcmFileEncoder) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn append(
        self: *VbrPcmFileEncoder,
        pcm: PcmFrame,
    ) !VbrPcmFrame {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3VbrFileEncoderState;
        const frame_index =
            self.stream.encoder.frames.frames_encoded;
        if (frame_index >= self.stream.frame_offsets.len)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        const old_offset = self.stream.frame_offsets[frame_index];
        var next = self.stream;
        const encoded = try next.append(
            pcm,
            self.frame_storage,
        );
        self.operations.writeAt(
            self.io,
            self.file,
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
            encoded.frame,
        ) catch |failure| {
            self.stream.frame_offsets[frame_index] = old_offset;
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next.encoder.byte_count;
        self.stream = next;
        return encoded;
    }

    pub fn startXingMetadata(
        self: *VbrPcmFileEncoder,
        quality: ?u32,
    ) !void {
        return self.startXingMetadataWithEncoder(
            quality,
            default_xing_encoder_identifier,
        );
    }

    pub fn startXingMetadataWithEncoder(
        self: *VbrPcmFileEncoder,
        quality: ?u32,
        encoder: [9]u8,
    ) !void {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3VbrFileEncoderState;
        if (self.stream.frame_offsets.len == 0)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        const old_offset = self.stream.frame_offsets[0];
        var next = self.stream;
        const encoded = try next.startXingMetadataWithEncoder(
            encoder,
            self.frame_storage,
        );
        self.operations.writeAt(
            self.io,
            self.file,
            self.audio_offset,
            encoded,
        ) catch |failure| {
            self.stream.frame_offsets[0] = old_offset;
            self.failed = true;
            return failure;
        };
        self.committed_bytes = next.encoder.byte_count;
        self.metadata_quality = quality;
        self.stream = next;
    }

    pub fn finalize(
        self: *VbrPcmFileEncoder,
    ) !VbrPcmFileSummary {
        try self.validate();
        if (self.finalized) {
            const summary = try self.stream.summary();
            return .{
                .stream = summary,
                .quality_misses = self.stream.quality_misses,
                .maximum_noise_to_mask_ratio = self.stream.maximum_noise_to_mask_ratio,
            };
        }
        if (self.failed)
            return error.InvalidMp3VbrFileEncoderState;
        const first_flush_index =
            self.stream.encoder.frames.frames_encoded;
        const header = try self.stream.encoder.frames.config
            .header(false);
        const flush_frames = std.math.divCeil(
            u16,
            encoder_analysis_delay,
            header.samplesPerFrame(),
        ) catch return error.Mp3SampleCountOverflow;
        if (first_flush_index + flush_frames >
            self.stream.frame_offsets.len)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        var old_offsets: [2]u64 = undefined;
        for (0..flush_frames) |index|
            old_offsets[index] = self.stream.frame_offsets[
                first_flush_index + index
            ];

        var next = self.stream;
        const finished = try next.finish(self.frame_storage);
        var metadata_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        const metadata = if (next.metadata_started)
            next.xingMetadataFrame(
                self.metadata_quality,
                &metadata_storage,
            ) catch |failure| {
                restoreVbrOffsets(
                    self.stream.frame_offsets,
                    first_flush_index,
                    old_offsets[0..flush_frames],
                );
                return failure;
            }
        else
            metadata_storage[0..0];
        self.operations.writeAt(
            self.io,
            self.file,
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
            finished.frames,
        ) catch |failure| {
            restoreVbrOffsets(
                self.stream.frame_offsets,
                first_flush_index,
                old_offsets[0..flush_frames],
            );
            self.failed = true;
            return failure;
        };
        if (metadata.len != 0) {
            self.operations.writeAt(
                self.io,
                self.file,
                self.audio_offset,
                metadata,
            ) catch |failure| {
                restoreVbrOffsets(
                    self.stream.frame_offsets,
                    first_flush_index,
                    old_offsets[0..flush_frames],
                );
                self.failed = true;
                return failure;
            };
        }
        self.operations.sync(self.io, self.file) catch |failure| {
            restoreVbrOffsets(
                self.stream.frame_offsets,
                first_flush_index,
                old_offsets[0..flush_frames],
            );
            self.failed = true;
            return failure;
        };
        self.committed_bytes = finished.summary.byte_count;
        self.stream = next;
        self.finalized = true;
        return .{
            .stream = finished.summary,
            .quality_misses = finished.quality_misses,
            .maximum_noise_to_mask_ratio = finished.maximum_noise_to_mask_ratio,
        };
    }

    pub fn recover(
        self: *VbrPcmFileEncoder,
    ) !void {
        try self.validate();
        if (self.finalized)
            return error.InvalidMp3VbrFileEncoderState;
        try file_writer_io.Checkpoint.exact(
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        ).restore(
            self.operations,
            self.io,
            self.file,
        );
        if (self.stream.metadata_started) {
            var metadata_config =
                self.stream.encoder.config.template;
            metadata_config.bitrate_kbps = bitrate(
                metadata_config.version,
                self.stream.encoder.config
                    .maximum_bitrate_index,
            );
            const placeholder = try encodeXingFrameFields(
                try metadata_config.header(false),
                .{
                    .kind = .variable,
                    .frame_count = 0,
                    .stream_bytes = 0,
                    .toc = @splat(0),
                    .quality = 0,
                    .encoder_delay = 0,
                    .encoder_padding = 0,
                    .encoder = self.stream.metadata_encoder,
                },
                self.frame_storage,
            );
            try self.operations.writeAt(
                self.io,
                self.file,
                self.audio_offset,
                placeholder,
            );
        }
        self.failed = false;
    }

    fn validate(self: VbrPcmFileEncoder) !void {
        if (self.frame_storage.len <
            maximum_encoded_frame_bytes * 2 or
            self.committed_bytes !=
                self.stream.encoder.byte_count or
            self.finalized != self.stream.finalized)
            return error.InvalidMp3VbrFileEncoderState;
        self.stream.validate() catch
            return error.InvalidMp3VbrFileEncoderState;
    }
};

pub const PcmReservoirFileSummary = struct {
    stream: EncoderStreamSummary,
    borrowed_bytes: u64,
};

pub const VbrPcmReservoirFileSummary = struct {
    stream: EncoderStreamSummary,
    quality_misses: u64,
    maximum_noise_to_mask_ratio: f32,
    borrowed_bytes: u64,
};

pub const VbrPcmReservoirFileEncoder = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    stream: VbrPcmReservoirStreamEncoder,
    frame_storage: []u8,
    audio_offset: u64 = 0,
    committed_bytes: u64 = 0,
    metadata_quality: ?u32 = null,
    failed: bool = false,
    finalized: bool = false,

    pub fn init(
        io: std.Io,
        file: std.Io.File,
        config: VbrEncoderConfig,
        frame_storage: []u8,
        frame_offsets: []u64,
    ) !VbrPcmReservoirFileEncoder {
        return initVbrPcmReservoirFileEncoder(
            io,
            file,
            config,
            frame_storage,
            frame_offsets,
            0,
            .{},
        );
    }

    /// Preserves the file prefix and starts MP3 audio at `audio_offset`.
    pub fn initAt(
        io: std.Io,
        file: std.Io.File,
        config: VbrEncoderConfig,
        frame_storage: []u8,
        frame_offsets: []u64,
        audio_offset: u64,
    ) !VbrPcmReservoirFileEncoder {
        return initVbrPcmReservoirFileEncoder(
            io,
            file,
            config,
            frame_storage,
            frame_offsets,
            audio_offset,
            .{},
        );
    }

    pub fn initWithOperations(
        io: std.Io,
        file: std.Io.File,
        config: VbrEncoderConfig,
        frame_storage: []u8,
        frame_offsets: []u64,
        operations: file_writer_io.Operations,
    ) !VbrPcmReservoirFileEncoder {
        return initVbrPcmReservoirFileEncoder(
            io,
            file,
            config,
            frame_storage,
            frame_offsets,
            0,
            operations,
        );
    }

    pub fn valid(self: *const VbrPcmReservoirFileEncoder) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn append(
        self: *VbrPcmReservoirFileEncoder,
        pcm: PcmFrame,
    ) !VbrPcmReservoirAppend {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3VbrReservoirFileEncoderState;
        const frame_index =
            self.stream.encoder.encoder.frames.frames_encoded;
        if (frame_index >= self.stream.encoder.frame_offsets.len)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        const old_offset =
            self.stream.encoder.frame_offsets[frame_index];
        var next = self.stream;
        const appended = try next.append(
            pcm,
            self.frame_storage,
        );
        if (appended.frame) |frame| {
            self.operations.writeAt(
                self.io,
                self.file,
                try fileEncoderOffset(
                    self.audio_offset,
                    self.committed_bytes,
                ),
                frame,
            ) catch |failure| {
                self.stream.encoder.frame_offsets[frame_index] =
                    old_offset;
                self.failed = true;
                return failure;
            };
        }
        self.committed_bytes =
            try emittedVbrReservoirBytes(next);
        self.stream = next;
        return appended;
    }

    pub fn startXingMetadata(
        self: *VbrPcmReservoirFileEncoder,
        quality: ?u32,
    ) !void {
        return self.startXingMetadataWithEncoder(
            quality,
            default_xing_encoder_identifier,
        );
    }

    pub fn startXingMetadataWithEncoder(
        self: *VbrPcmReservoirFileEncoder,
        quality: ?u32,
        encoder: [9]u8,
    ) !void {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3VbrReservoirFileEncoderState;
        if (self.stream.encoder.frame_offsets.len == 0)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        const old_offset = self.stream.encoder.frame_offsets[0];
        var next = self.stream;
        const encoded = try next.startXingMetadataWithEncoder(
            encoder,
            self.frame_storage,
        );
        self.operations.writeAt(
            self.io,
            self.file,
            self.audio_offset,
            encoded,
        ) catch |failure| {
            self.stream.encoder.frame_offsets[0] = old_offset;
            self.failed = true;
            return failure;
        };
        self.committed_bytes =
            try emittedVbrReservoirBytes(next);
        self.metadata_quality = quality;
        self.stream = next;
    }

    pub fn finalize(
        self: *VbrPcmReservoirFileEncoder,
    ) !VbrPcmReservoirFileSummary {
        try self.validate();
        if (self.finalized) {
            return .{
                .stream = try self.stream.summary(),
                .quality_misses = self.stream.encoder.quality_misses,
                .maximum_noise_to_mask_ratio = self.stream.encoder
                    .maximum_noise_to_mask_ratio,
                .borrowed_bytes = self.stream.borrowed_bytes,
            };
        }
        if (self.failed)
            return error.InvalidMp3VbrReservoirFileEncoderState;
        const first_flush_index =
            self.stream.encoder.encoder.frames.frames_encoded;
        const header = try self.stream.encoder.encoder.frames
            .config.header(false);
        const flush_frames = std.math.divCeil(
            u16,
            encoder_analysis_delay,
            header.samplesPerFrame(),
        ) catch return error.Mp3SampleCountOverflow;
        if (first_flush_index + flush_frames >
            self.stream.encoder.frame_offsets.len)
            return error.Mp3VbrFrameIndexStorageTooSmall;
        var old_offsets: [2]u64 = undefined;
        for (0..flush_frames) |index| {
            old_offsets[index] =
                self.stream.encoder.frame_offsets[
                    first_flush_index + index
                ];
        }

        var next = self.stream;
        const finished = try next.finish(self.frame_storage);
        var metadata_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        const metadata = if (next.encoder.metadata_started)
            next.xingMetadataFrame(
                self.metadata_quality,
                &metadata_storage,
            ) catch |failure| {
                restoreVbrOffsets(
                    self.stream.encoder.frame_offsets,
                    first_flush_index,
                    old_offsets[0..flush_frames],
                );
                return failure;
            }
        else
            metadata_storage[0..0];
        self.operations.writeAt(
            self.io,
            self.file,
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
            finished.frames,
        ) catch |failure| {
            restoreVbrOffsets(
                self.stream.encoder.frame_offsets,
                first_flush_index,
                old_offsets[0..flush_frames],
            );
            self.failed = true;
            return failure;
        };
        if (metadata.len != 0) {
            self.operations.writeAt(
                self.io,
                self.file,
                self.audio_offset,
                metadata,
            ) catch |failure| {
                restoreVbrOffsets(
                    self.stream.encoder.frame_offsets,
                    first_flush_index,
                    old_offsets[0..flush_frames],
                );
                self.failed = true;
                return failure;
            };
        }
        self.operations.sync(self.io, self.file) catch |failure| {
            restoreVbrOffsets(
                self.stream.encoder.frame_offsets,
                first_flush_index,
                old_offsets[0..flush_frames],
            );
            self.failed = true;
            return failure;
        };
        self.committed_bytes = finished.summary.byte_count;
        self.stream = next;
        self.finalized = true;
        return .{
            .stream = finished.summary,
            .quality_misses = finished.quality_misses,
            .maximum_noise_to_mask_ratio = finished.maximum_noise_to_mask_ratio,
            .borrowed_bytes = finished.borrowed_bytes,
        };
    }

    pub fn recover(
        self: *VbrPcmReservoirFileEncoder,
    ) !void {
        try self.validate();
        if (self.finalized)
            return error.InvalidMp3VbrReservoirFileEncoderState;
        try file_writer_io.Checkpoint.exact(
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        ).restore(
            self.operations,
            self.io,
            self.file,
        );
        if (self.stream.encoder.metadata_started) {
            var metadata_config =
                self.stream.encoder.encoder.config.template;
            metadata_config.bitrate_kbps = bitrate(
                metadata_config.version,
                self.stream.encoder.encoder.config
                    .maximum_bitrate_index,
            );
            const placeholder = try encodeXingFrameFields(
                try metadata_config.header(false),
                .{
                    .kind = .variable,
                    .frame_count = 0,
                    .stream_bytes = 0,
                    .toc = @splat(0),
                    .quality = 0,
                    .encoder_delay = 0,
                    .encoder_padding = 0,
                    .encoder = self.stream.encoder.metadata_encoder,
                },
                self.frame_storage,
            );
            try self.operations.writeAt(
                self.io,
                self.file,
                self.audio_offset,
                placeholder,
            );
        }
        self.failed = false;
    }

    fn validate(
        self: VbrPcmReservoirFileEncoder,
    ) !void {
        if (self.frame_storage.len <
            maximum_encoded_frame_bytes * 3 or
            self.finalized != self.stream.encoder.finalized)
            return error.InvalidMp3VbrReservoirFileEncoderState;
        self.stream.validate() catch
            return error.InvalidMp3VbrReservoirFileEncoderState;
        const expected = emittedVbrReservoirBytes(
            self.stream,
        ) catch
            return error.InvalidMp3VbrReservoirFileEncoderState;
        if (self.committed_bytes != expected)
            return error.InvalidMp3VbrReservoirFileEncoderState;
    }
};

pub const PcmReservoirFileEncoder = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    stream: PcmReservoirStreamEncoder,
    frame_storage: []u8,
    audio_offset: u64 = 0,
    committed_bytes: u64 = 0,
    failed: bool = false,
    finalized: bool = false,

    /// The caller owns the file and frame storage for the encoder lifetime.
    pub fn init(
        io: std.Io,
        file: std.Io.File,
        config: EncoderConfig,
        frame_storage: []u8,
    ) !PcmReservoirFileEncoder {
        return initPcmReservoirFileEncoder(
            io,
            file,
            config,
            frame_storage,
            0,
            .{},
        );
    }

    /// Preserves the file prefix and starts MP3 audio at `audio_offset`.
    pub fn initAt(
        io: std.Io,
        file: std.Io.File,
        config: EncoderConfig,
        frame_storage: []u8,
        audio_offset: u64,
    ) !PcmReservoirFileEncoder {
        return initPcmReservoirFileEncoder(
            io,
            file,
            config,
            frame_storage,
            audio_offset,
            .{},
        );
    }

    pub fn initWithOperations(
        io: std.Io,
        file: std.Io.File,
        config: EncoderConfig,
        frame_storage: []u8,
        operations: file_writer_io.Operations,
    ) !PcmReservoirFileEncoder {
        return initPcmReservoirFileEncoder(
            io,
            file,
            config,
            frame_storage,
            0,
            operations,
        );
    }

    pub fn valid(self: *const PcmReservoirFileEncoder) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn append(
        self: *PcmReservoirFileEncoder,
        pcm: PcmFrame,
    ) !u16 {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3ReservoirFileEncoderState;
        var next = self.stream;
        const appended = try next.append(
            pcm,
            self.frame_storage,
        );
        if (appended.frame) |frame| {
            self.operations.writeAt(
                self.io,
                self.file,
                try fileEncoderOffset(
                    self.audio_offset,
                    self.committed_bytes,
                ),
                frame,
            ) catch |failure| {
                self.failed = true;
                return failure;
            };
        }
        self.committed_bytes = try emittedReservoirBytes(
            next,
        );
        self.stream = next;
        return appended.borrowed_bytes;
    }

    pub fn startGaplessMetadata(
        self: *PcmReservoirFileEncoder,
    ) !void {
        return self.startGaplessMetadataWithEncoder(
            default_xing_encoder_identifier,
        );
    }

    pub fn startGaplessMetadataWithEncoder(
        self: *PcmReservoirFileEncoder,
        encoder: [9]u8,
    ) !void {
        try self.validate();
        if (self.failed or self.finalized)
            return error.InvalidMp3ReservoirFileEncoderState;
        var next = self.stream;
        const encoded = try next.startGaplessMetadataWithEncoder(
            encoder,
            self.frame_storage,
        );
        self.operations.writeAt(
            self.io,
            self.file,
            self.audio_offset,
            encoded,
        ) catch |failure| {
            self.failed = true;
            return failure;
        };
        self.committed_bytes = try emittedReservoirBytes(
            next,
        );
        self.stream = next;
    }

    pub fn finalize(
        self: *PcmReservoirFileEncoder,
    ) !PcmReservoirFileSummary {
        try self.validate();
        if (self.finalized)
            return .{
                .stream = try self.stream.summary(),
                .borrowed_bytes = self.stream.encoder.borrowed_bytes,
            };
        if (self.failed)
            return error.InvalidMp3ReservoirFileEncoderState;
        var next = self.stream;
        const finished = try next.finish(self.frame_storage);
        var metadata_storage: [maximum_encoded_frame_bytes]u8 =
            undefined;
        const metadata = if (next.metadata_started)
            try next.gaplessMetadataFrame(&metadata_storage)
        else
            metadata_storage[0..0];
        self.operations.writeAt(
            self.io,
            self.file,
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
            finished.frames,
        ) catch |failure| {
            self.failed = true;
            return failure;
        };
        if (metadata.len != 0) {
            self.operations.writeAt(
                self.io,
                self.file,
                self.audio_offset,
                metadata,
            ) catch |failure| {
                self.failed = true;
                return failure;
            };
        }
        self.operations.sync(self.io, self.file) catch |failure| {
            self.failed = true;
            return failure;
        };
        self.committed_bytes = finished.summary.byte_count;
        self.stream = next;
        self.finalized = true;
        return .{
            .stream = finished.summary,
            .borrowed_bytes = finished.borrowed_bytes,
        };
    }

    pub fn recover(
        self: *PcmReservoirFileEncoder,
    ) !void {
        try self.validate();
        if (self.finalized)
            return error.InvalidMp3ReservoirFileEncoderState;
        try file_writer_io.Checkpoint.exact(
            try fileEncoderOffset(
                self.audio_offset,
                self.committed_bytes,
            ),
        ).restore(
            self.operations,
            self.io,
            self.file,
        );
        if (self.stream.metadata_started) {
            const header = try self.stream.encoder.encoder
                .frames.config.header(false);
            const placeholder = try encodeInfoFrameFields(
                header,
                0,
                0,
                0,
                0,
                self.stream.metadata_encoder,
                self.frame_storage,
            );
            try self.operations.writeAt(
                self.io,
                self.file,
                self.audio_offset,
                placeholder,
            );
        }
        self.failed = false;
    }

    fn validate(
        self: PcmReservoirFileEncoder,
    ) !void {
        if (self.frame_storage.len <
            maximum_encoded_frame_bytes * 3 or
            self.finalized != self.stream.finalized)
            return error.InvalidMp3ReservoirFileEncoderState;
        self.stream.validate() catch
            return error.InvalidMp3ReservoirFileEncoderState;
        const expected = emittedReservoirBytes(
            self.stream,
        ) catch return error.InvalidMp3ReservoirFileEncoderState;
        if (self.committed_bytes != expected)
            return error.InvalidMp3ReservoirFileEncoderState;
    }
};

pub fn emittedReservoirBytes(
    stream: PcmReservoirStreamEncoder,
) !u64 {
    return (try encoderByteState(
        stream.encoder.encoder.frames.config,
        stream.encoder.frames_emitted,
    )).byte_count;
}

pub fn emittedVbrReservoirBytes(
    stream: VbrPcmReservoirStreamEncoder,
) !u64 {
    const pending_bytes: u64 = stream.pending_length;
    if (stream.encoder.encoder.byte_count < pending_bytes)
        return error.InvalidMp3VbrReservoirStreamState;
    return stream.encoder.encoder.byte_count - pending_bytes;
}

pub fn initPcmFileEncoder(
    io: std.Io,
    file: std.Io.File,
    config: EncoderConfig,
    frame_storage: []u8,
    audio_offset: u64,
    operations: file_writer_io.Operations,
) !PcmFileEncoder {
    if (frame_storage.len < maximum_encoded_frame_bytes * 2)
        return error.Mp3FrameBufferTooSmall;
    const stream = try PcmStreamEncoder.init(config);
    try operations.setLength(io, file, audio_offset);
    return .{
        .io = io,
        .file = file,
        .operations = operations,
        .stream = stream,
        .frame_storage = frame_storage[0 .. maximum_encoded_frame_bytes * 2],
        .audio_offset = audio_offset,
    };
}

pub fn initVbrPcmFileEncoder(
    io: std.Io,
    file: std.Io.File,
    config: VbrEncoderConfig,
    frame_storage: []u8,
    frame_offsets: []u64,
    audio_offset: u64,
    operations: file_writer_io.Operations,
) !VbrPcmFileEncoder {
    if (frame_storage.len <
        maximum_encoded_frame_bytes * 2)
        return error.Mp3FrameBufferTooSmall;
    const offset_bytes = std.math.mul(
        usize,
        frame_offsets.len,
        @sizeOf(u64),
    ) catch return error.OverlappingMp3VbrStorage;
    if (byteRangesOverlap(
        @intFromPtr(frame_storage.ptr),
        frame_storage.len,
        @intFromPtr(frame_offsets.ptr),
        offset_bytes,
    )) return error.OverlappingMp3VbrStorage;
    const stream = try VbrPcmStreamEncoder.init(
        config,
        frame_offsets,
    );
    try operations.setLength(io, file, audio_offset);
    @memset(frame_offsets, 0);
    return .{
        .io = io,
        .file = file,
        .operations = operations,
        .stream = stream,
        .frame_storage = frame_storage[0 .. maximum_encoded_frame_bytes * 2],
        .audio_offset = audio_offset,
    };
}

pub fn restoreVbrOffsets(
    frame_offsets: []u64,
    first: u64,
    values: []const u64,
) void {
    for (values, 0..) |value, index|
        frame_offsets[first + index] = value;
}

pub fn initPcmReservoirFileEncoder(
    io: std.Io,
    file: std.Io.File,
    config: EncoderConfig,
    frame_storage: []u8,
    audio_offset: u64,
    operations: file_writer_io.Operations,
) !PcmReservoirFileEncoder {
    if (frame_storage.len < maximum_encoded_frame_bytes * 3)
        return error.Mp3FrameBufferTooSmall;
    const stream =
        try PcmReservoirStreamEncoder.init(config);
    try operations.setLength(io, file, audio_offset);
    return .{
        .io = io,
        .file = file,
        .operations = operations,
        .stream = stream,
        .frame_storage = frame_storage[0 .. maximum_encoded_frame_bytes * 3],
        .audio_offset = audio_offset,
    };
}

pub fn initVbrPcmReservoirFileEncoder(
    io: std.Io,
    file: std.Io.File,
    config: VbrEncoderConfig,
    frame_storage: []u8,
    frame_offsets: []u64,
    audio_offset: u64,
    operations: file_writer_io.Operations,
) !VbrPcmReservoirFileEncoder {
    if (frame_storage.len < maximum_encoded_frame_bytes * 3)
        return error.Mp3FrameBufferTooSmall;
    const offset_bytes = std.math.mul(
        usize,
        frame_offsets.len,
        @sizeOf(u64),
    ) catch return error.OverlappingMp3VbrStorage;
    if (byteRangesOverlap(
        @intFromPtr(frame_storage.ptr),
        frame_storage.len,
        @intFromPtr(frame_offsets.ptr),
        offset_bytes,
    )) return error.OverlappingMp3VbrStorage;
    const stream = try VbrPcmReservoirStreamEncoder.init(
        config,
        frame_offsets,
    );
    try operations.setLength(io, file, audio_offset);
    @memset(frame_offsets, 0);
    return .{
        .io = io,
        .file = file,
        .operations = operations,
        .stream = stream,
        .frame_storage = frame_storage[0 .. maximum_encoded_frame_bytes * 3],
        .audio_offset = audio_offset,
    };
}

pub fn fileEncoderOffset(
    audio_offset: u64,
    stream_offset: u64,
) !u64 {
    return std.math.add(
        u64,
        audio_offset,
        stream_offset,
    ) catch error.Mp3FileOffsetOverflow;
}

pub const encoder_analysis_delay: u16 = 1057;

pub fn validatePcmEncoderStereo(header: Header) !void {
    if (header.channel_mode != .joint_stereo and
        header.mode_extension != 0)
        return error.InvalidMp3EncoderStereoMode;
}

pub fn quantizeEncoderChannel(
    header: Header,
    analyzed: AnalyzedEncoderChannel,
    psychoacoustic: EncoderPsychoacousticChannel,
    bit_budget: usize,
    granule: u2,
    channel: u2,
) !QuantizedEncoderChannel {
    try validateBlockDescription(analyzed.description);
    for (analyzed.spectrum.lines) |line| {
        if (!std.math.isFinite(line))
            return error.InvalidMp3RequantizedSpectrum;
    }
    const ordered = try orderEncoderSpectrum(
        header,
        analyzed.description,
        analyzed.spectrum,
    );
    const layout = try encoderBandLayout(
        header,
        analyzed.description,
    );
    if (psychoacoustic.band_count != layout.band_count)
        return error.InvalidMp3PsychoacousticBands;
    for (0..layout.band_count) |band| {
        if (!std.math.isFinite(psychoacoustic.energy[band]) or
            psychoacoustic.energy[band] < 0 or
            !std.math.isFinite(psychoacoustic.threshold[band]) or
            psychoacoustic.threshold[band] <= 0)
            return error.InvalidMp3PsychoacousticEnergy;
    }
    for (psychoacoustic.energy[layout.band_count..]) |energy| {
        if (energy != 0)
            return error.InvalidMp3PsychoacousticBands;
    }
    for (psychoacoustic.threshold[layout.band_count..]) |threshold| {
        if (threshold != 0)
            return error.InvalidMp3PsychoacousticBands;
    }

    var quantization_description = analyzed.description;
    const intensity_stereo =
        header.channel_mode == .joint_stereo and
        header.mode_extension & 1 != 0 and
        channel == 1;
    quantization_description.scalefac_compress =
        if (intensity_stereo)
            if (header.version == .mpeg1) 13 else 358
        else if (header.version == .mpeg1)
            15
        else
            399;
    const factor_widths = try encoderScaleFactorWidths(
        header,
        quantization_description,
        intensity_stereo,
    );
    const factor_count = scaleFactorValueCount(
        header,
        quantization_description,
    );
    for (
        analyzed.intensity_enabled,
        analyzed.intensity_positions,
        0..,
    ) |enabled, position, band| {
        if (enabled) {
            if (!intensity_stereo or band >= layout.band_count or
                band >= factor_count and
                    header.version != .mpeg1 or
                factor_widths[band] != 0 and
                    position >=
                        (@as(u16, 1) << factor_widths[band]) or
                header.version == .mpeg1 and position > 6 or
                header.version != .mpeg1 and
                    position ==
                        (@as(u16, 1) << factor_widths[band]) - 1 or
                containsNonzero(
                    ordered[layout.starts[band]..layout.starts[band + 1]],
                ))
                return error.InvalidMp3EncoderIntensityStereo;
        } else if (position != 0) {
            return error.InvalidMp3EncoderIntensityStereo;
        }
    }

    var gain: u16 = 0;
    while (gain <= std.math.maxInt(u8)) : (gain += 1) {
        var spectrum: [576]i32 = undefined;
        var factors = EncoderScaleFactors{
            .value_count = factor_count,
        };
        const global_exponent =
            (@as(f64, @floatFromInt(gain)) - 210.0) * 0.25;
        var fits_range = true;
        for (0..layout.band_count) |band| {
            const maximum_factor: u8 = if (band < factor_count and
                factor_widths[band] != 0)
                @intCast(
                    (@as(u16, 1) << factor_widths[band]) - 1,
                )
            else
                0;
            var selected_factor: ?u8 = null;
            const first_factor: u8 =
                if (analyzed.intensity_enabled[band])
                    analyzed.intensity_positions[band]
                else
                    0;
            const last_factor: u8 =
                if (analyzed.intensity_enabled[band])
                    first_factor
                else
                    maximum_factor;
            if (first_factor > maximum_factor) {
                fits_range = false;
                break;
            }
            var factor = first_factor;
            while (factor <= last_factor) : (factor += 1) {
                const exponent = global_exponent -
                    0.5 * @as(f64, @floatFromInt(factor));
                const attempt = quantizeEncoderBand(
                    ordered[layout.starts[band]..layout.starts[band + 1]],
                    spectrum[layout.starts[band]..layout.starts[band + 1]],
                    exponent,
                ) catch continue;
                selected_factor = factor;
                if (attempt <= psychoacoustic.threshold[band])
                    break;
                if (factor == maximum_factor)
                    break;
            }
            if (selected_factor) |selected|
                factors.values[band] = selected
            else {
                fits_range = false;
                break;
            }
        }
        if (!fits_range)
            continue;
        var scale_factor_storage: [64]u8 = undefined;
        const encoded_factors = try encodeScaleFactors(
            header,
            quantization_description,
            0,
            granule,
            channel,
            .{},
            factors,
            &scale_factor_storage,
        );
        const selected = selectEncoderHuffman(
            header,
            quantization_description,
            &spectrum,
        ) catch |failure| switch (failure) {
            error.Mp3HuffmanTableTooSmall => continue,
            else => return failure,
        };
        if (selected.bit_count +
            encoded_factors.main_data.bit_count > bit_budget)
            continue;
        var description = selected.description;
        description.global_gain = @intCast(gain);
        return .{
            .description = description,
            .scale_factors = factors,
            .spectrum = spectrum,
        };
    }
    return error.Mp3EncoderBitBudgetTooSmall;
}

pub fn quantizeEncoderBand(
    source: []const f32,
    destination: []i32,
    exponent: f64,
) !f32 {
    if (source.len != destination.len)
        return error.InvalidMp3ScaleFactorBands;
    const step = std.math.exp2(exponent);
    var error_energy: f64 = 0;
    for (source, destination) |line, *quantized| {
        const magnitude = @abs(@as(f64, line));
        const scaled = std.math.pow(
            f64,
            magnitude / step,
            0.75,
        );
        if (!std.math.isFinite(scaled) or scaled > 8206.49)
            return error.Mp3QuantizedBandOutOfRange;
        const value: i32 = @intFromFloat(@round(scaled));
        quantized.* = if (line < 0) -value else value;
        const reconstructed = std.math.pow(
            f64,
            @floatFromInt(value),
            4.0 / 3.0,
        ) * step;
        const difference =
            reconstructed - @abs(@as(f64, line));
        error_energy += difference * difference;
    }
    if (!std.math.isFinite(error_energy))
        return error.InvalidMp3QuantizationNoise;
    return @floatCast(error_energy);
}

pub fn orderEncoderSpectrum(
    header: Header,
    description: GranuleChannel,
    spectrum: RequantizedSpectrum,
) ![576]f32 {
    if (description.block_type != 2)
        return spectrum.lines;
    const bands = try scaleFactorBands(header);
    const short_boundary: usize = if (description.mixed_block)
        3 * bands.short_starts[3]
    else
        0;
    var result: [576]f32 = undefined;
    if (short_boundary != 0)
        @memcpy(result[0..short_boundary], spectrum.lines[0..short_boundary]);
    var destination = short_boundary;
    const first_band: usize =
        if (description.mixed_block) 3 else 0;
    for (first_band..13) |band| {
        const width: usize =
            bands.short_starts[band + 1] -
            bands.short_starts[band];
        for (0..3) |window| {
            for (0..width) |offset| {
                const source =
                    3 * (@as(usize, bands.short_starts[band]) +
                        offset) +
                    window;
                result[destination] = spectrum.lines[source];
                destination += 1;
            }
        }
    }
    if (destination != result.len)
        return error.InvalidMp3ScaleFactorBands;
    return result;
}

pub fn restoreEncoderSpectrumOrder(
    header: Header,
    description: GranuleChannel,
    ordered: [576]f32,
) !RequantizedSpectrum {
    if (description.block_type != 2)
        return .{ .lines = ordered };
    const bands = try scaleFactorBands(header);
    const short_boundary: usize = if (description.mixed_block)
        3 * bands.short_starts[3]
    else
        0;
    var result = RequantizedSpectrum{};
    if (short_boundary != 0)
        @memcpy(
            result.lines[0..short_boundary],
            ordered[0..short_boundary],
        );
    var source = short_boundary;
    const first_band: usize =
        if (description.mixed_block) 3 else 0;
    for (first_band..13) |band| {
        const width: usize =
            bands.short_starts[band + 1] -
            bands.short_starts[band];
        for (0..3) |window| {
            for (0..width) |offset| {
                const destination =
                    3 * (@as(usize, bands.short_starts[band]) +
                        offset) +
                    window;
                result.lines[destination] = ordered[source];
                source += 1;
            }
        }
    }
    if (source != ordered.len)
        return error.InvalidMp3ScaleFactorBands;
    return result;
}

pub const EncoderBandLayout = struct {
    starts: [40]u16 = @splat(0),
    band_count: u6,
};

pub fn encoderBandLayout(
    header: Header,
    description: GranuleChannel,
) !EncoderBandLayout {
    const bands = try scaleFactorBands(header);
    try validateBlockDescription(description);
    var result = EncoderBandLayout{ .band_count = 0 };
    if (description.block_type != 2) {
        for (bands.long_starts, 0..) |start, index|
            result.starts[index] = start;
        result.band_count = 22;
        return result;
    }

    var index: usize = 0;
    var offset: u16 = 0;
    if (description.mixed_block) {
        const boundary: u16 = 3 * bands.short_starts[3];
        var long_band: usize = 0;
        while (bands.long_starts[long_band] < boundary) : (long_band += 1) {
            result.starts[index] = bands.long_starts[long_band];
            index += 1;
        }
        if (bands.long_starts[long_band] != boundary)
            return error.InvalidMp3ScaleFactorBands;
        offset = boundary;
    }
    const first_short_band: usize =
        if (description.mixed_block) 3 else 0;
    for (first_short_band..13) |band| {
        const width =
            bands.short_starts[band + 1] -
            bands.short_starts[band];
        for (0..3) |_| {
            result.starts[index] = offset;
            offset += width;
            index += 1;
        }
    }
    result.starts[index] = offset;
    if (offset != 576 or index > std.math.maxInt(u6))
        return error.InvalidMp3ScaleFactorBands;
    result.band_count = @intCast(index);
    return result;
}

pub fn encoderScaleFactorWidths(
    header: Header,
    description: GranuleChannel,
    intensity_stereo: bool,
) ![39]u4 {
    var result: [39]u4 = @splat(0);
    if (header.version == .mpeg1) {
        if (description.scalefac_compress >=
            mpeg1_scale_factor_lengths.len)
            return error.InvalidMp3ScaleFactorCompression;
        const lengths =
            mpeg1_scale_factor_lengths[description.scalefac_compress];
        if (description.block_type == 2) {
            const first_count: usize =
                if (description.mixed_block) 17 else 18;
            @memset(result[0..first_count], lengths[0]);
            @memset(
                result[first_count .. first_count + 18],
                lengths[1],
            );
        } else {
            @memset(result[0..11], lengths[0]);
            @memset(result[11..21], lengths[1]);
        }
    } else {
        const plan = try lsfScaleFactorPlan(
            description.scalefac_compress,
            intensity_stereo,
        );
        const factor_layout: usize =
            if (description.block_type != 2)
                0
            else if (description.mixed_block)
                2
            else
                1;
        var index: usize = 0;
        for (
            lsf_scale_factor_counts[plan.table][factor_layout],
            0..,
        ) |count, part| {
            @memset(
                result[index .. index + count],
                plan.lengths[part],
            );
            index += count;
        }
    }
    if (description.block_type == 2) {
        const bands = try encoderBandLayout(header, description);
        @memset(
            result[bands.band_count - 3 .. bands.band_count],
            0,
        );
        @memset(
            result[scaleFactorValueCount(header, description)..],
            0,
        );
    } else result[21] = 0;
    return result;
}

pub const EncoderHuffmanSelection = struct {
    description: GranuleChannel,
    bit_count: usize,
};

pub fn selectEncoderHuffman(
    header: Header,
    source: GranuleChannel,
    spectrum: *const [576]i32,
) !EncoderHuffmanSelection {
    var last_nonzero: usize = 0;
    var last_large: usize = 0;
    for (spectrum, 0..) |value, index| {
        const magnitude = try quantizedMagnitude(value);
        if (magnitude != 0) last_nonzero = index + 1;
        if (magnitude > 1) last_large = index + 1;
    }
    var big_line_count = std.mem.alignForward(
        usize,
        last_large,
        2,
    );
    var count1_end = big_line_count + std.mem.alignForward(
        usize,
        if (last_nonzero > big_line_count)
            last_nonzero - big_line_count
        else
            0,
        4,
    );
    if (count1_end > spectrum.len) {
        big_line_count = std.mem.alignForward(
            usize,
            last_nonzero,
            2,
        );
        count1_end = big_line_count;
    }
    var description = source;
    description.big_values = @intCast(big_line_count / 2);

    const count1_a = try encoderCount1BitCost(
        false,
        spectrum[big_line_count..count1_end],
    );
    const count1_b = try encoderCount1BitCost(
        true,
        spectrum[big_line_count..count1_end],
    );
    description.count1_table_select = count1_b < count1_a;
    const count1_bits = @min(count1_a, count1_b);

    const regions = if (description.block_type == 2)
        try selectShortEncoderTables(
            header,
            description,
            spectrum,
            big_line_count,
        )
    else if (description.window_switching)
        try selectSwitchedLongEncoderTables(
            header,
            spectrum,
            big_line_count,
        )
    else
        try selectLongEncoderTables(
            header,
            spectrum,
            big_line_count,
        );
    description.table_select = regions.tables;
    description.region0_count = regions.region0_count;
    description.region1_count = regions.region1_count;
    return .{
        .description = description,
        .bit_count = regions.bit_count + count1_bits,
    };
}

pub const EncoderRegionSelection = struct {
    tables: [3]u5 = @splat(0),
    region0_count: u4 = 0,
    region1_count: u4 = 0,
    bit_count: usize,
};

pub fn selectShortEncoderTables(
    header: Header,
    description: GranuleChannel,
    spectrum: *const [576]i32,
    big_line_count: usize,
) !EncoderRegionSelection {
    const ends = try huffmanRegionEnds(header, description);
    const first_end = @min(@as(usize, ends[0]), big_line_count);
    const first = try selectEncoderTable(
        spectrum[0..first_end],
    );
    const second = try selectEncoderTable(
        spectrum[first_end..big_line_count],
    );
    const region0_count: u4 =
        if (description.mixed_block) 7 else 8;
    return .{
        .tables = .{ first.table, second.table, 0 },
        .region0_count = region0_count,
        .region1_count = @intCast(20 - @as(u8, region0_count)),
        .bit_count = first.bit_count + second.bit_count,
    };
}

pub fn selectSwitchedLongEncoderTables(
    header: Header,
    spectrum: *const [576]i32,
    big_line_count: usize,
) !EncoderRegionSelection {
    const bands = try scaleFactorBands(header);
    const first_end = @min(
        @as(usize, bands.long_starts[8]),
        big_line_count,
    );
    const first = try selectEncoderTable(
        spectrum[0..first_end],
    );
    const second = try selectEncoderTable(
        spectrum[first_end..big_line_count],
    );
    return .{
        .tables = .{ first.table, second.table, 0 },
        .region0_count = 7,
        .region1_count = 13,
        .bit_count = first.bit_count + second.bit_count,
    };
}

pub fn selectLongEncoderTables(
    header: Header,
    spectrum: *const [576]i32,
    big_line_count: usize,
) !EncoderRegionSelection {
    const bands = try scaleFactorBands(header);
    var best: ?EncoderRegionSelection = null;
    for (0..16) |region0| {
        for (0..8) |region1| {
            const first_index = region0 + 1;
            const second_index = first_index + region1 + 1;
            if (second_index >= bands.long_starts.len)
                continue;
            const first_end = @min(
                @as(usize, bands.long_starts[first_index]),
                big_line_count,
            );
            const second_end = @min(
                @as(usize, bands.long_starts[second_index]),
                big_line_count,
            );
            const first = try selectEncoderTable(
                spectrum[0..first_end],
            );
            const second = try selectEncoderTable(
                spectrum[first_end..second_end],
            );
            const third = try selectEncoderTable(
                spectrum[second_end..big_line_count],
            );
            const candidate = EncoderRegionSelection{
                .tables = .{
                    first.table,
                    second.table,
                    third.table,
                },
                .region0_count = @intCast(region0),
                .region1_count = @intCast(region1),
                .bit_count = first.bit_count +
                    second.bit_count + third.bit_count,
            };
            if (best) |current| {
                if (candidate.bit_count < current.bit_count)
                    best = candidate;
            } else {
                best = candidate;
            }
        }
    }
    return best orelse error.InvalidMp3RegionCounts;
}

pub const EncoderTableSelection = struct {
    table: u5,
    bit_count: usize,
};

pub fn selectEncoderTable(
    values: []const i32,
) !EncoderTableSelection {
    const valid_tables = [_]u5{
        0,  1,  2,  3,  5,  6,  7,  8,  9,  10,
        11, 12, 13, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
    };
    var best: ?EncoderTableSelection = null;
    for (valid_tables) |table_index| {
        const table = try huffman_tables.get(table_index);
        var bit_count: usize = 0;
        var line: usize = 0;
        var fits = true;
        while (line < values.len) : (line += 2) {
            const cost = encoderPairBitCost(
                table,
                values[line..][0..2].*,
            ) catch {
                fits = false;
                break;
            };
            bit_count += cost;
        }
        if (!fits) continue;
        if (best) |current| {
            if (bit_count >= current.bit_count) continue;
        }
        best = .{
            .table = table_index,
            .bit_count = bit_count,
        };
    }
    return best orelse error.Mp3HuffmanTableTooSmall;
}

pub fn encoderPairBitCost(
    table: huffman_tables.Table,
    values: [2]i32,
) !usize {
    var magnitudes: [2]u32 = undefined;
    for (values, 0..) |value, index|
        magnitudes[index] = try quantizedMagnitude(value);
    if (table.side == 1) {
        if (magnitudes[0] != 0 or magnitudes[1] != 0)
            return error.Mp3HuffmanTableTooSmall;
        return 0;
    }
    const maximum: u32 = if (table.linbits == 0)
        table.side - 1
    else
        15 + (@as(u32, 1) << table.linbits) - 1;
    if (magnitudes[0] > maximum or magnitudes[1] > maximum)
        return error.Mp3HuffmanTableTooSmall;
    const entry = table.entries[
        @as(usize, @min(magnitudes[0], 15)) * table.side +
            @as(usize, @min(magnitudes[1], 15))
    ];
    var bit_count: usize = entry.length;
    for (magnitudes) |magnitude| {
        if (magnitude >= 15 and table.linbits != 0)
            bit_count += table.linbits;
        if (magnitude != 0)
            bit_count += 1;
    }
    return bit_count;
}

pub fn encoderCount1BitCost(
    table_b: bool,
    values: []const i32,
) !usize {
    var bit_count: usize = 0;
    var line: usize = 0;
    while (line < values.len) : (line += 4) {
        var pattern: u4 = 0;
        var signs: usize = 0;
        for (values[line..][0..4], 0..) |value, index| {
            const magnitude = try quantizedMagnitude(value);
            if (magnitude > 1)
                return error.InvalidMp3Count1Value;
            pattern |= @as(u4, @intCast(magnitude)) <<
                @intCast(3 - index);
            signs += @intFromBool(magnitude != 0);
        }
        bit_count += if (table_b)
            4
        else
            count1_table_a[pattern].length;
        bit_count += signs;
    }
    return bit_count;
}

pub const Mp3FileFaults = struct {
    delegate: file_writer_io.Operations = .{},
    write_calls: usize = 0,
    sync_calls: usize = 0,
    fail_write_call: ?usize = null,
    fail_sync_call: ?usize = null,
    partial_write_bytes: usize = 0,

    pub fn operations(self: *Mp3FileFaults) file_writer_io.Operations {
        return .{
            .context = self,
            .vtable = &vtable,
        };
    }

    fn writeAt(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        offset: u64,
        bytes: []const u8,
    ) !usize {
        const self: *Mp3FileFaults = @ptrCast(@alignCast(
            context orelse return error.MissingFaultContext,
        ));
        self.write_calls += 1;
        if (self.fail_write_call == self.write_calls) {
            const partial = @min(
                self.partial_write_bytes,
                bytes.len,
            );
            if (partial != 0)
                try self.delegate.writeAt(
                    io,
                    file,
                    offset,
                    bytes[0..partial],
                );
            return error.InjectedMp3FileWriteFailure;
        }
        try self.delegate.writeAt(io, file, offset, bytes);
        return bytes.len;
    }

    fn setLength(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        length: u64,
    ) !void {
        const self: *Mp3FileFaults = @ptrCast(@alignCast(
            context orelse return error.MissingFaultContext,
        ));
        try self.delegate.setLength(io, file, length);
    }

    fn sync(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
    ) !void {
        const self: *Mp3FileFaults = @ptrCast(@alignCast(
            context orelse return error.MissingFaultContext,
        ));
        self.sync_calls += 1;
        if (self.fail_sync_call == self.sync_calls)
            return error.InjectedMp3FileSyncFailure;
        try self.delegate.sync(io, file);
    }

    const vtable = file_writer_io.Operations.VTable{
        .write_at = writeAt,
        .set_length = setLength,
        .sync = sync,
    };
};

pub fn testHeader(
    version_bits: u2,
    protection: bool,
    bitrate_index: u4,
    rate_index: u2,
    padding: bool,
    mode: ChannelMode,
) [4]u8 {
    var value: u32 = 0x7ff << 21;
    value |= @as(u32, version_bits) << 19;
    value |= 1 << 17;
    value |= @as(u32, @intFromBool(protection)) << 16;
    value |= @as(u32, bitrate_index) << 12;
    value |= @as(u32, rate_index) << 10;
    value |= @as(u32, @intFromBool(padding)) << 9;
    value |= @as(u32, @intFromEnum(mode)) << 6;
    return .{
        @intCast((value >> 24) & 0xff),
        @intCast((value >> 16) & 0xff),
        @intCast((value >> 8) & 0xff),
        @intCast(value & 0xff),
    };
}

pub fn setTestBits(
    destination: []u8,
    bit_offset: usize,
    bit_count: u5,
    value: u32,
) void {
    for (0..bit_count) |index| {
        const destination_bit = bit_offset + index;
        const mask: u8 =
            @as(u8, 1) << @intCast(7 - destination_bit % 8);
        const source_shift: u5 =
            @intCast(bit_count - 1 - index);
        if (value >> source_shift & 1 != 0)
            destination[destination_bit / 8] |= mask
        else
            destination[destination_bit / 8] &= ~mask;
    }
}

pub fn setMpeg1MonoLongChannel(
    side: []u8,
    granule: usize,
    part2_3_length: u12,
    big_values: u9,
    global_gain: u8,
    table_select_0: u5,
) void {
    const start = 18 + granule * 59;
    setTestBits(side, start, 12, part2_3_length);
    setTestBits(side, start + 12, 9, big_values);
    setTestBits(side, start + 21, 8, global_gain);
    setTestBits(side, start + 34, 5, table_select_0);
}

pub fn readTestI16(bytes: *const [2]u8) i16 {
    const value = @as(u16, bytes[0]) |
        (@as(u16, bytes[1]) << 8);
    return @bitCast(value);
}

pub fn appendFrame(
    destination: []u8,
    offset: usize,
    header_bytes: [4]u8,
) !usize {
    const header = try Header.parse(&header_bytes);
    const length = header.frameBytes();
    if (destination.len - offset < length) return error.TestStorageTooSmall;
    @memset(destination[offset .. offset + length], 0);
    @memcpy(destination[offset..][0..4], &header_bytes);
    return offset + length;
}

pub fn appendFreeFormatFrame(
    destination: []u8,
    offset: usize,
    header_bytes: [4]u8,
    base_bytes: usize,
) !usize {
    const header = try Header.parse(&header_bytes);
    if (!header.free_format)
        return error.TestHeaderIsNotFreeFormat;
    const length = try resolvedFrameBytes(header, base_bytes);
    if (offset > destination.len or
        length > destination.len - offset)
        return error.TestStorageTooSmall;
    @memset(destination[offset .. offset + length], 0);
    @memcpy(destination[offset..][0..4], &header_bytes);
    return offset + length;
}

pub fn repairTestFrameCrc(destination: []u8, offset: usize) !void {
    if (offset > destination.len or destination.len - offset < 4)
        return error.TestStorageTooSmall;
    const header = try Header.parse(destination[offset..]);
    if (!header.crc_present) return error.TestFrameHasNoCrc;
    const side_offset = offset + 6;
    const side_end = side_offset + header.sideInformationBytes();
    if (side_end > destination.len) return error.TestStorageTooSmall;
    var checksum = crc16(0xffff, destination[offset + 2 .. offset + 4]);
    checksum = crc16(checksum, destination[side_offset..side_end]);
    destination[offset + 4] = @intCast(checksum >> 8);
    destination[offset + 5] = @intCast(checksum & 0xff);
}
