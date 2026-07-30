const std = @import("std");
const file_reader_io = @import("file_reader_io.zig");
const huffman_tables = @import("mp3_huffman_tables.zig");
const synthesis_window_quantized =
    @import("mp3_synthesis_window.zig").values;

pub const Version = enum {
    mpeg1,
    mpeg2,
    mpeg25,
};

pub const ChannelMode = enum(u2) {
    stereo = 0,
    joint_stereo = 1,
    dual_channel = 2,
    mono = 3,
};

pub const maximum_free_format_frame_bytes: usize = 16 * 1024;
pub const maximum_encoded_frame_bytes: usize = 1441;
const maximum_frame_main_data_bytes: usize =
    (4 * std.math.maxInt(u12) + 7) / 8;

pub const Header = struct {
    version: Version,
    crc_present: bool,
    free_format: bool,
    bitrate_kbps: u16,
    sample_rate: u32,
    padding: bool,
    private: bool,
    channel_mode: ChannelMode,
    mode_extension: u2,
    copyright: bool,
    original: bool,
    emphasis: u2,

    pub fn parse(bytes: []const u8) !Header {
        if (bytes.len < 4) return error.TruncatedMp3Header;
        const value = readU32(bytes[0..4]);
        if (value >> 21 != 0x7ff) return error.InvalidMp3Sync;

        const version = switch (@as(u2, @intCast((value >> 19) & 0x3))) {
            0 => Version.mpeg25,
            1 => return error.ReservedMp3Version,
            2 => Version.mpeg2,
            3 => Version.mpeg1,
        };
        if (((value >> 17) & 0x3) != 1)
            return error.NotMp3LayerThree;

        const bitrate_index: u4 = @intCast((value >> 12) & 0xf);
        if (bitrate_index == 15) return error.InvalidMp3Bitrate;
        const rate_index: u2 = @intCast((value >> 10) & 0x3);
        if (rate_index == 3) return error.InvalidMp3SampleRate;

        return .{
            .version = version,
            .crc_present = ((value >> 16) & 1) == 0,
            .free_format = bitrate_index == 0,
            .bitrate_kbps = if (bitrate_index == 0)
                0
            else
                bitrate(version, bitrate_index),
            .sample_rate = sampleRate(version, rate_index),
            .padding = ((value >> 9) & 1) != 0,
            .private = ((value >> 8) & 1) != 0,
            .channel_mode = @enumFromInt((value >> 6) & 0x3),
            .mode_extension = @intCast((value >> 4) & 0x3),
            .copyright = ((value >> 3) & 1) != 0,
            .original = ((value >> 2) & 1) != 0,
            .emphasis = @intCast(value & 0x3),
        };
    }

    pub fn channels(self: Header) u8 {
        return if (self.channel_mode == .mono) 1 else 2;
    }

    pub fn samplesPerFrame(self: Header) u16 {
        return if (self.version == .mpeg1) 1152 else 576;
    }

    pub fn frameBytes(self: Header) usize {
        if (self.free_format) return 0;
        const coefficient: u64 =
            if (self.version == .mpeg1) 144_000 else 72_000;
        const base = coefficient * self.bitrate_kbps / self.sample_rate;
        return @intCast(base + @intFromBool(self.padding));
    }

    pub fn sideInformationBytes(self: Header) u8 {
        return switch (self.version) {
            .mpeg1 => if (self.channels() == 1) 17 else 32,
            .mpeg2, .mpeg25 => if (self.channels() == 1) 9 else 17,
        };
    }

    pub fn encode(self: Header) ![4]u8 {
        const version_bits: u2 = switch (self.version) {
            .mpeg1 => 3,
            .mpeg2 => 2,
            .mpeg25 => 0,
        };
        const rate_index = sampleRateIndex(
            self.version,
            self.sample_rate,
        ) orelse return error.InvalidMp3EncoderSampleRate;
        const bitrate_index: u4 = if (self.free_format) blk: {
            if (self.bitrate_kbps != 0)
                return error.InvalidMp3EncoderBitrate;
            break :blk 0;
        } else bitrateIndex(
            self.version,
            self.bitrate_kbps,
        ) orelse return error.InvalidMp3EncoderBitrate;
        if (self.emphasis == 2)
            return error.InvalidMp3EncoderEmphasis;

        var value: u32 = 0x7ff << 21;
        value |= @as(u32, version_bits) << 19;
        value |= 1 << 17;
        value |= @as(u32, @intFromBool(!self.crc_present)) << 16;
        value |= @as(u32, bitrate_index) << 12;
        value |= @as(u32, rate_index) << 10;
        value |= @as(u32, @intFromBool(self.padding)) << 9;
        value |= @as(u32, @intFromBool(self.private)) << 8;
        value |= @as(u32, @intFromEnum(self.channel_mode)) << 6;
        value |= @as(u32, self.mode_extension) << 4;
        value |= @as(u32, @intFromBool(self.copyright)) << 3;
        value |= @as(u32, @intFromBool(self.original)) << 2;
        value |= self.emphasis;
        return .{
            @intCast(value >> 24),
            @intCast((value >> 16) & 0xff),
            @intCast((value >> 8) & 0xff),
            @intCast(value & 0xff),
        };
    }

    fn compatible(self: Header, other: Header) bool {
        return self.version == other.version and
            self.sample_rate == other.sample_rate and
            self.free_format == other.free_format and
            self.channels() == other.channels();
    }
};

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

    pub fn nextFrameBytes(self: FrameEncoder) !usize {
        const next = try self.advance();
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
        const next = try self.advance();
        const frame_bytes = next.header.frameBytes();
        if (destination.len < frame_bytes)
            return error.InsufficientMp3EncoderStorage;

        var staged: [maximum_encoded_frame_bytes]u8 = @splat(0);
        const encoded_header = try next.header.encode();
        @memcpy(staged[0..4], &encoded_header);
        const side_offset: usize =
            if (next.header.crc_present) 6 else 4;
        const side_end = side_offset +
            next.header.sideInformationBytes();
        const channel_count: u2 =
            @intCast(next.header.channels());
        const granule_count: u2 =
            if (next.header.version == .mpeg1) 2 else 1;
        var side = SideInformation{
            .channel_count = channel_count,
            .granule_count = granule_count,
            .main_data_begin = 0,
            .private_bits = frame.private_bits,
            .scfsi = frame.scfsi,
            .main_data_bits = 0,
        };
        var main_writer = MainDataBitWriter{
            .bytes = staged[side_end..frame_bytes],
        };
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
                if (source.description.part2_3_length != 0 or
                    source.description.scalefac_compress != 0)
                    return error.UnsupportedMp3EncoderScaleFactors;
                const encoded = try encodeHuffmanChannel(
                    next.header,
                    source.description,
                    &source.spectrum,
                    &channel_storage,
                );
                try appendMainDataBits(
                    &main_writer,
                    encoded.main_data,
                );
                side.granules[granule].channels[channel] =
                    encoded.description;
                side.main_data_bits = std.math.add(
                    u16,
                    side.main_data_bits,
                    encoded.main_data.bit_count,
                ) catch return error.Mp3MainDataBitCountOverflow;
            }
        }
        if (main_writer.bit_offset != side.main_data_bits)
            return error.InvalidMp3EncoderState;
        var side_storage: [32]u8 = undefined;
        const encoded_side = try encodeSideInformation(
            next.header,
            side,
            &side_storage,
        );
        @memcpy(staged[side_offset..side_end], encoded_side);
        if (next.header.crc_present) {
            var checksum = crc16(0xffff, staged[2..4]);
            checksum = crc16(checksum, staged[side_offset..side_end]);
            staged[4] = @intCast(checksum >> 8);
            staged[5] = @intCast(checksum & 0xff);
        }

        @memcpy(destination[0..frame_bytes], staged[0..frame_bytes]);
        self.padding_accumulator = next.padding_accumulator;
        self.frames_encoded += 1;
        return destination[0..frame_bytes];
    }

    const Advance = struct {
        header: Header,
        padding_accumulator: u32,
    };

    fn advance(self: FrameEncoder) !Advance {
        _ = try self.config.header(false);
        if (self.padding_accumulator >= self.config.sample_rate)
            return error.InvalidMp3EncoderState;
        if (self.frames_encoded == std.math.maxInt(u64))
            return error.Mp3EncoderFrameCountOverflow;

        const coefficient: u64 =
            if (self.config.version == .mpeg1) 144_000 else 72_000;
        const numerator = coefficient * self.config.bitrate_kbps;
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
            .header = try self.config.header(padding),
            .padding_accumulator = next_accumulator,
        };
    }
};

pub const GranuleChannel = struct {
    part2_3_length: u12 = 0,
    big_values: u9 = 0,
    global_gain: u8 = 0,
    scalefac_compress: u9 = 0,
    window_switching: bool = false,
    block_type: u2 = 0,
    mixed_block: bool = false,
    table_select: [3]u5 = @splat(0),
    subblock_gain: [3]u3 = @splat(0),
    region0_count: u4 = 0,
    region1_count: u4 = 0,
    preflag: bool = false,
    scalefac_scale: bool = false,
    count1_table_select: bool = false,
};

pub const Granule = struct {
    channels: [2]GranuleChannel = @splat(.{}),
};

pub const QuantizedEncoderChannel = struct {
    description: GranuleChannel = .{},
    spectrum: [576]i32 = @splat(0),
};

pub const QuantizedEncoderFrame = struct {
    private_bits: u5 = 0,
    scfsi: [2]u4 = @splat(0),
    granules: [2][2]QuantizedEncoderChannel =
        @splat(@splat(.{})),
};

pub const SideInformation = struct {
    channel_count: u2,
    granule_count: u2,
    main_data_begin: u9,
    private_bits: u5,
    scfsi: [2]u4 = @splat(0),
    granules: [2]Granule = @splat(.{}),
    main_data_bits: u16,
};

pub fn encodeSideInformation(
    header: Header,
    side: SideInformation,
    destination: []u8,
) ![]u8 {
    _ = try header.encode();
    const channel_count: u2 = @intCast(header.channels());
    const granule_count: u2 =
        if (header.version == .mpeg1) 2 else 1;
    if (side.channel_count != channel_count or
        side.granule_count != granule_count)
        return error.InvalidMp3SideInformation;
    const size: usize = header.sideInformationBytes();
    if (destination.len < size)
        return error.InsufficientMp3SideInformationStorage;

    var staged: [32]u8 = @splat(0);
    var bit_offset: usize = 0;
    try writeSideInformationBits(
        &staged,
        &bit_offset,
        side.main_data_begin,
        if (header.version == .mpeg1) 9 else 8,
    );
    try writeSideInformationBits(
        &staged,
        &bit_offset,
        side.private_bits,
        switch (header.version) {
            .mpeg1 => if (channel_count == 1) 5 else 3,
            .mpeg2, .mpeg25 => if (channel_count == 1) 1 else 2,
        },
    );
    if (header.version == .mpeg1) {
        for (side.scfsi[0..channel_count]) |value|
            try writeSideInformationBits(
                &staged,
                &bit_offset,
                value,
                4,
            );
    }
    for (0..granule_count) |granule| {
        for (0..channel_count) |channel|
            try encodeGranuleChannelSideInformation(
                &staged,
                &bit_offset,
                header.version,
                side.granules[granule].channels[channel],
            );
    }
    if (bit_offset != size * 8)
        return error.InvalidMp3SideInformation;

    var frame_storage: [38]u8 = @splat(0);
    const encoded_header = try header.encode();
    @memcpy(frame_storage[0..4], &encoded_header);
    const side_offset: usize = if (header.crc_present) 6 else 4;
    @memcpy(frame_storage[side_offset..][0..size], staged[0..size]);
    const parsed = try parseSideInformation(
        frame_storage[0 .. side_offset + size],
        header,
    );
    if (!std.meta.eql(parsed, side))
        return error.InvalidMp3SideInformation;

    @memcpy(destination[0..size], staged[0..size]);
    return destination[0..size];
}

pub const MainData = struct {
    bytes: []const u8,
    bit_count: u16,
};

pub const ScaleFactorChannel = struct {
    values: [39]u8 = @splat(0),
    intensity_max: [39]bool = @splat(false),
    value_count: u6 = 0,
    part2_bits: u12 = 0,
    huffman_bit_offset: u16 = 0,
    huffman_bit_count: u12 = 0,
    preflag: bool = false,
    intensity_scale: bool = false,
};

pub const ScaleFactorGranule = struct {
    channels: [2]ScaleFactorChannel = @splat(.{}),
};

pub const ScaleFactors = struct {
    channel_count: u2,
    granule_count: u2,
    granules: [2]ScaleFactorGranule = @splat(.{}),
    bit_count: u16,
};

pub const ScaleFactorBands = struct {
    long_starts: []const u16,
    short_starts: []const u16,
};

pub const QuantizedSpectrum = struct {
    lines: [576]i32 = @splat(0),
    decoded_lines: u10 = 0,
    huffman_bits_consumed: u12 = 0,
};

pub const RequantizedSpectrum = struct {
    lines: [576]f32 = @splat(0),
};

pub const StereoSpectrum = struct {
    channels: [2]RequantizedSpectrum,
};

pub const HybridSamples = struct {
    time_slots: [18][32]f32 = @splat(@splat(0)),
};

pub const PcmGranule = struct {
    samples: [576]f32 = @splat(0),
};

pub const PcmFrame = struct {
    channels: [2][1152]f32 = @splat(@splat(0)),
    channel_count: u2,
    sample_count: u16,
};

pub const DecoderFormat = struct {
    version: Version,
    sample_rate: u32,
    channel_count: u2,
};

pub const HybridSynthesis = struct {
    overlap: [32][18]f32 = @splat(@splat(0)),

    pub fn reset(self: *HybridSynthesis) void {
        self.* = .{};
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
        for (self.overlap) |subband| {
            for (subband) |sample| {
                if (!std.math.isFinite(sample))
                    return error.InvalidMp3HybridState;
            }
        }

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

    pub fn process(
        self: *PolyphaseSynthesis,
        hybrid: HybridSamples,
    ) !PcmGranule {
        if (self.head_block >= 16)
            return error.InvalidMp3PolyphaseState;
        for (self.history) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidMp3PolyphaseState;
        }
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

    pub fn decode(
        self: *FrameDecoder,
        frame: anytype,
    ) !PcmFrame {
        if (try frame.crcValid()) |valid| {
            if (!valid) return error.InvalidMp3FrameCrc;
        }
        const format = DecoderFormat{
            .version = frame.header.version,
            .sample_rate = frame.header.sample_rate,
            .channel_count = @intCast(frame.header.channels()),
        };
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

    pub fn fromSummary(summary: Summary) !GaplessPlan {
        var leading: u32 = 0;
        var trailing: u32 = 0;
        if (summary.first_xing) |xing| {
            if ((xing.encoder_delay == null) !=
                (xing.encoder_padding == null))
                return error.InvalidMp3GaplessMetadata;
            if (xing.encoder_delay) |delay| {
                leading = delay;
                trailing = xing.encoder_padding orelse
                    return error.InvalidMp3GaplessMetadata;
            }
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
        const trimmed = std.math.add(
            u64,
            self.leading_samples,
            self.trailing_samples,
        ) catch return error.InvalidMp3GaplessPlan;
        if (trimmed > self.encoded_samples or
            self.audible_samples != self.encoded_samples - trimmed or
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
        if (summary.sample_rate == 0 or
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

    pub fn decode(
        self: *StreamDecoder,
        frame: anytype,
    ) !TrimmedPcmFrame {
        if (self.sample_rate == 0 or
            self.channel_count == 0 or
            self.channel_count > 2 or
            frame.header.sample_rate != self.sample_rate or
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
        if (self.sample_rate == 0 or
            self.channel_count == 0 or
            self.channel_count > 2)
            return error.InvalidMp3StreamDecoderState;
        _ = try self.plan.frameRange(
            self.plan.encoded_samples,
            0,
        );
        if (self.sample_offset != self.plan.encoded_samples)
            return error.Mp3GaplessStreamIncomplete;
    }
};

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

const ScaleFactorLayout = struct {
    bands: ScaleFactorBands,
    short_block: bool,
    short_boundary: usize,
    long_factor_count: usize,
};

fn scaleFactorLayout(
    header: Header,
    description: GranuleChannel,
    factors: ScaleFactorChannel,
) !ScaleFactorLayout {
    const bands = try scaleFactorBands(header);
    const short_block = description.block_type == 2;
    try validateBlockDescription(description);
    if (header.version == .mpeg1 and
        factors.preflag != description.preflag)
        return error.InvalidMp3ScaleFactors;

    const short_boundary: usize = 3 * bands.short_starts[3];
    var long_factor_count: usize = 0;
    if (description.mixed_block) {
        while (long_factor_count < bands.long_starts.len and
            bands.long_starts[long_factor_count] < short_boundary)
            long_factor_count += 1;
        if (long_factor_count >= bands.long_starts.len or
            bands.long_starts[long_factor_count] != short_boundary)
            return error.InvalidMp3ScaleFactorBands;
    }
    const expected_factor_count: u6 = switch (header.version) {
        .mpeg1 => if (!short_block)
            22
        else if (description.mixed_block)
            38
        else
            39,
        .mpeg2, .mpeg25 => if (!short_block)
            21
        else if (description.mixed_block)
            33
        else
            36,
    };
    if (factors.value_count != expected_factor_count)
        return error.InvalidMp3ScaleFactors;
    if (!short_block) {
        if (factors.values[21] != 0)
            return error.InvalidMp3ScaleFactors;
    } else {
        const terminal_start =
            if (description.mixed_block)
                long_factor_count + 27
            else
                36;
        for (factors.values[terminal_start..][0..3]) |factor| {
            if (factor != 0) return error.InvalidMp3ScaleFactors;
        }
    }
    return .{
        .bands = bands,
        .short_block = short_block,
        .short_boundary = short_boundary,
        .long_factor_count = long_factor_count,
    };
}

fn validateBlockDescription(description: GranuleChannel) !void {
    if (description.window_switching ==
        (description.block_type == 0) or
        description.mixed_block and !description.window_switching)
        return error.InvalidMp3BlockType;
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

const alias_cs = [_]f32{
    0.8574929257125442,
    0.8817419973177052,
    0.9496286491027328,
    0.9833145924917902,
    0.9955178160675858,
    0.9991605581781475,
    0.9998991952434471,
    0.9999931550702803,
};

const alias_ca = [_]f32{
    -0.5144957554275265,
    -0.47173196856497235,
    -0.31337745420390184,
    -0.18191319961098118,
    -0.09457419252642066,
    -0.04096558288530405,
    -0.01419856857247115,
    -0.0036999746737600373,
};

fn mixedLongSubbands(header: Header) usize {
    return if (header.version == .mpeg25 and
        header.sample_rate == 8_000)
        4
    else
        2;
}

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

fn buildSynthesisWindow() [512]f64 {
    var result: [512]f64 = undefined;
    for (synthesis_window_quantized, 0..) |value, index| {
        result[index] =
            @as(f64, @floatFromInt(value)) / 65_536.0;
    }
    return result;
}

const long_imdct = buildImdctMatrix(18);
const short_imdct = buildImdctMatrix(6);
const long_windows = buildLongWindows();
const short_window = buildShortWindow();
const synthesis_matrix = buildSynthesisMatrix();
const synthesis_window = buildSynthesisWindow();

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

fn checkedHybridSample(value: f64) !f32 {
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
        if ((last_nonzero == null or band > last_nonzero.?) and
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
            const use_intensity =
                (last_nonzero[window] == null or
                    band > last_nonzero[window].?) and
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

fn mpeg1IntensityGains(position: u8) [2]f32 {
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

fn lsfIntensityGains(
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

fn containsNonzero(lines: []const f32) bool {
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

pub fn MainDataReservoir(comptime capacity: usize) type {
    if (capacity < 511)
        @compileError("MP3 main-data reservoirs require at least 511 bytes");

    return struct {
        const Self = @This();

        storage: [capacity]u8 = @splat(0),
        length: usize = 0,

        pub fn reset(self: *Self) void {
            self.length = 0;
        }

        pub fn assemble(
            self: *Self,
            frame: anytype,
            destination: []u8,
        ) !MainData {
            if (self.length > self.storage.len)
                return error.InvalidMp3ReservoirState;
            const side = try frame.sideInformation();
            const current_offset = std.math.add(
                usize,
                if (frame.header.crc_present) 6 else 4,
                frame.header.sideInformationBytes(),
            ) catch return error.TruncatedMp3Frame;
            if (current_offset > frame.bytes.len)
                return error.TruncatedMp3Frame;
            const current = frame.bytes[current_offset..];
            if (byteRangesOverlap(
                @intFromPtr(frame.bytes.ptr),
                frame.bytes.len,
                @intFromPtr(self.storage[0..].ptr),
                self.storage.len,
            )) return error.OverlappingMp3ReservoirStorage;
            const history_bytes: usize = side.main_data_begin;
            if (history_bytes > self.length)
                return error.Mp3MainDataHistoryUnavailable;
            const required_bytes =
                (@as(usize, side.main_data_bits) + 7) / 8;
            if (required_bytes > history_bytes and
                required_bytes - history_bytes > current.len)
                return error.TruncatedMp3MainData;
            if (destination.len < required_bytes)
                return error.InsufficientMp3MainDataStorage;
            if (byteRangesOverlap(
                @intFromPtr(destination.ptr),
                required_bytes,
                @intFromPtr(self.storage[0..].ptr),
                self.storage.len,
            ) or byteRangesOverlap(
                @intFromPtr(destination.ptr),
                required_bytes,
                @intFromPtr(frame.bytes.ptr),
                frame.bytes.len,
            )) return error.OverlappingMp3MainDataStorage;

            const history_start = self.length - history_bytes;
            const copied_history =
                @min(history_bytes, required_bytes);
            @memcpy(
                destination[0..copied_history],
                self.storage[history_start..][0..copied_history],
            );
            const copied_current = required_bytes - copied_history;
            @memcpy(
                destination[copied_history..required_bytes],
                current[0..copied_current],
            );
            self.retain(current);
            return .{
                .bytes = destination[0..required_bytes],
                .bit_count = side.main_data_bits,
            };
        }

        fn retain(self: *Self, current: []const u8) void {
            if (current.len >= self.storage.len) {
                @memcpy(
                    &self.storage,
                    current[current.len - self.storage.len ..],
                );
                self.length = self.storage.len;
                return;
            }
            const retained_history =
                @min(self.length, self.storage.len - current.len);
            std.mem.copyForwards(
                u8,
                self.storage[0..retained_history],
                self.storage[self.length - retained_history .. self.length],
            );
            @memcpy(
                self.storage[retained_history..][0..current.len],
                current,
            );
            self.length = retained_history + current.len;
        }
    };
}

pub fn decodeScaleFactors(
    header: Header,
    side: SideInformation,
    main_data: MainData,
) !ScaleFactors {
    const channel_count: u2 = @intCast(header.channels());
    const granule_count: u2 =
        if (header.version == .mpeg1) 2 else 1;
    if (side.channel_count != channel_count or
        side.granule_count != granule_count)
        return error.InvalidMp3SideInformation;
    if (main_data.bit_count != side.main_data_bits or
        @as(usize, main_data.bit_count) > main_data.bytes.len * 8)
        return error.InvalidMp3MainDataLength;

    var reader = MainDataBitReader{
        .bytes = main_data.bytes,
        .bit_limit = main_data.bit_count,
    };
    var result = ScaleFactors{
        .channel_count = channel_count,
        .granule_count = granule_count,
        .bit_count = main_data.bit_count,
    };
    for (0..granule_count) |granule| {
        for (0..channel_count) |channel| {
            const description =
                side.granules[granule].channels[channel];
            const segment_start = reader.bit_offset;
            const segment_end = std.math.add(
                usize,
                segment_start,
                description.part2_3_length,
            ) catch return error.InvalidMp3Part23Length;
            if (segment_end > main_data.bit_count)
                return error.InvalidMp3Part23Length;
            reader.bit_limit = segment_end;

            var decoded = if (header.version == .mpeg1)
                try decodeMpeg1ScaleFactorChannel(
                    &reader,
                    description,
                    side.scfsi[channel],
                    granule,
                    result.granules[0].channels[channel],
                )
            else
                try decodeLsfScaleFactorChannel(
                    &reader,
                    description,
                    header.channel_mode == .joint_stereo and
                        header.mode_extension & 1 != 0 and
                        channel == 1,
                );
            const part2_bits = reader.bit_offset - segment_start;
            if (part2_bits > description.part2_3_length)
                return error.InvalidMp3Part23Length;
            decoded.part2_bits = @intCast(part2_bits);
            decoded.huffman_bit_offset = @intCast(reader.bit_offset);
            decoded.huffman_bit_count = @intCast(
                @as(usize, description.part2_3_length) -
                    part2_bits,
            );
            result.granules[granule].channels[channel] = decoded;
            reader.bit_offset = segment_end;
            reader.bit_limit = main_data.bit_count;
        }
    }
    if (reader.bit_offset != main_data.bit_count)
        return error.InvalidMp3MainDataLength;
    return result;
}

pub fn scaleFactorBands(header: Header) !ScaleFactorBands {
    return switch (header.version) {
        .mpeg1 => switch (header.sample_rate) {
            48_000 => .{
                .long_starts = &bands_48000_long,
                .short_starts = &bands_48000_short,
            },
            44_100 => .{
                .long_starts = &bands_44100_long,
                .short_starts = &bands_44100_short,
            },
            32_000 => .{
                .long_starts = &bands_32000_long,
                .short_starts = &bands_32000_short,
            },
            else => error.InvalidMp3SampleRate,
        },
        .mpeg2 => switch (header.sample_rate) {
            24_000 => .{
                .long_starts = &bands_24000_long,
                .short_starts = &bands_24000_short,
            },
            22_050 => .{
                .long_starts = &bands_22050_long,
                .short_starts = &bands_22050_short,
            },
            16_000 => .{
                .long_starts = &bands_16000_long,
                .short_starts = &bands_16000_short,
            },
            else => error.InvalidMp3SampleRate,
        },
        .mpeg25 => switch (header.sample_rate) {
            12_000, 11_025 => .{
                .long_starts = &bands_16000_long,
                .short_starts = &bands_16000_short,
            },
            8_000 => .{
                .long_starts = &bands_8000_long,
                .short_starts = &bands_8000_short,
            },
            else => error.InvalidMp3SampleRate,
        },
    };
}

pub fn huffmanRegionEnds(
    header: Header,
    channel: GranuleChannel,
) ![2]u16 {
    const bands = try scaleFactorBands(header);
    if (channel.block_type == 2) {
        if (!channel.window_switching)
            return error.InvalidMp3BlockType;
        return .{
            3 * bands.short_starts[3],
            576,
        };
    }
    const first_index =
        @as(usize, channel.region0_count) + 1;
    const second_index =
        first_index + @as(usize, channel.region1_count) + 1;
    if (first_index >= bands.long_starts.len or
        second_index >= bands.long_starts.len)
        return error.InvalidMp3RegionCounts;
    return .{
        bands.long_starts[first_index],
        bands.long_starts[second_index],
    };
}

pub const EncodedHuffmanChannel = struct {
    description: GranuleChannel,
    main_data: MainData,
};

pub fn encodeHuffmanChannel(
    header: Header,
    description: GranuleChannel,
    spectrum: *const [576]i32,
    destination: []u8,
) !EncodedHuffmanChannel {
    if (description.big_values > 288)
        return error.InvalidMp3BigValues;
    const big_line_count =
        @as(usize, description.big_values) * 2;
    var last_nonzero = big_line_count;
    for (spectrum[big_line_count..], big_line_count..) |value, line| {
        if (value != 0) last_nonzero = line + 1;
    }
    const count1_line_count = std.mem.alignForward(
        usize,
        last_nonzero - big_line_count,
        4,
    );
    if (big_line_count + count1_line_count > spectrum.len)
        return error.InvalidMp3Count1Region;
    for (spectrum[big_line_count + count1_line_count ..]) |value| {
        if (value != 0) return error.InvalidMp3QuantizedSpectrum;
    }

    const region_ends = try huffmanRegionEnds(
        header,
        description,
    );
    var staged: [512]u8 = @splat(0);
    var writer = MainDataBitWriter{ .bytes = &staged };
    var line: usize = 0;
    while (line < big_line_count) : (line += 2) {
        const table_index = description.table_select[
            if (line < region_ends[0])
                0
            else if (line < region_ends[1])
                1
            else
                2
        ];
        try encodeHuffmanPair(
            &writer,
            try huffman_tables.get(table_index),
            spectrum[line..][0..2].*,
        );
    }
    while (line < big_line_count + count1_line_count) : (line += 4)
        try encodeCount1Quad(
            &writer,
            description.count1_table_select,
            spectrum[line..][0..4].*,
        );

    if (writer.bit_offset > std.math.maxInt(u12))
        return error.Mp3HuffmanBitCountOverflow;
    const byte_count = (writer.bit_offset + 7) / 8;
    if (destination.len < byte_count)
        return error.InsufficientMp3HuffmanStorage;
    @memcpy(destination[0..byte_count], staged[0..byte_count]);

    var encoded_description = description;
    encoded_description.part2_3_length =
        @intCast(writer.bit_offset);
    return .{
        .description = encoded_description,
        .main_data = .{
            .bytes = destination[0..byte_count],
            .bit_count = @intCast(writer.bit_offset),
        },
    };
}

pub fn decodeHuffmanChannel(
    header: Header,
    description: GranuleChannel,
    factors: ScaleFactorChannel,
    main_data: MainData,
) !QuantizedSpectrum {
    if (@as(u16, factors.part2_bits) +
        factors.huffman_bit_count != description.part2_3_length)
        return error.InvalidMp3Part23Length;
    const segment_end = std.math.add(
        usize,
        factors.huffman_bit_offset,
        factors.huffman_bit_count,
    ) catch return error.InvalidMp3HuffmanRange;
    if (segment_end > main_data.bit_count or
        @as(usize, main_data.bit_count) > main_data.bytes.len * 8)
        return error.InvalidMp3HuffmanRange;
    if (description.big_values > 288)
        return error.InvalidMp3BigValues;

    const region_ends = try huffmanRegionEnds(
        header,
        description,
    );
    var reader = MainDataBitReader{
        .bytes = main_data.bytes,
        .bit_offset = factors.huffman_bit_offset,
        .bit_limit = segment_end,
    };
    const start = reader.bit_offset;
    var result = QuantizedSpectrum{};
    const big_line_count =
        @as(usize, description.big_values) * 2;
    var line: usize = 0;
    while (line < big_line_count) : (line += 2) {
        const table_index = description.table_select[
            if (line < region_ends[0])
                0
            else if (line < region_ends[1])
                1
            else
                2
        ];
        const pair = try decodeHuffmanPair(
            &reader,
            try huffman_tables.get(table_index),
        );
        result.lines[line] = pair[0];
        result.lines[line + 1] = pair[1];
    }

    while (line + 4 <= result.lines.len and
        reader.bit_offset < reader.bit_limit)
    {
        var trial = reader;
        const quad = decodeCount1Quad(
            &trial,
            description.count1_table_select,
        ) catch break;
        @memcpy(result.lines[line..][0..4], &quad);
        reader = trial;
        line += 4;
    }
    result.decoded_lines = @intCast(line);
    result.huffman_bits_consumed =
        @intCast(reader.bit_offset - start);
    return result;
}

fn encodeHuffmanPair(
    writer: *MainDataBitWriter,
    table: huffman_tables.Table,
    values: [2]i32,
) !void {
    var magnitudes: [2]u32 = undefined;
    for (values, 0..) |value, index| {
        magnitudes[index] = try quantizedMagnitude(value);
    }
    if (table.side == 1) {
        if (magnitudes[0] != 0 or magnitudes[1] != 0)
            return error.Mp3HuffmanTableTooSmall;
        return;
    }

    const maximum_magnitude: u32 = if (table.linbits == 0)
        table.side - 1
    else
        15 + (@as(u32, 1) << table.linbits) - 1;
    for (magnitudes) |magnitude| {
        if (magnitude > maximum_magnitude)
            return error.Mp3HuffmanTableTooSmall;
    }
    const x = @min(magnitudes[0], 15);
    const y = @min(magnitudes[1], 15);
    const entry_index =
        @as(usize, x) * table.side + @as(usize, y);
    const entry = table.entries[entry_index];
    try writer.write(entry.bits, entry.length);
    for (magnitudes, values) |magnitude, value| {
        if (magnitude >= 15 and table.linbits != 0)
            try writer.write(
                magnitude - 15,
                @intCast(table.linbits),
            );
        if (magnitude != 0)
            try writer.write(@intFromBool(value < 0), 1);
    }
}

fn decodeHuffmanPair(
    reader: *MainDataBitReader,
    table: huffman_tables.Table,
) ![2]i32 {
    if (table.side == 1) return .{ 0, 0 };

    var code: u19 = 0;
    var matched: ?usize = null;
    for (1..20) |length| {
        code = (code << 1) |
            @as(u19, @intCast(try reader.read(1)));
        for (table.entries, 0..) |entry, index| {
            if (entry.length == length and entry.bits == code) {
                matched = index;
                break;
            }
        }
        if (matched != null) break;
    }
    const index = matched orelse
        return error.InvalidMp3HuffmanCode;
    const side: usize = table.side;
    var magnitudes = [2]u16{
        @intCast(index / side),
        @intCast(index % side),
    };
    var result: [2]i32 = @splat(0);
    for (&magnitudes, 0..) |*magnitude, component| {
        if (magnitude.* == 15 and table.linbits != 0)
            magnitude.* += try reader.read(
                @intCast(table.linbits),
            );
        if (magnitude.* == 0) continue;
        const signed: i32 = magnitude.*;
        result[component] =
            if (try reader.read(1) == 0) signed else -signed;
    }
    return result;
}

const Count1Code = struct {
    length: u3,
    bits: u6,
};

const count1_table_a = [16]Count1Code{
    .{ .length = 1, .bits = 0b1 },
    .{ .length = 4, .bits = 0b0101 },
    .{ .length = 4, .bits = 0b0100 },
    .{ .length = 5, .bits = 0b00101 },
    .{ .length = 4, .bits = 0b0110 },
    .{ .length = 6, .bits = 0b000101 },
    .{ .length = 5, .bits = 0b00100 },
    .{ .length = 6, .bits = 0b000100 },
    .{ .length = 4, .bits = 0b0111 },
    .{ .length = 5, .bits = 0b00011 },
    .{ .length = 5, .bits = 0b00110 },
    .{ .length = 6, .bits = 0b000000 },
    .{ .length = 5, .bits = 0b00111 },
    .{ .length = 6, .bits = 0b000010 },
    .{ .length = 6, .bits = 0b000011 },
    .{ .length = 6, .bits = 0b000001 },
};

fn encodeCount1Quad(
    writer: *MainDataBitWriter,
    table_b: bool,
    values: [4]i32,
) !void {
    var pattern: u4 = 0;
    for (values, 0..) |value, index| {
        const magnitude = try quantizedMagnitude(value);
        if (magnitude > 1)
            return error.InvalidMp3Count1Value;
        pattern |= @as(u4, @intCast(magnitude)) <<
            @intCast(3 - index);
    }
    if (table_b)
        try writer.write(pattern ^ 0xf, 4)
    else {
        const entry = count1_table_a[pattern];
        try writer.write(entry.bits, entry.length);
    }
    for (values) |value| {
        if (value != 0)
            try writer.write(@intFromBool(value < 0), 1);
    }
}

fn quantizedMagnitude(value: i32) !u32 {
    if (value == std.math.minInt(i32))
        return error.InvalidMp3QuantizedValue;
    return @intCast(if (value < 0) -value else value);
}

fn decodeCount1Quad(
    reader: *MainDataBitReader,
    table_b: bool,
) ![4]i32 {
    var magnitudes: [4]u1 = undefined;
    if (table_b) {
        const encoded = try reader.read(4);
        for (&magnitudes, 0..) |*value, index|
            value.* = @intCast(
                ((encoded >> @intCast(3 - index)) & 1) ^ 1,
            );
    } else {
        var code: u6 = 0;
        var matched: ?u4 = null;
        for (1..7) |length| {
            code = (code << 1) |
                @as(u6, @intCast(try reader.read(1)));
            for (count1_table_a, 0..) |entry, pattern| {
                if (entry.length == length and
                    entry.bits == code)
                {
                    matched = @intCast(pattern);
                    break;
                }
            }
            if (matched != null) break;
        }
        const pattern = matched orelse
            return error.InvalidMp3Count1Code;
        for (&magnitudes, 0..) |*value, index|
            value.* = @intCast(
                pattern >> @intCast(3 - index) & 1,
            );
    }

    var result: [4]i32 = @splat(0);
    for (magnitudes, 0..) |magnitude, index| {
        if (magnitude == 0) continue;
        result[index] =
            if (try reader.read(1) == 0) 1 else -1;
    }
    return result;
}

fn buildBandStarts(comptime widths: anytype) [widths.len + 1]u16 {
    var starts: [widths.len + 1]u16 = @splat(0);
    for (widths, 0..) |width, index|
        starts[index + 1] = starts[index] + width;
    return starts;
}

const bands_48000_long = buildBandStarts([_]u16{
    4,  4,  4,  4,  4,  4,  6,  6,  6,  8,  10,
    12, 16, 18, 22, 28, 34, 40, 46, 54, 54, 192,
});
const bands_44100_long = buildBandStarts([_]u16{
    4,  4,  4,  4,  4,  4,  6,  6,  8,  8,  10,
    12, 16, 20, 24, 28, 34, 42, 50, 54, 76, 158,
});
const bands_32000_long = buildBandStarts([_]u16{
    4,  4,  4,  4,  4,  4,  6,  6,  8,  10,  12,
    16, 20, 24, 30, 38, 46, 56, 68, 84, 102, 26,
});
const bands_24000_long = buildBandStarts([_]u16{
    6,  6,  6,  6,  6,  6,  8,  10, 12, 14, 16,
    18, 22, 26, 32, 38, 46, 54, 62, 70, 76, 36,
});
const bands_22050_long = buildBandStarts([_]u16{
    6,  6,  6,  6,  6,  6,  8,  10, 12, 14, 16,
    20, 24, 28, 32, 38, 46, 52, 60, 68, 58, 54,
});
const bands_16000_long = bands_22050_long;
const bands_8000_long = buildBandStarts([_]u16{
    12, 12, 12, 12, 12, 12, 16, 20, 24, 28, 32,
    40, 48, 56, 64, 76, 90, 2,  2,  2,  2,  2,
});

const bands_48000_short = buildBandStarts([_]u16{
    4, 4, 4, 4, 6, 6, 10, 12, 14, 16, 20, 26, 66,
});
const bands_44100_short = buildBandStarts([_]u16{
    4, 4, 4, 4, 6, 8, 10, 12, 14, 18, 22, 30, 56,
});
const bands_32000_short = buildBandStarts([_]u16{
    4, 4, 4, 4, 6, 8, 12, 16, 20, 26, 34, 42, 12,
});
const bands_24000_short = buildBandStarts([_]u16{
    4, 4, 4, 6, 8, 10, 12, 14, 18, 24, 32, 44, 12,
});
const bands_22050_short = buildBandStarts([_]u16{
    4, 4, 4, 6, 6, 8, 10, 14, 18, 26, 32, 42, 18,
});
const bands_16000_short = buildBandStarts([_]u16{
    4, 4, 4, 6, 8, 10, 12, 14, 18, 24, 30, 40, 18,
});
const bands_8000_short = buildBandStarts([_]u16{
    8, 8, 8, 12, 16, 20, 24, 28, 36, 2, 2, 2, 26,
});

const mpeg1_scale_factor_lengths = [16][2]u3{
    .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ 0, 3 },
    .{ 3, 0 }, .{ 1, 1 }, .{ 1, 2 }, .{ 1, 3 },
    .{ 2, 1 }, .{ 2, 2 }, .{ 2, 3 }, .{ 3, 1 },
    .{ 3, 2 }, .{ 3, 3 }, .{ 4, 2 }, .{ 4, 3 },
};

const lsf_scale_factor_counts = [6][3][4]u5{
    .{
        .{ 6, 5, 5, 5 },
        .{ 9, 9, 9, 9 },
        .{ 6, 9, 9, 9 },
    },
    .{
        .{ 6, 5, 7, 3 },
        .{ 9, 9, 12, 6 },
        .{ 6, 9, 12, 6 },
    },
    .{
        .{ 11, 10, 0, 0 },
        .{ 18, 18, 0, 0 },
        .{ 15, 18, 0, 0 },
    },
    .{
        .{ 7, 7, 7, 0 },
        .{ 12, 12, 12, 0 },
        .{ 6, 15, 12, 0 },
    },
    .{
        .{ 6, 6, 6, 3 },
        .{ 12, 9, 9, 6 },
        .{ 6, 12, 9, 6 },
    },
    .{
        .{ 8, 8, 5, 0 },
        .{ 15, 12, 9, 0 },
        .{ 6, 18, 9, 0 },
    },
};

fn decodeMpeg1ScaleFactorChannel(
    reader: *MainDataBitReader,
    description: GranuleChannel,
    scfsi: u4,
    granule: usize,
    first_granule: ScaleFactorChannel,
) !ScaleFactorChannel {
    if (description.scalefac_compress >=
        mpeg1_scale_factor_lengths.len)
        return error.InvalidMp3ScaleFactorCompression;
    const lengths =
        mpeg1_scale_factor_lengths[description.scalefac_compress];
    var result = ScaleFactorChannel{
        .preflag = description.preflag,
    };
    if (description.block_type == 2) {
        const first_count: usize =
            if (description.mixed_block) 17 else 18;
        var index: usize = 0;
        while (index < first_count) : (index += 1)
            result.values[index] =
                @intCast(try reader.read(lengths[0]));
        while (index < first_count + 18) : (index += 1)
            result.values[index] =
                @intCast(try reader.read(lengths[1]));
        result.value_count = @intCast(index + 3);
        return result;
    }

    const ranges = [4][2]u5{
        .{ 0, 6 },
        .{ 6, 11 },
        .{ 11, 16 },
        .{ 16, 21 },
    };
    for (ranges, 0..) |range, group| {
        const reuse = granule == 1 and
            scfsi & (@as(u4, 8) >> @intCast(group)) != 0;
        for (range[0]..range[1]) |index| {
            result.values[index] = if (reuse)
                first_granule.values[index]
            else
                @intCast(try reader.read(
                    lengths[if (group < 2) 0 else 1],
                ));
        }
    }
    result.value_count = 22;
    return result;
}

fn decodeLsfScaleFactorChannel(
    reader: *MainDataBitReader,
    description: GranuleChannel,
    intensity_stereo: bool,
) !ScaleFactorChannel {
    var compression: usize = description.scalefac_compress;
    var lengths: [4]u4 = @splat(0);
    var table: usize = 0;
    var result = ScaleFactorChannel{};
    if (intensity_stereo) {
        result.intensity_scale =
            description.scalefac_compress & 1 != 0;
        compression >>= 1;
        if (compression < 180) {
            lengths = .{
                @intCast(compression / 36),
                @intCast(compression % 36 / 6),
                @intCast(compression % 6),
                0,
            };
            table = 3;
        } else if (compression < 244) {
            compression -= 180;
            lengths = .{
                @intCast(compression >> 4),
                @intCast((compression % 16) >> 2),
                @intCast(compression % 4),
                0,
            };
            table = 4;
        } else {
            compression -= 244;
            lengths = .{
                @intCast(compression / 3),
                @intCast(compression % 3),
                0,
                0,
            };
            table = 5;
        }
    } else if (compression < 400) {
        lengths = .{
            @intCast((compression >> 4) / 5),
            @intCast((compression >> 4) % 5),
            @intCast((compression % 16) >> 2),
            @intCast(compression % 4),
        };
    } else if (compression < 500) {
        compression -= 400;
        lengths = .{
            @intCast((compression >> 2) / 5),
            @intCast((compression >> 2) % 5),
            @intCast(compression % 4),
            0,
        };
        table = 1;
    } else if (compression < 512) {
        compression -= 500;
        lengths = .{
            @intCast(compression / 3),
            @intCast(compression % 3),
            0,
            0,
        };
        table = 2;
        result.preflag = true;
    } else {
        return error.InvalidMp3ScaleFactorCompression;
    }

    const layout: usize = if (description.block_type != 2)
        0
    else if (description.mixed_block)
        2
    else
        1;
    var index: usize = 0;
    for (lsf_scale_factor_counts[table][layout], 0..) |
        count,
        part,
    | {
        const width = lengths[part];
        const maximum: u16 =
            if (width == 0) 0 else (@as(u16, 1) << @intCast(width)) - 1;
        for (0..count) |_| {
            const value = try reader.read(@intCast(width));
            result.values[index] = @intCast(value);
            result.intensity_max[index] =
                intensity_stereo and value == maximum;
            index += 1;
        }
    }
    result.value_count = @intCast(index);
    return result;
}

const MainDataBitWriter = struct {
    bytes: []u8,
    bit_offset: usize = 0,

    fn write(
        self: *@This(),
        value: anytype,
        bit_count: u5,
    ) !void {
        const encoded: u32 = @intCast(value);
        if (bit_count < 32 and encoded >=
            (@as(u32, 1) << bit_count))
            return error.InvalidMp3HuffmanValue;
        if (@as(usize, bit_count) >
            self.bytes.len * 8 -| self.bit_offset)
            return error.Mp3HuffmanBitCountOverflow;
        for (0..bit_count) |index| {
            const source_shift: u5 =
                @intCast(bit_count - 1 - index);
            const destination_bit = self.bit_offset + index;
            const mask: u8 =
                @as(u8, 1) << @intCast(7 - destination_bit % 8);
            if (encoded >> source_shift & 1 != 0)
                self.bytes[destination_bit / 8] |= mask
            else
                self.bytes[destination_bit / 8] &= ~mask;
        }
        self.bit_offset += bit_count;
    }
};

fn appendMainDataBits(
    writer: *MainDataBitWriter,
    source: MainData,
) !void {
    if (@as(usize, source.bit_count) > source.bytes.len * 8)
        return error.InvalidMp3MainDataLength;
    for (0..source.bit_count) |bit_offset| {
        const byte = source.bytes[bit_offset / 8];
        const shift: u3 = @intCast(7 - bit_offset % 8);
        try writer.write((byte >> shift) & 1, 1);
    }
}

const MainDataBitReader = struct {
    bytes: []const u8,
    bit_offset: usize = 0,
    bit_limit: usize,

    fn read(self: *@This(), bit_count: u5) !u16 {
        if (bit_count > 16 or
            self.bit_offset > self.bit_limit or
            bit_count > self.bit_limit - self.bit_offset)
            return error.InvalidMp3Part23Length;
        var value: u16 = 0;
        for (0..bit_count) |_| {
            const byte = self.bytes[self.bit_offset / 8];
            const shift: u3 =
                @intCast(7 - self.bit_offset % 8);
            value = (value << 1) | ((byte >> shift) & 1);
            self.bit_offset += 1;
        }
        return value;
    }
};

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

    pub fn init(encoded: []const u8) !Stream {
        const audio_start = try leadingTagBytes(encoded);
        const audio_end = trailingTagStart(encoded, audio_start);
        if (audio_end - audio_start < 4) return error.Mp3StreamHasNoFrames;
        return .{
            .encoded = encoded,
            .audio_start = audio_start,
            .audio_end = audio_end,
            .cursor = audio_start,
        };
    }

    pub fn next(self: *Stream) !?Frame {
        if (self.audio_start > self.audio_end or
            self.audio_end > self.encoded.len or
            self.cursor < self.audio_start or
            self.cursor > self.audio_end)
        {
            return error.InvalidMp3StreamState;
        }
        if (self.cursor == self.audio_end) return null;
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
            if (!first.compatible(frame.header))
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

    pub fn summarize(encoded: []const u8) !Summary {
        var stream = try Stream.init(encoded);
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

    /// The caller owns the file and frame storage for the reader lifetime.
    pub fn init(io: std.Io, file: std.Io.File) !FileReader {
        const file_size = (try file.stat(io)).size;
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
        };
    }

    /// Returned frame slices borrow storage until the caller reuses it.
    pub fn next(self: *FileReader, storage: []u8) !?FileFrame {
        if (self.audio_start > self.audio_end or
            self.offset < self.audio_start or
            self.offset > self.audio_end)
        {
            return error.InvalidMp3FileReaderState;
        }
        if (self.offset == self.audio_end) return null;
        if (self.audio_end - self.offset < 4)
            return error.TrailingMp3Data;

        var header_bytes: [4]u8 = undefined;
        try readExactAt(self.io, self.file, self.offset, &header_bytes);
        const header = try Header.parse(&header_bytes);
        if (!self.first_header.compatible(header))
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

    pub fn seek(self: *FileReader, point: SeekPoint) !void {
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
        var header_bytes: [4]u8 = undefined;
        try readExactAt(self.io, self.file, byte_offset, &header_bytes);
        const header = Header.parse(&header_bytes) catch
            return error.InvalidMp3SeekPoint;
        if (!self.first_header.compatible(header))
            return error.InvalidMp3SeekPoint;
        const frame_bytes = resolvedFrameBytes(
            header,
            self.free_frame_base_bytes,
        ) catch return error.InvalidMp3SeekPoint;
        if (frame_bytes > self.audio_end - byte_offset)
            return error.InvalidMp3SeekPoint;
        self.offset = byte_offset;
        self.frame_index = point.frame_index;
        self.sample_offset = point.sample_offset;
    }

    pub fn summarize(
        io: std.Io,
        file: std.Io.File,
        storage: []u8,
    ) !FileSummary {
        var reader = try FileReader.init(io, file);
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

fn resolvedFrameBytes(
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

fn minimumFrameBytes(header: Header) usize {
    return 4 + @as(usize, if (header.crc_present) 2 else 0) +
        header.sideInformationBytes();
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
        if (!header.compatible(candidate_header)) continue;
        const frame_bytes = candidate - offset;
        const padding: usize = @intFromBool(header.padding);
        if (frame_bytes <= padding) continue;
        const base = frame_bytes - padding;
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
    const next = std.math.add(
        usize,
        candidate,
        frame_bytes,
    ) catch return false;
    if (next == audio_end) return true;
    if (next > audio_end -| 4) return false;
    const next_header =
        Header.parse(encoded[next..audio_end]) catch return false;
    return header.compatible(next_header);
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
    while (candidate <= maximum_candidate) : (candidate += 1) {
        try readExactAt(io, file, candidate, &header_bytes);
        const candidate_header =
            Header.parse(&header_bytes) catch continue;
        if (!header.compatible(candidate_header)) continue;
        const frame_bytes = std.math.cast(
            usize,
            candidate - offset,
        ) orelse return error.Mp3ByteCountOverflow;
        const padding: usize = @intFromBool(header.padding);
        if (frame_bytes <= padding) continue;
        const base = frame_bytes - padding;
        if (try confirmsFileFreeFormat(
            io,
            file,
            candidate,
            audio_end,
            candidate_header,
            base,
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
) !bool {
    const frame_bytes = try resolvedFrameBytes(header, base);
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
    return header.compatible(next_header);
}

fn frameAtKnownLength(
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

fn crc16(initial: u16, bytes: []const u8) u16 {
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

fn encodeGranuleChannelSideInformation(
    destination: []u8,
    bit_offset: *usize,
    version: Version,
    channel: GranuleChannel,
) !void {
    try writeSideInformationBits(
        destination,
        bit_offset,
        channel.part2_3_length,
        12,
    );
    try writeSideInformationBits(
        destination,
        bit_offset,
        channel.big_values,
        9,
    );
    try writeSideInformationBits(
        destination,
        bit_offset,
        channel.global_gain,
        8,
    );
    try writeSideInformationBits(
        destination,
        bit_offset,
        channel.scalefac_compress,
        if (version == .mpeg1) 4 else 9,
    );
    try writeSideInformationBits(
        destination,
        bit_offset,
        @intFromBool(channel.window_switching),
        1,
    );
    if (channel.window_switching) {
        try writeSideInformationBits(
            destination,
            bit_offset,
            channel.block_type,
            2,
        );
        try writeSideInformationBits(
            destination,
            bit_offset,
            @intFromBool(channel.mixed_block),
            1,
        );
        for (channel.table_select[0..2]) |table|
            try writeSideInformationBits(
                destination,
                bit_offset,
                table,
                5,
            );
        for (channel.subblock_gain) |gain|
            try writeSideInformationBits(
                destination,
                bit_offset,
                gain,
                3,
            );
    } else {
        for (channel.table_select) |table|
            try writeSideInformationBits(
                destination,
                bit_offset,
                table,
                5,
            );
        try writeSideInformationBits(
            destination,
            bit_offset,
            channel.region0_count,
            4,
        );
        try writeSideInformationBits(
            destination,
            bit_offset,
            channel.region1_count,
            3,
        );
    }
    if (version == .mpeg1)
        try writeSideInformationBits(
            destination,
            bit_offset,
            @intFromBool(channel.preflag),
            1,
        );
    try writeSideInformationBits(
        destination,
        bit_offset,
        @intFromBool(channel.scalefac_scale),
        1,
    );
    try writeSideInformationBits(
        destination,
        bit_offset,
        @intFromBool(channel.count1_table_select),
        1,
    );
}

fn writeSideInformationBits(
    destination: []u8,
    bit_offset: *usize,
    value: anytype,
    bit_count: u5,
) !void {
    const encoded: u16 = @intCast(value);
    if (bit_count < 16 and encoded >=
        (@as(u16, 1) << @as(u4, @intCast(bit_count))))
        return error.InvalidMp3SideInformation;
    if (@as(usize, bit_count) >
        destination.len * 8 -| bit_offset.*)
        return error.InvalidMp3SideInformation;
    for (0..bit_count) |index| {
        const source_shift: u4 =
            @intCast(bit_count - 1 - index);
        const destination_bit = bit_offset.* + index;
        const mask: u8 =
            @as(u8, 1) << @intCast(7 - destination_bit % 8);
        if (encoded >> source_shift & 1 != 0)
            destination[destination_bit / 8] |= mask
        else
            destination[destination_bit / 8] &= ~mask;
    }
    bit_offset.* += bit_count;
}

fn parseSideInformation(
    bytes: []const u8,
    header: Header,
) !SideInformation {
    const offset: usize = if (header.crc_present) 6 else 4;
    const size: usize = header.sideInformationBytes();
    if (bytes.len < offset or size > bytes.len - offset)
        return error.TruncatedMp3SideInformation;
    var reader = BitReader{
        .bytes = bytes[offset..][0..size],
    };
    const channel_count: u2 = @intCast(header.channels());
    const granule_count: u2 =
        if (header.version == .mpeg1) 2 else 1;
    var result = SideInformation{
        .channel_count = channel_count,
        .granule_count = granule_count,
        .main_data_begin = @intCast(try reader.read(
            if (header.version == .mpeg1) 9 else 8,
        )),
        .private_bits = @intCast(try reader.read(
            switch (header.version) {
                .mpeg1 => if (channel_count == 1) 5 else 3,
                .mpeg2, .mpeg25 => if (channel_count == 1) 1 else 2,
            },
        )),
        .main_data_bits = 0,
    };
    if (header.version == .mpeg1) {
        for (0..channel_count) |channel|
            result.scfsi[channel] =
                @intCast(try reader.read(4));
    }
    for (0..granule_count) |granule| {
        for (0..channel_count) |channel| {
            const parsed = try parseGranuleChannel(
                &reader,
                header.version,
            );
            result.main_data_bits = std.math.add(
                u16,
                result.main_data_bits,
                parsed.part2_3_length,
            ) catch return error.Mp3MainDataBitCountOverflow;
            result.granules[granule].channels[channel] = parsed;
        }
    }
    if (reader.remainingBits() != 0)
        return error.InvalidMp3SideInformation;
    return result;
}

fn parseGranuleChannel(
    reader: *BitReader,
    version: Version,
) !GranuleChannel {
    var result = GranuleChannel{
        .part2_3_length = @intCast(try reader.read(12)),
        .big_values = @intCast(try reader.read(9)),
        .global_gain = @intCast(try reader.read(8)),
        .scalefac_compress = @intCast(try reader.read(
            if (version == .mpeg1) 4 else 9,
        )),
        .window_switching = try reader.read(1) != 0,
    };
    if (result.big_values > 288)
        return error.InvalidMp3BigValues;
    if (result.window_switching) {
        result.block_type = @intCast(try reader.read(2));
        if (result.block_type == 0)
            return error.InvalidMp3BlockType;
        result.mixed_block = try reader.read(1) != 0;
        result.table_select[0] =
            @intCast(try reader.read(5));
        result.table_select[1] =
            @intCast(try reader.read(5));
        for (&result.subblock_gain) |*gain|
            gain.* = @intCast(try reader.read(3));
        result.region0_count =
            if (result.block_type == 2 and !result.mixed_block)
                8
            else
                7;
        result.region1_count =
            @intCast(20 - @as(u8, result.region0_count));
    } else {
        for (&result.table_select) |*table|
            table.* = @intCast(try reader.read(5));
        result.region0_count =
            @intCast(try reader.read(4));
        result.region1_count =
            @intCast(try reader.read(3));
        if (@as(u8, result.region0_count) +
            result.region1_count > 20)
            return error.InvalidMp3RegionCounts;
    }
    if (version == .mpeg1)
        result.preflag = try reader.read(1) != 0;
    result.scalefac_scale = try reader.read(1) != 0;
    result.count1_table_select = try reader.read(1) != 0;
    const table_count: usize =
        if (result.window_switching) 2 else 3;
    for (result.table_select[0..table_count]) |table| {
        if (table == 4 or table == 14)
            return error.InvalidMp3HuffmanTable;
    }
    return result;
}

const BitReader = struct {
    bytes: []const u8,
    bit_offset: usize = 0,

    fn read(self: *@This(), bit_count: u5) !u16 {
        if (bit_count > 16 or
            bit_count > self.remainingBits())
            return error.TruncatedMp3SideInformation;
        var value: u16 = 0;
        for (0..bit_count) |_| {
            const byte = self.bytes[self.bit_offset / 8];
            const shift: u3 =
                @intCast(7 - self.bit_offset % 8);
            value = (value << 1) | ((byte >> shift) & 1);
            self.bit_offset += 1;
        }
        return value;
    }

    fn remainingBits(self: @This()) usize {
        return self.bytes.len * 8 - self.bit_offset;
    }
};

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

fn parseXing(frame: []const u8, header: Header) !?Xing {
    const offset: usize = 4 + header.sideInformationBytes();
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
    if (flags & ~@as(u32, 0xf) != 0) return error.InvalidXingFlags;
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

    if (frame.len -| cursor >= 24) {
        const encoder = frame[cursor..][0..9].*;
        xing.encoder = encoder;
        const delay_offset = cursor + 21;
        const delay_fields =
            readU24(frame[delay_offset .. delay_offset + 3]);
        if (std.mem.startsWith(u8, &encoder, "LAME") or
            std.mem.startsWith(u8, &encoder, "Lavf") or
            std.mem.startsWith(u8, &encoder, "Lavc"))
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
    const toc_bytes = std.math.mul(
        usize,
        entry_count,
        entry_bytes,
    ) catch return error.VbriSizeOverflow;
    if (frame.len - (offset + 26) < toc_bytes)
        return error.TruncatedVbriToc;
    return .{
        .version = version,
        .delay = readU16(frame[offset + 6 .. offset + 8]),
        .quality = readU16(frame[offset + 8 .. offset + 10]),
        .stream_bytes = readU32(frame[offset + 10 .. offset + 14]),
        .frame_count = readU32(frame[offset + 14 .. offset + 18]),
        .toc_entries = entry_count,
        .toc_scale = readU16(frame[offset + 20 .. offset + 22]),
        .entry_bytes = entry_bytes,
        .frames_per_entry = readU16(frame[offset + 24 .. offset + 26]),
        .toc = frame[offset + 26 ..][0..toc_bytes],
    };
}

fn leadingTagBytes(encoded: []const u8) !usize {
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

fn trailingTagStart(encoded: []const u8, audio_start: usize) usize {
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

fn bitrate(version: Version, index: u4) u16 {
    const mpeg1 = [_]u16{
        0,   32,  40,  48,  56,  64,  80,  96,
        112, 128, 160, 192, 224, 256, 320, 0,
    };
    const mpeg2 = [_]u16{
        0,  8,  16, 24,  32,  40,  48,  56,
        64, 80, 96, 112, 128, 144, 160, 0,
    };
    return if (version == .mpeg1) mpeg1[index] else mpeg2[index];
}

fn bitrateIndex(version: Version, value: u16) ?u4 {
    for (1..15) |index| {
        const encoded_index: u4 = @intCast(index);
        if (bitrate(version, encoded_index) == value)
            return encoded_index;
    }
    return null;
}

fn sampleRate(version: Version, index: u2) u32 {
    const base = [_]u32{ 44_100, 48_000, 32_000, 0 };
    return switch (version) {
        .mpeg1 => base[index],
        .mpeg2 => base[index] / 2,
        .mpeg25 => base[index] / 4,
    };
}

fn sampleRateIndex(version: Version, value: u32) ?u2 {
    for (0..3) |index| {
        const encoded_index: u2 = @intCast(index);
        if (sampleRate(version, encoded_index) == value)
            return encoded_index;
    }
    return null;
}

fn readU16(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readU24(bytes: []const u8) u24 {
    return (@as(u24, bytes[0]) << 16) |
        (@as(u24, bytes[1]) << 8) |
        bytes[2];
}

fn readU32(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
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

fn byteRangesOverlap(
    first_start: usize,
    first_length: usize,
    second_start: usize,
    second_length: usize,
) bool {
    if (first_length == 0 or second_length == 0) return false;
    const first_end = std.math.add(
        usize,
        first_start,
        first_length,
    ) catch std.math.maxInt(usize);
    const second_end = std.math.add(
        usize,
        second_start,
        second_length,
    ) catch std.math.maxInt(usize);
    return first_start < second_end and second_start < first_end;
}

fn referencePolyphaseTimeSlot(
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

fn testHeader(
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

fn setTestBits(
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

fn setMpeg1MonoLongChannel(
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

fn readTestI16(bytes: *const [2]u8) i16 {
    const value = @as(u16, bytes[0]) |
        (@as(u16, bytes[1]) << 8);
    return @bitCast(value);
}

fn appendFrame(
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

fn appendFreeFormatFrame(
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

test "serializes every supported MP3 encoder header" {
    const versions = [_]Version{ .mpeg1, .mpeg2, .mpeg25 };
    const modes = [_]ChannelMode{
        .stereo,
        .joint_stereo,
        .dual_channel,
        .mono,
    };
    for (versions) |version| {
        for (0..3) |rate_index_value| {
            const rate_index: u2 = @intCast(rate_index_value);
            for (1..15) |bitrate_index_value| {
                const bitrate_index: u4 =
                    @intCast(bitrate_index_value);
                for (modes) |mode| {
                    for ([_]bool{ false, true }) |crc_present| {
                        const header = Header{
                            .version = version,
                            .crc_present = crc_present,
                            .free_format = false,
                            .bitrate_kbps = bitrate(
                                version,
                                bitrate_index,
                            ),
                            .sample_rate = sampleRate(
                                version,
                                rate_index,
                            ),
                            .padding = true,
                            .private = true,
                            .channel_mode = mode,
                            .mode_extension = 3,
                            .copyright = true,
                            .original = true,
                            .emphasis = 3,
                        };
                        try std.testing.expectEqual(
                            header,
                            try Header.parse(&try header.encode()),
                        );
                    }
                }
            }
        }
    }

    const free = Header{
        .version = .mpeg1,
        .crc_present = false,
        .free_format = true,
        .bitrate_kbps = 0,
        .sample_rate = 44_100,
        .padding = false,
        .private = false,
        .channel_mode = .stereo,
        .mode_extension = 0,
        .copyright = false,
        .original = false,
        .emphasis = 0,
    };
    try std.testing.expectEqual(
        free,
        try Header.parse(&try free.encode()),
    );
}

test "encodes transactional CBR silent MP3 frames" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
        .private = true,
        .copyright = true,
        .original = true,
        .emphasis = 1,
    };
    var encoder = try FrameEncoder.init(config);
    var decoder = FrameDecoder{};
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    var encoded_bytes: usize = 0;
    var padded_frames: usize = 0;
    for (0..100) |_| {
        const expected_bytes = try encoder.nextFrameBytes();
        const frame_bytes =
            try encoder.encodeSilentFrame(&storage);
        try std.testing.expectEqual(expected_bytes, frame_bytes.len);
        const frame = try Frame.parse(frame_bytes, 0);
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        const side = try frame.sideInformation();
        try std.testing.expectEqual(@as(u16, 0), side.main_data_bits);
        padded_frames += @intFromBool(frame.header.padding);
        encoded_bytes += frame_bytes.len;

        const decoded = try decoder.decode(frame);
        try std.testing.expectEqual(@as(u2, 1), decoded.channel_count);
        try std.testing.expectEqual(@as(u16, 1152), decoded.sample_count);
        for (decoded.channels[0]) |sample|
            try std.testing.expectEqual(@as(f32, 0), sample);
    }
    try std.testing.expectEqual(@as(usize, 95), padded_frames);
    try std.testing.expectEqual(
        @as(usize, 41_795),
        encoded_bytes,
    );
    try std.testing.expectEqual(@as(u64, 100), encoder.frames_encoded);

    encoder.reset();
    try std.testing.expectEqual(@as(u64, 0), encoder.frames_encoded);
    try std.testing.expectEqual(
        @as(u32, 0),
        encoder.padding_accumulator,
    );
    try std.testing.expectEqual(@as(usize, 417), try encoder.nextFrameBytes());
}

test "encodes nonzero quantized MP3 frames through the decoder" {
    var encoder = try FrameEncoder.init(.{
        .channel_mode = .mono,
        .crc_present = true,
    });
    var source = QuantizedEncoderFrame{};
    source.private_bits = 7;
    source.scfsi[0] = 0xf;
    source.granules[0][0].description = .{
        .big_values = 1,
        .global_gain = 210,
        .table_select = @splat(1),
        .region0_count = 7,
        .region1_count = 5,
    };
    source.granules[0][0].spectrum[0] = 1;
    source.granules[0][0].spectrum[1] = -1;
    source.granules[1][0].description = .{
        .global_gain = 210,
        .region0_count = 7,
        .region1_count = 5,
        .count1_table_select = true,
    };
    source.granules[1][0].spectrum[0] = 1;
    source.granules[1][0].spectrum[2] = -1;
    source.granules[1][0].spectrum[3] = 1;

    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const encoded = try encoder.encodeQuantizedFrame(
        &source,
        &storage,
    );
    const parsed = try Frame.parse(encoded, 0);
    try std.testing.expectEqual(
        @as(?bool, true),
        try parsed.crcValid(),
    );
    const side = try parsed.sideInformation();
    try std.testing.expectEqual(@as(u5, 7), side.private_bits);
    try std.testing.expectEqual(@as(u4, 0xf), side.scfsi[0]);
    try std.testing.expect(side.main_data_bits > 0);
    try std.testing.expectEqual(
        side.main_data_bits,
        side.granules[0].channels[0].part2_3_length +
            side.granules[1].channels[0].part2_3_length,
    );

    var reservoir = MainDataReservoir(511){};
    var main_storage: [512]u8 = undefined;
    const main_data = try reservoir.assemble(
        parsed,
        &main_storage,
    );
    const factors = try decodeScaleFactors(
        parsed.header,
        side,
        main_data,
    );
    const first_spectrum = try decodeHuffmanChannel(
        parsed.header,
        side.granules[0].channels[0],
        factors.granules[0].channels[0],
        main_data,
    );
    try std.testing.expectEqualSlices(
        i32,
        source.granules[0][0].spectrum[0..2],
        first_spectrum.lines[0..2],
    );
    const second_spectrum = try decodeHuffmanChannel(
        parsed.header,
        side.granules[1].channels[0],
        factors.granules[1].channels[0],
        main_data,
    );
    try std.testing.expectEqualSlices(
        i32,
        source.granules[1][0].spectrum[0..4],
        second_spectrum.lines[0..4],
    );

    var decoder = FrameDecoder{};
    const pcm = try decoder.decode(parsed);
    var nonzero = false;
    for (pcm.channels[0]) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        nonzero = nonzero or sample != 0;
    }
    try std.testing.expect(nonzero);
}

test "rejects oversized and malformed quantized MP3 frames" {
    var encoder = try FrameEncoder.init(.{
        .version = .mpeg2,
        .bitrate_kbps = 8,
        .sample_rate = 24_000,
        .channel_mode = .stereo,
    });
    var source = QuantizedEncoderFrame{};
    for (0..2) |channel| {
        source.granules[0][channel].description = .{
            .big_values = 288,
            .global_gain = 210,
            .table_select = @splat(13),
            .region0_count = 7,
            .region1_count = 5,
        };
        source.granules[0][channel].spectrum = @splat(15);
    }
    const before = encoder;
    var storage: [maximum_encoded_frame_bytes]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.Mp3HuffmanBitCountOverflow,
        encoder.encodeQuantizedFrame(&source, &storage),
    );
    try std.testing.expectEqual(before, encoder);
    try std.testing.expectEqualSlices(
        u8,
        &(@as(
            [maximum_encoded_frame_bytes]u8,
            @splat(0x5a),
        )),
        &storage,
    );

    source = .{};
    source.granules[0][0].description.scalefac_compress = 1;
    try std.testing.expectError(
        error.UnsupportedMp3EncoderScaleFactors,
        encoder.encodeQuantizedFrame(&source, &storage),
    );

    source = .{};
    source.granules[1][0].spectrum[0] = 1;
    try std.testing.expectError(
        error.InvalidMp3EncoderFrame,
        encoder.encodeQuantizedFrame(&source, &storage),
    );
}

test "encodes silence for every MP3 version and rejects hostile state" {
    const configs = [_]EncoderConfig{
        .{
            .version = .mpeg1,
            .bitrate_kbps = 320,
            .sample_rate = 32_000,
            .channel_mode = .stereo,
        },
        .{
            .version = .mpeg2,
            .bitrate_kbps = 8,
            .sample_rate = 24_000,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .{
            .version = .mpeg25,
            .bitrate_kbps = 160,
            .sample_rate = 8_000,
            .channel_mode = .dual_channel,
        },
    };
    for (configs) |config| {
        var encoder = try FrameEncoder.init(config);
        var storage: [maximum_encoded_frame_bytes]u8 = undefined;
        const encoded = try encoder.encodeSilentFrame(&storage);
        const frame = try Frame.parse(encoded, 0);
        try std.testing.expectEqual(config.version, frame.header.version);
        try std.testing.expectEqual(
            config.channel_mode,
            frame.header.channel_mode,
        );
        try std.testing.expectEqual(
            config.crc_present,
            frame.header.crc_present,
        );
        var decoder = FrameDecoder{};
        const decoded = try decoder.decode(frame);
        try std.testing.expectEqual(
            frame.header.samplesPerFrame(),
            decoded.sample_count,
        );
    }

    try std.testing.expectError(
        error.InvalidMp3EncoderBitrate,
        FrameEncoder.init(.{ .bitrate_kbps = 17 }),
    );
    try std.testing.expectError(
        error.InvalidMp3EncoderSampleRate,
        FrameEncoder.init(.{ .sample_rate = 96_000 }),
    );
    try std.testing.expectError(
        error.InvalidMp3EncoderEmphasis,
        FrameEncoder.init(.{ .emphasis = 2 }),
    );

    var encoder = try FrameEncoder.init(.{});
    const before = encoder;
    var short: [16]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.encodeSilentFrame(&short),
    );
    try std.testing.expectEqual(before, encoder);
    try std.testing.expectEqualSlices(
        u8,
        &(@as([16]u8, @splat(0x5a))),
        &short,
    );

    encoder.padding_accumulator = encoder.config.sample_rate;
    const hostile = encoder;
    var storage: [maximum_encoded_frame_bytes]u8 = @splat(0x33);
    try std.testing.expectError(
        error.InvalidMp3EncoderState,
        encoder.encodeSilentFrame(&storage),
    );
    try std.testing.expectEqual(hostile, encoder);
    try std.testing.expectEqualSlices(
        u8,
        &(@as(
            [maximum_encoded_frame_bytes]u8,
            @splat(0x33),
        )),
        &storage,
    );
}

test "parses MPEG Layer III versions, CRC, padding, and frame sizes" {
    const mpeg1 = try Header.parse(&testHeader(
        3,
        false,
        9,
        0,
        false,
        .stereo,
    ));
    try std.testing.expectEqual(Version.mpeg1, mpeg1.version);
    try std.testing.expect(mpeg1.crc_present);
    try std.testing.expectEqual(@as(u16, 128), mpeg1.bitrate_kbps);
    try std.testing.expectEqual(@as(u32, 44_100), mpeg1.sample_rate);
    try std.testing.expectEqual(@as(usize, 417), mpeg1.frameBytes());
    try std.testing.expectEqual(@as(u16, 1152), mpeg1.samplesPerFrame());
    try std.testing.expectEqual(@as(u8, 32), mpeg1.sideInformationBytes());

    const mpeg2 = try Header.parse(&testHeader(
        2,
        true,
        8,
        0,
        true,
        .mono,
    ));
    try std.testing.expectEqual(Version.mpeg2, mpeg2.version);
    try std.testing.expect(!mpeg2.crc_present);
    try std.testing.expectEqual(@as(u16, 64), mpeg2.bitrate_kbps);
    try std.testing.expectEqual(@as(u32, 22_050), mpeg2.sample_rate);
    try std.testing.expectEqual(@as(usize, 209), mpeg2.frameBytes());
    try std.testing.expectEqual(@as(u16, 576), mpeg2.samplesPerFrame());
    try std.testing.expectEqual(@as(u8, 9), mpeg2.sideInformationBytes());

    const mpeg25 = try Header.parse(&testHeader(
        0,
        true,
        1,
        2,
        false,
        .joint_stereo,
    ));
    try std.testing.expectEqual(@as(u32, 8_000), mpeg25.sample_rate);
    try std.testing.expectEqual(@as(u16, 8), mpeg25.bitrate_kbps);
    try std.testing.expectEqual(@as(usize, 72), mpeg25.frameBytes());
}

test "validates protected Layer III header and side information" {
    const protected_header =
        testHeader(3, false, 9, 0, false, .stereo);
    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(
        &encoded,
        0,
        protected_header,
    );
    for (encoded[6..38], 0..) |*byte, index|
        byte.* = @intCast(index);
    encoded[4] = 0x65;
    encoded[5] = 0xe8;

    var frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());
    const file_frame = FileFrame{
        .byte_offset = 0,
        .bytes = frame.bytes,
        .header = frame.header,
        .xing = frame.xing,
        .vbri = frame.vbri,
    };
    try std.testing.expectEqual(
        @as(?bool, true),
        try file_frame.crcValid(),
    );

    encoded[20] ^= 1;
    frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectEqual(@as(?bool, false), try frame.crcValid());
    encoded[20] ^= 1;
    encoded[38] ^= 1;
    frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());

    const unprotected_header =
        testHeader(3, true, 9, 0, false, .stereo);
    const unprotected_end = try appendFrame(
        &encoded,
        0,
        unprotected_header,
    );
    frame = try Frame.parse(encoded[0..unprotected_end], 0);
    try std.testing.expectEqual(@as(?bool, null), try frame.crcValid());

    const truncated = Frame{
        .offset = 0,
        .bytes = encoded[0..6],
        .header = try Header.parse(&protected_header),
        .xing = null,
        .vbri = null,
    };
    try std.testing.expectError(
        error.TruncatedMp3Frame,
        truncated.crcValid(),
    );

    const mpeg2_mono_header =
        testHeader(2, false, 8, 0, false, .mono);
    const mpeg2_end = try appendFrame(
        &encoded,
        0,
        mpeg2_mono_header,
    );
    for (encoded[6..15], 0..) |*byte, index|
        byte.* = @intCast(0xa0 + index);
    encoded[4] = 0x2f;
    encoded[5] = 0x43;
    try std.testing.expectEqual(
        @as(?bool, true),
        try (try Frame.parse(encoded[0..mpeg2_end], 0)).crcValid(),
    );

    const mpeg25_stereo_header =
        testHeader(0, false, 8, 0, false, .joint_stereo);
    const mpeg25_end = try appendFrame(
        &encoded,
        0,
        mpeg25_stereo_header,
    );
    for (encoded[6..23], 0..) |*byte, index|
        byte.* = @intCast(0x40 + index);
    encoded[4] = 0x37;
    encoded[5] = 0x89;
    try std.testing.expectEqual(
        @as(?bool, true),
        try (try Frame.parse(encoded[0..mpeg25_end], 0)).crcValid(),
    );
}

test "parses bounded Layer III side information" {
    const header_bytes =
        testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(&encoded, 0, header_bytes);
    const side = encoded[4..36];
    setTestBits(side, 0, 9, 17);
    setTestBits(side, 9, 3, 5);
    setTestBits(side, 12, 4, 0xa);
    setTestBits(side, 16, 4, 0x3);
    setTestBits(side, 20, 12, 321);
    setTestBits(side, 32, 9, 144);
    setTestBits(side, 41, 8, 200);
    setTestBits(side, 49, 4, 9);
    setTestBits(side, 53, 1, 1);
    setTestBits(side, 54, 2, 2);
    setTestBits(side, 57, 5, 7);
    setTestBits(side, 62, 5, 8);
    setTestBits(side, 67, 3, 1);
    setTestBits(side, 70, 3, 2);
    setTestBits(side, 73, 3, 3);
    setTestBits(side, 76, 1, 1);
    setTestBits(side, 78, 1, 1);

    const frame = try Frame.parse(encoded[0..frame_end], 0);
    const parsed = try frame.sideInformation();
    try std.testing.expectEqual(@as(u2, 2), parsed.channel_count);
    try std.testing.expectEqual(@as(u2, 2), parsed.granule_count);
    try std.testing.expectEqual(@as(u9, 17), parsed.main_data_begin);
    try std.testing.expectEqual(@as(u5, 5), parsed.private_bits);
    try std.testing.expectEqual(@as(u4, 0xa), parsed.scfsi[0]);
    try std.testing.expectEqual(@as(u4, 0x3), parsed.scfsi[1]);
    try std.testing.expectEqual(@as(u16, 321), parsed.main_data_bits);
    const channel = parsed.granules[0].channels[0];
    try std.testing.expectEqual(@as(u12, 321), channel.part2_3_length);
    try std.testing.expectEqual(@as(u9, 144), channel.big_values);
    try std.testing.expectEqual(@as(u8, 200), channel.global_gain);
    try std.testing.expectEqual(@as(u9, 9), channel.scalefac_compress);
    try std.testing.expect(channel.window_switching);
    try std.testing.expectEqual(@as(u2, 2), channel.block_type);
    try std.testing.expect(!channel.mixed_block);
    try std.testing.expectEqual([3]u5{ 7, 8, 0 }, channel.table_select);
    try std.testing.expectEqual([3]u3{ 1, 2, 3 }, channel.subblock_gain);
    try std.testing.expectEqual(@as(u4, 8), channel.region0_count);
    try std.testing.expectEqual(@as(u4, 12), channel.region1_count);
    try std.testing.expect(channel.preflag);
    try std.testing.expect(!channel.scalefac_scale);
    try std.testing.expect(channel.count1_table_select);

    const file_frame = FileFrame{
        .byte_offset = 0,
        .bytes = frame.bytes,
        .header = frame.header,
        .xing = frame.xing,
        .vbri = frame.vbri,
    };
    try std.testing.expectEqual(
        parsed,
        try file_frame.sideInformation(),
    );
}

test "serializes Layer III side information transactionally" {
    const mpeg1 = try Header.parse(
        &testHeader(3, false, 9, 0, false, .mono),
    );
    var mpeg1_side = SideInformation{
        .channel_count = 1,
        .granule_count = 2,
        .main_data_begin = 31,
        .private_bits = 17,
        .scfsi = .{ 0xa, 0 },
        .main_data_bits = 30,
    };
    mpeg1_side.granules[0].channels[0] = .{
        .part2_3_length = 10,
        .big_values = 1,
        .global_gain = 210,
        .scalefac_compress = 3,
        .table_select = .{ 1, 2, 3 },
        .region0_count = 7,
        .region1_count = 5,
        .preflag = true,
        .scalefac_scale = true,
    };
    mpeg1_side.granules[1].channels[0] = .{
        .part2_3_length = 20,
        .big_values = 2,
        .global_gain = 190,
        .scalefac_compress = 7,
        .table_select = .{ 5, 6, 7 },
        .region0_count = 6,
        .region1_count = 4,
        .count1_table_select = true,
    };
    var storage: [32]u8 = undefined;
    const encoded_mpeg1 = try encodeSideInformation(
        mpeg1,
        mpeg1_side,
        &storage,
    );
    try std.testing.expectEqual(
        @as(usize, 17),
        encoded_mpeg1.len,
    );
    var frame_storage: [23]u8 = @splat(0);
    const header_bytes = try mpeg1.encode();
    @memcpy(frame_storage[0..4], &header_bytes);
    @memcpy(frame_storage[6..23], encoded_mpeg1);
    try std.testing.expectEqual(
        mpeg1_side,
        try parseSideInformation(&frame_storage, mpeg1),
    );

    const mpeg2 = try Header.parse(
        &testHeader(2, true, 8, 0, false, .stereo),
    );
    var mpeg2_side = SideInformation{
        .channel_count = 2,
        .granule_count = 1,
        .main_data_begin = 200,
        .private_bits = 2,
        .main_data_bits = 0,
    };
    mpeg2_side.granules[0].channels[0] = .{
        .global_gain = 180,
        .scalefac_compress = 300,
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
        .table_select = .{ 13, 15, 0 },
        .subblock_gain = .{ 1, 2, 3 },
        .region0_count = 7,
        .region1_count = 13,
        .scalefac_scale = true,
    };
    mpeg2_side.granules[0].channels[1] = .{
        .global_gain = 181,
        .scalefac_compress = 301,
        .window_switching = true,
        .block_type = 2,
        .table_select = .{ 16, 24, 0 },
        .subblock_gain = .{ 3, 2, 1 },
        .region0_count = 8,
        .region1_count = 12,
        .count1_table_select = true,
    };
    const encoded_mpeg2 = try encodeSideInformation(
        mpeg2,
        mpeg2_side,
        &storage,
    );
    try std.testing.expectEqual(
        @as(usize, 17),
        encoded_mpeg2.len,
    );
    var mpeg2_frame: [21]u8 = @splat(0);
    const mpeg2_header = try mpeg2.encode();
    @memcpy(mpeg2_frame[0..4], &mpeg2_header);
    @memcpy(mpeg2_frame[4..21], encoded_mpeg2);
    try std.testing.expectEqual(
        mpeg2_side,
        try parseSideInformation(&mpeg2_frame, mpeg2),
    );

    var malformed = mpeg1_side;
    malformed.main_data_bits += 1;
    var retained: [32]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.InvalidMp3SideInformation,
        encodeSideInformation(mpeg1, malformed, &retained),
    );
    try std.testing.expectEqualSlices(
        u8,
        &(@as([32]u8, @splat(0x5a))),
        &retained,
    );
    try std.testing.expectError(
        error.InsufficientMp3SideInformationStorage,
        encodeSideInformation(mpeg1, mpeg1_side, retained[0..16]),
    );

    malformed = mpeg1_side;
    malformed.granules[0].channels[1].global_gain = 1;
    try std.testing.expectError(
        error.InvalidMp3SideInformation,
        encodeSideInformation(mpeg1, malformed, &retained),
    );
}

test "rejects malformed Layer III side information" {
    const header_bytes =
        testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(&encoded, 0, header_bytes);
    const side = encoded[4..36];
    setTestBits(side, 32, 9, 289);
    var frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectError(
        error.InvalidMp3BigValues,
        frame.sideInformation(),
    );

    @memset(side, 0);
    setTestBits(side, 53, 1, 1);
    frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectError(
        error.InvalidMp3BlockType,
        frame.sideInformation(),
    );

    @memset(side, 0);
    setTestBits(side, 54, 5, 14);
    frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectError(
        error.InvalidMp3HuffmanTable,
        frame.sideInformation(),
    );

    @memset(side, 0);
    setTestBits(side, 69, 4, 15);
    setTestBits(side, 73, 3, 7);
    frame = try Frame.parse(encoded[0..frame_end], 0);
    try std.testing.expectError(
        error.InvalidMp3RegionCounts,
        frame.sideInformation(),
    );

    const parsed_header = try Header.parse(&header_bytes);
    const truncated = Frame{
        .offset = 0,
        .bytes = encoded[0..35],
        .header = parsed_header,
        .xing = null,
        .vbri = null,
    };
    try std.testing.expectError(
        error.TruncatedMp3SideInformation,
        truncated.sideInformation(),
    );

    const mpeg2_header =
        testHeader(2, true, 8, 0, false, .stereo);
    const mpeg2_end = try appendFrame(
        &encoded,
        0,
        mpeg2_header,
    );
    const mpeg2 = try (try Frame.parse(
        encoded[0..mpeg2_end],
        0,
    )).sideInformation();
    try std.testing.expectEqual(@as(u2, 1), mpeg2.granule_count);
    try std.testing.expectEqual(@as(u2, 2), mpeg2.channel_count);
    try std.testing.expectEqual(@as(u16, 0), mpeg2.main_data_bits);
}

test "assembles bounded Layer III main-data reservoirs transactionally" {
    const Reservoir = MainDataReservoir(511);
    const header_bytes =
        testHeader(3, true, 9, 0, false, .stereo);
    var first_encoded: [500]u8 = undefined;
    const first_end = try appendFrame(
        &first_encoded,
        0,
        header_bytes,
    );
    setTestBits(first_encoded[4..36], 20, 12, 16);
    first_encoded[first_end - 2] = 0xa1;
    first_encoded[first_end - 1] = 0xb2;
    const first = try Frame.parse(
        first_encoded[0..first_end],
        0,
    );

    var reservoir = Reservoir{};
    var first_output: [2]u8 = @splat(0xff);
    const first_data = try reservoir.assemble(
        first,
        &first_output,
    );
    try std.testing.expectEqual(@as(u16, 16), first_data.bit_count);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0 }, first_data.bytes);

    var partial_encoded = first_encoded;
    setTestBits(partial_encoded[4..36], 20, 12, 9);
    const partial = try Frame.parse(
        partial_encoded[0..first_end],
        0,
    );
    var partial_reservoir = Reservoir{};
    var partial_output: [2]u8 = @splat(0xff);
    const partial_data = try partial_reservoir.assemble(
        partial,
        &partial_output,
    );
    try std.testing.expectEqual(@as(u16, 9), partial_data.bit_count);
    try std.testing.expectEqual(@as(usize, 2), partial_data.bytes.len);

    var second_encoded: [500]u8 = undefined;
    const second_end = try appendFrame(
        &second_encoded,
        0,
        header_bytes,
    );
    setTestBits(second_encoded[4..36], 0, 9, 2);
    setTestBits(second_encoded[4..36], 20, 12, 24);
    second_encoded[36] = 0xc3;
    const second = try Frame.parse(
        second_encoded[0..second_end],
        0,
    );
    var second_output: [3]u8 = @splat(0);
    const second_data = try reservoir.assemble(
        second,
        &second_output,
    );
    try std.testing.expectEqual(@as(u16, 24), second_data.bit_count);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xa1, 0xb2, 0xc3 },
        second_data.bytes,
    );

    var missing = Reservoir{};
    var unchanged: [3]u8 = @splat(0x7a);
    try std.testing.expectError(
        error.Mp3MainDataHistoryUnavailable,
        missing.assemble(second, &unchanged),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x7a, 0x7a, 0x7a },
        &unchanged,
    );
    try std.testing.expectEqual(@as(usize, 0), missing.length);

    var short = Reservoir{};
    _ = try short.assemble(first, &first_output);
    const retained_length = short.length;
    var short_output: [2]u8 = @splat(0x6b);
    try std.testing.expectError(
        error.InsufficientMp3MainDataStorage,
        short.assemble(second, &short_output),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x6b, 0x6b },
        &short_output,
    );
    try std.testing.expectEqual(retained_length, short.length);

    var aliased = Reservoir{};
    @memcpy(
        aliased.storage[0..first.bytes.len],
        first.bytes,
    );
    const aliased_frame = try Frame.parse(
        aliased.storage[0..first.bytes.len],
        0,
    );
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        aliased.assemble(aliased_frame, &first_output),
    );
    try std.testing.expectEqual(@as(usize, 0), aliased.length);

    const file_second = FileFrame{
        .byte_offset = 0,
        .bytes = second.bytes,
        .header = second.header,
        .xing = second.xing,
        .vbri = second.vbri,
    };
    _ = try short.assemble(file_second, &second_output);
    short.reset();
    try std.testing.expectEqual(@as(usize, 0), short.length);

    short.length = short.storage.len + 1;
    try std.testing.expectError(
        error.InvalidMp3ReservoirState,
        short.assemble(second, &second_output),
    );
}

test "decodes MPEG-1 scale factors and granule reuse groups" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var side = SideInformation{
        .channel_count = 1,
        .granule_count = 2,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = 36,
    };
    side.scfsi[0] = 0b1010;
    side.granules[0].channels[0].part2_3_length = 24;
    side.granules[0].channels[0].scalefac_compress = 5;
    side.granules[1].channels[0].part2_3_length = 12;
    side.granules[1].channels[0].scalefac_compress = 5;

    var encoded: [5]u8 = @splat(0);
    for (0..21) |bit| setTestBits(&encoded, bit, 1, 1);
    for (29..34) |bit| setTestBits(&encoded, bit, 1, 1);
    const decoded = try decodeScaleFactors(
        header,
        side,
        .{ .bytes = &encoded, .bit_count = 36 },
    );
    const first = decoded.granules[0].channels[0];
    try std.testing.expectEqual(@as(u6, 22), first.value_count);
    try std.testing.expectEqual(@as(u12, 21), first.part2_bits);
    try std.testing.expectEqual(@as(u16, 21), first.huffman_bit_offset);
    try std.testing.expectEqual(@as(u12, 3), first.huffman_bit_count);
    try std.testing.expectEqual(@as(u8, 1), first.values[20]);
    try std.testing.expectEqual(@as(u8, 0), first.values[21]);

    const second = decoded.granules[1].channels[0];
    try std.testing.expectEqual(@as(u12, 10), second.part2_bits);
    try std.testing.expectEqual(@as(u16, 34), second.huffman_bit_offset);
    try std.testing.expectEqual(@as(u12, 2), second.huffman_bit_count);
    try std.testing.expectEqual(@as(u8, 1), second.values[0]);
    try std.testing.expectEqual(@as(u8, 0), second.values[6]);
    try std.testing.expectEqual(@as(u8, 1), second.values[11]);
    try std.testing.expectEqual(@as(u8, 1), second.values[16]);
}

test "decodes short and low-sampling-frequency scale factors" {
    const mpeg1_header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var short_side = SideInformation{
        .channel_count = 1,
        .granule_count = 2,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = 104,
    };
    short_side.granules[0].channels[0] = .{
        .part2_3_length = 104,
        .scalefac_compress = 14,
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    };
    var short_bits: [13]u8 = @splat(0xff);
    const short = try decodeScaleFactors(
        mpeg1_header,
        short_side,
        .{ .bytes = &short_bits, .bit_count = 104 },
    );
    const short_channel = short.granules[0].channels[0];
    try std.testing.expectEqual(@as(u6, 38), short_channel.value_count);
    try std.testing.expectEqual(@as(u12, 104), short_channel.part2_bits);
    try std.testing.expectEqual(@as(u8, 15), short_channel.values[16]);
    try std.testing.expectEqual(@as(u8, 3), short_channel.values[34]);
    try std.testing.expectEqual(@as(u8, 0), short_channel.values[35]);
    try std.testing.expectEqual(@as(u8, 0), short_channel.values[37]);

    const mpeg2_header = try Header.parse(
        &testHeader(2, true, 8, 0, false, .mono),
    );
    var lsf_side = SideInformation{
        .channel_count = 1,
        .granule_count = 1,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = 16,
    };
    lsf_side.granules[0].channels[0] = .{
        .part2_3_length = 16,
        .scalefac_compress = 421,
    };
    var lsf_bits: [2]u8 = @splat(0xff);
    const lsf = try decodeScaleFactors(
        mpeg2_header,
        lsf_side,
        .{ .bytes = &lsf_bits, .bit_count = 16 },
    );
    const lsf_channel = lsf.granules[0].channels[0];
    try std.testing.expectEqual(@as(u6, 21), lsf_channel.value_count);
    try std.testing.expectEqual(@as(u12, 13), lsf_channel.part2_bits);
    try std.testing.expectEqual(@as(u12, 3), lsf_channel.huffman_bit_count);
    try std.testing.expectEqual(@as(u8, 1), lsf_channel.values[5]);
    try std.testing.expectEqual(@as(u8, 0), lsf_channel.values[6]);
    try std.testing.expectEqual(@as(u8, 1), lsf_channel.values[17]);
}

test "decodes low-sampling-frequency intensity scale factors" {
    var header_bytes =
        testHeader(2, true, 8, 0, false, .joint_stereo);
    header_bytes[3] |= 1 << 4;
    const header = try Header.parse(&header_bytes);
    var side = SideInformation{
        .channel_count = 2,
        .granule_count = 1,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = 35,
    };
    side.granules[0].channels[1] = .{
        .part2_3_length = 35,
        .scalefac_compress = 100,
    };
    var encoded: [5]u8 = @splat(0xff);
    const decoded = try decodeScaleFactors(
        header,
        side,
        .{ .bytes = &encoded, .bit_count = 35 },
    );
    const right = decoded.granules[0].channels[1];
    try std.testing.expectEqual(@as(u6, 21), right.value_count);
    try std.testing.expectEqual(@as(u12, 35), right.part2_bits);
    for (right.intensity_max[0..21]) |is_max|
        try std.testing.expect(is_max);
}

test "covers low-sampling-frequency compression families and layouts" {
    const Case = struct {
        compression: u9,
        intensity: bool,
        expected_bits: usize,
        expected_count: u6,
        expected_preflag: bool = false,
    };
    const cases = [_]Case{
        .{
            .compression = 100,
            .intensity = false,
            .expected_bits = 16,
            .expected_count = 21,
        },
        .{
            .compression = 421,
            .intensity = false,
            .expected_bits = 13,
            .expected_count = 21,
        },
        .{
            .compression = 503,
            .intensity = false,
            .expected_bits = 11,
            .expected_count = 21,
            .expected_preflag = true,
        },
        .{
            .compression = 100,
            .intensity = true,
            .expected_bits = 35,
            .expected_count = 21,
        },
        .{
            .compression = 401,
            .intensity = true,
            .expected_bits = 12,
            .expected_count = 21,
        },
        .{
            .compression = 501,
            .intensity = true,
            .expected_bits = 16,
            .expected_count = 21,
        },
    };
    var storage: [32]u8 = @splat(0);
    for (cases) |case| {
        var reader = MainDataBitReader{
            .bytes = &storage,
            .bit_limit = storage.len * 8,
        };
        const decoded = try decodeLsfScaleFactorChannel(
            &reader,
            .{ .scalefac_compress = case.compression },
            case.intensity,
        );
        try std.testing.expectEqual(case.expected_bits, reader.bit_offset);
        try std.testing.expectEqual(
            case.expected_count,
            decoded.value_count,
        );
        try std.testing.expectEqual(
            case.expected_preflag,
            decoded.preflag,
        );
        try std.testing.expectEqual(
            case.intensity and case.compression & 1 != 0,
            decoded.intensity_scale,
        );
    }

    var short_reader = MainDataBitReader{
        .bytes = &storage,
        .bit_limit = storage.len * 8,
    };
    const short = try decodeLsfScaleFactorChannel(
        &short_reader,
        .{
            .scalefac_compress = 100,
            .window_switching = true,
            .block_type = 2,
        },
        false,
    );
    try std.testing.expectEqual(@as(u6, 36), short.value_count);
    try std.testing.expectEqual(@as(usize, 27), short_reader.bit_offset);

    var mixed_reader = MainDataBitReader{
        .bytes = &storage,
        .bit_limit = storage.len * 8,
    };
    const mixed = try decodeLsfScaleFactorChannel(
        &mixed_reader,
        .{
            .scalefac_compress = 100,
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
        false,
    );
    try std.testing.expectEqual(@as(u6, 33), mixed.value_count);
    try std.testing.expectEqual(@as(usize, 24), mixed_reader.bit_offset);
}

test "maps every Layer III sample rate to bounded spectral bands" {
    const versions = [_]u2{ 3, 2, 0 };
    for (versions) |version_bits| {
        for (0..3) |rate_index| {
            const header = try Header.parse(&testHeader(
                version_bits,
                true,
                8,
                @intCast(rate_index),
                false,
                .stereo,
            ));
            const bands = try scaleFactorBands(header);
            try std.testing.expectEqual(
                @as(usize, 23),
                bands.long_starts.len,
            );
            try std.testing.expectEqual(
                @as(usize, 14),
                bands.short_starts.len,
            );
            try std.testing.expectEqual(
                @as(u16, 0),
                bands.long_starts[0],
            );
            try std.testing.expectEqual(
                @as(u16, 576),
                bands.long_starts[22],
            );
            try std.testing.expectEqual(
                @as(u16, 192),
                bands.short_starts[13],
            );
            for (bands.long_starts[0..22], bands.long_starts[1..23]) |
                first,
                second,
            | try std.testing.expect(first < second);
            for (
                bands.short_starts[0..13],
                bands.short_starts[1..14],
            ) |first, second| try std.testing.expect(first < second);
        }
    }
}

test "plans long short and low-rate Huffman regions" {
    const mpeg1 = try Header.parse(
        &testHeader(3, true, 9, 0, false, .stereo),
    );
    try std.testing.expectEqual(
        [2]u16{ 36, 110 },
        try huffmanRegionEnds(mpeg1, .{
            .region0_count = 7,
            .region1_count = 5,
        }),
    );
    try std.testing.expectEqual(
        [2]u16{ 36, 576 },
        try huffmanRegionEnds(mpeg1, .{
            .window_switching = true,
            .block_type = 2,
        }),
    );

    const mpeg25 = try Header.parse(
        &testHeader(0, true, 8, 2, false, .stereo),
    );
    try std.testing.expectEqual(@as(u32, 8_000), mpeg25.sample_rate);
    try std.testing.expectEqual(
        [2]u16{ 72, 576 },
        try huffmanRegionEnds(mpeg25, .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        }),
    );

    try std.testing.expectError(
        error.InvalidMp3BlockType,
        huffmanRegionEnds(mpeg1, .{ .block_type = 2 }),
    );
    try std.testing.expectError(
        error.InvalidMp3RegionCounts,
        huffmanRegionEnds(mpeg1, .{
            .region0_count = 15,
            .region1_count = 15,
        }),
    );
    var invalid_rate = mpeg1;
    invalid_rate.sample_rate = 12_345;
    try std.testing.expectError(
        error.InvalidMp3SampleRate,
        scaleFactorBands(invalid_rate),
    );
}

test "encodes every Layer III Huffman pair codebook" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    for (0..32) |table_value| {
        const table_index: u5 = @intCast(table_value);
        if (table_index == 4 or table_index == 14) continue;
        const table = try huffman_tables.get(table_index);
        for (table.entries, 0..) |_, entry_index| {
            const x: i32 = @intCast(entry_index / table.side);
            const y: i32 = @intCast(entry_index % table.side);
            var spectrum: [576]i32 = @splat(0);
            spectrum[0] = if (x == 0) 0 else -x;
            spectrum[1] = y;
            var storage: [512]u8 = undefined;
            const encoded = try encodeHuffmanChannel(
                header,
                .{
                    .big_values = 1,
                    .table_select = @splat(table_index),
                    .region0_count = 7,
                    .region1_count = 5,
                },
                &spectrum,
                &storage,
            );
            const decoded = try decodeHuffmanChannel(
                header,
                encoded.description,
                .{
                    .huffman_bit_count = encoded.description.part2_3_length,
                },
                encoded.main_data,
            );
            try std.testing.expectEqualSlices(
                i32,
                spectrum[0..2],
                decoded.lines[0..2],
            );
        }
    }

    var escape_spectrum: [576]i32 = @splat(0);
    escape_spectrum[0] = -(15 + 8191);
    escape_spectrum[1] = 15 + 8191;
    var storage: [512]u8 = undefined;
    const encoded = try encodeHuffmanChannel(
        header,
        .{
            .big_values = 1,
            .table_select = @splat(31),
            .region0_count = 7,
            .region1_count = 5,
        },
        &escape_spectrum,
        &storage,
    );
    const decoded = try decodeHuffmanChannel(
        header,
        encoded.description,
        .{
            .huffman_bit_count = encoded.description.part2_3_length,
        },
        encoded.main_data,
    );
    try std.testing.expectEqualSlices(
        i32,
        escape_spectrum[0..2],
        decoded.lines[0..2],
    );
}

test "encodes both Layer III count1 codebooks" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    for ([_]bool{ false, true }) |table_b| {
        var spectrum: [576]i32 = @splat(0);
        for (0..16) |pattern| {
            for (0..4) |component| {
                const line = pattern * 4 + component;
                const magnitude =
                    (pattern >> @intCast(3 - component)) & 1;
                spectrum[line] = if (magnitude == 0)
                    0
                else if (line & 1 == 0)
                    -1
                else
                    1;
            }
        }
        var storage: [512]u8 = undefined;
        const encoded = try encodeHuffmanChannel(
            header,
            .{
                .count1_table_select = table_b,
                .region0_count = 7,
                .region1_count = 5,
            },
            &spectrum,
            &storage,
        );
        const decoded = try decodeHuffmanChannel(
            header,
            encoded.description,
            .{
                .huffman_bit_count = encoded.description.part2_3_length,
            },
            encoded.main_data,
        );
        try std.testing.expectEqual(@as(u10, 64), decoded.decoded_lines);
        try std.testing.expectEqualSlices(
            i32,
            spectrum[0..64],
            decoded.lines[0..64],
        );
    }
}

test "rejects malformed Huffman encoder inputs transactionally" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var spectrum: [576]i32 = @splat(0);
    spectrum[0] = 2;
    var destination: [8]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.Mp3HuffmanTableTooSmall,
        encodeHuffmanChannel(
            header,
            .{
                .big_values = 1,
                .table_select = @splat(1),
                .region0_count = 7,
                .region1_count = 5,
            },
            &spectrum,
            &destination,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &(@as([8]u8, @splat(0x5a))),
        &destination,
    );

    spectrum[0] = std.math.minInt(i32);
    try std.testing.expectError(
        error.InvalidMp3QuantizedValue,
        encodeHuffmanChannel(
            header,
            .{
                .big_values = 1,
                .table_select = @splat(31),
                .region0_count = 7,
                .region1_count = 5,
            },
            &spectrum,
            &destination,
        ),
    );
    spectrum[0] = 0;
    spectrum[2] = 2;
    try std.testing.expectError(
        error.InvalidMp3Count1Value,
        encodeHuffmanChannel(
            header,
            .{
                .big_values = 1,
                .table_select = @splat(1),
                .region0_count = 7,
                .region1_count = 5,
            },
            &spectrum,
            &destination,
        ),
    );

    spectrum = @splat(0);
    spectrum[0] = 1;
    try std.testing.expectError(
        error.InsufficientMp3HuffmanStorage,
        encodeHuffmanChannel(
            header,
            .{
                .big_values = 1,
                .table_select = @splat(1),
                .region0_count = 7,
                .region1_count = 5,
            },
            &spectrum,
            &.{},
        ),
    );
}

test "decodes bounded Layer III count1 Huffman tables" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var table_a_bits: [1]u8 = @splat(0);
    setTestBits(&table_a_bits, 0, 4, 0b0111);
    setTestBits(&table_a_bits, 4, 1, 1);
    const table_a = try decodeHuffmanChannel(
        header,
        .{ .part2_3_length = 5 },
        .{
            .huffman_bit_offset = 0,
            .huffman_bit_count = 5,
        },
        .{ .bytes = &table_a_bits, .bit_count = 5 },
    );
    try std.testing.expectEqual(@as(u10, 4), table_a.decoded_lines);
    try std.testing.expectEqual(@as(u12, 5), table_a.huffman_bits_consumed);
    try std.testing.expectEqualSlices(
        i32,
        &.{ -1, 0, 0, 0 },
        table_a.lines[0..4],
    );

    var table_b_bits: [1]u8 = @splat(0);
    setTestBits(&table_b_bits, 0, 4, 0b0101);
    setTestBits(&table_b_bits, 4, 2, 0b01);
    const table_b = try decodeHuffmanChannel(
        header,
        .{
            .part2_3_length = 6,
            .count1_table_select = true,
        },
        .{
            .huffman_bit_offset = 0,
            .huffman_bit_count = 6,
        },
        .{ .bytes = &table_b_bits, .bit_count = 6 },
    );
    try std.testing.expectEqualSlices(
        i32,
        &.{ 1, 0, -1, 0 },
        table_b.lines[0..4],
    );

    var incomplete_bits: [1]u8 = @splat(0);
    const incomplete = try decodeHuffmanChannel(
        header,
        .{
            .part2_3_length = 5,
            .count1_table_select = true,
        },
        .{
            .huffman_bit_offset = 0,
            .huffman_bit_count = 5,
        },
        .{ .bytes = &incomplete_bits, .bit_count = 5 },
    );
    try std.testing.expectEqual(@as(u10, 0), incomplete.decoded_lines);
    try std.testing.expectEqual(
        @as(u12, 0),
        incomplete.huffman_bits_consumed,
    );
}

test "decodes zero pair codebooks before the count1 partition" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var encoded: [1]u8 = @splat(0);
    setTestBits(&encoded, 0, 3, 0b111);
    const decoded = try decodeHuffmanChannel(
        header,
        .{
            .part2_3_length = 3,
            .big_values = 2,
        },
        .{
            .huffman_bit_offset = 0,
            .huffman_bit_count = 3,
        },
        .{ .bytes = &encoded, .bit_count = 3 },
    );
    try std.testing.expectEqual(@as(u10, 16), decoded.decoded_lines);
    try std.testing.expectEqual(@as(u12, 3), decoded.huffman_bits_consumed);
    try std.testing.expectEqualSlices(
        i32,
        &@as([16]i32, @splat(0)),
        decoded.lines[0..16],
    );

    try std.testing.expectError(
        error.InvalidMp3HuffmanTable,
        decodeHuffmanChannel(
            header,
            .{
                .big_values = 1,
                .table_select = .{ 4, 0, 0 },
            },
            .{},
            .{ .bytes = &.{}, .bit_count = 0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3Part23Length,
        decodeHuffmanChannel(
            header,
            .{ .part2_3_length = 2 },
            .{ .huffman_bit_count = 1 },
            .{ .bytes = &encoded, .bit_count = 1 },
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3HuffmanRange,
        decodeHuffmanChannel(
            header,
            .{ .part2_3_length = 2 },
            .{
                .huffman_bit_offset = 1,
                .huffman_bit_count = 2,
            },
            .{ .bytes = &encoded, .bit_count = 2 },
        ),
    );
}

test "decodes every Layer III pair codebook and escape width" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    for (0..32) |table_number| {
        if (table_number == 4 or table_number == 14) continue;
        const table = try huffman_tables.get(
            @intCast(table_number),
        );
        const entry = table.entries[table.entries.len - 1];
        var encoded: [8]u8 = @splat(0);
        var bit_offset: usize = 0;
        setTestBits(
            &encoded,
            bit_offset,
            @intCast(entry.length),
            entry.bits,
        );
        bit_offset += entry.length;

        const base_magnitude: u16 = table.side - 1;
        var expected: [2]i32 = @splat(0);
        for (0..2) |component| {
            var magnitude = base_magnitude;
            if (base_magnitude == 15 and table.linbits != 0) {
                const extension: u16 =
                    if (component == 0) 1 else 0;
                setTestBits(
                    &encoded,
                    bit_offset,
                    @intCast(table.linbits),
                    extension,
                );
                bit_offset += table.linbits;
                magnitude += extension;
            }
            if (magnitude == 0) continue;
            const negative = component == 0;
            setTestBits(
                &encoded,
                bit_offset,
                1,
                @intFromBool(negative),
            );
            bit_offset += 1;
            expected[component] =
                if (negative)
                    -@as(i32, magnitude)
                else
                    magnitude;
        }

        const decoded = try decodeHuffmanChannel(
            header,
            .{
                .part2_3_length = @intCast(bit_offset),
                .big_values = 1,
                .table_select = .{
                    @intCast(table_number),
                    0,
                    0,
                },
            },
            .{
                .huffman_bit_offset = 0,
                .huffman_bit_count = @intCast(bit_offset),
            },
            .{
                .bytes = &encoded,
                .bit_count = @intCast(bit_offset),
            },
        );
        try std.testing.expectEqual(
            @as(u10, 2),
            decoded.decoded_lines,
        );
        try std.testing.expectEqual(
            @as(u12, @intCast(bit_offset)),
            decoded.huffman_bits_consumed,
        );
        try std.testing.expectEqualSlices(
            i32,
            &expected,
            decoded.lines[0..2],
        );
    }
}

test "enforces Layer III pair budgets and region transitions" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );

    var signs_truncated: [1]u8 = @splat(0);
    setTestBits(&signs_truncated, 0, 3, 0b000);
    try std.testing.expectError(
        error.InvalidMp3Part23Length,
        decodeHuffmanChannel(
            header,
            .{
                .part2_3_length = 4,
                .big_values = 1,
                .table_select = .{ 1, 0, 0 },
            },
            .{
                .huffman_bit_count = 4,
            },
            .{
                .bytes = &signs_truncated,
                .bit_count = 4,
            },
        ),
    );

    const escape_table = try huffman_tables.get(31);
    const escape_entry =
        escape_table.entries[escape_table.entries.len - 1];
    var escape_truncated: [3]u8 = @splat(0);
    setTestBits(
        &escape_truncated,
        0,
        escape_entry.length,
        escape_entry.bits,
    );
    try std.testing.expectError(
        error.InvalidMp3Part23Length,
        decodeHuffmanChannel(
            header,
            .{
                .part2_3_length = escape_entry.length,
                .big_values = 1,
                .table_select = .{ 31, 0, 0 },
            },
            .{
                .huffman_bit_count = escape_entry.length,
            },
            .{
                .bytes = &escape_truncated,
                .bit_count = escape_entry.length,
            },
        ),
    );

    var region_bits: [1]u8 = @splat(0);
    setTestBits(&region_bits, 0, 1, 0b1);
    const regions = try decodeHuffmanChannel(
        header,
        .{
            .part2_3_length = 1,
            .big_values = 5,
            .table_select = .{ 0, 0, 1 },
        },
        .{
            .huffman_bit_count = 1,
        },
        .{
            .bytes = &region_bits,
            .bit_count = 1,
        },
    );
    try std.testing.expectEqual(
        @as(u10, 10),
        regions.decoded_lines,
    );
    try std.testing.expectEqual(
        @as(u12, 1),
        regions.huffman_bits_consumed,
    );
    try std.testing.expectEqualSlices(
        i32,
        &@as([10]i32, @splat(0)),
        regions.lines[0..10],
    );
}

test "validates Layer III pair codebook prefixes" {
    for (0..32) |table_number| {
        if (table_number == 4 or table_number == 14) {
            try std.testing.expectError(
                error.InvalidMp3HuffmanTable,
                huffman_tables.get(@intCast(table_number)),
            );
            continue;
        }
        const table = try huffman_tables.get(
            @intCast(table_number),
        );
        try std.testing.expectEqual(
            @as(usize, table.side) * table.side,
            table.entries.len,
        );
        for (table.entries, 0..) |entry, first_index| {
            if (table_number == 0) {
                try std.testing.expectEqual(
                    @as(u5, 0),
                    entry.length,
                );
                continue;
            }
            try std.testing.expect(entry.length > 0);
            try std.testing.expect(
                entry.bits < @as(u32, 1) << @intCast(entry.length),
            );
            for (table.entries, 0..) |other, second_index| {
                if (first_index == second_index or
                    entry.length > other.length)
                    continue;
                try std.testing.expect(
                    other.bits >>
                        @intCast(other.length - entry.length) !=
                        entry.bits,
                );
            }

            var encoded: [8]u8 = @splat(0);
            var bit_offset: usize = 0;
            setTestBits(
                &encoded,
                bit_offset,
                @intCast(entry.length),
                entry.bits,
            );
            bit_offset += entry.length;
            const side: usize = table.side;
            const magnitudes = [2]u16{
                @intCast(first_index / side),
                @intCast(first_index % side),
            };
            for (magnitudes) |magnitude| {
                if (magnitude == 15 and table.linbits != 0)
                    bit_offset += table.linbits;
                if (magnitude != 0) bit_offset += 1;
            }
            var reader = MainDataBitReader{
                .bytes = &encoded,
                .bit_limit = bit_offset,
            };
            try std.testing.expectEqual(
                [2]i32{
                    magnitudes[0],
                    magnitudes[1],
                },
                try decodeHuffmanPair(&reader, table),
            );
            try std.testing.expectEqual(
                bit_offset,
                reader.bit_offset,
            );
        }
    }
}

test "requantizes long Layer III spectra with scale factors" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const bands = try scaleFactorBands(header);
    const preemphasized_line = bands.long_starts[11];
    var quantized = QuantizedSpectrum{
        .decoded_lines = @intCast(preemphasized_line + 1),
    };
    quantized.lines[0] = 1;
    quantized.lines[1] = -8;
    quantized.lines[4] = 1;
    quantized.lines[preemphasized_line] = 1;
    var factors = ScaleFactorChannel{
        .value_count = 22,
        .preflag = true,
    };
    factors.values[1] = 1;
    const decoded = try requantizeChannel(
        header,
        .{
            .global_gain = 210,
            .preflag = true,
        },
        factors,
        quantized,
    );
    try std.testing.expectEqual(@as(f32, 1), decoded.lines[0]);
    try std.testing.expectEqual(@as(f32, -16), decoded.lines[1]);
    try std.testing.expectApproxEqAbs(
        @as(f32, @floatCast(@sqrt(0.5))),
        decoded.lines[4],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @floatCast(@sqrt(0.5))),
        decoded.lines[preemphasized_line],
        1e-6,
    );
    for ([_]u2{ 1, 3 }) |block_type| {
        const switched = try requantizeChannel(
            header,
            .{
                .global_gain = 210,
                .window_switching = true,
                .block_type = block_type,
                .preflag = true,
            },
            factors,
            quantized,
        );
        try std.testing.expectEqual(@as(f32, 1), switched.lines[0]);
        const mixed = try requantizeChannel(
            header,
            .{
                .global_gain = 210,
                .window_switching = true,
                .block_type = block_type,
                .mixed_block = true,
                .preflag = true,
            },
            factors,
            quantized,
        );
        try std.testing.expectEqual(@as(f32, 1), mixed.lines[0]);
    }
    factors.values[21] = 1;
    try std.testing.expectError(
        error.InvalidMp3ScaleFactors,
        requantizeChannel(
            header,
            .{
                .global_gain = 210,
                .preflag = true,
            },
            factors,
            quantized,
        ),
    );
}

test "requantizes and reorders short Layer III spectra" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var quantized = QuantizedSpectrum{
        .decoded_lines = 9,
    };
    quantized.lines[0] = 1;
    quantized.lines[1] = -1;
    quantized.lines[4] = 1;
    quantized.lines[8] = 1;
    const decoded = try requantizeChannel(
        header,
        .{
            .global_gain = 210,
            .window_switching = true,
            .block_type = 2,
            .subblock_gain = .{ 0, 1, 2 },
        },
        .{ .value_count = 39 },
        quantized,
    );
    try std.testing.expectEqual(@as(f32, 1), decoded.lines[0]);
    try std.testing.expectEqual(@as(f32, 0.25), decoded.lines[1]);
    try std.testing.expectEqual(@as(f32, 0.0625), decoded.lines[2]);
    try std.testing.expectEqual(@as(f32, -1), decoded.lines[3]);

    var invalid = quantized;
    invalid.lines[0] = 8207;
    try std.testing.expectError(
        error.InvalidMp3QuantizedValue,
        requantizeChannel(
            header,
            .{
                .global_gain = 210,
                .window_switching = true,
                .block_type = 2,
            },
            .{ .value_count = 39 },
            invalid,
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3ScaleFactors,
        requantizeChannel(
            header,
            .{},
            .{ .value_count = 20 },
            quantized,
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3ScaleFactors,
        requantizeChannel(
            header,
            .{},
            .{ .value_count = 40 },
            quantized,
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3BlockType,
        requantizeChannel(
            header,
            .{ .block_type = 2 },
            .{ .value_count = 39 },
            quantized,
        ),
    );
    var terminal_factor = ScaleFactorChannel{
        .value_count = 39,
    };
    terminal_factor.values[36] = 1;
    try std.testing.expectError(
        error.InvalidMp3ScaleFactors,
        requantizeChannel(
            header,
            .{
                .window_switching = true,
                .block_type = 2,
            },
            terminal_factor,
            quantized,
        ),
    );
}

test "requantizes mixed blocks at version-specific boundaries" {
    const headers = [_]Header{
        try Header.parse(
            &testHeader(3, true, 9, 0, false, .mono),
        ),
        try Header.parse(
            &testHeader(0, true, 9, 2, false, .mono),
        ),
    };
    for (headers) |header| {
        const bands = try scaleFactorBands(header);
        const boundary: usize = 3 * bands.short_starts[3];
        const width: usize =
            bands.short_starts[4] - bands.short_starts[3];
        var quantized = QuantizedSpectrum{
            .decoded_lines = @intCast(boundary + width + 1),
        };
        quantized.lines[boundary - 1] = -1;
        quantized.lines[boundary + width] = 1;
        const decoded = try requantizeChannel(
            header,
            .{
                .global_gain = 210,
                .window_switching = true,
                .block_type = 2,
                .mixed_block = true,
            },
            .{
                .value_count = if (header.version == .mpeg1) 38 else 33,
            },
            quantized,
        );
        try std.testing.expectEqual(
            @as(f32, -1),
            decoded.lines[boundary - 1],
        );
        try std.testing.expectEqual(
            @as(f32, 1),
            decoded.lines[boundary + 1],
        );
    }

    try std.testing.expectError(
        error.InvalidMp3QuantizedSpectrum,
        requantizeChannel(
            headers[0],
            .{},
            .{ .value_count = 22 },
            .{ .decoded_lines = 577 },
        ),
    );
    var hidden_line = QuantizedSpectrum{};
    hidden_line.lines[0] = 1;
    try std.testing.expectError(
        error.InvalidMp3QuantizedSpectrum,
        requantizeChannel(
            headers[0],
            .{},
            .{ .value_count = 22 },
            hidden_line,
        ),
    );
}

test "reconstructs Layer III mid-side stereo transactionally" {
    var header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .stereo),
    );
    const descriptions: [2]GranuleChannel = @splat(.{});
    const factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 22 });
    var spectra: [2]RequantizedSpectrum = @splat(.{});
    spectra[0].lines[0] = 2;
    spectra[1].lines[0] = 1;
    const independent = try processStereo(
        header,
        descriptions,
        factors,
        spectra,
    );
    try std.testing.expectEqual(
        spectra,
        independent.channels,
    );
    header.channel_mode = .joint_stereo;
    header.mode_extension = 2;
    const decoded = try processStereo(
        header,
        descriptions,
        factors,
        spectra,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 3.0 / @sqrt(2.0)),
        decoded.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        decoded.channels[1].lines[0],
        1e-6,
    );

    var mismatched = descriptions;
    mismatched[1].window_switching = true;
    mismatched[1].block_type = 1;
    try std.testing.expectError(
        error.InvalidMp3StereoBlocks,
        processStereo(header, mismatched, factors, spectra),
    );
    var malformed = spectra;
    malformed[0].lines[0] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        processStereo(header, descriptions, factors, malformed),
    );
    header.channel_mode = .mono;
    try std.testing.expectError(
        error.InvalidMp3StereoChannels,
        processStereo(header, descriptions, factors, spectra),
    );
}

test "reconstructs MPEG-1 intensity and fallback stereo bands" {
    var header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .stereo),
    );
    header.channel_mode = .joint_stereo;
    header.mode_extension = 3;
    const descriptions: [2]GranuleChannel = @splat(.{});
    var factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 22 });
    factors[1].values[1] = 0;
    factors[1].values[2] = 3;
    factors[1].values[3] = 6;
    factors[1].values[4] = 7;
    const bands = try scaleFactorBands(header);
    var spectra: [2]RequantizedSpectrum = @splat(.{});
    spectra[1].lines[0] = 1;
    for (1..5) |band|
        spectra[0].lines[bands.long_starts[band]] = 1;

    const decoded = try processStereo(
        header,
        descriptions,
        factors,
        spectra,
    );
    const position_zero = bands.long_starts[1];
    try std.testing.expectEqual(
        @as(f32, 1),
        decoded.channels[0].lines[position_zero],
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        decoded.channels[1].lines[position_zero],
    );
    const centered = bands.long_starts[2];
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        decoded.channels[0].lines[centered],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        decoded.channels[1].lines[centered],
        1e-6,
    );
    const right = bands.long_starts[3];
    try std.testing.expectEqual(
        @as(f32, 0),
        decoded.channels[0].lines[right],
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        decoded.channels[1].lines[right],
    );
    const fallback = bands.long_starts[4];
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        decoded.channels[0].lines[fallback],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        decoded.channels[1].lines[fallback],
        1e-6,
    );
}

test "reconstructs LSF and per-window short intensity stereo" {
    var lsf_header = try Header.parse(
        &testHeader(2, true, 9, 0, false, .stereo),
    );
    lsf_header.channel_mode = .joint_stereo;
    lsf_header.mode_extension = 1;
    const long_descriptions: [2]GranuleChannel = @splat(.{});
    var long_factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 21 });
    long_factors[1].values[1] = 1;
    long_factors[1].values[2] = 2;
    const lsf_bands = try scaleFactorBands(lsf_header);
    var long_spectra: [2]RequantizedSpectrum = @splat(.{});
    long_spectra[0].lines[lsf_bands.long_starts[0]] = 1;
    long_spectra[0].lines[lsf_bands.long_starts[1]] = 1;
    long_spectra[0].lines[lsf_bands.long_starts[2]] = 1;
    const lsf = try processStereo(
        lsf_header,
        long_descriptions,
        long_factors,
        long_spectra,
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        lsf.channels[1].lines[lsf_bands.long_starts[0]],
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @exp2(-0.25)),
        lsf.channels[0].lines[lsf_bands.long_starts[1]],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @exp2(-0.25)),
        lsf.channels[1].lines[lsf_bands.long_starts[2]],
        1e-6,
    );
    var fine_scale = long_factors;
    fine_scale[1].intensity_scale = true;
    const fine = try processStereo(
        lsf_header,
        long_descriptions,
        fine_scale,
        long_spectra,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @exp2(-0.5)),
        fine.channels[0].lines[lsf_bands.long_starts[1]],
        1e-6,
    );
    var fallback_factors = long_factors;
    fallback_factors[1].intensity_max[3] = true;
    var fallback_spectra = long_spectra;
    fallback_spectra[0].lines[lsf_bands.long_starts[3]] = 2;
    fallback_spectra[1].lines[lsf_bands.long_starts[3]] = 1;
    lsf_header.mode_extension = 3;
    const fallback = try processStereo(
        lsf_header,
        long_descriptions,
        fallback_factors,
        fallback_spectra,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 3.0 / @sqrt(2.0)),
        fallback.channels[0].lines[lsf_bands.long_starts[3]],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        fallback.channels[1].lines[lsf_bands.long_starts[3]],
        1e-6,
    );
    lsf_header.mode_extension = 1;
    var invalid_position = long_factors;
    invalid_position[1].values[3] = 16;
    var invalid_spectra = long_spectra;
    invalid_spectra[0].lines[lsf_bands.long_starts[3]] = 1;
    try std.testing.expectError(
        error.InvalidMp3IntensityPosition,
        processStereo(
            lsf_header,
            long_descriptions,
            invalid_position,
            invalid_spectra,
        ),
    );

    var short_header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .stereo),
    );
    short_header.channel_mode = .joint_stereo;
    short_header.mode_extension = 3;
    const short_descriptions: [2]GranuleChannel = @splat(.{
        .window_switching = true,
        .block_type = 2,
    });
    const short_factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 39 });
    const short_bands = try scaleFactorBands(short_header);
    var short_spectra: [2]RequantizedSpectrum = @splat(.{});
    short_spectra[0].lines[0] = 1;
    short_spectra[1].lines[0] = 1;
    short_spectra[0].lines[1] = 1;
    const next_band_window_zero =
        3 * @as(usize, short_bands.short_starts[1]);
    short_spectra[0].lines[next_band_window_zero] = 1;
    const short = try processStereo(
        short_header,
        short_descriptions,
        short_factors,
        short_spectra,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @sqrt(2.0)),
        short.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        short.channels[0].lines[1],
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        short.channels[1].lines[1],
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        short.channels[0].lines[next_band_window_zero],
    );

    const mixed_descriptions: [2]GranuleChannel = @splat(.{
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    });
    const mixed_factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 38 });
    const mixed_boundary: usize = 3 * short_bands.short_starts[3];
    var mixed_spectra: [2]RequantizedSpectrum = @splat(.{});
    mixed_spectra[0].lines[0] = 1;
    mixed_spectra[0].lines[mixed_boundary] = 1;
    const mixed = try processStereo(
        short_header,
        mixed_descriptions,
        mixed_factors,
        mixed_spectra,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        mixed.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        mixed.channels[1].lines[0],
        1e-6,
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        mixed.channels[0].lines[mixed_boundary],
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        mixed.channels[1].lines[mixed_boundary],
    );

    var low_rate_header = try Header.parse(
        &testHeader(0, true, 9, 2, false, .stereo),
    );
    low_rate_header.channel_mode = .joint_stereo;
    low_rate_header.mode_extension = 1;
    const low_rate_bands = try scaleFactorBands(low_rate_header);
    const low_rate_boundary: usize =
        3 * low_rate_bands.short_starts[3];
    const low_rate_factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 33 });
    var low_rate_spectra: [2]RequantizedSpectrum = @splat(.{});
    low_rate_spectra[0].lines[low_rate_boundary - 1] = 1;
    low_rate_spectra[0].lines[low_rate_boundary] = 1;
    const low_rate = try processStereo(
        low_rate_header,
        mixed_descriptions,
        low_rate_factors,
        low_rate_spectra,
    );
    try std.testing.expectEqual(@as(usize, 72), low_rate_boundary);
    try std.testing.expectEqual(
        @as(f32, 1),
        low_rate.channels[0].lines[low_rate_boundary - 1],
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        low_rate.channels[1].lines[low_rate_boundary - 1],
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        low_rate.channels[0].lines[low_rate_boundary],
    );
    try std.testing.expectEqual(
        @as(f32, 1),
        low_rate.channels[1].lines[low_rate_boundary],
    );
}

test "reduces Layer III aliases across long and mixed boundaries" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var long_spectrum = RequantizedSpectrum{};
    for (1..32) |subband| {
        const boundary = 18 * subband;
        long_spectrum.lines[boundary - 1] =
            @floatFromInt(subband);
        long_spectrum.lines[boundary] =
            @floatFromInt(subband + 1);
    }
    for (0..8) |index| {
        long_spectrum.lines[17 - index] =
            @floatFromInt(index + 1);
        long_spectrum.lines[18 + index] =
            @floatFromInt(index + 2);
    }
    const reduced = try reduceAliases(
        header,
        .{},
        long_spectrum,
    );
    for (1..32) |subband| {
        const boundary = 18 * subband;
        const upper: f32 = @floatFromInt(subband);
        const lower: f32 = @floatFromInt(subband + 1);
        try std.testing.expectApproxEqAbs(
            upper * alias_cs[0] - lower * alias_ca[0],
            reduced.lines[boundary - 1],
            1e-6,
        );
        try std.testing.expectApproxEqAbs(
            lower * alias_cs[0] + upper * alias_ca[0],
            reduced.lines[boundary],
            1e-6,
        );
    }
    const alias_c = [_]f32{
        -0.6,
        -0.535,
        -0.33,
        -0.185,
        -0.095,
        -0.041,
        -0.0142,
        -0.0037,
    };
    for (alias_c, alias_cs, alias_ca, 0..) |c, cs, ca, index| {
        const wide_c: f64 = c;
        const expected_cs: f32 =
            @floatCast(1.0 / @sqrt(1.0 + wide_c * wide_c));
        try std.testing.expectApproxEqAbs(expected_cs, cs, 1e-7);
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(wide_c * expected_cs)),
            ca,
            1e-7,
        );
        const upper: f32 = @floatFromInt(index + 1);
        const lower: f32 = @floatFromInt(index + 2);
        try std.testing.expectApproxEqAbs(
            upper * cs - lower * ca,
            reduced.lines[17 - index],
            1e-6,
        );
        try std.testing.expectApproxEqAbs(
            lower * cs + upper * ca,
            reduced.lines[18 + index],
            1e-6,
        );
    }

    const pure_short = try reduceAliases(
        header,
        .{
            .window_switching = true,
            .block_type = 2,
        },
        long_spectrum,
    );
    try std.testing.expectEqual(long_spectrum, pure_short);

    var mixed_spectrum = RequantizedSpectrum{};
    mixed_spectrum.lines[17] = 1;
    mixed_spectrum.lines[18] = 2;
    mixed_spectrum.lines[35] = 3;
    mixed_spectrum.lines[36] = 4;
    const mixed = try reduceAliases(
        header,
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
        mixed_spectrum,
    );
    try std.testing.expect(mixed.lines[17] != 1);
    try std.testing.expect(mixed.lines[18] != 2);
    try std.testing.expectEqual(@as(f32, 3), mixed.lines[35]);
    try std.testing.expectEqual(@as(f32, 4), mixed.lines[36]);

    const low_rate_header = try Header.parse(
        &testHeader(0, true, 9, 2, false, .mono),
    );
    var low_rate_spectrum = RequantizedSpectrum{};
    for (1..5) |subband| {
        const boundary = 18 * subband;
        low_rate_spectrum.lines[boundary - 1] = 1;
        low_rate_spectrum.lines[boundary] = 2;
    }
    const low_rate = try reduceAliases(
        low_rate_header,
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
        low_rate_spectrum,
    );
    for (1..4) |subband| {
        const boundary = 18 * subband;
        try std.testing.expect(low_rate.lines[boundary - 1] != 1);
        try std.testing.expect(low_rate.lines[boundary] != 2);
    }
    try std.testing.expectEqual(
        @as(f32, 1),
        low_rate.lines[4 * 18 - 1],
    );
    try std.testing.expectEqual(
        @as(f32, 2),
        low_rate.lines[4 * 18],
    );

    const mixed_start = try reduceAliases(
        header,
        .{
            .window_switching = true,
            .block_type = 1,
            .mixed_block = true,
        },
        long_spectrum,
    );
    try std.testing.expect(mixed_start.lines[31 * 18 - 1] !=
        long_spectrum.lines[31 * 18 - 1]);

    var malformed = long_spectrum;
    malformed.lines[0] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        reduceAliases(header, .{}, malformed),
    );
    try std.testing.expectError(
        error.InvalidMp3BlockType,
        reduceAliases(
            header,
            .{ .block_type = 2 },
            long_spectrum,
        ),
    );
}

test "synthesizes long MP3 hybrid blocks with overlap and inversion" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var spectrum = RequantizedSpectrum{};
    spectrum.lines[0] = 1;
    spectrum.lines[18] = 1;
    var synthesis = HybridSynthesis{};
    const first = try synthesis.process(header, .{}, spectrum);
    for (0..36) |time| {
        const position: f64 = @floatFromInt(time);
        const transformed = @cos(
            std.math.pi / 18.0 *
                (position + 9.5) * 0.5,
        ) * @sin(
            std.math.pi / 36.0 * (position + 0.5),
        );
        if (time < 18) {
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(transformed)),
                first.time_slots[time][0],
                1e-6,
            );
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(
                    if (time & 1 == 0)
                        transformed
                    else
                        -transformed,
                )),
                first.time_slots[time][1],
                1e-6,
            );
        } else {
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(transformed)),
                synthesis.overlap[0][time - 18],
                1e-6,
            );
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(transformed)),
                synthesis.overlap[1][time - 18],
                1e-6,
            );
        }
    }

    const second = try synthesis.process(
        header,
        .{},
        .{},
    );
    for (0..18) |time| {
        const position: f64 = @floatFromInt(time + 18);
        const tail = @cos(
            std.math.pi / 18.0 *
                (position + 9.5) * 0.5,
        ) * @sin(
            std.math.pi / 36.0 * (position + 0.5),
        );
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(tail)),
            second.time_slots[time][0],
            1e-6,
        );
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(
                if (time & 1 == 0) tail else -tail,
            )),
            second.time_slots[time][1],
            1e-6,
        );
    }
    try std.testing.expectEqual(
        @as([32][18]f32, @splat(@splat(0))),
        synthesis.overlap,
    );

    _ = try synthesis.process(header, .{}, spectrum);
    synthesis.reset();
    try std.testing.expectEqual(HybridSynthesis{}, synthesis);
}

test "synthesizes short transition and mixed MP3 hybrid blocks" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const short_description = GranuleChannel{
        .window_switching = true,
        .block_type = 2,
    };
    var short_spectrum = RequantizedSpectrum{};
    short_spectrum.lines[0] = 1;
    short_spectrum.lines[1] = 2;
    short_spectrum.lines[2] = 3;
    var short_synthesis = HybridSynthesis{};
    const short = try short_synthesis.process(
        header,
        short_description,
        short_spectrum,
    );
    var expected_short: [36]f64 = @splat(0);
    for (0..3) |window| {
        const magnitude: f64 = @floatFromInt(window + 1);
        for (0..12) |time| {
            const position: f64 = @floatFromInt(time);
            expected_short[6 + window * 6 + time] +=
                magnitude *
                @cos(
                    std.math.pi / 6.0 *
                        (position + 3.5) * 0.5,
                ) *
                @sin(std.math.pi / 12.0 * (position + 0.5));
        }
    }
    for (0..18) |time| {
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(expected_short[time])),
            short.time_slots[time][0],
            1e-6,
        );
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(expected_short[time + 18])),
            short_synthesis.overlap[0][time],
            1e-6,
        );
    }
    for (0..6) |time| {
        try std.testing.expectEqual(
            @as(f32, 0),
            short.time_slots[time][0],
        );
        try std.testing.expectEqual(
            @as(f32, 0),
            short_synthesis.overlap[0][time + 12],
        );
    }

    var transition_spectrum = RequantizedSpectrum{};
    transition_spectrum.lines[0] = 1;
    var start_synthesis = HybridSynthesis{};
    _ = try start_synthesis.process(
        header,
        .{
            .window_switching = true,
            .block_type = 1,
        },
        transition_spectrum,
    );
    for (12..18) |time|
        try std.testing.expectEqual(
            @as(f32, 0),
            start_synthesis.overlap[0][time],
        );
    var stop_synthesis = HybridSynthesis{};
    const stop = try stop_synthesis.process(
        header,
        .{
            .window_switching = true,
            .block_type = 3,
        },
        transition_spectrum,
    );
    for (0..6) |time|
        try std.testing.expectEqual(
            @as(f32, 0),
            stop.time_slots[time][0],
        );

    const mixed_description = GranuleChannel{
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    };
    var mixed_spectrum = RequantizedSpectrum{};
    mixed_spectrum.lines[0] = 1;
    mixed_spectrum.lines[18] = 1;
    mixed_spectrum.lines[36] = 1;
    var mixed_synthesis = HybridSynthesis{};
    const mixed = try mixed_synthesis.process(
        header,
        mixed_description,
        mixed_spectrum,
    );
    try std.testing.expect(mixed.time_slots[0][0] != 0);
    try std.testing.expect(mixed.time_slots[0][1] != 0);
    for (0..6) |time|
        try std.testing.expectEqual(
            @as(f32, 0),
            mixed.time_slots[time][2],
        );

    const low_rate_header = try Header.parse(
        &testHeader(0, true, 9, 2, false, .mono),
    );
    var low_rate_spectrum = RequantizedSpectrum{};
    low_rate_spectrum.lines[3 * 18] = 1;
    low_rate_spectrum.lines[4 * 18] = 1;
    var low_rate_synthesis = HybridSynthesis{};
    const low_rate = try low_rate_synthesis.process(
        low_rate_header,
        mixed_description,
        low_rate_spectrum,
    );
    try std.testing.expect(low_rate.time_slots[0][3] != 0);
    for (0..6) |time|
        try std.testing.expectEqual(
            @as(f32, 0),
            low_rate.time_slots[time][4],
        );

    const preserved = low_rate_synthesis;
    var malformed = RequantizedSpectrum{};
    malformed.lines[0] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        low_rate_synthesis.process(
            low_rate_header,
            mixed_description,
            malformed,
        ),
    );
    try std.testing.expectEqual(preserved, low_rate_synthesis);

    var overflowing = RequantizedSpectrum{};
    for (0..18) |frequency| {
        overflowing.lines[frequency] =
            if (long_imdct[8][frequency] < 0)
                -std.math.floatMax(f32)
            else
                std.math.floatMax(f32);
    }
    const before_overflow = low_rate_synthesis;
    try std.testing.expectError(
        error.InvalidMp3HybridSample,
        low_rate_synthesis.process(
            low_rate_header,
            .{},
            overflowing,
        ),
    );
    try std.testing.expectEqual(before_overflow, low_rate_synthesis);

    low_rate_synthesis.overlap[0][0] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3HybridState,
        low_rate_synthesis.process(
            low_rate_header,
            .{},
            .{},
        ),
    );
    low_rate_synthesis.reset();
    try std.testing.expectError(
        error.InvalidMp3BlockType,
        low_rate_synthesis.process(
            low_rate_header,
            .{ .block_type = 2 },
            .{},
        ),
    );
}

test "preserves the quantized MP3 synthesis window" {
    try std.testing.expectEqual(
        @as(usize, 512),
        synthesis_window_quantized.len,
    );
    try std.testing.expectEqual(
        @as(i32, 0),
        synthesis_window_quantized[0],
    );
    try std.testing.expectEqual(
        @as(i32, 213),
        synthesis_window_quantized[64],
    );
    try std.testing.expectEqual(
        @as(i32, 2037),
        synthesis_window_quantized[128],
    );
    try std.testing.expectEqual(
        @as(i32, 75_038),
        synthesis_window_quantized[256],
    );
    try std.testing.expectEqual(
        @as(i32, 1),
        synthesis_window_quantized[511],
    );
}

test "synthesizes MP3 polyphase PCM against a shift register" {
    var hybrid = HybridSamples{};
    for (&hybrid.time_slots, 0..) |*time_slot, time| {
        for (time_slot, 0..) |*sample, band| {
            const pattern: i16 =
                @intCast((time * 17 + band * 13) % 29);
            sample.* =
                @as(f32, @floatFromInt(pattern - 14)) / 17.0;
        }
    }

    var synthesis = PolyphaseSynthesis{};
    var reference_history: [1024]f64 = @splat(0);
    const first = try synthesis.process(hybrid);
    for (&hybrid.time_slots, 0..) |*time_slot, time| {
        const reference = referencePolyphaseTimeSlot(
            &reference_history,
            time_slot,
        );
        for (reference, 0..) |expected, sample| {
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(expected)),
                first.samples[time * 32 + sample],
                1e-5,
            );
        }
    }

    const second = try synthesis.process(.{});
    const silence = [_]f32{0} ** 32;
    for (0..18) |time| {
        const reference = referencePolyphaseTimeSlot(
            &reference_history,
            &silence,
        );
        for (reference, 0..) |expected, sample| {
            try std.testing.expectApproxEqAbs(
                @as(f32, @floatCast(expected)),
                second.samples[time * 32 + sample],
                1e-5,
            );
        }
    }

    synthesis.reset();
    try std.testing.expectEqual(
        PolyphaseSynthesis{},
        synthesis,
    );
    const zero = try synthesis.process(.{});
    try std.testing.expectEqual(PcmGranule{}, zero);
}

test "rejects invalid MP3 polyphase input and state transactionally" {
    var synthesis = PolyphaseSynthesis{};
    var malformed = HybridSamples{};
    malformed.time_slots[0][0] = std.math.nan(f32);
    const initial = synthesis;
    try std.testing.expectError(
        error.InvalidMp3HybridSamples,
        synthesis.process(malformed),
    );
    try std.testing.expectEqual(initial, synthesis);

    synthesis.head_block = 16;
    const bad_head = synthesis;
    try std.testing.expectError(
        error.InvalidMp3PolyphaseState,
        synthesis.process(.{}),
    );
    try std.testing.expectEqual(bad_head, synthesis);

    synthesis = .{};
    synthesis.history[17] = std.math.inf(f64);
    const bad_history = synthesis;
    try std.testing.expectError(
        error.InvalidMp3PolyphaseState,
        synthesis.process(.{}),
    );
    try std.testing.expectEqual(bad_history, synthesis);

    synthesis = .{};
    var overflowing = HybridSamples{};
    for (&overflowing.time_slots[0], 0..) |*sample, band| {
        sample.* = if (synthesis_matrix[0][band] < 0)
            -std.math.floatMax(f32)
        else
            std.math.floatMax(f32);
    }
    const before_overflow = synthesis;
    try std.testing.expectError(
        error.InvalidMp3PolyphaseSample,
        synthesis.process(overflowing),
    );
    try std.testing.expectEqual(before_overflow, synthesis);
}

test "composes silent MP3 frames through the complete decoder" {
    const header_bytes =
        testHeader(3, true, 9, 0, false, .mono);
    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(
        &encoded,
        0,
        header_bytes,
    );
    const frame = try Frame.parse(encoded[0..frame_end], 0);

    var decoder = FrameDecoder{};
    const decoded = try decoder.decode(frame);
    try std.testing.expectEqual(@as(u2, 1), decoded.channel_count);
    try std.testing.expectEqual(@as(u16, 1152), decoded.sample_count);
    for (decoded.channels[0]) |sample|
        try std.testing.expectEqual(@as(f32, 0), sample);
    for (decoded.channels[1]) |sample|
        try std.testing.expectEqual(@as(f32, 0), sample);
    try std.testing.expectEqual(
        @as(?DecoderFormat, .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_count = 1,
        }),
        decoder.format,
    );

    const file_frame = FileFrame{
        .byte_offset = 0,
        .bytes = frame.bytes,
        .header = frame.header,
        .xing = frame.xing,
        .vbri = frame.vbri,
    };
    var file_decoder = FrameDecoder{};
    try std.testing.expectEqual(
        decoded,
        try file_decoder.decode(file_frame),
    );

    decoder.reset();
    try std.testing.expectEqual(FrameDecoder{}, decoder);
}

test "decodes MP3 main data across frame reservoir boundaries" {
    const header_bytes =
        testHeader(3, true, 9, 0, false, .mono);
    var first_bytes: [500]u8 = undefined;
    const first_end = try appendFrame(
        &first_bytes,
        0,
        header_bytes,
    );
    first_bytes[first_end - 1] = 0x08;
    const first = try Frame.parse(
        first_bytes[0..first_end],
        0,
    );

    var second_bytes: [500]u8 = undefined;
    const second_end = try appendFrame(
        &second_bytes,
        0,
        header_bytes,
    );
    const second_side = second_bytes[4..21];
    setTestBits(second_side, 0, 9, 1);
    setMpeg1MonoLongChannel(
        second_side,
        0,
        5,
        1,
        210,
        1,
    );
    setMpeg1MonoLongChannel(
        second_side,
        1,
        0,
        0,
        210,
        0,
    );
    const second = try Frame.parse(
        second_bytes[0..second_end],
        0,
    );

    var decoder = FrameDecoder{};
    const silent = try decoder.decode(first);
    try std.testing.expectEqual(PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    }, silent);
    const decoded = try decoder.decode(second);
    var nonzero = false;
    for (decoded.channels[0]) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        nonzero = nonzero or sample != 0;
    }
    try std.testing.expect(nonzero);
}

test "rejects MP3 frame decoder discontinuities transactionally" {
    const header_bytes =
        testHeader(3, true, 9, 0, false, .mono);
    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(
        &encoded,
        0,
        header_bytes,
    );
    const frame = try Frame.parse(encoded[0..frame_end], 0);
    var decoder = FrameDecoder{};
    _ = try decoder.decode(frame);

    var changed_bytes: [300]u8 = undefined;
    const changed_end = try appendFrame(
        &changed_bytes,
        0,
        testHeader(2, true, 8, 0, false, .mono),
    );
    const changed = try Frame.parse(
        changed_bytes[0..changed_end],
        0,
    );
    const before_change = decoder;
    try std.testing.expectError(
        error.Mp3DecoderFormatChanged,
        decoder.decode(changed),
    );
    try std.testing.expectEqual(before_change, decoder);

    var missing_bytes = encoded;
    setTestBits(missing_bytes[4..21], 0, 9, 1);
    const missing = try Frame.parse(
        missing_bytes[0..frame_end],
        0,
    );
    var fresh = FrameDecoder{};
    const fresh_before = fresh;
    try std.testing.expectError(
        error.Mp3MainDataHistoryUnavailable,
        fresh.decode(missing),
    );
    try std.testing.expectEqual(fresh_before, fresh);

    var protected_bytes: [500]u8 = undefined;
    const protected_end = try appendFrame(
        &protected_bytes,
        0,
        testHeader(3, false, 9, 0, false, .mono),
    );
    const protected = try Frame.parse(
        protected_bytes[0..protected_end],
        0,
    );
    try std.testing.expectError(
        error.InvalidMp3FrameCrc,
        fresh.decode(protected),
    );
    try std.testing.expectEqual(fresh_before, fresh);

    fresh.reservoir.length = 512;
    const malformed = fresh;
    try std.testing.expectError(
        error.InvalidMp3ReservoirState,
        fresh.decode(frame),
    );
    try std.testing.expectEqual(malformed, fresh);
}

test "matches independent Layer III conformance PCM" {
    const encoded_base64 = std.mem.trim(
        u8,
        @embedFile(
            "test-fixtures/mp3/layer3-conformance.bit.b64",
        ),
        " \r\n\t",
    );
    const reference_base64 = std.mem.trim(
        u8,
        @embedFile(
            "test-fixtures/mp3/layer3-conformance.pcm.b64",
        ),
        " \r\n\t",
    );
    var encoded: [9600]u8 = undefined;
    var reference: [46_080]u8 = undefined;
    try std.base64.standard.Decoder.decode(
        &encoded,
        encoded_base64,
    );
    try std.base64.standard.Decoder.decode(
        &reference,
        reference_base64,
    );

    var stream = try Stream.init(&encoded);
    var decoder = FrameDecoder{};
    var frame_count: usize = 0;
    var sample_offset: usize = 0;
    var squared_error: f64 = 0;
    var maximum_error: f64 = 0;
    while (try stream.next()) |frame| {
        const decoded = try decoder.decode(frame);
        try std.testing.expectEqual(
            @as(u2, 2),
            decoded.channel_count,
        );
        for (0..decoded.sample_count) |sample| {
            for (0..decoded.channel_count) |channel| {
                const reference_index =
                    (sample_offset + sample) * 2 + channel;
                const reference_sample: f64 = @floatFromInt(
                    readTestI16(
                        reference[reference_index * 2 ..][0..2],
                    ),
                );
                const rendered =
                    @as(f64, decoded.channels[channel][sample]) *
                    32_768.0;
                const difference = rendered - reference_sample;
                squared_error += difference * difference;
                maximum_error =
                    @max(maximum_error, @abs(difference));
            }
        }
        sample_offset += decoded.sample_count;
        frame_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 10), frame_count);
    try std.testing.expectEqual(
        reference.len / 4,
        sample_offset,
    );
    const sample_total: f64 =
        @floatFromInt(reference.len / 2);
    try std.testing.expect(
        @sqrt(squared_error / sample_total) < 0.5,
    );
    try std.testing.expect(maximum_error < 2.0);
}

test "trims MP3 decoder frames with gapless metadata" {
    const summary = Summary{
        .audio_offset = 0,
        .audio_bytes = 3 * 417,
        .frame_count = 3,
        .sample_count = 3 * 1152,
        .sample_rate = 44_100,
        .channels = 1,
        .first_xing = .{
            .kind = .variable,
            .frame_count = 3,
            .stream_bytes = null,
            .toc = null,
            .quality = null,
            .encoder = null,
            .encoder_delay = 100,
            .encoder_padding = 200,
        },
        .first_vbri = null,
    };
    const plan = try GaplessPlan.fromSummary(summary);
    try std.testing.expectEqual(@as(u64, 3456), plan.encoded_samples);
    try std.testing.expectEqual(@as(u64, 3156), plan.audible_samples);

    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(
        &encoded,
        0,
        testHeader(3, true, 9, 0, false, .mono),
    );
    const frame = try Frame.parse(encoded[0..frame_end], 0);
    var decoder = try StreamDecoder.init(summary);
    try std.testing.expectError(
        error.Mp3GaplessStreamIncomplete,
        decoder.finish(),
    );
    const first = try decoder.decode(frame);
    try std.testing.expectEqual(
        PcmRange{ .start = 100, .length = 1052 },
        first.audible,
    );
    const second = try decoder.decode(frame);
    try std.testing.expectEqual(
        PcmRange{ .start = 0, .length = 1152 },
        second.audible,
    );
    const third = try decoder.decode(frame);
    try std.testing.expectEqual(
        PcmRange{ .start = 0, .length = 952 },
        third.audible,
    );
    try decoder.finish();

    const completed = decoder;
    try std.testing.expectError(
        error.InvalidMp3GaplessPlan,
        decoder.decode(frame),
    );
    try std.testing.expectEqual(completed, decoder);

    decoder.reset();
    try std.testing.expectEqual(@as(u64, 0), decoder.sample_offset);
    try std.testing.expectEqual(FrameDecoder{}, decoder.decoder);
    try std.testing.expectEqual(plan, decoder.plan);
}

test "rejects invalid MP3 gapless metadata and plans" {
    var summary = Summary{
        .audio_offset = 0,
        .audio_bytes = 417,
        .frame_count = 1,
        .sample_count = 1152,
        .sample_rate = 44_100,
        .channels = 1,
        .first_xing = .{
            .kind = .variable,
            .frame_count = 1,
            .stream_bytes = null,
            .toc = null,
            .quality = null,
            .encoder = null,
            .encoder_delay = 100,
            .encoder_padding = null,
        },
        .first_vbri = null,
    };
    try std.testing.expectError(
        error.InvalidMp3GaplessMetadata,
        GaplessPlan.fromSummary(summary),
    );
    var oversized = summary.first_xing orelse
        return error.TestXingMissing;
    oversized.encoder_padding = 1100;
    summary.first_xing = oversized;
    try std.testing.expectError(
        error.InvalidMp3GaplessMetadata,
        GaplessPlan.fromSummary(summary),
    );

    const leading = GaplessPlan{
        .encoded_samples = 100,
        .leading_samples = 100,
        .trailing_samples = 0,
        .audible_samples = 0,
    };
    try std.testing.expectEqual(
        PcmRange{ .start = 100, .length = 0 },
        try leading.frameRange(0, 100),
    );
    const trailing = GaplessPlan{
        .encoded_samples = 100,
        .leading_samples = 0,
        .trailing_samples = 100,
        .audible_samples = 0,
    };
    try std.testing.expectEqual(
        PcmRange{ .start = 0, .length = 0 },
        try trailing.frameRange(0, 100),
    );
    var malformed = trailing;
    malformed.audible_samples = 1;
    try std.testing.expectError(
        error.InvalidMp3GaplessPlan,
        malformed.frameRange(0, 100),
    );
    try std.testing.expectError(
        error.InvalidMp3GaplessPlan,
        (StreamDecoder{
            .plan = malformed,
            .sample_rate = 44_100,
            .channel_count = 1,
            .sample_offset = 100,
        }).finish(),
    );

    summary.first_xing = null;
    summary.sample_rate = 0;
    try std.testing.expectError(
        error.InvalidMp3Summary,
        StreamDecoder.init(summary),
    );
}

test "rejects inconsistent scale-factor bit ranges" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var side = SideInformation{
        .channel_count = 1,
        .granule_count = 2,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = 21,
    };
    side.granules[0].channels[0] = .{
        .part2_3_length = 20,
        .scalefac_compress = 5,
    };
    side.granules[1].channels[0].part2_3_length = 1;
    var encoded: [3]u8 = @splat(0);
    try std.testing.expectError(
        error.InvalidMp3Part23Length,
        decodeScaleFactors(
            header,
            side,
            .{ .bytes = &encoded, .bit_count = 21 },
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3MainDataLength,
        decodeScaleFactors(
            header,
            side,
            .{ .bytes = &encoded, .bit_count = 20 },
        ),
    );
    side.channel_count = 2;
    try std.testing.expectError(
        error.InvalidMp3SideInformation,
        decodeScaleFactors(
            header,
            side,
            .{ .bytes = &encoded, .bit_count = 21 },
        ),
    );
    side.channel_count = 1;
    try std.testing.expectError(
        error.InvalidMp3MainDataLength,
        decodeScaleFactors(
            header,
            side,
            .{ .bytes = encoded[0..2], .bit_count = 21 },
        ),
    );
}

test "rejects malformed and unsupported MPEG headers" {
    try std.testing.expectError(
        error.TruncatedMp3Header,
        Header.parse(&.{ 0xff, 0xfb, 0x90 }),
    );
    try std.testing.expectError(
        error.InvalidMp3Sync,
        Header.parse(&.{ 0, 0, 0, 0 }),
    );
    try std.testing.expectError(
        error.ReservedMp3Version,
        Header.parse(&testHeader(1, true, 9, 0, false, .stereo)),
    );
    var not_layer_three = testHeader(3, true, 9, 0, false, .stereo);
    not_layer_three[1] |= 0x04;
    try std.testing.expectError(
        error.NotMp3LayerThree,
        Header.parse(&not_layer_three),
    );
    const free = try Header.parse(
        &testHeader(3, true, 0, 0, false, .stereo),
    );
    try std.testing.expect(free.free_format);
    try std.testing.expectEqual(@as(u16, 0), free.bitrate_kbps);
    try std.testing.expectEqual(@as(usize, 0), free.frameBytes());
    try std.testing.expectError(
        error.InvalidMp3Bitrate,
        Header.parse(&testHeader(3, true, 15, 0, false, .stereo)),
    );
    try std.testing.expectError(
        error.InvalidMp3SampleRate,
        Header.parse(&testHeader(3, true, 9, 3, false, .stereo)),
    );
}

test "free-format MP3 infers padded frame sizes transactionally" {
    var encoded: [1700]u8 = @splat(0);
    const plain = testHeader(3, true, 0, 0, false, .stereo);
    const padded = testHeader(3, true, 0, 0, true, .stereo);
    var cursor = try appendFreeFormatFrame(
        &encoded,
        0,
        plain,
        500,
    );
    cursor = try appendFreeFormatFrame(
        &encoded,
        cursor,
        padded,
        500,
    );
    cursor = try appendFreeFormatFrame(
        &encoded,
        cursor,
        plain,
        500,
    );
    @memcpy(encoded[100..104], &plain);

    const first = try Frame.parse(encoded[0..cursor], 0);
    try std.testing.expect(first.header.free_format);
    try std.testing.expectEqual(@as(usize, 500), first.bytes.len);

    var stream = try Stream.init(encoded[0..cursor]);
    try std.testing.expectEqual(
        @as(usize, 500),
        (try stream.next()).?.bytes.len,
    );
    try std.testing.expectEqual(
        @as(usize, 501),
        (try stream.next()).?.bytes.len,
    );
    try std.testing.expectEqual(
        @as(usize, 500),
        (try stream.next()).?.bytes.len,
    );
    try std.testing.expect((try stream.next()) == null);
    try std.testing.expectEqual(@as(?usize, 500), stream.free_frame_base_bytes);

    var one_frame: [500]u8 = undefined;
    _ = try appendFreeFormatFrame(&one_frame, 0, plain, 500);
    try std.testing.expectError(
        error.CannotInferFreeFormatMp3FrameSize,
        Frame.parse(&one_frame, 0),
    );
}

test "file-backed free-format MP3 scans summarizes and seeks" {
    var encoded: [1600]u8 = @splat(0);
    const header = testHeader(3, true, 0, 0, false, .stereo);
    var cursor = try appendFreeFormatFrame(
        &encoded,
        0,
        header,
        500,
    );
    cursor = try appendFreeFormatFrame(
        &encoded,
        cursor,
        header,
        500,
    );
    cursor = try appendFreeFormatFrame(
        &encoded,
        cursor,
        header,
        500,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "free-format.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..cursor],
        0,
    );

    var reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(
        @as(?usize, 500),
        reader.free_frame_base_bytes,
    );
    var storage: [501]u8 = undefined;
    try std.testing.expectEqual(
        @as(usize, 500),
        (try reader.next(&storage)).?.bytes.len,
    );
    const summary = try FileReader.summarize(
        std.testing.io,
        file,
        &storage,
    );
    try std.testing.expectEqual(@as(u64, 3), summary.frame_count);

    var points: [3]SeekPoint = undefined;
    const index = try buildFileSeekIndex(
        std.testing.io,
        file,
        &storage,
        1,
        &points,
    );
    try reader.seek(index[2]);
    try std.testing.expectEqual(
        @as(u64, 1000),
        reader.offset,
    );
    try std.testing.expectEqual(
        @as(usize, 500),
        (try reader.next(&storage)).?.bytes.len,
    );
}

test "parses bounded Xing fields and LAME delay metadata" {
    var storage: [500]u8 = undefined;
    const header_bytes = testHeader(3, false, 9, 0, false, .stereo);
    const end = try appendFrame(&storage, 0, header_bytes);
    const offset = 4 + 32;
    @memcpy(storage[offset..][0..4], "Xing");
    storage[offset + 7] = 0xf;
    storage[offset + 8 ..][0..4].* = .{ 0, 0, 0, 10 };
    storage[offset + 12 ..][0..4].* = .{ 0, 0, 4, 0 };
    for (storage[offset + 16 ..][0..100], 0..) |*byte, index|
        byte.* = @intCast(index);
    storage[offset + 116 ..][0..4].* = .{ 0, 0, 0, 7 };
    @memcpy(storage[offset + 120 ..][0..9], "LAME3.100");
    storage[offset + 141 ..][0..3].* = .{ 0x24, 0x03, 0x21 };

    const frame = try Frame.parse(storage[0..end], 0);
    const xing = frame.xing.?;
    try std.testing.expectEqual(XingKind.variable, xing.kind);
    try std.testing.expectEqual(@as(?u32, 10), xing.frame_count);
    try std.testing.expectEqual(@as(?u32, 1024), xing.stream_bytes);
    try std.testing.expectEqual(@as(u8, 99), xing.toc.?[99]);
    try std.testing.expectEqual(@as(?u32, 7), xing.quality);
    try std.testing.expectEqual(@as(?u12, 0x240), xing.encoder_delay);
    try std.testing.expectEqual(@as(?u12, 0x321), xing.encoder_padding);

    storage[offset + 7] = 0x10;
    try std.testing.expectError(
        error.InvalidXingFlags,
        Frame.parse(storage[0..end], 0),
    );
    const short_end = try appendFrame(
        &storage,
        0,
        testHeader(3, true, 1, 0, false, .stereo),
    );
    @memcpy(storage[offset..][0..4], "Xing");
    storage[offset + 7] = 0x4;
    try std.testing.expectError(
        error.TruncatedXingHeader,
        Frame.parse(storage[0..short_end], 0),
    );
}

test "parses bounded VBRI header and table" {
    var storage: [500]u8 = undefined;
    const end = try appendFrame(
        &storage,
        0,
        testHeader(3, true, 9, 0, false, .stereo),
    );
    const offset = 36;
    @memcpy(storage[offset..][0..4], "VBRI");
    storage[offset + 4 ..][0..22].* = .{
        0, 1, 0, 2, 0, 3,
        0, 0, 4, 0, 0, 0,
        0, 9, 0, 2, 0, 1,
        0, 2, 0, 4,
    };
    storage[offset + 26 ..][0..4].* = .{ 0, 5, 0, 6 };
    const frame = try Frame.parse(storage[0..end], 0);
    const vbri = frame.vbri.?;
    try std.testing.expectEqual(@as(u16, 1), vbri.version);
    try std.testing.expectEqual(@as(u32, 1024), vbri.stream_bytes);
    try std.testing.expectEqual(@as(u32, 9), vbri.frame_count);
    try std.testing.expectEqualSlices(u8, &.{ 0, 5, 0, 6 }, vbri.toc);

    storage[offset + 23] = 5;
    try std.testing.expectError(
        error.InvalidVbriEntrySize,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 23] = 2;
    storage[offset + 18 ..][0..2].* = .{ 0xff, 0xff };
    try std.testing.expectError(
        error.TruncatedVbriToc,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 18 ..][0..2].* = .{ 0, 2 };
    storage[offset + 5] = 2;
    try std.testing.expectError(
        error.UnsupportedVbriVersion,
        Frame.parse(storage[0..end], 0),
    );
}

test "stream skips ID3 tags, summarizes frames, and builds seek index" {
    var storage: [1600]u8 = undefined;
    @memset(&storage, 0);
    @memcpy(storage[0..3], "ID3");
    storage[3] = 4;
    storage[5] = 0x10;
    storage[9] = 5;
    @memcpy(storage[15..18], "3DI");
    var cursor: usize = 25;
    const header = testHeader(3, true, 9, 0, false, .stereo);
    cursor = try appendFrame(&storage, cursor, header);
    cursor = try appendFrame(&storage, cursor, header);
    cursor = try appendFrame(&storage, cursor, header);
    @memcpy(storage[cursor..][0..3], "TAG");
    cursor += 128;

    const summary = try Stream.summarize(storage[0..cursor]);
    try std.testing.expectEqual(@as(usize, 25), summary.audio_offset);
    try std.testing.expectEqual(@as(u64, 3), summary.frame_count);
    try std.testing.expectEqual(@as(u64, 3456), summary.sample_count);
    try std.testing.expectEqual(@as(u32, 44_100), summary.sample_rate);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3456.0 / 44_100.0),
        summary.durationSeconds(),
        1e-12,
    );

    try std.testing.expectEqual(
        @as(usize, 2),
        try requiredSeekPoints(storage[0..cursor], 2),
    );
    var points: [2]SeekPoint = undefined;
    const index = try buildSeekIndex(storage[0..cursor], 2, &points);
    try std.testing.expectEqual(@as(usize, 25), index[0].byte_offset);
    try std.testing.expectEqual(@as(u64, 2), index[1].frame_index);
    try std.testing.expectEqual(@as(u64, 2304), index[1].sample_offset);
    try std.testing.expectEqual(
        index[0],
        try findSeekPoint(index, 2303),
    );
    try std.testing.expectEqual(
        index[1],
        try findSeekPoint(index, 2304),
    );
}

test "file reader scans summarizes indexes and seeks without whole-file storage" {
    var encoded: [1600]u8 = undefined;
    @memset(&encoded, 0);
    @memcpy(encoded[0..3], "ID3");
    encoded[3] = 3;
    encoded[9] = 4;
    var cursor: usize = 14;
    const header = testHeader(3, true, 9, 0, false, .stereo);
    cursor = try appendFrame(&encoded, cursor, header);
    cursor = try appendFrame(&encoded, cursor, header);
    cursor = try appendFrame(&encoded, cursor, header);
    @memcpy(encoded[cursor..][0..3], "TAG");
    cursor += 128;

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "framing.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);

    var reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(@as(u64, 14), reader.audio_start);
    const original_offset = reader.offset;
    var short_storage: [100]u8 = undefined;
    try std.testing.expectError(
        error.Mp3FrameBufferTooSmall,
        reader.next(&short_storage),
    );
    try std.testing.expectEqual(original_offset, reader.offset);

    var frame_storage: [500]u8 = undefined;
    const first = (try reader.next(&frame_storage)).?;
    try std.testing.expectEqual(@as(u64, 14), first.byte_offset);
    try std.testing.expectEqual(@as(usize, 417), first.bytes.len);

    const summary = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(@as(u64, 3), summary.frame_count);
    try std.testing.expectEqual(@as(u64, 3456), summary.sample_count);
    try std.testing.expectEqual(@as(u64, 14), summary.audio_offset);

    try std.testing.expectEqual(
        @as(usize, 2),
        try requiredFileSeekPoints(
            std.testing.io,
            file,
            &frame_storage,
            2,
        ),
    );
    var points: [2]SeekPoint = undefined;
    const index = try buildFileSeekIndex(
        std.testing.io,
        file,
        &frame_storage,
        2,
        &points,
    );
    try std.testing.expectEqual(@as(u64, 2), index[1].frame_index);
    try reader.seek(index[1]);
    try std.testing.expectEqual(@as(u64, 2), reader.frame_index);
    const sought = (try reader.next(&frame_storage)).?;
    try std.testing.expectEqual(
        @as(u64, @intCast(index[1].byte_offset)),
        sought.byte_offset,
    );

    const retained_offset = reader.offset;
    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = 1,
            .sample_offset = 1152,
            .byte_offset = 15,
        }),
    );
    try std.testing.expectEqual(retained_offset, reader.offset);
    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = index[1].frame_index,
            .sample_offset = index[1].sample_offset + 1,
            .byte_offset = index[1].byte_offset,
        }),
    );
    try std.testing.expectEqual(retained_offset, reader.offset);
}

test "MP3 readers reject counter rollover transactionally" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [500]u8 = undefined;
    const encoded_bytes = try appendFrame(&encoded, 0, header);

    var stream = try Stream.init(encoded[0..encoded_bytes]);
    stream.frame_index = std.math.maxInt(u64);
    try std.testing.expectError(
        error.Mp3FrameCountOverflow,
        stream.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), stream.cursor);
    try std.testing.expect(stream.first_header == null);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        stream.frame_index,
    );
    try std.testing.expectEqual(@as(u64, 0), stream.sample_offset);

    stream.frame_index = 0;
    stream.sample_offset = std.math.maxInt(u64);
    try std.testing.expectError(
        error.Mp3SampleCountOverflow,
        stream.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), stream.cursor);
    try std.testing.expect(stream.first_header == null);
    try std.testing.expectEqual(@as(u64, 0), stream.frame_index);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        stream.sample_offset,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "counter-rollover.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..encoded_bytes],
        0,
    );

    var reader = try FileReader.init(std.testing.io, file);
    var frame_storage: [500]u8 = @splat(0xaa);
    const original_storage = frame_storage;
    reader.frame_index = std.math.maxInt(u64);
    try std.testing.expectError(
        error.Mp3FrameCountOverflow,
        reader.next(&frame_storage),
    );
    try std.testing.expectEqual(@as(u64, 0), reader.offset);
    try std.testing.expectEqualSlices(
        u8,
        &original_storage,
        &frame_storage,
    );

    reader.frame_index = 0;
    reader.sample_offset = std.math.maxInt(u64);
    try std.testing.expectError(
        error.Mp3SampleCountOverflow,
        reader.next(&frame_storage),
    );
    try std.testing.expectEqual(@as(u64, 0), reader.offset);
    try std.testing.expectEqual(@as(u64, 0), reader.frame_index);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        reader.sample_offset,
    );
    try std.testing.expectEqualSlices(
        u8,
        &original_storage,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        trailingTagStart(&.{}, std.math.maxInt(usize)),
    );
}

test "stream and seek indexing reject invalid boundaries transactionally" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var storage: [900]u8 = undefined;
    var cursor = try appendFrame(&storage, 0, header);
    cursor = try appendFrame(&storage, cursor, header);

    var changed = storage;
    const second = (try Header.parse(&header)).frameBytes();
    changed[second + 2] = 0x94;
    try std.testing.expectError(
        error.Mp3StreamFormatChanged,
        Stream.summarize(changed[0..cursor]),
    );

    var trailing = storage;
    trailing[cursor] = 0;
    try std.testing.expectError(
        error.TrailingMp3Data,
        Stream.summarize(trailing[0 .. cursor + 1]),
    );
    var short_destination = [_]SeekPoint{.{
        .frame_index = 99,
        .sample_offset = 99,
        .byte_offset = 99,
    }};
    try std.testing.expectError(
        error.Mp3SeekIndexTooSmall,
        buildSeekIndex(storage[0..cursor], 1, &short_destination),
    );
    try std.testing.expectEqual(@as(u64, 99), short_destination[0].frame_index);
    try std.testing.expectError(
        error.InvalidMp3SeekStride,
        requiredSeekPoints(storage[0..cursor], 0),
    );
    try std.testing.expectError(
        error.InvalidMp3SeekIndex,
        findSeekPoint(&.{.{
            .frame_index = 1,
            .sample_offset = 0,
            .byte_offset = 0,
        }}, 0),
    );

    var stream = try Stream.init(storage[0..cursor]);
    stream.audio_end = stream.encoded.len + 1;
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        stream.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), stream.cursor);

    stream.audio_end = stream.encoded.len;
    stream.audio_start = 1;
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        stream.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), stream.cursor);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "invalid-reader-state.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        storage[0..cursor],
        0,
    );
    var reader = try FileReader.init(std.testing.io, file);
    const original_offset = reader.offset;
    reader.audio_start = original_offset + 1;
    var frame_storage: [500]u8 = @splat(0xaa);
    const original_frame_storage = frame_storage;
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        reader.next(&frame_storage),
    );
    try std.testing.expectEqual(original_offset, reader.offset);
    try std.testing.expectEqualSlices(
        u8,
        &original_frame_storage,
        &frame_storage,
    );
}

test "MP3 seek index builders reject overlapping storage" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var aliased: [900]u8 align(@alignOf(SeekPoint)) = undefined;
    const aliased_points: *[2]SeekPoint = @ptrCast(&aliased);
    var encoded_bytes = try appendFrame(&aliased, 0, header);
    encoded_bytes = try appendFrame(
        &aliased,
        encoded_bytes,
        header,
    );
    const original = aliased;
    try std.testing.expectError(
        error.OverlappingMp3SeekStorage,
        buildSeekIndex(
            aliased[0..encoded_bytes],
            1,
            aliased_points,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &original,
        &aliased,
    );

    var file_bytes: [900]u8 = undefined;
    var file_length = try appendFrame(&file_bytes, 0, header);
    file_length = try appendFrame(&file_bytes, file_length, header);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "overlapping-index.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        file_bytes[0..file_length],
        0,
    );

    var file_alias: [500]u8 align(@alignOf(SeekPoint)) =
        @splat(0xaa);
    const file_alias_points: *[2]SeekPoint =
        @ptrCast(&file_alias);
    const original_file_alias = file_alias;
    try std.testing.expectError(
        error.OverlappingMp3SeekStorage,
        buildFileSeekIndex(
            std.testing.io,
            file,
            &file_alias,
            1,
            file_alias_points,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &original_file_alias,
        &file_alias,
    );
}

test "leading ID3 validation and truncated frames are bounded" {
    try std.testing.expectError(
        error.TruncatedLeadingId3Tag,
        Stream.init("ID3"),
    );
    try std.testing.expectError(
        error.InvalidLeadingId3Size,
        Stream.init(&.{ 'I', 'D', '3', 4, 0, 0, 0x80, 0, 0, 0 }),
    );
    try std.testing.expectError(
        error.TruncatedLeadingId3Tag,
        Stream.init(&.{ 'I', 'D', '3', 4, 0, 0, 0, 0, 0, 1 }),
    );

    var frame: [32]u8 = undefined;
    @memset(&frame, 0);
    const header = testHeader(3, true, 9, 0, false, .stereo);
    @memcpy(frame[0..4], &header);
    try std.testing.expectError(
        error.TruncatedMp3Frame,
        Frame.parse(&frame, 0),
    );
}
