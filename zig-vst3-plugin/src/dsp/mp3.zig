const std = @import("std");
const file_reader_io = @import("file_reader_io.zig");
const file_writer_io = @import("file_writer_io.zig");
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
pub const maximum_encoded_main_data_bytes: usize = 2048;
pub const Limits = struct {
    max_stream_bytes: u64 = std.math.maxInt(u32),
    max_frames: u64 = 10_000_000,

    pub fn validate(self: Limits) !void {
        if (self.max_stream_bytes < 4 or self.max_frames == 0)
            return error.InvalidMp3Limits;
    }
};

pub const default_limits = Limits{};

const maximum_frame_main_data_bytes: usize =
    (4 * std.math.maxInt(u12) + 7) / 8;
const decoder_delay_samples: u16 = 528 + 1;

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

const StagedQuantizedFrame = struct {
    frame: [maximum_encoded_frame_bytes]u8 = @splat(0),
    main_data: [maximum_encoded_main_data_bytes]u8 = @splat(0),
    main_data_bits: u16 = 0,
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

pub const EncoderScaleFactors = struct {
    values: [39]u8 = @splat(0),
    value_count: u6 = 0,
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

pub const PcmFrame = struct {
    channels: [2][1152]f32 = @splat(@splat(0)),
    channel_count: u2,
    sample_count: u16,
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

fn encoderIntensityStartBand(
    description: GranuleChannel,
    layout: EncoderBandLayout,
) usize {
    if (description.block_type != 2) return 14;
    if (!description.mixed_block) return 24;
    return layout.band_count - 15;
}

fn selectEncoderIntensityPosition(
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

fn encoderIntensityGains(
    header: Header,
    position: u8,
) [2]f32 {
    return switch (header.version) {
        .mpeg1 => mpeg1IntensityGains(position),
        .mpeg2, .mpeg25 => lsfIntensityGains(position, false),
    };
}

fn validateAnalyzedEncoderFrame(
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

fn hasEncoderAttack(samples: []const f32, attack_ratio: f32) !bool {
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

fn validatePsychoacousticHistory(
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

fn validateEncoderPsychoacousticConfig(
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

pub const ReservoirQuantizerBudget = struct {
    physical_bits: usize,
    history_bits: usize,
    logical_bits: usize,
};

pub const ReservoirCreditDecision = struct {
    history_bytes: u16,
    physical_bytes: u16,
    logical_bytes: u16,
    next_history_bytes: u16,
};

pub const ReservoirCreditTracker = struct {
    version: Version,
    sample_rate: u32,
    channel_count: u2,
    maximum_history_bytes: u16,
    available_history_bytes: u16 = 0,
    frames_committed: u64 = 0,

    pub fn init(
        header: Header,
        maximum_history_bytes: u16,
    ) !ReservoirCreditTracker {
        _ = try reservoirQuantizerBudget(
            header,
            maximum_history_bytes,
        );
        return .{
            .version = header.version,
            .sample_rate = header.sample_rate,
            .channel_count = @intCast(header.channels()),
            .maximum_history_bytes = maximum_history_bytes,
        };
    }

    pub fn reset(self: *ReservoirCreditTracker) void {
        self.available_history_bytes = 0;
        self.frames_committed = 0;
    }

    pub fn valid(self: *const ReservoirCreditTracker) bool {
        if (self.channel_count == 0 or self.channel_count > 2 or
            sampleRateIndex(self.version, self.sample_rate) == null or
            self.available_history_bytes > self.maximum_history_bytes or
            self.frames_committed == 0 and
                self.available_history_bytes != 0)
            return false;
        const format_limit: u16 =
            if (self.version == .mpeg1) 511 else 255;
        return self.maximum_history_bytes <= format_limit;
    }

    pub fn budget(
        self: ReservoirCreditTracker,
        header: Header,
    ) !ReservoirQuantizerBudget {
        try self.validateHeader(header);
        return reservoirQuantizerBudget(
            header,
            self.available_history_bytes,
        );
    }

    pub fn commit(
        self: *ReservoirCreditTracker,
        header: Header,
        logical_main_data_bits: u16,
    ) !ReservoirCreditDecision {
        try self.validateHeader(header);
        const main_data_offset = frameMainDataOffset(header);
        const frame_bytes = header.frameBytes();
        if (main_data_offset > frame_bytes)
            return error.InvalidMp3EncoderFrameSize;
        const physical_bytes = frame_bytes - main_data_offset;
        const logical_bytes = try std.math.divCeil(
            usize,
            logical_main_data_bits,
            8,
        );
        const available_bytes = std.math.add(
            usize,
            physical_bytes,
            self.available_history_bytes,
        ) catch return error.Mp3ReservoirSizeOverflow;
        if (logical_bytes > available_bytes)
            return error.Mp3ReservoirCreditExceeded;
        const next_history = @min(
            available_bytes - logical_bytes,
            self.maximum_history_bytes,
        );
        const next_frames = std.math.add(
            u64,
            self.frames_committed,
            1,
        ) catch return error.Mp3EncoderFrameCountOverflow;
        const result = ReservoirCreditDecision{
            .history_bytes = self.available_history_bytes,
            .physical_bytes = @intCast(physical_bytes),
            .logical_bytes = @intCast(logical_bytes),
            .next_history_bytes = @intCast(next_history),
        };
        self.available_history_bytes = result.next_history_bytes;
        self.frames_committed = next_frames;
        return result;
    }

    fn validateHeader(
        self: ReservoirCreditTracker,
        header: Header,
    ) !void {
        if (!self.valid())
            return error.InvalidMp3ReservoirCreditState;
        _ = try reservoirQuantizerBudget(header, 0);
        if (header.version != self.version or
            header.sample_rate != self.sample_rate or
            header.channels() != self.channel_count)
            return error.Mp3ReservoirFormatChanged;
    }
};

pub fn reservoirQuantizerBudget(
    header: Header,
    available_history_bytes: u16,
) !ReservoirQuantizerBudget {
    _ = try header.encode();
    if (header.free_format)
        return error.UnsupportedFreeFormatMp3;
    const maximum_history: u16 =
        if (header.version == .mpeg1) 511 else 255;
    if (available_history_bytes > maximum_history)
        return error.InvalidMp3ReservoirHistoryLimit;
    const frame_bytes = header.frameBytes();
    const main_data_offset = frameMainDataOffset(header);
    if (main_data_offset > frame_bytes)
        return error.InvalidMp3EncoderFrameSize;
    const physical_bits = (frame_bytes - main_data_offset) * 8;
    const history_bits = @as(usize, available_history_bytes) * 8;
    const active_channels = @as(usize, header.channels()) *
        (if (header.version == .mpeg1) @as(usize, 2) else 1);
    const side_information_limit =
        active_channels * std.math.maxInt(u12);
    return .{
        .physical_bits = physical_bits,
        .history_bits = history_bits,
        .logical_bits = @min(
            physical_bits + history_bits,
            side_information_limit,
        ),
    };
}

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

const Mp3StorageRange = struct { start: usize, length: usize };

fn validateAdaptiveGaplessStartStorage(
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

fn validateAdaptiveGaplessFinishStorage(
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

fn validateDisjointMp3Storage(
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

fn validateAdaptiveReservoirStorage(
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

fn requiredAdaptiveGaplessFileFinishStorage(
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

fn validateAdaptiveGaplessFileStorage(
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

fn validateAdaptiveReservoirFileStorage(
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

const GaplessReservoirBatchStorage = struct {
    destination_bytes: usize,
};

fn validateGaplessReservoirBatchStorage(
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

fn adaptiveGaplessFlushFrames(header: Header) !usize {
    return std.math.divCeil(
        usize,
        encoder_analysis_delay,
        header.samplesPerFrame(),
    ) catch error.Mp3SampleCountOverflow;
}

fn adaptiveGaplessSummary(
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

fn validateMp3FrameOffsetStorage(
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

fn mp3FrameOffsetSlicesOverlap(
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

fn validateIndexedMp3FrameOffsets(
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

fn validateIndexedVbrFrameSpans(
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

fn recordMp3FileFrameOffsets(
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

fn xingTocFromFrameOffsets(
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

fn reservoirBatchXingToc(
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

fn writeReservoirBatchBytes(
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

fn writeReservoirBatchFileBytes(
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

fn encoderNoiseToMaskRatio(
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

fn reservoirPackingRequirements(
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
            if (!first.compatible(frame.header))
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

fn packMainDataReservoirStaged(
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

const ReservoirMainDataWriter = struct {
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

fn setFrameMainDataBegin(
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

fn validatePendingReservoirFrame(
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

fn reservoirBorrowedBytesValid(
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

fn reservoirPendingBorrowedBytesValid(
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

fn borrowMainData(
    previous: []u8,
    current: []u8,
) !u16 {
    const previous_frame = try Frame.parse(previous, 0);
    const current_frame = try Frame.parse(current, 0);
    if (!previous_frame.header.compatible(current_frame.header) or
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

fn frameMainDataOffset(header: Header) usize {
    return (if (header.crc_present) @as(usize, 6) else 4) +
        header.sideInformationBytes();
}

fn frameXingOffset(header: Header) usize {
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

fn storedXingEncoderDelay(header: Header, total_delay: u16) !u12 {
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

fn storedXingEncoderPadding(end_padding: u16) !u12 {
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

fn encodeInfoFrameFields(
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

fn encodeXingFrameFields(
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

fn validateXingEncoderIdentifier(encoder: [9]u8) !void {
    if (!isValidXingEncoderIdentifier(encoder))
        return error.InvalidMp3EncoderIdentifier;
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

const EncoderByteState = struct {
    byte_count: u64,
    padding_accumulator: u32,
};

fn encoderByteState(
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

fn writeId3v2FilePrefixWithOperations(
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

fn appendId3v1FileTailWithOperations(
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

fn emittedReservoirBytes(
    stream: PcmReservoirStreamEncoder,
) !u64 {
    return (try encoderByteState(
        stream.encoder.encoder.frames.config,
        stream.encoder.frames_emitted,
    )).byte_count;
}

fn emittedVbrReservoirBytes(
    stream: VbrPcmReservoirStreamEncoder,
) !u64 {
    const pending_bytes: u64 = stream.pending_length;
    if (stream.encoder.encoder.byte_count < pending_bytes)
        return error.InvalidMp3VbrReservoirStreamState;
    return stream.encoder.encoder.byte_count - pending_bytes;
}

fn initPcmFileEncoder(
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

fn initVbrPcmFileEncoder(
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

fn restoreVbrOffsets(
    frame_offsets: []u64,
    first: u64,
    values: []const u64,
) void {
    for (values, 0..) |value, index|
        frame_offsets[first + index] = value;
}

fn initPcmReservoirFileEncoder(
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

fn initVbrPcmReservoirFileEncoder(
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

fn fileEncoderOffset(
    audio_offset: u64,
    stream_offset: u64,
) !u64 {
    return std.math.add(
        u64,
        audio_offset,
        stream_offset,
    ) catch error.Mp3FileOffsetOverflow;
}

const encoder_analysis_delay: u16 = 1057;

fn validatePcmEncoderStereo(header: Header) !void {
    if (header.channel_mode != .joint_stereo and
        header.mode_extension != 0)
        return error.InvalidMp3EncoderStereoMode;
}

fn quantizeEncoderChannel(
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

fn quantizeEncoderBand(
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

fn orderEncoderSpectrum(
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

fn restoreEncoderSpectrumOrder(
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

const EncoderBandLayout = struct {
    starts: [40]u16 = @splat(0),
    band_count: u6,
};

fn encoderBandLayout(
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

fn encoderScaleFactorWidths(
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

const EncoderHuffmanSelection = struct {
    description: GranuleChannel,
    bit_count: usize,
};

fn selectEncoderHuffman(
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

const EncoderRegionSelection = struct {
    tables: [3]u5 = @splat(0),
    region0_count: u4 = 0,
    region1_count: u4 = 0,
    bit_count: usize,
};

fn selectShortEncoderTables(
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

fn selectSwitchedLongEncoderTables(
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

fn selectLongEncoderTables(
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

const EncoderTableSelection = struct {
    table: u5,
    bit_count: usize,
};

fn selectEncoderTable(
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

fn encoderPairBitCost(
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

fn encoderCount1BitCost(
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

pub const DecoderFormat = struct {
    version: Version,
    sample_rate: u32,
    channel_count: u2,
};

fn formatFromHeader(header: Header) DecoderFormat {
    return .{
        .version = header.version,
        .sample_rate = header.sample_rate,
        .channel_count = @intCast(header.channels()),
    };
}

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

fn mp3SampleRateValid(sample_rate: u32) bool {
    return mp3SamplesPerFrameForRate(sample_rate) != null;
}

fn mp3SamplesPerFrameForRate(sample_rate: u32) ?u16 {
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

const ScaleFactorLayout = struct {
    bands: ScaleFactorBands,
    short_block: bool,
    short_boundary: usize,
    long_factor_count: usize,
};

fn scaleFactorValueCount(
    header: Header,
    description: GranuleChannel,
) u6 {
    const short_block = description.block_type == 2;
    return switch (header.version) {
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
}

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
    const expected_factor_count =
        scaleFactorValueCount(header, description);
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

const long_imdct = buildImdctMatrix(18);
const short_imdct = buildImdctMatrix(6);
const long_windows = buildLongWindows();
const short_window = buildShortWindow();
const synthesis_matrix = buildSynthesisMatrix();
const synthesis_window = buildSynthesisWindow();
const analysis_matrix = buildAnalysisMatrix();
const analysis_window = buildAnalysisWindow();

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

fn analyzeHybridBlock(
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

        pub fn valid(self: *const Self) bool {
            return self.length <= self.storage.len;
        }

        pub fn assemble(
            self: *Self,
            frame: anytype,
            destination: []u8,
        ) !MainData {
            if (!self.valid())
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

const LsfScaleFactorPlan = struct {
    lengths: [4]u4,
    table: u3,
    preflag: bool,
    intensity_scale: bool,
};

fn lsfScaleFactorPlan(
    encoded_compression: u9,
    intensity_stereo: bool,
) !LsfScaleFactorPlan {
    var compression: usize = encoded_compression;
    var result = LsfScaleFactorPlan{
        .lengths = @splat(0),
        .table = 0,
        .preflag = false,
        .intensity_scale = false,
    };
    if (intensity_stereo) {
        result.intensity_scale = encoded_compression & 1 != 0;
        compression >>= 1;
        if (compression < 180) {
            result.lengths = .{
                @intCast(compression / 36),
                @intCast(compression % 36 / 6),
                @intCast(compression % 6),
                0,
            };
            result.table = 3;
        } else if (compression < 244) {
            compression -= 180;
            result.lengths = .{
                @intCast(compression >> 4),
                @intCast((compression % 16) >> 2),
                @intCast(compression % 4),
                0,
            };
            result.table = 4;
        } else {
            compression -= 244;
            result.lengths = .{
                @intCast(compression / 3),
                @intCast(compression % 3),
                0,
                0,
            };
            result.table = 5;
        }
    } else if (compression < 400) {
        result.lengths = .{
            @intCast((compression >> 4) / 5),
            @intCast((compression >> 4) % 5),
            @intCast((compression % 16) >> 2),
            @intCast(compression % 4),
        };
    } else if (compression < 500) {
        compression -= 400;
        result.lengths = .{
            @intCast((compression >> 2) / 5),
            @intCast((compression >> 2) % 5),
            @intCast(compression % 4),
            0,
        };
        result.table = 1;
    } else if (compression < 512) {
        compression -= 500;
        result.lengths = .{
            @intCast(compression / 3),
            @intCast(compression % 3),
            0,
            0,
        };
        result.table = 2;
        result.preflag = true;
    } else {
        return error.InvalidMp3ScaleFactorCompression;
    }
    return result;
}

fn decodeLsfScaleFactorChannel(
    reader: *MainDataBitReader,
    description: GranuleChannel,
    intensity_stereo: bool,
) !ScaleFactorChannel {
    const plan = try lsfScaleFactorPlan(
        description.scalefac_compress,
        intensity_stereo,
    );
    var result = ScaleFactorChannel{
        .preflag = plan.preflag,
        .intensity_scale = plan.intensity_scale,
    };

    const layout: usize = if (description.block_type != 2)
        0
    else if (description.mixed_block)
        2
    else
        1;
    var index: usize = 0;
    for (lsf_scale_factor_counts[plan.table][layout], 0..) |
        count,
        part,
    | {
        const width = plan.lengths[part];
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

pub const EncodedScaleFactors = struct {
    main_data: MainData,
};

pub fn encodeScaleFactors(
    header: Header,
    description: GranuleChannel,
    scfsi: u4,
    granule: u2,
    channel: u2,
    first_granule: EncoderScaleFactors,
    factors: EncoderScaleFactors,
    destination: []u8,
) !EncodedScaleFactors {
    _ = try scaleFactorBands(header);
    try validateBlockDescription(description);
    const channel_count: u2 = @intCast(header.channels());
    const granule_count: u2 =
        if (header.version == .mpeg1) 2 else 1;
    if (channel >= channel_count or granule >= granule_count)
        return error.InvalidMp3EncoderScaleFactorPosition;
    if (header.version != .mpeg1 and scfsi != 0)
        return error.InvalidMp3EncoderScaleFactors;

    const normalized = try normalizeEncoderScaleFactors(
        header,
        description,
        factors,
    );
    var staged: [64]u8 = @splat(0);
    var writer = MainDataBitWriter{ .bytes = &staged };
    if (header.version == .mpeg1) {
        if (description.scalefac_compress >=
            mpeg1_scale_factor_lengths.len)
            return error.InvalidMp3ScaleFactorCompression;
        const lengths =
            mpeg1_scale_factor_lengths[description.scalefac_compress];
        if (description.block_type == 2) {
            if (granule == 1 and scfsi != 0)
                return error.InvalidMp3EncoderScaleFactors;
            const first_count: usize =
                if (description.mixed_block) 17 else 18;
            for (0..first_count) |index|
                try writeEncoderScaleFactor(
                    &writer,
                    normalized.values[index],
                    lengths[0],
                );
            for (first_count..first_count + 18) |index|
                try writeEncoderScaleFactor(
                    &writer,
                    normalized.values[index],
                    lengths[1],
                );
        } else {
            const ranges = [4][2]u5{
                .{ 0, 6 },
                .{ 6, 11 },
                .{ 11, 16 },
                .{ 16, 21 },
            };
            const normalized_first =
                if (granule == 1 and scfsi != 0)
                    try normalizeEncoderScaleFactors(
                        header,
                        description,
                        first_granule,
                    )
                else
                    EncoderScaleFactors{};
            for (ranges, 0..) |range, group| {
                const reuse = granule == 1 and
                    scfsi & (@as(u4, 8) >> @intCast(group)) != 0;
                const width = lengths[if (group < 2) 0 else 1];
                for (range[0]..range[1]) |index| {
                    if (reuse) {
                        if (normalized.values[index] !=
                            normalized_first.values[index])
                            return error.InvalidMp3EncoderScaleFactorReuse;
                    } else {
                        try writeEncoderScaleFactor(
                            &writer,
                            normalized.values[index],
                            width,
                        );
                    }
                }
            }
        }
    } else {
        const intensity_stereo =
            header.channel_mode == .joint_stereo and
            header.mode_extension & 1 != 0 and
            channel == 1;
        const plan = try lsfScaleFactorPlan(
            description.scalefac_compress,
            intensity_stereo,
        );
        const layout: usize = if (description.block_type != 2)
            0
        else if (description.mixed_block)
            2
        else
            1;
        var index: usize = 0;
        for (lsf_scale_factor_counts[plan.table][layout], 0..) |
            count,
            part,
        | {
            for (0..count) |_| {
                try writeEncoderScaleFactor(
                    &writer,
                    normalized.values[index],
                    plan.lengths[part],
                );
                index += 1;
            }
        }
        if (index != normalized.value_count)
            return error.InvalidMp3EncoderScaleFactors;
    }

    if (writer.bit_offset > std.math.maxInt(u12))
        return error.Mp3ScaleFactorBitCountOverflow;
    const byte_count = (writer.bit_offset + 7) / 8;
    if (destination.len < byte_count)
        return error.InsufficientMp3ScaleFactorStorage;
    @memcpy(destination[0..byte_count], staged[0..byte_count]);
    return .{
        .main_data = .{
            .bytes = destination[0..byte_count],
            .bit_count = @intCast(writer.bit_offset),
        },
    };
}

fn normalizeEncoderScaleFactors(
    header: Header,
    description: GranuleChannel,
    factors: EncoderScaleFactors,
) !EncoderScaleFactors {
    const expected_count =
        scaleFactorValueCount(header, description);
    var result = factors;
    if (result.value_count == 0)
        result.value_count = expected_count;
    if (result.value_count != expected_count)
        return error.InvalidMp3EncoderScaleFactors;
    for (result.values[result.value_count..]) |value| {
        if (value != 0)
            return error.InvalidMp3EncoderScaleFactors;
    }
    _ = try scaleFactorLayout(
        header,
        description,
        .{
            .values = result.values,
            .value_count = result.value_count,
            .preflag = description.preflag,
        },
    );
    return result;
}

fn writeEncoderScaleFactor(
    writer: *MainDataBitWriter,
    value: u8,
    bit_count: u4,
) !void {
    const maximum: u16 =
        if (bit_count == 0)
            0
        else
            (@as(u16, 1) << @intCast(bit_count)) - 1;
    if (value > maximum)
        return error.InvalidMp3EncoderScaleFactorValue;
    try writer.write(value, @intCast(bit_count));
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
                if (!first.compatible(header)) continue;
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
                    if (!header.compatible(following_header))
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
            if (!self.first_header.compatible(header)) continue;
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
        if (!self.first_header.compatible(header))
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
        if (!header.compatible(candidate_header)) continue;
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
    if (!header.compatible(next_header)) return false;
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
        if (!header.compatible(candidate_header)) continue;
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
    if (!header.compatible(next_header)) return false;
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

fn frameRecoveryCandidateValid(frame: Frame) bool {
    if (frameCrcValid(frame.bytes, frame.header) catch return false) |crc_valid| {
        if (!crc_valid) return false;
    }
    _ = parseSideInformation(frame.bytes, frame.header) catch return false;
    return true;
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

const Mp3FileFaults = struct {
    delegate: file_writer_io.Operations = .{},
    write_calls: usize = 0,
    sync_calls: usize = 0,
    fail_write_call: ?usize = null,
    fail_sync_call: ?usize = null,
    partial_write_bytes: usize = 0,

    fn operations(self: *Mp3FileFaults) file_writer_io.Operations {
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

fn repairTestFrameCrc(destination: []u8, offset: usize) !void {
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
        .scalefac_compress = 5,
        .table_select = @splat(1),
        .region0_count = 7,
        .region1_count = 5,
    };
    source.granules[0][0].scale_factors.value_count = 22;
    source.granules[0][0].scale_factors.values[0] = 1;
    source.granules[0][0].spectrum[0] = 1;
    source.granules[0][0].spectrum[1] = -1;
    source.granules[1][0].description = .{
        .global_gain = 210,
        .scalefac_compress = 5,
        .region0_count = 7,
        .region1_count = 5,
        .count1_table_select = true,
    };
    source.granules[1][0].scale_factors =
        source.granules[0][0].scale_factors;
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
    try std.testing.expectEqual(
        @as(u8, 1),
        factors.granules[0].channels[0].values[0],
    );
    try std.testing.expectEqual(
        factors.granules[0].channels[0].values,
        factors.granules[1].channels[0].values,
    );
    try std.testing.expectEqual(
        @as(u12, 21),
        factors.granules[0].channels[0].part2_bits,
    );
    try std.testing.expectEqual(
        @as(u12, 0),
        factors.granules[1].channels[0].part2_bits,
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
    source.granules[0][0].scale_factors.values[0] = 1;
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactorValue,
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
    try std.testing.expect(encoder.valid());
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
    try std.testing.expect(!encoder.valid());
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
    encoder.reset();
    try std.testing.expect(encoder.valid());
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
    try std.testing.expect(missing.valid());
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
    try std.testing.expect(short.valid());
    try std.testing.expectEqual(@as(usize, 0), short.length);

    short.length = short.storage.len + 1;
    try std.testing.expect(!short.valid());
    const invalid_reservoir = short;
    try std.testing.expectError(
        error.InvalidMp3ReservoirState,
        short.assemble(second, &second_output),
    );
    try std.testing.expectEqual(invalid_reservoir, short);
}

test "encodes MPEG-1 scale factors and reuse groups" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const long_description = GranuleChannel{
        .scalefac_compress = 15,
    };
    var long_factors = EncoderScaleFactors{
        .value_count = 22,
    };
    for (0..11) |index|
        long_factors.values[index] = @intCast((index * 3) % 16);
    for (11..21) |index|
        long_factors.values[index] = @intCast((index * 5) % 8);
    var storage: [64]u8 = @splat(0x5a);
    const encoded_long = try encodeScaleFactors(
        header,
        long_description,
        0,
        0,
        0,
        .{},
        long_factors,
        &storage,
    );
    try std.testing.expectEqual(
        @as(u16, 74),
        encoded_long.main_data.bit_count,
    );
    var long_reader = MainDataBitReader{
        .bytes = encoded_long.main_data.bytes,
        .bit_limit = encoded_long.main_data.bit_count,
    };
    const decoded_long = try decodeMpeg1ScaleFactorChannel(
        &long_reader,
        long_description,
        0,
        0,
        .{},
    );
    try std.testing.expectEqual(
        long_factors.values,
        decoded_long.values,
    );
    try std.testing.expectEqual(
        @as(usize, encoded_long.main_data.bit_count),
        long_reader.bit_offset,
    );

    const reuse_description = GranuleChannel{
        .scalefac_compress = 10,
    };
    var first = EncoderScaleFactors{
        .value_count = 22,
    };
    @memset(first.values[0..21], 1);
    var second = first;
    @memset(second.values[6..11], 2);
    @memset(second.values[16..21], 3);
    const encoded_reuse = try encodeScaleFactors(
        header,
        reuse_description,
        0b1010,
        1,
        0,
        first,
        second,
        &storage,
    );
    try std.testing.expectEqual(
        @as(u16, 25),
        encoded_reuse.main_data.bit_count,
    );
    var reuse_reader = MainDataBitReader{
        .bytes = encoded_reuse.main_data.bytes,
        .bit_limit = encoded_reuse.main_data.bit_count,
    };
    const decoded_reuse = try decodeMpeg1ScaleFactorChannel(
        &reuse_reader,
        reuse_description,
        0b1010,
        1,
        .{
            .values = first.values,
            .value_count = first.value_count,
        },
    );
    try std.testing.expectEqual(second.values, decoded_reuse.values);

    const short_descriptions = [_]GranuleChannel{
        .{
            .scalefac_compress = 5,
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .scalefac_compress = 5,
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
    };
    for (short_descriptions, 0..) |description, case_index| {
        var factors = EncoderScaleFactors{
            .value_count = scaleFactorValueCount(
                header,
                description,
            ),
        };
        @memset(factors.values[0 .. factors.value_count - 3], 1);
        const encoded = try encodeScaleFactors(
            header,
            description,
            0,
            0,
            0,
            .{},
            factors,
            &storage,
        );
        try std.testing.expectEqual(
            @as(u16, if (case_index == 0) 36 else 35),
            encoded.main_data.bit_count,
        );
        var reader = MainDataBitReader{
            .bytes = encoded.main_data.bytes,
            .bit_limit = encoded.main_data.bit_count,
        };
        const decoded = try decodeMpeg1ScaleFactorChannel(
            &reader,
            description,
            0,
            0,
            .{},
        );
        try std.testing.expectEqual(
            factors.values,
            decoded.values,
        );
    }
}

test "encodes every low-sampling-frequency scale-factor family" {
    const descriptions = [_]GranuleChannel{
        .{},
        .{
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
    };
    const non_intensity_compressions =
        [_]u9{ 0, 399, 400, 499, 500, 511 };
    const intensity_compressions =
        [_]u9{ 0, 359, 360, 487, 488, 511 };
    const normal_header = try Header.parse(
        &testHeader(2, true, 8, 0, false, .mono),
    );
    var intensity_header = try Header.parse(
        &testHeader(2, true, 8, 0, false, .joint_stereo),
    );
    intensity_header.mode_extension = 1;
    const headers = [_]Header{ normal_header, intensity_header };
    var storage: [64]u8 = undefined;
    for (headers, 0..) |header, header_index| {
        const intensity = header_index == 1;
        const compressions = if (intensity)
            intensity_compressions
        else
            non_intensity_compressions;
        for (compressions, 0..) |compression, case_index| {
            var description =
                descriptions[case_index % descriptions.len];
            description.scalefac_compress = compression;
            const plan = try lsfScaleFactorPlan(
                compression,
                intensity,
            );
            const layout: usize = if (description.block_type != 2)
                0
            else if (description.mixed_block)
                2
            else
                1;
            var factors = EncoderScaleFactors{
                .value_count = scaleFactorValueCount(
                    header,
                    description,
                ),
            };
            var index: usize = 0;
            for (lsf_scale_factor_counts[plan.table][layout], 0..) |
                count,
                part,
            | {
                const width = plan.lengths[part];
                const maximum: u8 = if (width == 0)
                    0
                else
                    @intCast((@as(u16, 1) << @intCast(width)) - 1);
                for (0..count) |_| {
                    factors.values[index] =
                        if (maximum == 0)
                            0
                        else
                            @intCast((index * 3 + 1) %
                                (@as(usize, maximum) + 1));
                    index += 1;
                }
            }
            if (description.block_type == 2)
                @memset(
                    factors.values[factors.value_count - 3 .. factors.value_count],
                    0,
                );
            const channel: u2 = if (intensity) 1 else 0;
            const encoded = try encodeScaleFactors(
                header,
                description,
                0,
                0,
                channel,
                .{},
                factors,
                &storage,
            );
            var reader = MainDataBitReader{
                .bytes = encoded.main_data.bytes,
                .bit_limit = encoded.main_data.bit_count,
            };
            const decoded = try decodeLsfScaleFactorChannel(
                &reader,
                description,
                intensity,
            );
            try std.testing.expectEqual(
                factors.values,
                decoded.values,
            );
            try std.testing.expectEqual(
                plan.preflag,
                decoded.preflag,
            );
            try std.testing.expectEqual(
                plan.intensity_scale,
                decoded.intensity_scale,
            );
            try std.testing.expectEqual(
                @as(usize, encoded.main_data.bit_count),
                reader.bit_offset,
            );
        }
    }

    const low_rate_header = try Header.parse(
        &testHeader(0, true, 9, 2, false, .mono),
    );
    const low_rate_description = GranuleChannel{
        .scalefac_compress = 401,
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    };
    const low_rate = try encodeScaleFactors(
        low_rate_header,
        low_rate_description,
        0,
        0,
        0,
        .{},
        .{},
        &storage,
    );
    try std.testing.expect(low_rate.main_data.bit_count > 0);
}

test "rejects malformed scale-factor encoding transactionally" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const description = GranuleChannel{
        .scalefac_compress = 5,
    };
    var storage: [64]u8 = @splat(0x5a);
    const original = storage;

    var excessive = EncoderScaleFactors{
        .value_count = 22,
    };
    excessive.values[0] = 2;
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactorValue,
        encodeScaleFactors(
            header,
            description,
            0,
            0,
            0,
            .{},
            excessive,
            &storage,
        ),
    );
    try std.testing.expectEqual(original, storage);

    var wrong_count = excessive;
    wrong_count.values[0] = 0;
    wrong_count.value_count = 21;
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactors,
        encodeScaleFactors(
            header,
            description,
            0,
            0,
            0,
            .{},
            wrong_count,
            &storage,
        ),
    );
    try std.testing.expectEqual(original, storage);

    var trailing = EncoderScaleFactors{
        .value_count = 22,
    };
    trailing.values[38] = 1;
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactors,
        encodeScaleFactors(
            header,
            description,
            0,
            0,
            0,
            .{},
            trailing,
            &storage,
        ),
    );
    try std.testing.expectEqual(original, storage);

    const first = EncoderScaleFactors{
        .value_count = 22,
    };
    var second = first;
    second.values[0] = 1;
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactorReuse,
        encodeScaleFactors(
            header,
            description,
            0b1000,
            1,
            0,
            first,
            second,
            &storage,
        ),
    );
    try std.testing.expectEqual(original, storage);

    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactorPosition,
        encodeScaleFactors(
            header,
            description,
            0,
            0,
            1,
            .{},
            .{},
            &storage,
        ),
    );
    const lsf_header = try Header.parse(
        &testHeader(2, true, 8, 0, false, .mono),
    );
    try std.testing.expectError(
        error.InvalidMp3EncoderScaleFactors,
        encodeScaleFactors(
            lsf_header,
            .{},
            1,
            0,
            0,
            .{},
            .{},
            &storage,
        ),
    );

    var short_storage: [1]u8 = @splat(0x6b);
    try std.testing.expectError(
        error.InsufficientMp3ScaleFactorStorage,
        encodeScaleFactors(
            header,
            description,
            0,
            0,
            0,
            .{},
            .{},
            &short_storage,
        ),
    );
    try std.testing.expectEqual(
        @as([1]u8, @splat(0x6b)),
        short_storage,
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

    const prepared = try prepareAliasesForEncoding(
        header,
        .{},
        reduced,
    );
    for (long_spectrum.lines, prepared.lines) |expected, actual| {
        try std.testing.expectApproxEqAbs(expected, actual, 5e-6);
    }
    const mixed_prepared = try prepareAliasesForEncoding(
        header,
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
        mixed,
    );
    for (mixed_spectrum.lines, mixed_prepared.lines) |expected, actual| {
        try std.testing.expectApproxEqAbs(expected, actual, 5e-6);
    }
    const short_prepared = try prepareAliasesForEncoding(
        header,
        .{
            .window_switching = true,
            .block_type = 2,
        },
        long_spectrum,
    );
    try std.testing.expectEqual(long_spectrum, short_prepared);

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
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        prepareAliasesForEncoding(header, .{}, malformed),
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

    low_rate_synthesis.overlap[0][0] = std.math.inf(f32);
    try std.testing.expect(!low_rate_synthesis.valid());
    const invalid_synthesis = low_rate_synthesis;
    try std.testing.expectError(
        error.InvalidMp3HybridState,
        low_rate_synthesis.process(
            low_rate_header,
            .{},
            .{},
        ),
    );
    try std.testing.expectEqual(invalid_synthesis, low_rate_synthesis);
    low_rate_synthesis.reset();
    try std.testing.expect(low_rate_synthesis.valid());
    try std.testing.expectError(
        error.InvalidMp3BlockType,
        low_rate_synthesis.process(
            low_rate_header,
            .{ .block_type = 2 },
            .{},
        ),
    );
}

test "round trips MP3 hybrid analysis across window transitions" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const descriptions = [_]GranuleChannel{
        .{},
        .{},
        .{
            .window_switching = true,
            .block_type = 1,
        },
        .{
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .window_switching = true,
            .block_type = 3,
        },
        .{},
        .{},
    };
    var analysis = HybridAnalysis{};
    var synthesis = HybridSynthesis{};
    var maximum_error: f32 = 0;
    for (descriptions, 0..) |description, granule| {
        var input = HybridSamples{};
        for (&input.time_slots, 0..) |*time_slot, time| {
            for (time_slot, 0..) |*sample, band| {
                const phase: f32 = @floatFromInt(
                    (granule * 18 + time) * 7 + band * 11,
                );
                sample.* = 0.4 * @sin(phase * 0.037) +
                    0.15 * @cos(phase * 0.091);
            }
        }
        const encoded = try analysis.process(
            header,
            description,
            input,
        );
        const output = try synthesis.process(
            header,
            description,
            try reduceAliases(header, description, encoded),
        );
        if (granule == 0) continue;
        for (output.time_slots, 0..) |time_slot, time| {
            for (time_slot, 0..) |sample, band| {
                const phase: f32 = @floatFromInt(
                    ((granule - 1) * 18 + time) * 7 +
                        band * 11,
                );
                const expected =
                    0.4 * @sin(phase * 0.037) +
                    0.15 * @cos(phase * 0.091);
                maximum_error = @max(
                    maximum_error,
                    @abs(sample - expected),
                );
            }
        }
    }
    try std.testing.expect(maximum_error < 0.00001);

    analysis.reset();
    try std.testing.expectEqual(HybridAnalysis{}, analysis);
}

test "round trips mixed MP3 hybrid analysis at both boundaries" {
    const headers = [_]Header{
        try Header.parse(
            &testHeader(3, true, 9, 0, false, .mono),
        ),
        try Header.parse(
            &testHeader(0, true, 9, 2, false, .mono),
        ),
    };
    const description = GranuleChannel{
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    };
    for (headers) |header| {
        var analysis = HybridAnalysis{};
        var synthesis = HybridSynthesis{};
        var maximum_error: f32 = 0;
        for (0..4) |granule| {
            var input = HybridSamples{};
            for (&input.time_slots, 0..) |*time_slot, time| {
                for (time_slot, 0..) |*sample, band| {
                    const phase: f32 = @floatFromInt(
                        (granule * 18 + time) * 5 + band * 13,
                    );
                    sample.* = 0.45 * @sin(phase * 0.041);
                }
            }
            const encoded = try analysis.process(
                header,
                description,
                input,
            );
            const output = try synthesis.process(
                header,
                description,
                try reduceAliases(header, description, encoded),
            );
            if (granule == 0) continue;
            for (output.time_slots, 0..) |time_slot, time| {
                for (time_slot, 0..) |sample, band| {
                    const phase: f32 = @floatFromInt(
                        ((granule - 1) * 18 + time) * 5 +
                            band * 13,
                    );
                    maximum_error = @max(
                        maximum_error,
                        @abs(sample -
                            0.45 * @sin(phase * 0.041)),
                    );
                }
            }
        }
        try std.testing.expect(maximum_error < 0.00001);
    }
}

test "rejects invalid MP3 hybrid analysis transactionally" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var analysis = HybridAnalysis{};
    try std.testing.expect(analysis.valid());
    var malformed = HybridSamples{};
    malformed.time_slots[0][0] = std.math.nan(f32);
    const initial = analysis;
    try std.testing.expectError(
        error.InvalidMp3HybridSamples,
        analysis.process(header, .{}, malformed),
    );
    try std.testing.expectEqual(initial, analysis);

    analysis.history[0][0] = std.math.inf(f32);
    try std.testing.expect(!analysis.valid());
    const bad_history = analysis;
    try std.testing.expectError(
        error.InvalidMp3HybridAnalysisState,
        analysis.process(header, .{}, .{}),
    );
    try std.testing.expectEqual(bad_history, analysis);

    analysis = .{};
    try std.testing.expect(analysis.valid());
    var overflowing = HybridSamples{};
    overflowing.time_slots = @splat(
        @splat(std.math.floatMax(f32)),
    );
    const before_overflow = analysis;
    try std.testing.expectError(
        error.InvalidMp3HybridSample,
        analysis.process(header, .{}, overflowing),
    );
    try std.testing.expectEqual(before_overflow, analysis);

    try std.testing.expectError(
        error.InvalidMp3BlockType,
        analysis.process(
            header,
            .{ .block_type = 2 },
            .{},
        ),
    );
    try std.testing.expectEqual(before_overflow, analysis);
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

    var synthesis_hash = std.crypto.hash.sha2.Sha256.init(.{});
    var encoded_value: [4]u8 = undefined;
    for (synthesis_window_quantized) |value| {
        std.mem.writeInt(u32, &encoded_value, @bitCast(value), .big);
        synthesis_hash.update(&encoded_value);
    }
    var synthesis_digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 =
        undefined;
    synthesis_hash.final(&synthesis_digest);
    var expected_digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 =
        undefined;
    _ = try std.fmt.hexToBytes(
        &expected_digest,
        "e8d6792457f2a517d0e36a87d29f83610aa00d6cca6281f0b31802faa4b2ccf3",
    );
    try std.testing.expectEqual(expected_digest, synthesis_digest);
}

test "preserves the MP3 Huffman table codewords" {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var encoded_bits: [4]u8 = undefined;
    for (0..32) |table_index| {
        const index: u5 = @intCast(table_index);
        const table = huffman_tables.get(index) catch |err| switch (err) {
            error.InvalidMp3HuffmanTable => {
                hash.update(&.{ @intCast(index), 0xff });
                continue;
            },
        };
        hash.update(&.{
            @intCast(index),
            @intCast(table.side),
            @intCast(table.linbits),
        });
        for (table.entries) |entry| {
            hash.update(&.{@intCast(entry.length)});
            std.mem.writeInt(u32, &encoded_bits, entry.bits, .big);
            hash.update(&encoded_bits);
        }
    }
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hash.final(&digest);
    var expected_digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 =
        undefined;
    _ = try std.fmt.hexToBytes(
        &expected_digest,
        "9fdeb0ca3c74ac54a8ee9154544e8dced73aef97837de1311572e75866de76ec",
    );
    try std.testing.expectEqual(expected_digest, digest);
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
    try std.testing.expect(synthesis.valid());
    var malformed = HybridSamples{};
    malformed.time_slots[0][0] = std.math.nan(f32);
    const initial = synthesis;
    try std.testing.expectError(
        error.InvalidMp3HybridSamples,
        synthesis.process(malformed),
    );
    try std.testing.expectEqual(initial, synthesis);

    synthesis.head_block = 16;
    try std.testing.expect(!synthesis.valid());
    const bad_head = synthesis;
    try std.testing.expectError(
        error.InvalidMp3PolyphaseState,
        synthesis.process(.{}),
    );
    try std.testing.expectEqual(bad_head, synthesis);

    synthesis = .{};
    synthesis.history[17] = std.math.inf(f64);
    try std.testing.expect(!synthesis.valid());
    const bad_history = synthesis;
    try std.testing.expectError(
        error.InvalidMp3PolyphaseState,
        synthesis.process(.{}),
    );
    try std.testing.expectEqual(bad_history, synthesis);

    synthesis = .{};
    try std.testing.expect(synthesis.valid());
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

test "round trips the MP3 polyphase analysis and synthesis banks" {
    var analysis = PolyphaseAnalysis{};
    var synthesis = PolyphaseSynthesis{};
    var maximum_error: f32 = 0;
    for (0..8) |granule| {
        var pcm = PcmGranule{};
        for (&pcm.samples, 0..) |*sample, index| {
            const absolute: f32 =
                @floatFromInt(granule * 576 + index);
            sample.* = 0.6 * @sin(absolute * 0.071) +
                0.2 * @cos(absolute * 0.193);
        }
        const output = try synthesis.process(
            try analysis.process(pcm),
        );
        for (output.samples, 0..) |sample, index| {
            const absolute = granule * 576 + index;
            if (absolute < 481) continue;
            const source: f32 =
                @floatFromInt(absolute - 481);
            const expected = 0.6 * @sin(source * 0.071) +
                0.2 * @cos(source * 0.193);
            maximum_error = @max(
                maximum_error,
                @abs(sample - expected),
            );
        }
    }
    try std.testing.expect(maximum_error < 0.00007);

    analysis.reset();
    synthesis.reset();
    var impulse = PcmGranule{};
    impulse.samples[0] = 1;
    var peak: f32 = 0;
    var peak_index: usize = 0;
    for (0..2) |granule| {
        const output = try synthesis.process(
            try analysis.process(
                if (granule == 0) impulse else .{},
            ),
        );
        for (output.samples, 0..) |sample, index| {
            if (@abs(sample) > @abs(peak)) {
                peak = sample;
                peak_index = granule * 576 + index;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 481), peak_index);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1),
        peak,
        0.00001,
    );
}

test "rejects invalid MP3 polyphase analysis transactionally" {
    var analysis = PolyphaseAnalysis{};
    try std.testing.expect(analysis.valid());
    var malformed = PcmGranule{};
    malformed.samples[0] = std.math.nan(f32);
    const initial = analysis;
    try std.testing.expectError(
        error.InvalidMp3PcmSamples,
        analysis.process(malformed),
    );
    try std.testing.expectEqual(initial, analysis);

    analysis.history[0] = std.math.inf(f64);
    try std.testing.expect(!analysis.valid());
    const bad_history = analysis;
    try std.testing.expectError(
        error.InvalidMp3PolyphaseAnalysisState,
        analysis.process(.{}),
    );
    try std.testing.expectEqual(bad_history, analysis);

    analysis = .{};
    try std.testing.expect(analysis.valid());
    var overflowing = PcmGranule{};
    overflowing.samples = @splat(std.math.floatMax(f32));
    const before_overflow = analysis;
    try std.testing.expectError(
        error.InvalidMp3HybridSample,
        analysis.process(overflowing),
    );
    try std.testing.expectEqual(before_overflow, analysis);

    analysis.reset();
    try std.testing.expect(analysis.valid());
    try std.testing.expectEqual(PolyphaseAnalysis{}, analysis);
}

test "analyzes complete MP3 PCM frames for decoder reconstruction" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .stereo,
    };
    const header = try config.header(false);
    var analysis = try EncoderAnalysis.init(config);
    var hybrid_synthesis: [2]HybridSynthesis = @splat(.{});
    var polyphase_synthesis: [2]PolyphaseSynthesis = @splat(.{});
    const descriptions: [2][2]GranuleChannel =
        @splat(@splat(.{}));
    var maximum_error: f32 = 0;

    for (0..5) |frame_index| {
        var pcm = PcmFrame{
            .channel_count = 2,
            .sample_count = 1152,
        };
        for (0..2) |channel| {
            for (&pcm.channels[channel], 0..) |*sample, index| {
                const absolute: f32 =
                    @floatFromInt(frame_index * 1152 + index);
                const channel_phase: f32 =
                    @floatFromInt(channel);
                sample.* =
                    0.5 * @sin(absolute * 0.029 +
                        channel_phase * 0.4) +
                    0.1 * @cos(absolute * 0.083 -
                        channel_phase * 0.2);
            }
        }
        const analyzed = try analysis.analyze(
            descriptions,
            pcm,
        );
        try std.testing.expectEqual(
            @as(u2, 2),
            analyzed.channel_count,
        );
        try std.testing.expectEqual(
            @as(u2, 2),
            analyzed.granule_count,
        );
        for (0..2) |granule| {
            for (0..2) |channel| {
                const analyzed_channel =
                    analyzed.granules[granule][channel];
                const hybrid = try hybrid_synthesis[channel].process(
                    header,
                    analyzed_channel.description,
                    try reduceAliases(
                        header,
                        analyzed_channel.description,
                        analyzed_channel.spectrum,
                    ),
                );
                const reconstructed =
                    try polyphase_synthesis[channel].process(hybrid);
                for (reconstructed.samples, 0..) |sample, index| {
                    const absolute =
                        frame_index * 1152 +
                        granule * 576 +
                        index;
                    if (absolute < 1057) continue;
                    const source: f32 =
                        @floatFromInt(absolute - 1057);
                    const channel_phase: f32 =
                        @floatFromInt(channel);
                    const expected =
                        0.5 * @sin(source * 0.029 +
                            channel_phase * 0.4) +
                        0.1 * @cos(source * 0.083 -
                            channel_phase * 0.2);
                    maximum_error = @max(
                        maximum_error,
                        @abs(sample - expected),
                    );
                }
            }
        }
    }
    try std.testing.expect(maximum_error < 0.00008);
    try std.testing.expectEqual(
        @as(u64, 5),
        analysis.frames_analyzed,
    );
}

test "validates MP3 encoder analysis state transactionally" {
    const config = EncoderConfig{
        .version = .mpeg2,
        .bitrate_kbps = 64,
        .sample_rate = 22_050,
        .channel_mode = .mono,
    };
    var analysis = try EncoderAnalysis.init(config);
    try std.testing.expect(analysis.valid());
    const descriptions: [2][2]GranuleChannel =
        @splat(@splat(.{}));
    const pcm = PcmFrame{
        .channel_count = 1,
        .sample_count = 576,
    };
    const first = try analysis.analyze(descriptions, pcm);
    try std.testing.expect(analysis.valid());
    try std.testing.expectEqual(@as(u2, 1), first.channel_count);
    try std.testing.expectEqual(@as(u2, 1), first.granule_count);
    try std.testing.expectEqual(
        AnalyzedEncoderChannel{},
        first.granules[0][1],
    );
    try std.testing.expectEqual(
        AnalyzedEncoderChannel{},
        first.granules[1][0],
    );

    var wrong_count = pcm;
    wrong_count.sample_count = 575;
    const before_count = analysis;
    try std.testing.expectError(
        error.InvalidMp3EncoderPcmFrame,
        analysis.analyze(descriptions, wrong_count),
    );
    try std.testing.expectEqual(before_count, analysis);

    var malformed = pcm;
    malformed.channels[0][0] = std.math.nan(f32);
    const before_malformed = analysis;
    try std.testing.expectError(
        error.InvalidMp3PcmSamples,
        analysis.analyze(descriptions, malformed),
    );
    try std.testing.expectEqual(before_malformed, analysis);

    var hidden_description = descriptions;
    hidden_description[1][0].global_gain = 1;
    const before_hidden = analysis;
    try std.testing.expectError(
        error.InvalidMp3EncoderAnalysisFrame,
        analysis.analyze(hidden_description, pcm),
    );
    try std.testing.expectEqual(before_hidden, analysis);

    analysis.config.sample_rate = 24_000;
    try std.testing.expect(!analysis.valid());
    const before_format = analysis;
    try std.testing.expectError(
        error.Mp3EncoderAnalysisFormatChanged,
        analysis.analyze(descriptions, pcm),
    );
    try std.testing.expectEqual(before_format, analysis);
    analysis.config = config;

    analysis.polyphase[0].history[0] = std.math.inf(f64);
    try std.testing.expect(!analysis.valid());
    const before_history = analysis;
    try std.testing.expectError(
        error.InvalidMp3EncoderAnalysisState,
        analysis.analyze(descriptions, pcm),
    );
    try std.testing.expectEqual(before_history, analysis);
    analysis.polyphase[0].reset();
    try std.testing.expect(analysis.valid());

    analysis.frames_analyzed = std.math.maxInt(u64);
    const before_overflow = analysis;
    try std.testing.expectError(
        error.Mp3EncoderFrameCountOverflow,
        analysis.analyze(descriptions, pcm),
    );
    try std.testing.expectEqual(before_overflow, analysis);

    analysis.frames_analyzed = 3;
    analysis.reset();
    try std.testing.expect(analysis.valid());
    try std.testing.expectEqual(@as(u64, 0), analysis.frames_analyzed);
    try std.testing.expectEqual(config, analysis.config);
    try std.testing.expectEqual(
        formatFromHeader(try config.header(false)),
        analysis.format,
    );
    try std.testing.expectEqual(
        @as([2]PolyphaseAnalysis, @splat(.{})),
        analysis.polyphase,
    );
    try std.testing.expectEqual(
        @as([2]HybridAnalysis, @splat(.{})),
        analysis.hybrid,
    );
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
    try std.testing.expect(decoder.valid());
    const decoded = try decoder.decode(frame);
    try std.testing.expect(decoder.valid());
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

    var hostile_decoder = decoder;
    hostile_decoder.hybrid[0].overlap[0][0] = std.math.inf(f32);
    try std.testing.expect(!hostile_decoder.valid());
    const hostile_decoder_before = hostile_decoder;
    try std.testing.expectError(
        error.InvalidMp3DecoderState,
        hostile_decoder.decode(frame),
    );
    try std.testing.expectEqual(
        hostile_decoder_before,
        hostile_decoder,
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
    try std.testing.expect(decoder.valid());
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
            .encoder_padding = 729,
        },
        .first_vbri = null,
    };
    const plan = try GaplessPlan.fromSummary(summary);
    try std.testing.expect(plan.valid());
    try std.testing.expectEqual(@as(u64, 3456), plan.encoded_samples);
    try std.testing.expectEqual(@as(u64, 1475), plan.audible_samples);

    var vbri_summary = summary;
    vbri_summary.first_xing = null;
    vbri_summary.first_vbri = .{
        .version = 1,
        .delay = 0,
        .quality = 0,
        .stream_bytes = 3 * 417,
        .frame_count = 3,
        .toc_entries = 3,
        .toc_scale = 1,
        .entry_bytes = 1,
        .frames_per_entry = 1,
        .toc = &.{ 1, 1, 1 },
    };
    const vbri_plan = try GaplessPlan.fromSummary(vbri_summary);
    try std.testing.expectEqual(@as(u32, 1152), vbri_plan.leading_samples);
    try std.testing.expectEqual(@as(u64, 2304), vbri_plan.audible_samples);

    var encoded: [500]u8 = undefined;
    const frame_end = try appendFrame(
        &encoded,
        0,
        testHeader(3, true, 9, 0, false, .mono),
    );
    const frame = try Frame.parse(encoded[0..frame_end], 0);
    var decoder = try StreamDecoder.init(summary);
    try std.testing.expect(decoder.valid());
    try std.testing.expectError(
        error.Mp3GaplessStreamIncomplete,
        decoder.finish(),
    );
    const first = try decoder.decode(frame);
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(
        PcmRange{ .start = 1152, .length = 0 },
        first.audible,
    );
    var fractional_decoder = decoder;
    fractional_decoder.sample_offset = 1;
    try std.testing.expect(!fractional_decoder.valid());
    const fractional_before = fractional_decoder;
    try std.testing.expectError(
        error.InvalidMp3StreamDecoderState,
        fractional_decoder.decode(frame),
    );
    try std.testing.expectEqual(
        fractional_before,
        fractional_decoder,
    );
    const second = try decoder.decode(frame);
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(
        PcmRange{ .start = 629, .length = 523 },
        second.audible,
    );
    const third = try decoder.decode(frame);
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(
        PcmRange{ .start = 0, .length = 952 },
        third.audible,
    );
    try decoder.finish();

    var hostile_decoder = decoder;
    hostile_decoder.decoder.polyphase[0].head_block = 16;
    try std.testing.expect(!hostile_decoder.valid());
    const hostile_decoder_before = hostile_decoder;
    try std.testing.expectError(
        error.InvalidMp3StreamDecoderState,
        hostile_decoder.decode(frame),
    );
    try std.testing.expectEqual(hostile_decoder_before, hostile_decoder);

    const completed = decoder;
    try std.testing.expectError(
        error.InvalidMp3GaplessPlan,
        decoder.decode(frame),
    );
    try std.testing.expectEqual(completed, decoder);

    decoder.reset();
    try std.testing.expect(decoder.valid());
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
    try std.testing.expect(!malformed.valid());
    try std.testing.expectError(
        error.InvalidMp3GaplessPlan,
        malformed.frameRange(0, 100),
    );
    const malformed_decoder = StreamDecoder{
        .plan = malformed,
        .sample_rate = 44_100,
        .channel_count = 1,
        .sample_offset = 100,
    };
    try std.testing.expect(!malformed_decoder.valid());
    try std.testing.expectError(
        error.InvalidMp3GaplessPlan,
        malformed_decoder.finish(),
    );

    summary.first_xing = null;
    summary.sample_rate = 0;
    try std.testing.expectError(
        error.InvalidMp3Summary,
        StreamDecoder.init(summary),
    );
    summary.sample_rate = 44_100;
    summary.sample_count = 1151;
    try std.testing.expectError(
        error.InvalidMp3Summary,
        StreamDecoder.init(summary),
    );
    summary.sample_count = 0;
    summary.frame_count = 0;
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
    @memcpy(encoded[200..204], &plain);
    setTestBits(encoded[104..136], 32, 9, 511);
    try std.testing.expectError(
        error.InvalidMp3BigValues,
        (try frameAtKnownLength(
            &encoded,
            100,
            try Header.parse(&plain),
            100,
        )).sideInformation(),
    );

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
    @memcpy(encoded[100..104], &header);
    @memcpy(encoded[200..204], &header);
    setTestBits(encoded[104..136], 32, 9, 511);

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

test "protected free-format MP3 preserves CRC validation across readers" {
    var encoded: [1600]u8 = @splat(0);
    const plain = testHeader(3, false, 0, 0, false, .stereo);
    const padded = testHeader(3, false, 0, 0, true, .stereo);
    var cursor = try appendFreeFormatFrame(&encoded, 0, plain, 500);
    try repairTestFrameCrc(&encoded, 0);
    const second_offset = cursor;
    cursor = try appendFreeFormatFrame(&encoded, cursor, padded, 500);
    try repairTestFrameCrc(&encoded, second_offset);
    const third_offset = cursor;
    cursor = try appendFreeFormatFrame(&encoded, cursor, plain, 500);
    try repairTestFrameCrc(&encoded, third_offset);

    const first = try Frame.parse(encoded[0..cursor], 0);
    try std.testing.expectEqual(@as(usize, 500), first.bytes.len);
    try std.testing.expectEqual(@as(?bool, true), try first.crcValid());
    var stream = try Stream.init(encoded[0..cursor]);
    for ([_]usize{ 500, 501, 500 }) |expected_bytes| {
        const frame = (try stream.next()).?;
        try std.testing.expectEqual(expected_bytes, frame.bytes.len);
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
    }
    try std.testing.expect((try stream.next()) == null);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "protected-free-format.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(
        @as(?usize, 500),
        reader.free_frame_base_bytes,
    );
    try reader.seek(.{
        .frame_index = 2,
        .sample_offset = 2304,
        .byte_offset = third_offset,
    });
    var frame_storage: [501]u8 = undefined;
    const sought = (try reader.next(&frame_storage)).?;
    try std.testing.expectEqual(@as(usize, 500), sought.bytes.len);
    try std.testing.expectEqual(@as(?bool, true), try sought.crcValid());
    try std.testing.expect((try reader.next(&frame_storage)) == null);
}

test "protected free-format MP3 resynchronizes with retained frame size" {
    const header = testHeader(3, false, 0, 0, false, .stereo);
    var encoded: [2600]u8 = @splat(0);
    var cursor: usize = 0;
    for (0..3) |_| {
        const frame_offset = cursor;
        cursor = try appendFreeFormatFrame(
            &encoded,
            cursor,
            header,
            500,
        );
        try repairTestFrameCrc(&encoded, frame_offset);
    }
    const damaged_offset = cursor;
    const junk = [_]u8{ 0, 1, 2 };
    @memcpy(encoded[cursor..][0..junk.len], &junk);
    cursor += junk.len;
    const recovered_offset = cursor;
    for (0..2) |_| {
        const frame_offset = cursor;
        cursor = try appendFreeFormatFrame(
            &encoded,
            cursor,
            header,
            500,
        );
        try repairTestFrameCrc(&encoded, frame_offset);
    }

    var stream = try Stream.init(encoded[0..cursor]);
    for (0..3) |_| _ = try stream.next();
    try std.testing.expectEqual(damaged_offset, stream.cursor);
    const retained_stream = stream;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        stream.resynchronize(junk.len - 1),
    );
    try std.testing.expectEqualDeep(retained_stream, stream);
    try std.testing.expectEqual(junk.len, try stream.resynchronize(junk.len));
    try std.testing.expectEqual(recovered_offset, stream.cursor);
    for (0..2) |_| {
        const frame = (try stream.next()).?;
        try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());
    }
    try std.testing.expect((try stream.next()) == null);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "protected-free-format-resync.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    var frame_storage: [500]u8 = undefined;
    for (0..3) |_| _ = try reader.next(&frame_storage);
    try std.testing.expectEqual(
        @as(u64, @intCast(damaged_offset)),
        reader.offset,
    );
    const retained_reader = reader;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        reader.resynchronize(junk.len - 1),
    );
    try std.testing.expectEqualDeep(retained_reader, reader);
    try std.testing.expectEqual(
        @as(u64, junk.len),
        try reader.resynchronize(junk.len),
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(recovered_offset)),
        reader.offset,
    );
    for (0..2) |_| {
        const frame = (try reader.next(&frame_storage)).?;
        try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());
    }
    try std.testing.expect((try reader.next(&frame_storage)) == null);
}

test "parses bounded Xing fields and LAME delay metadata" {
    var storage: [500]u8 = undefined;
    const header_bytes = testHeader(3, false, 9, 0, false, .stereo);
    const end = try appendFrame(&storage, 0, header_bytes);
    const offset = frameXingOffset(try Header.parse(&header_bytes));
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

    @memcpy(storage[offset + 120 ..][0..9], "Lavc60.31");
    storage[offset + 141 ..][0..3].* = .{ 0, 0, 0 };
    const unspecified = try Frame.parse(storage[0..end], 0);
    try std.testing.expectEqual(
        @as(?u12, null),
        unspecified.xing.?.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(?u12, null),
        unspecified.xing.?.encoder_padding,
    );

    storage[offset + 7] = 0x4f;
    @memcpy(storage[offset + 120 ..][0..9], "LAMEH5.24");
    storage[offset + 141 ..][0..3].* = .{ 0x24, 0x03, 0x21 };
    const info_tag = try Frame.parse(storage[0..end], 0);
    try std.testing.expectEqual(
        "LAMEH5.24".*,
        info_tag.xing.?.encoder.?,
    );

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
    const short_offset = 4 + 32;
    @memcpy(storage[short_offset..][0..4], "Xing");
    storage[short_offset + 7] = 0x4;
    try std.testing.expectError(
        error.TruncatedXingHeader,
        Frame.parse(storage[0..short_end], 0),
    );
}

test "encodes truthful and validated Xing encoder identifiers" {
    const header = try (EncoderConfig{
        .bitrate_kbps = 320,
        .channel_mode = .stereo,
    }).header(false);
    var storage: [maximum_encoded_frame_bytes]u8 = @splat(0xa5);
    const encoded = try encodeXingFrame(
        header,
        .{
            .kind = .variable,
            .frame_count = 17,
            .stream_bytes = 4096,
            .encoder_delay = 0x123,
            .encoder_padding = 0x456,
        },
        &storage,
    );
    const parsed = (try Frame.parse(encoded, 0)).xing.?;
    try std.testing.expectEqual(
        default_xing_encoder_identifier,
        parsed.encoder.?,
    );
    try std.testing.expectEqual(@as(?u12, 0x123), parsed.encoder_delay);
    try std.testing.expectEqual(@as(?u12, 0x456), parsed.encoder_padding);

    const custom: [9]u8 = "StudioX 1".*;
    const custom_encoded = try encodeXingFrame(
        header,
        .{
            .kind = .constant,
            .frame_count = 18,
            .stream_bytes = 8192,
            .encoder_delay = 0x234,
            .encoder_padding = 0x567,
            .encoder = custom,
        },
        &storage,
    );
    const parsed_custom = (try Frame.parse(custom_encoded, 0)).xing.?;
    try std.testing.expectEqual(
        custom,
        parsed_custom.encoder.?,
    );
    try std.testing.expectEqual(
        @as(?u12, 0x234),
        parsed_custom.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(?u12, 0x567),
        parsed_custom.encoder_padding,
    );

    var protected_header = header;
    protected_header.crc_present = true;
    const protected_encoded = try encodeXingFrame(
        protected_header,
        .{
            .kind = .variable,
            .frame_count = 19,
            .stream_bytes = 12_288,
            .encoder_delay = 0x345,
            .encoder_padding = 0x678,
        },
        &storage,
    );
    const protected_offset = frameXingOffset(protected_header);
    try std.testing.expectEqualSlices(
        u8,
        "Xing",
        protected_encoded[protected_offset..][0..4],
    );
    try std.testing.expectEqual(
        protected_offset + 2,
        frameMainDataOffset(protected_header),
    );
    try std.testing.expect(!std.mem.eql(
        u8,
        "Xing",
        protected_encoded[frameMainDataOffset(protected_header)..][0..4],
    ));
    const protected_parsed = try Frame.parse(protected_encoded, 0);
    try std.testing.expectEqual(
        @as(?bool, true),
        try protected_parsed.crcValid(),
    );
    try std.testing.expectEqual(
        @as(?u32, 19),
        protected_parsed.xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u12, 0x345),
        protected_parsed.xing.?.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(?u12, 0x678),
        protected_parsed.xing.?.encoder_padding,
    );

    const before = storage;
    try std.testing.expectError(
        error.InvalidMp3EncoderIdentifier,
        encodeXingFrame(
            header,
            .{
                .kind = .variable,
                .frame_count = 1,
                .stream_bytes = 1,
                .encoder_delay = 0,
                .encoder_padding = 0,
                .encoder = @splat(' '),
            },
            &storage,
        ),
    );
    try std.testing.expectEqual(before, storage);

    var control_identifier = custom;
    control_identifier[4] = '\n';
    try std.testing.expectError(
        error.InvalidMp3EncoderIdentifier,
        encodeXingFrame(
            header,
            .{
                .kind = .variable,
                .frame_count = 1,
                .stream_bytes = 1,
                .encoder_delay = 0,
                .encoder_padding = 0,
                .encoder = control_identifier,
            },
            &storage,
        ),
    );
    try std.testing.expectEqual(before, storage);

    var hostile_cbr = try PcmStreamEncoder.init(.{});
    hostile_cbr.metadata_encoder[0] = 0;
    try std.testing.expectError(
        error.InvalidMp3EncoderStreamState,
        hostile_cbr.summary(),
    );
    var hostile_reservoir = try PcmReservoirStreamEncoder.init(.{});
    hostile_reservoir.metadata_encoder[0] = 0x7f;
    try std.testing.expectError(
        error.InvalidMp3ReservoirStreamState,
        hostile_reservoir.summary(),
    );
    var hostile_offsets: [1]u64 = undefined;
    var hostile_vbr = try VbrPcmStreamEncoder.init(
        .{},
        &hostile_offsets,
    );
    hostile_vbr.metadata_encoder = @splat(' ');
    try std.testing.expectError(
        error.InvalidMp3VbrStreamState,
        hostile_vbr.summary(),
    );
    var hostile_vbr_reservoir =
        try VbrPcmReservoirStreamEncoder.init(
            .{},
            &hostile_offsets,
        );
    hostile_vbr_reservoir.encoder.metadata_encoder[0] = 0;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirStreamState,
        hostile_vbr_reservoir.summary(),
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
        0, 1,  0, 2, 0, 3,
        0, 0,  4, 0, 0, 0,
        0, 10, 0, 3, 0, 1,
        0, 2,  0, 4,
    };
    storage[offset + 26 ..][0..6].* = .{ 0, 5, 0, 6, 0, 7 };
    const frame = try Frame.parse(storage[0..end], 0);
    const vbri = frame.vbri.?;
    try std.testing.expectEqual(@as(u16, 1), vbri.version);
    try std.testing.expectEqual(@as(u32, 1024), vbri.stream_bytes);
    try std.testing.expectEqual(@as(u32, 10), vbri.frame_count);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 5, 0, 6, 0, 7 },
        vbri.toc,
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        try vbri.approximateByteOffsetForFrame(0),
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        try vbri.approximateByteOffsetForFrame(2),
    );
    try std.testing.expectEqual(
        @as(u32, 5),
        try vbri.approximateByteOffsetForFrame(4),
    );
    try std.testing.expectEqual(
        @as(u32, 12),
        try vbri.approximateByteOffsetForFrame(9),
    );
    try std.testing.expectEqual(
        @as(u32, 1024),
        try vbri.approximateByteOffsetForFrame(10),
    );
    var one_uncovered = vbri;
    one_uncovered.frame_count = 13;
    try std.testing.expectEqual(
        @as(u32, 16),
        try one_uncovered.approximateByteOffsetForFrame(12),
    );

    try std.testing.expectError(
        error.InvalidVbriTargetFrame,
        vbri.approximateByteOffsetForFrame(11),
    );
    var short_toc = vbri;
    short_toc.toc = short_toc.toc[0..4];
    try std.testing.expectError(
        error.InvalidVbriTocSize,
        short_toc.approximateByteOffsetForFrame(1),
    );
    var incomplete = vbri;
    incomplete.toc_entries = 2;
    incomplete.toc = incomplete.toc[0..4];
    try std.testing.expectError(
        error.IncompleteVbriFrameCoverage,
        incomplete.approximateByteOffsetForFrame(1),
    );
    var oversized = vbri;
    oversized.stream_bytes = 10;
    try std.testing.expectError(
        error.InvalidVbriStreamBytes,
        oversized.approximateByteOffsetForFrame(1),
    );
    const zero_toc = [_]u8{ 0, 5, 0, 0, 0, 7 };
    var zero_entry = vbri;
    zero_entry.toc = &zero_toc;
    try std.testing.expectError(
        error.InvalidVbriTocEntry,
        zero_entry.approximateByteOffsetForFrame(1),
    );

    storage[offset + 28 ..][0..2].* = .{ 0, 0 };
    try std.testing.expectError(
        error.InvalidVbriTocEntry,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 28 ..][0..2].* = .{ 0, 6 };
    storage[offset + 14 ..][0..4].* = .{ 0, 0, 0, 14 };
    try std.testing.expectError(
        error.IncompleteVbriFrameCoverage,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 14 ..][0..4].* = .{ 0, 0, 0, 10 };
    storage[offset + 10 ..][0..4].* = .{ 0, 0, 0, 10 };
    try std.testing.expectError(
        error.InvalidVbriStreamBytes,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 10 ..][0..4].* = .{ 0, 0, 4, 0 };

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
    storage[offset + 20 ..][0..2].* = .{ 0, 0 };
    try std.testing.expectError(
        error.InvalidVbriTocScale,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 20 ..][0..2].* = .{ 0, 1 };
    storage[offset + 24 ..][0..2].* = .{ 0, 0 };
    try std.testing.expectError(
        error.InvalidVbriFramesPerEntry,
        Frame.parse(storage[0..end], 0),
    );
    storage[offset + 24 ..][0..2].* = .{ 0, 4 };
    storage[offset + 5] = 2;
    try std.testing.expectError(
        error.UnsupportedVbriVersion,
        Frame.parse(storage[0..end], 0),
    );
}

test "VBRI seek lookup decodes every table entry width" {
    for (1..5) |entry_bytes| {
        var toc_storage: [8]u8 = @splat(0);
        toc_storage[entry_bytes - 1] = 3;
        toc_storage[entry_bytes * 2 - 1] = 5;
        const vbri = Vbri{
            .version = 1,
            .delay = 0,
            .quality = 0,
            .stream_bytes = 16,
            .frame_count = 2,
            .toc_entries = 2,
            .toc_scale = 2,
            .entry_bytes = @intCast(entry_bytes),
            .frames_per_entry = 1,
            .toc = toc_storage[0 .. entry_bytes * 2],
        };
        try std.testing.expectEqual(
            @as(u32, 0),
            try vbri.approximateByteOffsetForFrame(0),
        );
        try std.testing.expectEqual(
            @as(u32, 6),
            try vbri.approximateByteOffsetForFrame(1),
        );
        try std.testing.expectEqual(
            @as(u32, 16),
            try vbri.approximateByteOffsetForFrame(2),
        );
    }
}

test "VBRI seek lookup matches generated segment tables" {
    var random_state = std.Random.DefaultPrng.init(0x5642_5249_5345_454b);
    const random = random_state.random();
    for (0..256) |_| {
        const entry_count = random.intRangeAtMost(usize, 1, 8);
        const entry_bytes = random.intRangeAtMost(usize, 1, 4);
        const frames_per_entry = random.intRangeAtMost(u16, 1, 8);
        const scale = random.intRangeAtMost(u16, 1, 16);
        const covered_frames =
            entry_count * @as(usize, frames_per_entry);
        const frame_count = random.intRangeAtMost(
            usize,
            1,
            covered_frames,
        );
        var toc_storage: [32]u8 = @splat(0);
        var segment_sizes: [8]u32 = @splat(0);
        var stream_bytes: u32 = 0;
        for (0..entry_count) |entry_index| {
            const entry = random.intRangeAtMost(u32, 1, 127);
            segment_sizes[entry_index] = entry * scale;
            stream_bytes += segment_sizes[entry_index];
            for (0..entry_bytes) |byte_index| {
                const shift: u5 = @intCast(
                    (entry_bytes - byte_index - 1) * 8,
                );
                toc_storage[entry_index * entry_bytes + byte_index] =
                    @intCast(entry >> shift);
            }
        }
        const vbri = Vbri{
            .version = 1,
            .delay = 0,
            .quality = 0,
            .stream_bytes = stream_bytes,
            .frame_count = @intCast(frame_count),
            .toc_entries = @intCast(entry_count),
            .toc_scale = scale,
            .entry_bytes = @intCast(entry_bytes),
            .frames_per_entry = frames_per_entry,
            .toc = toc_storage[0 .. entry_count * entry_bytes],
        };
        for (0..frame_count + 1) |target_frame| {
            var expected: u32 = 0;
            if (target_frame == frame_count) {
                expected = stream_bytes;
            } else {
                const group =
                    target_frame / @as(usize, frames_per_entry);
                for (segment_sizes[0..group]) |segment_bytes| {
                    expected += segment_bytes;
                }
                expected += segment_sizes[group] *
                    @as(
                        u32,
                        @intCast(
                            target_frame %
                                @as(usize, frames_per_entry),
                        ),
                    ) /
                    frames_per_entry;
            }
            try std.testing.expectEqual(
                expected,
                try vbri.approximateByteOffsetForFrame(
                    @intCast(target_frame),
                ),
            );
        }
    }
}

test "encodes bounded VBRI metadata frames transactionally" {
    const header = try (EncoderConfig{
        .bitrate_kbps = 320,
        .channel_mode = .stereo,
    }).header(false);
    const toc = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var storage: [maximum_encoded_frame_bytes + 4]u8 =
        @splat(0xa5);
    for (1..5) |entry_bytes| {
        var width_toc: [8]u8 = @splat(0);
        width_toc[entry_bytes - 1] = 3;
        width_toc[entry_bytes * 2 - 1] = 5;
        const toc_bytes = width_toc[0 .. entry_bytes * 2];
        const encoded = try encodeVbriFrame(
            header,
            .{
                .delay = 17,
                .quality = 83,
                .stream_bytes = 16,
                .frame_count = 14,
                .toc_scale = 2,
                .entry_bytes = @intCast(entry_bytes),
                .frames_per_entry = 7,
                .toc = toc_bytes,
            },
            &storage,
        );
        try std.testing.expectEqual(
            header.frameBytes(),
            encoded.len,
        );
        try std.testing.expectEqualSlices(
            u8,
            &@as([4]u8, @splat(0xa5)),
            storage[encoded.len..][0..4],
        );
        const frame = try Frame.parse(encoded, 0);
        const vbri = frame.vbri orelse
            return error.TestMp3VbriMissing;
        try std.testing.expectEqual(@as(u16, 1), vbri.version);
        try std.testing.expectEqual(@as(u16, 17), vbri.delay);
        try std.testing.expectEqual(@as(u16, 83), vbri.quality);
        try std.testing.expectEqual(
            @as(u32, 16),
            vbri.stream_bytes,
        );
        try std.testing.expectEqual(
            @as(u32, 14),
            vbri.frame_count,
        );
        try std.testing.expectEqual(
            @as(u16, 2),
            vbri.toc_entries,
        );
        try std.testing.expectEqual(
            @as(u16, @intCast(entry_bytes)),
            vbri.entry_bytes,
        );
        try std.testing.expectEqual(
            @as(u16, 7),
            vbri.frames_per_entry,
        );
        try std.testing.expectEqualSlices(
            u8,
            toc_bytes,
            vbri.toc,
        );
    }

    var unchanged: [64]u8 = @splat(0x5a);
    const before = unchanged;
    const base = VbriEncoderMetadata{
        .quality = 1,
        .stream_bytes = 3,
        .frame_count = 2,
        .toc_scale = 1,
        .entry_bytes = 1,
        .frames_per_entry = 1,
        .toc = toc[0..2],
    };
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encodeVbriFrame(header, base, &unchanged),
    );
    try std.testing.expectEqual(before, unchanged);
    var invalid = base;
    invalid.entry_bytes = 0;
    try std.testing.expectError(
        error.InvalidVbriEntrySize,
        encodeVbriFrame(header, invalid, &storage),
    );
    invalid = base;
    invalid.toc_scale = 0;
    try std.testing.expectError(
        error.InvalidVbriTocScale,
        encodeVbriFrame(header, invalid, &storage),
    );
    invalid = base;
    invalid.frames_per_entry = 0;
    try std.testing.expectError(
        error.InvalidVbriFramesPerEntry,
        encodeVbriFrame(header, invalid, &storage),
    );
    invalid = base;
    invalid.entry_bytes = 3;
    try std.testing.expectError(
        error.InvalidVbriTocSize,
        encodeVbriFrame(header, invalid, &storage),
    );
    invalid = base;
    invalid.frame_count = 4;
    try std.testing.expectError(
        error.IncompleteVbriFrameCoverage,
        encodeVbriFrame(header, invalid, &storage),
    );
    invalid = base;
    invalid.stream_bytes = 2;
    try std.testing.expectError(
        error.InvalidVbriStreamBytes,
        encodeVbriFrame(header, invalid, &storage),
    );
    const zero_entry_toc = [_]u8{ 1, 0 };
    invalid = base;
    invalid.toc = &zero_entry_toc;
    try std.testing.expectError(
        error.InvalidVbriTocEntry,
        encodeVbriFrame(header, invalid, &storage),
    );
    var protected = header;
    protected.crc_present = true;
    try std.testing.expectError(
        error.UnsupportedProtectedVbriFrame,
        encodeVbriFrame(protected, base, &storage),
    );

    var offsets = [_]u64{ 0, 100, 230, 400 };
    try std.testing.expectEqual(
        @as(usize, 4),
        try requiredVbriTocBytes(4, 2, 2),
    );
    var built_storage: [8]u8 = @splat(0xa5);
    const built = try buildVbriToc(
        &offsets,
        4,
        600,
        2,
        10,
        2,
        &built_storage,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 23, 0, 37 },
        built,
    );
    try std.testing.expectEqualSlices(
        u8,
        &@as([4]u8, @splat(0xa5)),
        built_storage[4..],
    );
    var short_toc: [3]u8 = @splat(0x5a);
    const short_before = short_toc;
    try std.testing.expectError(
        error.InsufficientVbriTocStorage,
        buildVbriToc(
            &offsets,
            4,
            600,
            2,
            10,
            2,
            &short_toc,
        ),
    );
    try std.testing.expectEqual(short_before, short_toc);
    try std.testing.expectError(
        error.InexactVbriTocScale,
        buildVbriToc(
            &offsets,
            4,
            600,
            2,
            9,
            2,
            &built_storage,
        ),
    );
    try std.testing.expectError(
        error.VbriTocEntryOverflow,
        buildVbriToc(
            &offsets,
            4,
            600,
            2,
            1,
            1,
            &built_storage,
        ),
    );
    offsets[2] = 100;
    try std.testing.expectError(
        error.InvalidMp3VbrFrameOffsets,
        buildVbriToc(
            &offsets,
            4,
            600,
            2,
            1,
            2,
            &built_storage,
        ),
    );
    offsets[2] = 230;
    try std.testing.expectError(
        error.OverlappingMp3VbrStorage,
        buildVbriToc(
            &offsets,
            4,
            600,
            2,
            1,
            2,
            std.mem.sliceAsBytes(offsets[0..]),
        ),
    );
}

test "finalizes reserved VBRI stream metadata transactionally" {
    const config = EncoderConfig{
        .bitrate_kbps = 320,
        .sample_rate = 44_100,
        .channel_mode = .joint_stereo,
        .mode_extension = 3,
    };
    var encoder = try PcmStreamEncoder.init(config);
    var encoded: [maximum_encoded_frame_bytes * 6]u8 = undefined;
    var cursor: usize = 0;
    const metadata = try encoder.startGaplessMetadata(encoded[cursor..]);
    cursor += metadata.len;
    for (0..2) |_| {
        const frame = try encoder.append(
            .{ .channel_count = 2, .sample_count = 1152 },
            encoded[cursor..],
        );
        cursor += frame.len;
    }
    const finished = try encoder.finish(encoded[cursor..]);
    cursor += finished.frames.len;

    var offsets: [5]u64 = undefined;
    var toc_storage: [20]u8 = undefined;
    const finalized = try finalizeVbriStreamMetadata(
        encoded[0..cursor],
        81,
        1,
        1,
        4,
        &offsets,
        &toc_storage,
    );
    const summary = try Stream.summarize(encoded[0..cursor]);
    const vbri = summary.first_vbri orelse
        return error.TestMp3VbriMissing;
    try std.testing.expectEqual(summary.frame_count, finalized.frame_count);
    try std.testing.expectEqual(summary.audio_bytes, finalized.stream_bytes);
    try std.testing.expectEqual(@as(u16, 81), vbri.quality);
    try std.testing.expectEqual(finalized.frame_count, vbri.frame_count);
    try std.testing.expectEqual(finalized.stream_bytes, vbri.stream_bytes);
    try std.testing.expectEqual(@as(u64, 0), offsets[0]);
    try std.testing.expectEqual(
        finalized.stream_bytes,
        try vbri.approximateByteOffsetForFrame(vbri.frame_count),
    );
    const finalized_bytes = encoded;
    try std.testing.expectError(
        error.OverlappingMp3VbrStorage,
        finalizeVbriStreamMetadata(
            encoded[0..cursor],
            81,
            1,
            1,
            4,
            &offsets,
            encoded[0..toc_storage.len],
        ),
    );
    try std.testing.expectEqual(finalized_bytes, encoded);

    var no_reservation = try PcmStreamEncoder.init(config);
    var plain: [maximum_encoded_frame_bytes]u8 = undefined;
    const plain_frame = try no_reservation.append(
        .{ .channel_count = 2, .sample_count = 1152 },
        &plain,
    );
    var retained: [maximum_encoded_frame_bytes]u8 = undefined;
    @memcpy(retained[0..plain_frame.len], plain_frame);
    try std.testing.expectError(
        error.MissingReservedMp3MetadataFrame,
        finalizeVbriStreamMetadata(
            plain_frame,
            81,
            1,
            1,
            4,
            &offsets,
            &toc_storage,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        retained[0..plain_frame.len],
        plain_frame,
    );

    var protected_config = config;
    protected_config.crc_present = true;
    var protected_encoder = try PcmStreamEncoder.init(protected_config);
    var protected: [maximum_encoded_frame_bytes]u8 = undefined;
    const protected_metadata = try protected_encoder.startGaplessMetadata(
        &protected,
    );
    @memcpy(retained[0..protected_metadata.len], protected_metadata);
    try std.testing.expectError(
        error.UnsupportedProtectedVbriFrame,
        finalizeVbriStreamMetadata(
            protected_metadata,
            81,
            1,
            1,
            4,
            &offsets,
            &toc_storage,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        retained[0..protected_metadata.len],
        protected_metadata,
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
    try std.testing.expectError(
        error.InvalidMp3Limits,
        Stream.initWithLimits(storage[0..cursor], .{ .max_frames = 0 }),
    );
    try std.testing.expectError(
        error.Mp3StreamLimitExceeded,
        Stream.initWithLimits(storage[0..cursor], .{
            .max_stream_bytes = cursor - 1,
        }),
    );
    try std.testing.expectError(
        error.Mp3FrameLimitExceeded,
        Stream.summarizeWithLimits(storage[0..cursor], .{
            .max_stream_bytes = cursor,
            .max_frames = 2,
        }),
    );
    const limited_summary = try Stream.summarizeWithLimits(
        storage[0..cursor],
        .{ .max_stream_bytes = cursor, .max_frames = 3 },
    );
    try std.testing.expectEqual(@as(u64, 3), limited_summary.frame_count);

    var limited_stream = try Stream.initWithLimits(
        storage[0..cursor],
        .{ .max_stream_bytes = cursor, .max_frames = 2 },
    );
    _ = try limited_stream.next();
    _ = try limited_stream.next();
    const limited_before = limited_stream;
    try std.testing.expectError(
        error.Mp3FrameLimitExceeded,
        limited_stream.next(),
    );
    try std.testing.expectEqualDeep(limited_before, limited_stream);

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

    try std.testing.expectError(
        error.Mp3StreamLimitExceeded,
        FileReader.initWithLimits(std.testing.io, file, .{
            .max_stream_bytes = cursor - 1,
        }),
    );
    var limited_reader = try FileReader.initWithLimits(
        std.testing.io,
        file,
        .{ .max_stream_bytes = cursor, .max_frames = 2 },
    );
    var limited_storage: [maximum_free_format_frame_bytes]u8 = undefined;
    _ = try limited_reader.next(&limited_storage);
    _ = try limited_reader.next(&limited_storage);
    const limited_reader_before = limited_reader;
    try std.testing.expectError(
        error.Mp3FrameLimitExceeded,
        limited_reader.next(&limited_storage),
    );
    try std.testing.expectEqualDeep(limited_reader_before, limited_reader);

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
            .frame_index = 2,
            .sample_offset = 2304,
            .byte_offset = 14,
        }),
    );
    try std.testing.expectEqual(retained_offset, reader.offset);
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

test "transactional MP3 file iteration preserves state and destination" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [1000]u8 = undefined;
    const second_offset = try appendFrame(&encoded, 0, header);
    const encoded_bytes = try appendFrame(
        &encoded,
        second_offset,
        header,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional-iteration.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..encoded_bytes],
        0,
    );
    try file.setLength(std.testing.io, encoded_bytes);

    var reader = try FileReader.init(std.testing.io, file);
    const initial = reader;
    var short_destination: [100]u8 = @splat(0xa5);
    const short_before = short_destination;
    var scratch: [500]u8 = undefined;
    try std.testing.expectError(
        error.Mp3FrameBufferTooSmall,
        reader.nextTransactional(&short_destination, &scratch),
    );
    try std.testing.expectEqualDeep(initial, reader);
    try std.testing.expectEqual(short_before, short_destination);

    var destination: [500]u8 = @splat(0x5a);
    var short_scratch: [100]u8 = undefined;
    const destination_before = destination;
    try std.testing.expectError(
        error.Mp3FrameBufferTooSmall,
        reader.nextTransactional(&destination, &short_scratch),
    );
    try std.testing.expectEqualDeep(initial, reader);
    try std.testing.expectEqual(destination_before, destination);

    var aliased: [600]u8 = @splat(0x3c);
    const aliased_before = aliased;
    try std.testing.expectError(
        error.OverlappingMp3FileReaderBuffers,
        reader.nextTransactional(
            aliased[0..500],
            aliased[100..600],
        ),
    );
    try std.testing.expectEqualDeep(initial, reader);
    try std.testing.expectEqual(aliased_before, aliased);

    const first = (try reader.nextTransactional(
        &destination,
        &scratch,
    )).?;
    try std.testing.expectEqual(@as(u64, 0), first.byte_offset);
    try std.testing.expectEqual(second_offset, first.bytes.len);
    try std.testing.expectEqual(
        @intFromPtr(destination[0..].ptr),
        @intFromPtr(first.bytes.ptr),
    );
    try std.testing.expectEqualSlices(
        u8,
        encoded[0..second_offset],
        first.bytes,
    );

    const after_first = reader;
    destination = @splat(0x6b);
    const truncated_destination = destination;
    try file.setLength(
        std.testing.io,
        second_offset + 100,
    );
    try std.testing.expectError(
        error.TruncatedMp3File,
        reader.nextTransactional(&destination, &scratch),
    );
    try std.testing.expectEqualDeep(after_first, reader);
    try std.testing.expectEqual(truncated_destination, destination);
}

test "transactional MP3 file iteration rebinds VBRI storage" {
    const header = try (EncoderConfig{
        .bitrate_kbps = 320,
        .channel_mode = .stereo,
    }).header(false);
    const toc = [_]u8{ 3, 5 };
    var encoded: [maximum_encoded_frame_bytes]u8 = undefined;
    const frame = try encodeVbriFrame(
        header,
        .{
            .delay = 17,
            .quality = 83,
            .stream_bytes = 16,
            .frame_count = 2,
            .toc_scale = 2,
            .entry_bytes = 1,
            .frames_per_entry = 1,
            .toc = &toc,
        },
        &encoded,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional-vbri.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, frame, 0);
    try file.setLength(std.testing.io, frame.len);

    var reader = try FileReader.init(std.testing.io, file);
    var destination: [maximum_encoded_frame_bytes]u8 = @splat(0xa5);
    var scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    const published = (try reader.nextTransactional(
        &destination,
        &scratch,
    )).?;
    const vbri = published.vbri orelse return error.TestMp3VbriMissing;
    try std.testing.expectEqualSlices(u8, &toc, vbri.toc);
    const destination_start = @intFromPtr(destination[0..].ptr);
    const destination_end = destination_start + published.bytes.len;
    const toc_start = @intFromPtr(vbri.toc.ptr);
    try std.testing.expect(toc_start >= destination_start);
    try std.testing.expect(toc_start + vbri.toc.len <= destination_end);

    const finished = reader;
    const destination_before = destination;
    try std.testing.expect(
        try reader.nextTransactional(&destination, &scratch) == null,
    );
    try std.testing.expectEqualDeep(finished, reader);
    try std.testing.expectEqual(destination_before, destination);
}

test "MP3 file seeking rejects malformed complete frames transactionally" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    const protected_header = testHeader(
        3,
        false,
        9,
        0,
        false,
        .stereo,
    );
    var encoded: [2200]u8 = undefined;
    var cursor = try appendFrame(&encoded, 0, header);
    const malformed_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    const metadata_offset = malformed_offset + 4 + 32;
    @memcpy(encoded[metadata_offset..][0..4], "Xing");
    encoded[metadata_offset + 7] = 0x10;
    const invalid_crc_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, protected_header);
    const invalid_crc_frame = try Frame.parse(
        encoded[0..cursor],
        invalid_crc_offset,
    );
    try std.testing.expectEqual(
        @as(?bool, false),
        try invalid_crc_frame.crcValid(),
    );
    const invalid_side_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    setTestBits(
        encoded[invalid_side_offset + 4 .. invalid_side_offset + 36],
        32,
        9,
        511,
    );
    try std.testing.expectError(
        error.InvalidMp3BigValues,
        (try Frame.parse(
            encoded[0..cursor],
            invalid_side_offset,
        )).sideInformation(),
    );
    const valid_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "seek-validation.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    const retained = reader;

    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = 1,
            .sample_offset = 1152,
            .byte_offset = malformed_offset,
        }),
    );
    try std.testing.expectEqualDeep(retained, reader);
    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = 2,
            .sample_offset = 2304,
            .byte_offset = invalid_crc_offset,
        }),
    );
    try std.testing.expectEqualDeep(retained, reader);
    try std.testing.expectError(
        error.InvalidMp3SeekPoint,
        reader.seek(.{
            .frame_index = 3,
            .sample_offset = 3456,
            .byte_offset = invalid_side_offset,
        }),
    );
    try std.testing.expectEqualDeep(retained, reader);

    try reader.seek(.{
        .frame_index = 4,
        .sample_offset = 4608,
        .byte_offset = valid_offset,
    });
    try std.testing.expectEqual(
        @as(u64, @intCast(valid_offset)),
        reader.offset,
    );
    var frame_storage: [500]u8 = undefined;
    _ = try reader.next(&frame_storage);
    try std.testing.expect((try reader.next(&frame_storage)) == null);
}

test "MP3 readers resynchronize across bounded junk transactionally" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    const junk = [_]u8{ 0x00, 0x49, 0x44, 0x33, 0x7f };
    var encoded: [1400]u8 = undefined;
    var cursor = try appendFrame(&encoded, 0, header);
    const junk_offset = cursor;
    @memcpy(encoded[cursor..][0..junk.len], &junk);
    cursor += junk.len;
    const recovered_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    cursor = try appendFrame(&encoded, cursor, header);

    var stream = try Stream.init(encoded[0..cursor]);
    _ = try stream.next();
    try std.testing.expectEqual(junk_offset, stream.cursor);
    const retained_stream = stream;
    try std.testing.expectError(
        error.InvalidMp3Sync,
        stream.next(),
    );
    try std.testing.expectEqual(retained_stream.cursor, stream.cursor);
    try std.testing.expectError(
        error.InvalidMp3ResynchronizationLimit,
        stream.resynchronize(0),
    );
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        stream.resynchronize(junk.len - 1),
    );
    try std.testing.expectEqual(retained_stream.cursor, stream.cursor);
    try std.testing.expectEqual(
        junk.len,
        try stream.resynchronize(junk.len),
    );
    try std.testing.expectEqual(recovered_offset, stream.cursor);
    _ = try stream.next();
    _ = try stream.next();
    try std.testing.expect((try stream.next()) == null);
    try std.testing.expectEqual(@as(u64, 3), stream.frame_index);
    try std.testing.expectEqual(@as(u64, 3456), stream.sample_offset);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "resynchronized.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    var frame_storage: [500]u8 = undefined;
    _ = try reader.next(&frame_storage);
    try std.testing.expectEqual(junk_offset, reader.offset);
    const retained_reader = reader;
    try std.testing.expectError(
        error.InvalidMp3Sync,
        reader.next(&frame_storage),
    );
    try std.testing.expectEqual(retained_reader.offset, reader.offset);
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        reader.resynchronize(junk.len - 1),
    );
    try std.testing.expectEqual(retained_reader.offset, reader.offset);
    try std.testing.expectEqual(
        junk.len,
        try reader.resynchronize(junk.len),
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(recovered_offset)),
        reader.offset,
    );
    _ = try reader.next(&frame_storage);
    _ = try reader.next(&frame_storage);
    try std.testing.expect(
        (try reader.next(&frame_storage)) == null,
    );
    try std.testing.expectEqual(@as(u64, 3), reader.frame_index);
    try std.testing.expectEqual(@as(u64, 3456), reader.sample_offset);

    reader.audio_start = reader.audio_end + 1;
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        reader.resynchronize(1),
    );
}

test "MP3 readers skip malformed metadata frames while resynchronizing" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [2000]u8 = undefined;
    var cursor = try appendFrame(&encoded, 0, header);
    const damaged_offset = cursor;
    encoded[cursor] = 0;
    cursor += 1;
    const malformed_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    const metadata_offset = malformed_offset + 4 + 32;
    @memcpy(encoded[metadata_offset..][0..4], "Xing");
    encoded[metadata_offset + 7] = 0x10;
    const malformed_vbri_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    const vbri_offset = malformed_vbri_offset + 4 + 32;
    @memcpy(encoded[vbri_offset..][0..4], "VBRI");
    try std.testing.expectError(
        error.UnsupportedVbriVersion,
        Frame.parse(encoded[0..cursor], malformed_vbri_offset),
    );
    const recovered_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    const required_skip = recovered_offset - damaged_offset;

    var stream = try Stream.init(encoded[0..cursor]);
    _ = try stream.next();
    const retained_stream = stream;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        stream.resynchronize(required_skip - 1),
    );
    try std.testing.expectEqual(retained_stream.cursor, stream.cursor);
    try std.testing.expectEqual(
        required_skip,
        try stream.resynchronize(required_skip),
    );
    try std.testing.expectEqual(recovered_offset, stream.cursor);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "metadata-resynchronized.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    var frame_storage: [500]u8 = undefined;
    _ = try reader.next(&frame_storage);
    const retained_reader = reader;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        reader.resynchronize(required_skip - 1),
    );
    try std.testing.expectEqual(retained_reader.offset, reader.offset);
    try std.testing.expectEqual(
        @as(u64, @intCast(required_skip)),
        try reader.resynchronize(required_skip),
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(recovered_offset)),
        reader.offset,
    );
    _ = try reader.next(&frame_storage);
    try std.testing.expect((try reader.next(&frame_storage)) == null);
}

test "MP3 readers skip invalid protected and side-information frames while resynchronizing" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    const protected_header = testHeader(
        3,
        false,
        9,
        0,
        false,
        .stereo,
    );
    var encoded: [2000]u8 = undefined;
    var cursor = try appendFrame(&encoded, 0, header);
    const damaged_offset = cursor;
    encoded[cursor] = 0;
    cursor += 1;
    const invalid_crc_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, protected_header);
    const invalid_crc_frame = try Frame.parse(
        encoded[0..cursor],
        invalid_crc_offset,
    );
    try std.testing.expectEqual(
        @as(?bool, false),
        try invalid_crc_frame.crcValid(),
    );
    const invalid_side_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    setTestBits(
        encoded[invalid_side_offset + 4 .. invalid_side_offset + 36],
        32,
        9,
        511,
    );
    try std.testing.expectError(
        error.InvalidMp3BigValues,
        (try Frame.parse(
            encoded[0..cursor],
            invalid_side_offset,
        )).sideInformation(),
    );
    const recovered_offset = cursor;
    cursor = try appendFrame(&encoded, cursor, header);
    const required_skip = recovered_offset - damaged_offset;

    var stream = try Stream.init(encoded[0..cursor]);
    _ = try stream.next();
    const retained_stream = stream;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        stream.resynchronize(required_skip - 1),
    );
    try std.testing.expectEqual(retained_stream.cursor, stream.cursor);
    try std.testing.expectEqual(
        required_skip,
        try stream.resynchronize(required_skip),
    );
    try std.testing.expectEqual(recovered_offset, stream.cursor);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "crc-resynchronized.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, encoded[0..cursor], 0);
    var reader = try FileReader.init(std.testing.io, file);
    var frame_storage: [500]u8 = undefined;
    _ = try reader.next(&frame_storage);
    const retained_reader = reader;
    try std.testing.expectError(
        error.Mp3ResynchronizationLimitReached,
        reader.resynchronize(required_skip - 1),
    );
    try std.testing.expectEqual(retained_reader.offset, reader.offset);
    try std.testing.expectEqual(
        @as(u64, @intCast(required_skip)),
        try reader.resynchronize(required_skip),
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(recovered_offset)),
        reader.offset,
    );
    _ = try reader.next(&frame_storage);
    try std.testing.expect((try reader.next(&frame_storage)) == null);
}

test "MP3 stream contains deterministic frame mutations" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var baseline: [1000]u8 = undefined;
    const second_offset = try appendFrame(&baseline, 0, header);
    const encoded_bytes = try appendFrame(
        &baseline,
        second_offset,
        header,
    );

    for (second_offset..encoded_bytes) |byte_index| {
        for ([_]u8{ 0x01, 0x80, 0xff }) |mask| {
            var candidate = baseline;
            candidate[byte_index] ^= mask;
            var stream = try Stream.init(candidate[0..encoded_bytes]);
            _ = try stream.next();
            const retained = stream;
            if (stream.next()) |frame| {
                if (frame) |accepted| {
                    try std.testing.expect(accepted.bytes.len >= 4);
                    try std.testing.expect(stream.cursor <= stream.audio_end);
                    try std.testing.expectEqual(
                        @as(u64, 2),
                        stream.frame_index,
                    );
                } else {
                    try std.testing.expectEqual(
                        stream.audio_end,
                        stream.cursor,
                    );
                }
            } else |_| {
                try std.testing.expectEqual(retained.cursor, stream.cursor);
                try std.testing.expectEqual(
                    retained.first_header,
                    stream.first_header,
                );
                try std.testing.expectEqual(
                    retained.frame_index,
                    stream.frame_index,
                );
                try std.testing.expectEqual(
                    retained.sample_offset,
                    stream.sample_offset,
                );
                try std.testing.expectEqual(
                    retained.free_frame_base_bytes,
                    stream.free_frame_base_bytes,
                );
            }
        }
    }

    for (second_offset + 1..encoded_bytes) |prefix_bytes| {
        var stream = try Stream.init(baseline[0..prefix_bytes]);
        _ = try stream.next();
        const retained = stream;
        if (stream.next()) |frame| {
            if (frame) |_| {
                try std.testing.expect(stream.cursor <= stream.audio_end);
            } else {
                try std.testing.expectEqual(
                    stream.audio_end,
                    stream.cursor,
                );
            }
        } else |_| {
            try std.testing.expectEqual(retained.cursor, stream.cursor);
            try std.testing.expectEqual(
                retained.first_header,
                stream.first_header,
            );
            try std.testing.expectEqual(
                retained.frame_index,
                stream.frame_index,
            );
            try std.testing.expectEqual(
                retained.sample_offset,
                stream.sample_offset,
            );
            try std.testing.expectEqual(
                retained.free_frame_base_bytes,
                stream.free_frame_base_bytes,
            );
        }
    }
}

test "MP3 file reader contains deterministic frame mutations" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var baseline: [1000]u8 = undefined;
    const second_offset = try appendFrame(&baseline, 0, header);
    const encoded_bytes = try appendFrame(
        &baseline,
        second_offset,
        header,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "mutated-framing.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var frame_storage: [500]u8 = undefined;
    var frame_scratch: [500]u8 = undefined;

    for (second_offset..encoded_bytes) |byte_index| {
        for ([_]u8{ 0x01, 0x80, 0xff }) |mask| {
            var candidate = baseline;
            candidate[byte_index] ^= mask;
            try file.setLength(std.testing.io, encoded_bytes);
            try file.writePositionalAll(
                std.testing.io,
                candidate[0..encoded_bytes],
                0,
            );

            var reader = try FileReader.init(std.testing.io, file);
            _ = try reader.next(&frame_scratch);
            const retained = reader;
            frame_storage = @splat(0xa5);
            const storage_before = frame_storage;
            if (reader.nextTransactional(
                &frame_storage,
                &frame_scratch,
            )) |frame| {
                if (frame) |accepted| {
                    try std.testing.expect(accepted.bytes.len >= 4);
                    try std.testing.expect(reader.offset <= reader.audio_end);
                    try std.testing.expectEqual(
                        @as(u64, 2),
                        reader.frame_index,
                    );
                    try std.testing.expect(reader.valid());
                } else {
                    try std.testing.expectEqual(
                        reader.audio_end,
                        reader.offset,
                    );
                    try std.testing.expectEqual(
                        storage_before,
                        frame_storage,
                    );
                }
            } else |_| {
                try std.testing.expectEqualDeep(retained, reader);
                try std.testing.expectEqual(
                    storage_before,
                    frame_storage,
                );
            }
        }
    }

    for (second_offset + 1..encoded_bytes) |prefix_bytes| {
        try file.setLength(std.testing.io, encoded_bytes);
        try file.writePositionalAll(
            std.testing.io,
            baseline[0..encoded_bytes],
            0,
        );
        try file.setLength(std.testing.io, prefix_bytes);

        var reader = try FileReader.init(std.testing.io, file);
        _ = try reader.next(&frame_scratch);
        const retained = reader;
        frame_storage = @splat(0x5a);
        const storage_before = frame_storage;
        if (reader.nextTransactional(
            &frame_storage,
            &frame_scratch,
        )) |frame| {
            if (frame) |_| {
                try std.testing.expect(reader.offset <= reader.audio_end);
            } else {
                try std.testing.expectEqual(
                    reader.audio_end,
                    reader.offset,
                );
                try std.testing.expectEqual(
                    storage_before,
                    frame_storage,
                );
            }
        } else |_| {
            try std.testing.expectEqualDeep(retained, reader);
            try std.testing.expectEqual(
                storage_before,
                frame_storage,
            );
        }
    }
}

test "MP3 readers reject malformed retained counters transactionally" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [500]u8 = undefined;
    const encoded_bytes = try appendFrame(&encoded, 0, header);

    var stream = try Stream.init(encoded[0..encoded_bytes]);
    try std.testing.expect(stream.valid());
    stream.frame_index = std.math.maxInt(u64);
    try std.testing.expect(!stream.valid());
    try std.testing.expectError(
        error.InvalidMp3StreamState,
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
    try std.testing.expect(!stream.valid());
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        stream.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), stream.cursor);
    try std.testing.expect(stream.first_header == null);
    try std.testing.expectEqual(@as(u64, 0), stream.frame_index);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        stream.sample_offset,
    );

    var impossible_stream_progress =
        try Stream.init(encoded[0..encoded_bytes]);
    _ = try impossible_stream_progress.next();
    impossible_stream_progress.cursor =
        impossible_stream_progress.audio_start;
    const impossible_stream_progress_before = impossible_stream_progress;
    try std.testing.expect(!impossible_stream_progress.valid());
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        impossible_stream_progress.next(),
    );
    try std.testing.expectEqualDeep(
        impossible_stream_progress_before,
        impossible_stream_progress,
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
    try std.testing.expect(reader.valid());
    var frame_storage: [500]u8 = @splat(0xaa);
    var impossible_file_progress = reader;
    impossible_file_progress.frame_index = 1;
    impossible_file_progress.sample_offset = 1152;
    const impossible_file_progress_before = impossible_file_progress;
    try std.testing.expect(!impossible_file_progress.valid());
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        impossible_file_progress.next(&frame_storage),
    );
    try std.testing.expectEqualDeep(
        impossible_file_progress_before,
        impossible_file_progress,
    );
    const original_storage = frame_storage;
    reader.frame_index = std.math.maxInt(u64);
    try std.testing.expect(!reader.valid());
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
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
    try std.testing.expect(!reader.valid());
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
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
    try std.testing.expect(stream.valid());
    stream.audio_end = stream.encoded.len + 1;
    try std.testing.expect(!stream.valid());
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        stream.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), stream.cursor);

    stream.audio_end = stream.encoded.len;
    stream.audio_start = 1;
    try std.testing.expect(!stream.valid());
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
    try std.testing.expect(reader.valid());
    const original_offset = reader.offset;
    reader.audio_start = original_offset + 1;
    try std.testing.expect(!reader.valid());
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
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        reader.seek(.{
            .frame_index = 0,
            .sample_offset = 0,
            .byte_offset = original_offset,
        }),
    );
    try std.testing.expectEqual(original_offset, reader.offset);
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

test "transactional MP3 file seek index preserves destination" {
    const header = testHeader(3, true, 9, 0, false, .stereo);
    var encoded: [1300]u8 = undefined;
    var encoded_bytes = try appendFrame(&encoded, 0, header);
    encoded_bytes = try appendFrame(&encoded, encoded_bytes, header);
    encoded_bytes = try appendFrame(&encoded, encoded_bytes, header);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional-index.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..encoded_bytes],
        0,
    );
    try file.setLength(std.testing.io, encoded_bytes);

    var frame_storage: [500]u8 = undefined;
    var expected_storage: [3]SeekPoint = undefined;
    const expected = try buildFileSeekIndex(
        std.testing.io,
        file,
        &frame_storage,
        1,
        &expected_storage,
    );
    var destination: [3]SeekPoint = undefined;
    var index_scratch: [3]SeekPoint = undefined;
    const index = try buildFileSeekIndexTransactional(
        std.testing.io,
        file,
        &frame_storage,
        1,
        &destination,
        &index_scratch,
    );
    try std.testing.expectEqualSlices(SeekPoint, expected, index);
    try std.testing.expectEqual(
        @intFromPtr(destination[0..].ptr),
        @intFromPtr(index.ptr),
    );

    const sentinel = SeekPoint{
        .frame_index = 99,
        .sample_offset = 99,
        .byte_offset = 99,
    };
    var short_destination = [_]SeekPoint{sentinel};
    const short_destination_before = short_destination;
    try std.testing.expectError(
        error.Mp3SeekIndexTooSmall,
        buildFileSeekIndexTransactional(
            std.testing.io,
            file,
            &frame_storage,
            1,
            &short_destination,
            &index_scratch,
        ),
    );
    try std.testing.expectEqual(
        short_destination_before,
        short_destination,
    );

    destination = @splat(sentinel);
    const destination_before = destination;
    var short_scratch: [2]SeekPoint = undefined;
    try std.testing.expectError(
        error.Mp3SeekIndexTooSmall,
        buildFileSeekIndexTransactional(
            std.testing.io,
            file,
            &frame_storage,
            1,
            &destination,
            &short_scratch,
        ),
    );
    try std.testing.expectEqual(destination_before, destination);

    var aliased = [_]SeekPoint{sentinel} ** 4;
    const aliased_before = aliased;
    try std.testing.expectError(
        error.OverlappingMp3SeekStorage,
        buildFileSeekIndexTransactional(
            std.testing.io,
            file,
            &frame_storage,
            1,
            aliased[0..3],
            aliased[1..4],
        ),
    );
    try std.testing.expectEqual(aliased_before, aliased);

    var aliased_frame_storage: [500]u8 align(@alignOf(SeekPoint)) =
        undefined;
    const frame_aliased_scratch = std.mem.bytesAsSlice(
        SeekPoint,
        aliased_frame_storage[0 .. 3 * @sizeOf(SeekPoint)],
    );
    destination = @splat(sentinel);
    const frame_alias_destination_before = destination;
    try std.testing.expectError(
        error.OverlappingMp3SeekStorage,
        buildFileSeekIndexTransactional(
            std.testing.io,
            file,
            &aliased_frame_storage,
            1,
            &destination,
            frame_aliased_scratch,
        ),
    );
    try std.testing.expectEqual(
        frame_alias_destination_before,
        destination,
    );

    destination = @splat(sentinel);
    const truncated_before = destination;
    try file.setLength(std.testing.io, encoded_bytes - 1);
    try std.testing.expectError(
        error.TruncatedMp3Frame,
        buildFileSeekIndexTransactional(
            std.testing.io,
            file,
            &frame_storage,
            1,
            &destination,
            &index_scratch,
        ),
    );
    try std.testing.expectEqual(truncated_before, destination);
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

test "classifies MP3 encoder block transitions transactionally" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .stereo),
    );
    var classifier = EncoderBlockClassifier{};
    try std.testing.expect(classifier.valid());
    var pcm = PcmFrame{
        .channel_count = 2,
        .sample_count = 1152,
    };
    pcm.channels[0][192] = 1;
    pcm.channels[0][576 + 192] = 1;
    const first = try classifier.classify(header, pcm);
    try std.testing.expectEqual(@as(u2, 1), first[0][0].block_type);
    try std.testing.expectEqual(@as(u2, 2), first[1][0].block_type);
    try std.testing.expectEqual(GranuleChannel{}, first[0][1]);
    try std.testing.expectEqual(GranuleChannel{}, first[1][1]);
    try std.testing.expect(classifier.short_active[0]);
    try std.testing.expect(classifier.valid());

    const silence = PcmFrame{
        .channel_count = 2,
        .sample_count = 1152,
    };
    const second = try classifier.classify(header, silence);
    try std.testing.expectEqual(@as(u2, 3), second[0][0].block_type);
    try std.testing.expectEqual(GranuleChannel{}, second[1][0]);
    try std.testing.expect(!classifier.short_active[0]);

    classifier.attack_ratio = 1;
    const before = classifier;
    try std.testing.expect(!classifier.valid());
    try std.testing.expectError(
        error.InvalidMp3EncoderAttackRatio,
        classifier.classify(header, silence),
    );
    try std.testing.expectEqual(before, classifier);
    classifier.attack_ratio = 8;
    try std.testing.expect(classifier.valid());
    var malformed = silence;
    malformed.channels[0][0] = std.math.nan(f32);
    const before_malformed = classifier;
    try std.testing.expectError(
        error.InvalidMp3EncoderPcmSample,
        classifier.classify(header, malformed),
    );
    try std.testing.expectEqual(before_malformed, classifier);

    var joint_header = header;
    joint_header.channel_mode = .joint_stereo;
    var joint_classifier = EncoderBlockClassifier{};
    const joint = try joint_classifier.classify(
        joint_header,
        pcm,
    );
    try std.testing.expectEqual(
        joint[0][0],
        joint[0][1],
    );
    try std.testing.expectEqual(
        joint[1][0],
        joint[1][1],
    );
    try std.testing.expectEqual(
        joint_classifier.short_active[0],
        joint_classifier.short_active[1],
    );
}

test "prepares MP3 mid-side encoder spectra transactionally" {
    var header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .joint_stereo),
    );
    header.mode_extension = 2;
    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 2,
        .granule_count = 2,
    };
    for (0..2) |granule| {
        analyzed.granules[granule][0].spectrum.lines[0] = 3;
        analyzed.granules[granule][1].spectrum.lines[0] = 1;
    }
    const prepared = try prepareEncoderStereo(
        header,
        analyzed,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 2 * @sqrt(2.0)),
        prepared.granules[0][0].spectrum.lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @sqrt(2.0)),
        prepared.granules[0][1].spectrum.lines[0],
        1e-6,
    );
    const restored = try processStereo(
        header,
        @splat(.{}),
        @splat(.{ .value_count = 22 }),
        .{
            prepared.granules[0][0].spectrum,
            prepared.granules[0][1].spectrum,
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 3),
        restored.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1),
        restored.channels[1].lines[0],
        1e-6,
    );

    var mismatched = analyzed;
    mismatched.granules[0][1].description = .{
        .window_switching = true,
        .block_type = 1,
    };
    try std.testing.expectError(
        error.InvalidMp3EncoderStereoBlocks,
        prepareEncoderStereo(header, mismatched),
    );
    var malformed = analyzed;
    malformed.granules[0][0].spectrum.lines[0] =
        std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        prepareEncoderStereo(header, malformed),
    );
    header.mode_extension = 0;
    try std.testing.expectEqual(
        analyzed,
        try prepareEncoderStereo(header, analyzed),
    );
}

test "prepares MP3 intensity stereo above the joint-stereo cutoff" {
    var header = try Header.parse(
        &testHeader(3, true, 11, 0, false, .joint_stereo),
    );
    header.mode_extension = 3;
    const bands = try scaleFactorBands(header);
    const intensity_line = bands.long_starts[14];
    const gains = mpeg1IntensityGains(2);
    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 2,
        .granule_count = 2,
    };
    for (0..2) |granule| {
        analyzed.granules[granule][0].spectrum.lines[0] = 3;
        analyzed.granules[granule][1].spectrum.lines[0] = 1;
        analyzed.granules[granule][0]
            .spectrum.lines[intensity_line] = 2 * gains[0];
        analyzed.granules[granule][1]
            .spectrum.lines[intensity_line] = 2 * gains[1];
    }

    const prepared = try prepareEncoderStereo(header, analyzed);
    try std.testing.expect(
        prepared.granules[0][1].intensity_enabled[14],
    );
    try std.testing.expectEqual(
        @as(u8, 2),
        prepared.granules[0][1].intensity_positions[14],
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        prepared.granules[0][1].spectrum.lines[intensity_line],
    );

    var factors: [2]ScaleFactorChannel =
        @splat(.{ .value_count = 22 });
    for (0..22) |band|
        factors[1].values[band] =
            prepared.granules[0][1].intensity_positions[band];
    const restored = try processStereo(
        header,
        @splat(.{}),
        factors,
        .{
            prepared.granules[0][0].spectrum,
            prepared.granules[0][1].spectrum,
        },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 3),
        restored.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1),
        restored.channels[1].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        2 * gains[0],
        restored.channels[0].lines[intensity_line],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        2 * gains[1],
        restored.channels[1].lines[intensity_line],
        1e-6,
    );

    var malformed = prepared;
    malformed.granules[0][1].intensity_positions[14] = 7;
    try std.testing.expectError(
        error.InvalidMp3EncoderIntensityStereo,
        EncoderQuantizer.quantize(header, malformed),
    );
    malformed = prepared;
    malformed.granules[0][0].intensity_enabled[14] = true;
    try std.testing.expectError(
        error.InvalidMp3EncoderIntensityStereo,
        EncoderQuantizer.quantize(header, malformed),
    );
}

test "prepares short and low-rate MP3 intensity stereo layouts" {
    const header_bytes = [_][4]u8{
        testHeader(3, true, 11, 0, false, .joint_stereo),
        testHeader(2, true, 8, 0, false, .joint_stereo),
        testHeader(0, true, 8, 0, false, .joint_stereo),
    };
    const descriptions = [_]GranuleChannel{
        .{
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
    };
    for (header_bytes) |bytes| {
        var header = try Header.parse(&bytes);
        header.mode_extension = 1;
        const granule_count: u2 =
            if (header.version == .mpeg1) 2 else 1;
        const bands = try scaleFactorBands(header);
        const line: usize = 3 * bands.short_starts[8];
        const gains = encoderIntensityGains(header, 2);
        for (descriptions) |description| {
            const layout = try encoderBandLayout(
                header,
                description,
            );
            const factor_index =
                encoderIntensityStartBand(description, layout);
            var analyzed = AnalyzedEncoderFrame{
                .channel_count = 2,
                .granule_count = granule_count,
            };
            for (0..granule_count) |granule| {
                analyzed.granules[granule][0].description =
                    description;
                analyzed.granules[granule][1].description =
                    description;
                analyzed.granules[granule][0]
                    .spectrum.lines[line] = 2 * gains[0];
                analyzed.granules[granule][1]
                    .spectrum.lines[line] = 2 * gains[1];
            }
            const prepared =
                try prepareEncoderStereo(header, analyzed);
            try std.testing.expect(
                prepared.granules[0][1]
                    .intensity_enabled[factor_index],
            );
            try std.testing.expectEqual(
                @as(u8, 2),
                prepared.granules[0][1]
                    .intensity_positions[factor_index],
            );
            try std.testing.expectEqual(
                @as(f32, 0),
                prepared.granules[0][1].spectrum.lines[line],
            );

            const factor_count =
                scaleFactorValueCount(header, description);
            var factors: [2]ScaleFactorChannel =
                @splat(.{});
            factors[0].value_count = factor_count;
            factors[1].value_count = factor_count;
            for (0..factor_count) |band|
                factors[1].values[band] =
                    prepared.granules[0][1]
                        .intensity_positions[band];
            const restored = try processStereo(
                header,
                @splat(description),
                factors,
                .{
                    prepared.granules[0][0].spectrum,
                    prepared.granules[0][1].spectrum,
                },
            );
            try std.testing.expectApproxEqAbs(
                2 * gains[0],
                restored.channels[0].lines[line],
                1e-6,
            );
            try std.testing.expectApproxEqAbs(
                2 * gains[1],
                restored.channels[1].lines[line],
                1e-6,
            );
        }
    }
}

test "analyzes bounded MP3 psychoacoustic bands" {
    const headers = [_]Header{
        try Header.parse(
            &testHeader(3, true, 9, 0, false, .mono),
        ),
        try Header.parse(
            &testHeader(0, true, 9, 2, false, .mono),
        ),
    };
    const descriptions = [_]GranuleChannel{
        .{},
        .{
            .window_switching = true,
            .block_type = 2,
        },
        .{
            .window_switching = true,
            .block_type = 2,
            .mixed_block = true,
        },
    };
    const model = EncoderPsychoacousticModel{};
    for (headers) |header| {
        for (descriptions) |description| {
            var channel = AnalyzedEncoderChannel{
                .description = description,
            };
            channel.spectrum.lines[0] = 2;
            channel.spectrum.lines[1] = -1;
            channel.spectrum.lines[40] = 0.25;
            const analyzed = try model.analyze(header, channel);
            const layout = try encoderBandLayout(
                header,
                description,
            );
            try std.testing.expectEqual(
                layout.band_count,
                analyzed.band_count,
            );
            try std.testing.expect(analyzed.energy[0] > 0);
            for (analyzed.threshold[0..analyzed.band_count]) |value|
                try std.testing.expect(
                    std.math.isFinite(value) and value > 0,
                );
            for (analyzed.energy[analyzed.band_count..]) |value|
                try std.testing.expectEqual(@as(f32, 0), value);
        }
    }

    var invalid_model = model;
    invalid_model.config.masking_ratio = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3EncoderPsychoacousticConfig,
        invalid_model.analyze(headers[0], .{}),
    );
    var malformed = AnalyzedEncoderChannel{};
    malformed.spectrum.lines[0] = std.math.inf(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        model.analyze(headers[0], malformed),
    );
    const invalid_quantizer = EncoderQuantizer{
        .psychoacoustics = invalid_model,
    };
    const invalid_frame = AnalyzedEncoderFrame{
        .channel_count = 1,
        .granule_count = 2,
    };
    try std.testing.expectError(
        error.InvalidMp3EncoderPsychoacousticConfig,
        invalid_quantizer.process(headers[0], invalid_frame),
    );
}

test "MP3 psychoacoustics distinguish tonal and noise-like bands" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    const layout = try encoderBandLayout(header, .{});
    const line_count =
        layout.starts[1] - layout.starts[0];
    try std.testing.expect(line_count > 1);

    var tonal = AnalyzedEncoderChannel{};
    tonal.spectrum.lines[layout.starts[0]] =
        @sqrt(@as(f32, @floatFromInt(line_count)));
    var noise = AnalyzedEncoderChannel{};
    for (
        noise.spectrum.lines[layout.starts[0]..layout.starts[1]],
    ) |*line|
        line.* = 1.0;

    const model = EncoderPsychoacousticModel{
        .config = .{ .tonal_masking_reduction = 0.5 },
    };
    const tonal_result = try model.analyze(header, tonal);
    const noise_result = try model.analyze(header, noise);
    try std.testing.expectApproxEqAbs(
        tonal_result.energy[0],
        noise_result.energy[0],
        0.000_001,
    );
    try std.testing.expect(
        tonal_result.tonality[0] >
            noise_result.tonality[0] + 0.9,
    );
    try std.testing.expect(
        tonal_result.threshold[0] <
            noise_result.threshold[0],
    );
}

test "MP3 psychoacoustic timeline applies forward masking transactionally" {
    const header = try Header.parse(
        &testHeader(3, true, 9, 0, false, .mono),
    );
    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 1,
        .granule_count = 2,
    };
    analyzed.granules[0][0].spectrum.lines[0] = 10.0;
    analyzed.granules[1][0].spectrum.lines[0] = 0.001;
    var timeline = EncoderPsychoacousticTimeline{
        .model = .{
            .config = .{ .forward_masking_ratio = 0.1 },
        },
    };
    try std.testing.expect(timeline.valid());
    const result = try timeline.analyzeFrame(header, analyzed);
    try std.testing.expect(timeline.valid());
    try std.testing.expect(
        result[1][0].threshold[0] >=
            result[0][0].energy[0] * 0.099,
    );
    try std.testing.expect(timeline.history_present[0]);
    try std.testing.expectEqual(
        result[1][0],
        timeline.previous[0],
    );

    const retained = timeline;
    timeline.history_present[1] = false;
    timeline.previous[1].energy[0] = 1.0;
    const invalid = timeline;
    try std.testing.expect(!timeline.valid());
    try std.testing.expectError(
        error.InvalidMp3PsychoacousticHistory,
        timeline.analyzeFrame(header, analyzed),
    );
    try std.testing.expectEqual(invalid, timeline);
    timeline = retained;
    timeline.previous[1] = timeline.previous[0];
    timeline.history_present = .{ false, true };
    const impossible_channel_order = timeline;
    try std.testing.expect(!timeline.valid());
    try std.testing.expectError(
        error.InvalidMp3PsychoacousticHistory,
        timeline.analyzeFrame(header, analyzed),
    );
    try std.testing.expectEqual(impossible_channel_order, timeline);
    timeline = retained;
    timeline.reset();
    try std.testing.expect(timeline.valid());
    try std.testing.expectEqual(
        EncoderPsychoacousticTimeline{
            .model = retained.model,
        },
        timeline,
    );
}

test "quantizes analyzed MP3 spectra with automatic codebooks" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    };
    const header = try config.header(false);
    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 1,
        .granule_count = 2,
    };
    for (0..2) |granule| {
        for (0..240) |line| {
            analyzed.granules[granule][0].spectrum.lines[line] =
                0.2 * @sin(
                    @as(f32, @floatFromInt(line)) * 0.37,
                );
        }
        analyzed.granules[granule][0].spectrum.lines[0] = 2.5;
        analyzed.granules[granule][0].spectrum.lines[1] = -1.5;
        analyzed.granules[granule][0].spectrum.lines[40] = 0.25;
        analyzed.granules[granule][0].spectrum.lines[43] = -0.25;
        analyzed.granules[granule][0].spectrum.lines[350] = 0.001;
    }
    const quantized = try EncoderQuantizer.quantize(
        header,
        analyzed,
    );
    for (0..2) |granule| {
        const channel = quantized.granules[granule][0];
        try std.testing.expect(channel.description.big_values > 0);
        try std.testing.expect(
            channel.description.table_select[0] != 0,
        );
        try std.testing.expect(
            channel.spectrum[0] != 0 or
                channel.spectrum[1] != 0,
        );
        var nonzero_factor = false;
        for (channel.scale_factors.values) |factor|
            nonzero_factor = nonzero_factor or factor != 0;
        try std.testing.expect(nonzero_factor);
    }

    var encoder = try FrameEncoder.init(config);
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const bytes = try encoder.encodeQuantizedFrame(
        &quantized,
        &storage,
    );
    const parsed = try Frame.parse(bytes, 0);
    const side = try parsed.sideInformation();
    try std.testing.expect(side.main_data_bits > 0);
    var reservoir = MainDataReservoir(511){};
    var main_storage: [512]u8 = undefined;
    const main_data = try reservoir.assemble(
        parsed,
        &main_storage,
    );
    const decoded_factors = try decodeScaleFactors(
        parsed.header,
        side,
        main_data,
    );
    for (0..2) |granule| {
        try std.testing.expectEqual(
            quantized.granules[granule][0].scale_factors.values,
            decoded_factors.granules[granule].channels[0].values,
        );
        const reconstructed = try requantizeChannel(
            header,
            quantized.granules[granule][0].description,
            decoded_factors.granules[granule].channels[0],
            .{
                .lines = quantized.granules[granule][0].spectrum,
                .decoded_lines = 576,
            },
        );
        try std.testing.expect(reconstructed.lines[350] != 0);
    }
    var decoder = FrameDecoder{};
    const pcm = try decoder.decode(parsed);
    for (pcm.channels[0]) |sample|
        try std.testing.expect(std.math.isFinite(sample));

    var transitions = analyzed;
    transitions.granules[0][0].description = .{
        .window_switching = true,
        .block_type = 1,
    };
    transitions.granules[1][0].description = .{
        .window_switching = true,
        .block_type = 2,
    };
    const transition_quantized = try EncoderQuantizer.quantize(
        header,
        transitions,
    );
    try std.testing.expectEqual(
        @as(u4, 7),
        transition_quantized.granules[0][0]
            .description.region0_count,
    );
    try std.testing.expectEqual(
        @as(u5, 0),
        transition_quantized.granules[0][0]
            .description.table_select[2],
    );
    const short_quantized = QuantizedSpectrum{
        .lines = transition_quantized.granules[1][0].spectrum,
        .decoded_lines = 576,
    };
    const short_reconstructed = try requantizeChannel(
        header,
        transition_quantized.granules[1][0].description,
        .{
            .values = transition_quantized.granules[1][0]
                .scale_factors.values,
            .value_count = transition_quantized.granules[1][0]
                .scale_factors.value_count,
        },
        short_quantized,
    );
    try std.testing.expect(short_reconstructed.lines[40] != 0);
    try std.testing.expect(short_reconstructed.lines[43] != 0);
    const transition_bytes = try encoder.encodeQuantizedFrame(
        &transition_quantized,
        &storage,
    );
    const transition_parsed = try Frame.parse(
        transition_bytes,
        0,
    );
    const transition_side =
        try transition_parsed.sideInformation();
    try std.testing.expectEqual(
        @as(u4, 7),
        transition_side.granules[0].channels[0]
            .region0_count,
    );
    const transition_pcm = try decoder.decode(
        transition_parsed,
    );
    for (transition_pcm.channels[0]) |sample|
        try std.testing.expect(std.math.isFinite(sample));

    var malformed = analyzed;
    malformed.granules[0][0].spectrum.lines[0] =
        std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMp3RequantizedSpectrum,
        EncoderQuantizer.quantize(header, malformed),
    );
    malformed = analyzed;
    malformed.channel_count = 2;
    try std.testing.expectError(
        error.InvalidMp3EncoderAnalysisFrame,
        EncoderQuantizer.quantize(header, malformed),
    );
}

test "spends bounded MP3 reservoir history on quantization" {
    const header = try (EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 64,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    }).header(false);
    const physical_budget = try reservoirQuantizerBudget(
        header,
        0,
    );
    const reservoir_budget = try reservoirQuantizerBudget(
        header,
        511,
    );
    try std.testing.expectEqual(
        physical_budget.physical_bits,
        physical_budget.logical_bits,
    );
    try std.testing.expectEqual(
        @as(usize, 511 * 8),
        reservoir_budget.history_bits,
    );
    try std.testing.expectEqual(
        physical_budget.logical_bits + 511 * 8,
        reservoir_budget.logical_bits,
    );

    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 1,
        .granule_count = 2,
    };
    for (0..2) |granule| {
        for (0..576) |line| {
            const position: f32 = @floatFromInt(line);
            analyzed.granules[granule][0].spectrum.lines[line] =
                0.7 * @sin(position * 0.17) +
                0.3 * @cos(position * 0.41);
        }
    }
    var timeline = EncoderPsychoacousticTimeline{};
    const masking = try timeline.analyzeFrame(
        header,
        analyzed,
    );
    const quantizer = EncoderQuantizer{};
    const physical = try quantizer.processWithMasking(
        header,
        analyzed,
        masking,
    );
    const expanded = try quantizer.processWithReservoirMasking(
        header,
        analyzed,
        masking,
        511,
    );
    const physical_ratio = try encoderNoiseToMaskRatio(
        header,
        analyzed,
        physical,
        masking,
    );
    const expanded_ratio = try encoderNoiseToMaskRatio(
        header,
        analyzed,
        expanded,
        masking,
    );
    try std.testing.expect(expanded_ratio < physical_ratio);
    try std.testing.expect(!std.meta.eql(physical, expanded));

    var parts_encoder = try FrameEncoder.init(.{
        .version = .mpeg1,
        .bitrate_kbps = 64,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    });
    var frame_storage: [maximum_encoded_frame_bytes]u8 =
        @splat(0xa5);
    var main_data_storage: [maximum_encoded_main_data_bytes + 8]u8 =
        @splat(0x5a);
    const parts = try parts_encoder.encodeQuantizedFrameParts(
        &expanded,
        &frame_storage,
        &main_data_storage,
    );
    try std.testing.expect(
        parts.main_data_bits > physical_budget.physical_bits,
    );
    try std.testing.expectEqual(
        @as(usize, parts.main_data_bits + 7) / 8,
        parts.main_data.len,
    );
    const parts_frame = try Frame.parse(parts.frame, 0);
    const parts_side = try parts_frame.sideInformation();
    try std.testing.expectEqual(
        parts.main_data_bits,
        parts_side.main_data_bits,
    );
    for (parts.frame[frameMainDataOffset(header)..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectEqualSlices(
        u8,
        &@as([8]u8, @splat(0x5a)),
        main_data_storage[parts.main_data.len..][0..8],
    );

    var ordinary_encoder = try FrameEncoder.init(.{
        .version = .mpeg1,
        .bitrate_kbps = 64,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    });
    const ordinary_encoder_before = ordinary_encoder;
    var ordinary_storage: [maximum_encoded_frame_bytes]u8 =
        @splat(0x3c);
    const ordinary_storage_before = ordinary_storage;
    try std.testing.expectError(
        error.Mp3HuffmanBitCountOverflow,
        ordinary_encoder.encodeQuantizedFrame(
            &expanded,
            &ordinary_storage,
        ),
    );
    try std.testing.expectEqual(
        ordinary_encoder_before,
        ordinary_encoder,
    );
    try std.testing.expectEqual(
        ordinary_storage_before,
        ordinary_storage,
    );

    var short_encoder = try FrameEncoder.init(.{
        .version = .mpeg1,
        .bitrate_kbps = 64,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    });
    const short_encoder_before = short_encoder;
    var short_frame_storage: [maximum_encoded_frame_bytes]u8 =
        @splat(0x6b);
    const short_frame_before = short_frame_storage;
    try std.testing.expectError(
        error.InsufficientMp3MainDataStorage,
        short_encoder.encodeQuantizedFrameParts(
            &expanded,
            &short_frame_storage,
            main_data_storage[0 .. parts.main_data.len - 1],
        ),
    );
    try std.testing.expectEqual(short_encoder_before, short_encoder);
    try std.testing.expectEqual(short_frame_before, short_frame_storage);

    var batch_encoder = try FrameEncoder.init(.{
        .version = .mpeg1,
        .bitrate_kbps = 64,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    });
    var batch_frames: [maximum_encoded_frame_bytes * 4]u8 =
        undefined;
    var batch_main_data: [maximum_encoded_main_data_bytes * 4]u8 =
        undefined;
    var batch_frame_length: usize = 0;
    var batch_main_data_length: usize = 0;
    const silent_quantized = QuantizedEncoderFrame{};
    for (0..4) |index| {
        const batch_parts = try batch_encoder.encodeQuantizedFrameParts(
            if (index == 3) &expanded else &silent_quantized,
            batch_frames[batch_frame_length..],
            batch_main_data[batch_main_data_length..],
        );
        batch_frame_length += batch_parts.frame.len;
        batch_main_data_length += batch_parts.main_data.len;
    }
    var batch_scratch: [maximum_encoded_frame_bytes * 4]u8 =
        @splat(0x27);
    const batch_shells = batch_frames;
    const packed_result = try packMainDataReservoir(
        batch_frames[0..batch_frame_length],
        batch_main_data[0..batch_main_data_length],
        511,
        &batch_scratch,
    );
    try std.testing.expectEqual(@as(u64, 4), packed_result.frame_count);
    try std.testing.expectEqual(@as(u16, 511), packed_result.maximum_backpointer);
    var packed_reader = try Stream.init(
        batch_frames[0..batch_frame_length],
    );
    var packed_decoder = FrameDecoder{};
    var frame_index: usize = 0;
    var final_frame_nonzero = false;
    while (try packed_reader.next()) |packed_frame| : (frame_index += 1) {
        const packed_side = try packed_frame.sideInformation();
        if (frame_index < 3)
            try std.testing.expectEqual(
                @as(u16, 0),
                packed_side.main_data_begin,
            )
        else {
            try std.testing.expectEqual(
                @as(u16, 511),
                packed_side.main_data_begin,
            );
            try std.testing.expect(
                packed_side.main_data_bits >
                    (packed_frame.bytes.len -
                        frameMainDataOffset(packed_frame.header)) * 8,
            );
        }
        const decoded = try packed_decoder.decode(packed_frame);
        if (frame_index == 3) {
            for (decoded.channels[0]) |sample| {
                try std.testing.expect(std.math.isFinite(sample));
                final_frame_nonzero = final_frame_nonzero or sample != 0;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 4), frame_index);
    try std.testing.expect(final_frame_nonzero);

    var rejected_frames: [maximum_encoded_frame_bytes * 4]u8 = undefined;
    @memcpy(
        rejected_frames[0..batch_frame_length],
        batch_shells[0..batch_frame_length],
    );
    const rejected_frames_before = rejected_frames;
    try std.testing.expectError(
        error.InvalidMp3LogicalMainDataLength,
        packMainDataReservoir(
            rejected_frames[0..batch_frame_length],
            batch_main_data[0 .. batch_main_data_length - 1],
            511,
            &batch_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_frames_before, rejected_frames);

    try std.testing.expectError(
        error.InvalidMp3ReservoirHistoryLimit,
        reservoirQuantizerBudget(header, 512),
    );
    const low_rate_header = try (EncoderConfig{
        .version = .mpeg2,
        .bitrate_kbps = 64,
        .sample_rate = 22_050,
        .channel_mode = .mono,
    }).header(false);
    const low_rate_budget = try reservoirQuantizerBudget(
        low_rate_header,
        255,
    );
    try std.testing.expectEqual(
        @as(usize, 255 * 8),
        low_rate_budget.history_bits,
    );
    try std.testing.expectError(
        error.InvalidMp3ReservoirHistoryLimit,
        reservoirQuantizerBudget(low_rate_header, 256),
    );
    const maximum_header = try (EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 320,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    }).header(false);
    try std.testing.expectEqual(
        @as(usize, 2 * std.math.maxInt(u12)),
        (try reservoirQuantizerBudget(
            maximum_header,
            511,
        )).logical_bits,
    );
    var free_format = header;
    free_format.free_format = true;
    free_format.bitrate_kbps = 0;
    try std.testing.expectError(
        error.UnsupportedFreeFormatMp3,
        reservoirQuantizerBudget(free_format, 0),
    );
}

test "orders pure and mixed short spectra for MP3 encoding" {
    const headers = [_]Header{
        try Header.parse(
            &testHeader(3, true, 9, 0, false, .mono),
        ),
        try Header.parse(
            &testHeader(0, true, 9, 2, false, .mono),
        ),
    };
    var spectrum = RequantizedSpectrum{};
    for (&spectrum.lines, 0..) |*line, index|
        line.* = @floatFromInt(index);
    for (headers) |header| {
        const bands = try scaleFactorBands(header);
        const pure = try orderEncoderSpectrum(
            header,
            .{
                .window_switching = true,
                .block_type = 2,
            },
            spectrum,
        );
        const first_width: usize =
            bands.short_starts[1] - bands.short_starts[0];
        try std.testing.expectEqual(@as(f32, 0), pure[0]);
        try std.testing.expectEqual(
            @as(f32, 1),
            pure[first_width],
        );
        try std.testing.expectEqual(
            @as(f32, 2),
            pure[first_width * 2],
        );

        const mixed = try orderEncoderSpectrum(
            header,
            .{
                .window_switching = true,
                .block_type = 2,
                .mixed_block = true,
            },
            spectrum,
        );
        const boundary: usize = 3 * bands.short_starts[3];
        try std.testing.expectEqual(
            @as(f32, @floatFromInt(boundary - 1)),
            mixed[boundary - 1],
        );
        try std.testing.expectEqual(
            @as(f32, @floatFromInt(boundary)),
            mixed[boundary],
        );
        try std.testing.expectEqual(
            @as(f32, @floatFromInt(boundary + 1)),
            mixed[
                boundary +
                    bands.short_starts[4] -
                    bands.short_starts[3]
            ],
        );
    }
}

test "keeps low-rate mixed terminal scale factors zero" {
    const header = try Header.parse(
        &testHeader(0, true, 9, 2, false, .mono),
    );
    var analyzed = AnalyzedEncoderFrame{
        .channel_count = 1,
        .granule_count = 1,
    };
    analyzed.granules[0][0].description = .{
        .window_switching = true,
        .block_type = 2,
        .mixed_block = true,
    };
    analyzed.granules[0][0].spectrum.lines[0] = 1;
    analyzed.granules[0][0].spectrum.lines[575] = 0.1;
    const quantized = try EncoderQuantizer.quantize(
        header,
        analyzed,
    );
    const channel = quantized.granules[0][0];
    try std.testing.expectEqual(
        @as(u6, 33),
        channel.scale_factors.value_count,
    );
    const layout = try encoderBandLayout(
        header,
        channel.description,
    );
    for (channel.scale_factors.values[layout.band_count - 3 ..]) |factor|
        try std.testing.expectEqual(@as(u8, 0), factor);
    var storage: [64]u8 = undefined;
    _ = try encodeScaleFactors(
        header,
        channel.description,
        0,
        0,
        0,
        .{},
        channel.scale_factors,
        &storage,
    );
}

test "encodes PCM into complete MP3 frames transactionally" {
    const config = EncoderConfig{
        .version = .mpeg2,
        .bitrate_kbps = 64,
        .sample_rate = 22_050,
        .channel_mode = .mono,
    };
    var encoder = try PcmEncoder.init(config);
    try std.testing.expect(encoder.valid());
    var pcm = PcmFrame{
        .channel_count = 1,
        .sample_count = 576,
    };
    for (&pcm.channels[0], 0..) |*sample, index| {
        sample.* = 0.2 * @sin(
            @as(f32, @floatFromInt(index)) * 0.07,
        );
    }
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const first = try encoder.encode(pcm, &storage);
    try std.testing.expect(encoder.valid());
    const parsed = try Frame.parse(first, 0);
    try std.testing.expectEqual(config.version, parsed.header.version);
    try std.testing.expectEqual(
        @as(u64, 1),
        encoder.frames.frames_encoded,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        encoder.analysis.frames_analyzed,
    );
    var decoder = FrameDecoder{};
    const decoded = try decoder.decode(parsed);
    for (decoded.channels[0]) |sample|
        try std.testing.expect(std.math.isFinite(sample));

    const before = encoder;
    var short_storage: [8]u8 = undefined;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.encode(pcm, &short_storage),
    );
    try std.testing.expectEqual(before, encoder);

    var hostile = encoder;
    hostile.analysis.frames_analyzed += 1;
    try std.testing.expect(!hostile.valid());
    const hostile_before = hostile;
    try std.testing.expectError(
        error.InvalidMp3PcmEncoderState,
        hostile.encode(pcm, &storage),
    );
    try std.testing.expectEqual(hostile_before, hostile);

    encoder.reset();
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(u64, 0),
        encoder.frames.frames_encoded,
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        encoder.analysis.frames_analyzed,
    );
}

test "selects bounded MP3 VBR frames transactionally" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 14,
        .maximum_noise_to_mask_ratio = 0.25,
    };
    var encoder = try VbrPcmEncoder.init(config);
    try std.testing.expect(encoder.valid());
    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const quiet = try encoder.encode(silence, &storage);
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(@as(u4, 1), quiet.bitrate_index);
    try std.testing.expect(quiet.quality_met);
    try std.testing.expectEqual(
        bitrate(.mpeg1, quiet.bitrate_index),
        quiet.header.bitrate_kbps,
    );
    try std.testing.expectEqual(
        quiet.header.frameBytes(),
        quiet.frame.len,
    );
    try std.testing.expectEqual(
        @as(?bool, true),
        try (try Frame.parse(quiet.frame, 0)).crcValid(),
    );

    var complex = silence;
    for (&complex.channels[0], 0..) |*sample, index| {
        const position: f32 = @floatFromInt(index);
        sample.* =
            0.18 * @sin(position * 0.031) +
            0.16 * @sin(position * 0.173) +
            0.12 * @sin(position * 0.419);
        if (index % 37 == 0)
            sample.* += if (index % 74 == 0) 0.3 else -0.3;
    }
    const detailed = try encoder.encode(complex, &storage);
    try std.testing.expect(encoder.valid());
    try std.testing.expect(
        detailed.bitrate_index > quiet.bitrate_index,
    );
    try std.testing.expect(
        std.math.isFinite(
            detailed.maximum_noise_to_mask_ratio,
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        encoder.frames.frames_encoded,
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        encoder.analysis.frames_analyzed,
    );
    var histogram_frames: u64 = 0;
    for (encoder.bitrate_histogram) |count|
        histogram_frames += count;
    try std.testing.expectEqual(@as(u64, 2), histogram_frames);

    const before = encoder;
    var short_storage: [8]u8 = undefined;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.encode(complex, &short_storage),
    );
    try std.testing.expectEqual(before, encoder);
    try std.testing.expectError(
        error.Mp3VbrBitrateOutsidePolicy,
        encoder.encodeAtBitrateIndex(
            complex,
            &storage,
            0,
        ),
    );
    try std.testing.expectEqual(before, encoder);

    var hostile = encoder;
    hostile.bitrate_histogram[0] = 1;
    try std.testing.expect(!hostile.valid());
    const hostile_before = hostile;
    try std.testing.expectError(
        error.InvalidMp3VbrEncoderState,
        hostile.encode(complex, &storage),
    );
    try std.testing.expectEqual(hostile_before, hostile);
    try std.testing.expectError(
        error.InvalidMp3VbrEncoderConfig,
        VbrPcmEncoder.init(.{
            .minimum_bitrate_index = 14,
            .maximum_bitrate_index = 1,
        }),
    );
    try std.testing.expectError(
        error.InvalidMp3VbrEncoderConfig,
        VbrPcmEncoder.init(.{
            .maximum_noise_to_mask_ratio = std.math.nan(f32),
        }),
    );

    var low_rate = try VbrPcmEncoder.init(.{
        .template = .{
            .version = .mpeg2,
            .sample_rate = 22_050,
            .channel_mode = .mono,
        },
        .minimum_bitrate_index = 8,
        .maximum_bitrate_index = 8,
    });
    const low_rate_frame = try low_rate.encode(
        .{
            .channel_count = 1,
            .sample_count = 576,
        },
        &storage,
    );
    try std.testing.expectEqual(
        Version.mpeg2,
        low_rate_frame.header.version,
    );
    try std.testing.expectEqual(
        @as(u16, 64),
        low_rate_frame.header.bitrate_kbps,
    );
}

test "finishes MP3 VBR streams with Xing metadata" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .maximum_noise_to_mask_ratio = 0.25,
    };
    var offsets: [8]u64 = undefined;
    var encoder = try VbrPcmStreamEncoder.init(
        config,
        &offsets,
    );
    var encoded: [maximum_encoded_frame_bytes * 5]u8 = @splat(0x5a);
    var cursor: usize = 0;
    const metadata_encoder: [9]u8 = "VBRTest 1".*;
    const placeholder = try encoder.startXingMetadataWithEncoder(
        metadata_encoder,
        encoded[cursor..],
    );
    cursor += placeholder.len;
    const provisional = try Frame.parse(
        encoded[0..cursor],
        0,
    );
    try std.testing.expectEqual(
        XingKind.variable,
        provisional.xing.?.kind,
    );
    try std.testing.expectEqual(
        @as(?u32, 0),
        provisional.xing.?.frame_count,
    );
    try std.testing.expect(
        provisional.xing.?.toc != null,
    );
    try std.testing.expectEqual(
        metadata_encoder,
        provisional.xing.?.encoder.?,
    );

    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };
    const quiet = try encoder.append(
        silence,
        encoded[cursor..],
    );
    cursor += quiet.frame.len;
    var detailed_pcm = silence;
    for (&detailed_pcm.channels[0], 0..) |*sample, index| {
        const position: f32 = @floatFromInt(index);
        sample.* =
            0.2 * @sin(position * 0.039) +
            0.17 * @sin(position * 0.211);
        if (index % 41 == 0)
            sample.* += 0.25;
    }
    const detailed = try encoder.append(
        detailed_pcm,
        encoded[cursor..],
    );
    cursor += detailed.frame.len;
    try std.testing.expect(
        detailed.bitrate_index > quiet.bitrate_index,
    );

    const before_finish = encoder;
    const offsets_before_finish = offsets;
    var short_storage: [8]u8 = undefined;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.finish(&short_storage),
    );
    try std.testing.expectEqual(before_finish, encoder);
    try std.testing.expectEqual(
        offsets_before_finish,
        offsets,
    );

    const finished = try encoder.finish(encoded[cursor..]);
    cursor += finished.frames.len;
    try std.testing.expectEqual(@as(u64, 4), finished.summary.frame_count);
    try std.testing.expectEqual(@as(u64, 2304), finished.summary.input_samples);
    try std.testing.expectEqual(@as(u16, 2209), finished.summary.encoder_delay);
    try std.testing.expectEqual(@as(u16, 95), finished.summary.end_padding);
    try std.testing.expectEqual(
        @as(u64, cursor),
        finished.summary.byte_count,
    );

    var final_metadata: [maximum_encoded_frame_bytes]u8 =
        undefined;
    const replacement = try encoder.xingMetadataFrame(
        37,
        &final_metadata,
    );
    try std.testing.expectEqual(placeholder.len, replacement.len);
    @memcpy(encoded[0..replacement.len], replacement);
    const summary = try Stream.summarize(encoded[0..cursor]);
    const xing = summary.first_xing.?;
    try std.testing.expectEqual(metadata_encoder, xing.encoder.?);
    try std.testing.expectEqual(XingKind.variable, xing.kind);
    try std.testing.expectEqual(
        @as(?u32, 4),
        xing.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(cursor)),
        xing.stream_bytes,
    );
    try std.testing.expectEqual(@as(?u32, 37), xing.quality);
    try std.testing.expectEqual(
        @as(?u12, 528),
        xing.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(?u12, 624),
        xing.encoder_padding,
    );
    const toc = xing.toc.?;
    try std.testing.expectEqual(@as(u8, 0), toc[0]);
    for (1..toc.len) |index|
        try std.testing.expect(toc[index] >= toc[index - 1]);

    const repeated = try encoder.finish(encoded[cursor..]);
    try std.testing.expectEqual(@as(usize, 0), repeated.frames.len);
    const hostile = encoder;
    offsets[1] = 0;
    try std.testing.expectError(
        error.InvalidMp3VbrStreamState,
        hostile.summary(),
    );
}

test "encodes correlated PCM through MP3 mid-side stereo" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .joint_stereo,
        .mode_extension = 2,
    };
    var encoder = try PcmEncoder.init(config);
    var pcm = PcmFrame{
        .channel_count = 2,
        .sample_count = 1152,
    };
    for (0..1152) |index| {
        const sample = 0.2 * @sin(
            @as(f32, @floatFromInt(index)) * 0.05,
        );
        pcm.channels[0][index] = sample;
        pcm.channels[1][index] = sample;
    }
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const bytes = try encoder.encode(pcm, &storage);
    const parsed = try Frame.parse(bytes, 0);
    try std.testing.expectEqual(
        ChannelMode.joint_stereo,
        parsed.header.channel_mode,
    );
    try std.testing.expectEqual(
        @as(u2, 2),
        parsed.header.mode_extension,
    );
    var decoder = FrameDecoder{};
    const decoded = try decoder.decode(parsed);
    var nonzero = false;
    for (
        decoded.channels[0],
        decoded.channels[1],
    ) |left, right| {
        try std.testing.expectApproxEqAbs(left, right, 1e-6);
        nonzero = nonzero or left != 0;
    }
    try std.testing.expect(nonzero);

    var intensity_encoder = try PcmEncoder.init(.{
        .bitrate_kbps = 192,
        .channel_mode = .joint_stereo,
        .mode_extension = 1,
    });
    const intensity_bytes =
        try intensity_encoder.encode(pcm, &storage);
    const intensity_frame =
        try Frame.parse(intensity_bytes, 0);
    try std.testing.expectEqual(
        @as(u2, 1),
        intensity_frame.header.mode_extension,
    );
    var intensity_decoder = FrameDecoder{};
    const intensity_decoded =
        try intensity_decoder.decode(intensity_frame);
    var intensity_nonzero = false;
    for (
        intensity_decoded.channels[0],
        intensity_decoded.channels[1],
    ) |left, right| {
        try std.testing.expect(std.math.isFinite(left));
        try std.testing.expect(std.math.isFinite(right));
        intensity_nonzero =
            intensity_nonzero or left != 0 or right != 0;
    }
    try std.testing.expect(intensity_nonzero);
}

test "encodes MP3 intensity stereo through VBR selection" {
    var encoder = try VbrPcmEncoder.init(.{
        .template = .{
            .channel_mode = .joint_stereo,
            .mode_extension = 1,
        },
        .minimum_bitrate_index = 11,
        .maximum_bitrate_index = 11,
    });
    var pcm = PcmFrame{
        .channel_count = 2,
        .sample_count = 1152,
    };
    for (0..1152) |index| {
        const position: f32 = @floatFromInt(index);
        pcm.channels[0][index] =
            0.18 * @sin(position * 0.05);
        pcm.channels[1][index] =
            0.12 * @sin(position * 0.05 + 0.3);
    }
    var storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const selected = try encoder.encode(pcm, &storage);
    try std.testing.expectEqual(@as(u4, 11), selected.bitrate_index);
    try std.testing.expectEqual(
        @as(u2, 1),
        selected.header.mode_extension,
    );
    try std.testing.expect(
        std.math.isFinite(
            selected.maximum_noise_to_mask_ratio,
        ),
    );
}

test "encodes low-rate MP3 intensity stereo through the decoder" {
    const configs = [_]EncoderConfig{
        .{
            .version = .mpeg2,
            .bitrate_kbps = 64,
            .sample_rate = 22_050,
            .channel_mode = .joint_stereo,
            .mode_extension = 1,
        },
        .{
            .version = .mpeg25,
            .bitrate_kbps = 32,
            .sample_rate = 11_025,
            .channel_mode = .joint_stereo,
            .mode_extension = 1,
        },
    };
    for (configs) |config| {
        var encoder = try PcmEncoder.init(config);
        var pcm = PcmFrame{
            .channel_count = 2,
            .sample_count = 576,
        };
        for (0..576) |index| {
            const position: f32 = @floatFromInt(index);
            pcm.channels[0][index] =
                0.16 * @sin(position * 0.07);
            pcm.channels[1][index] =
                0.1 * @sin(position * 0.07 + 0.5);
        }
        var storage: [maximum_encoded_frame_bytes]u8 = undefined;
        const bytes = try encoder.encode(pcm, &storage);
        const frame = try Frame.parse(bytes, 0);
        try std.testing.expectEqual(config.version, frame.header.version);
        try std.testing.expectEqual(
            ChannelMode.joint_stereo,
            frame.header.channel_mode,
        );
        var decoder = FrameDecoder{};
        const decoded = try decoder.decode(frame);
        var nonzero = false;
        for (decoded.channels[0], decoded.channels[1]) |left, right| {
            try std.testing.expect(std.math.isFinite(left));
            try std.testing.expect(std.math.isFinite(right));
            nonzero = nonzero or left != 0 or right != 0;
        }
        try std.testing.expect(nonzero);
    }
}

test "reuses MP3 main-data capacity across pending PCM frames" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    const samples_per_frame =
        (try config.header(false)).samplesPerFrame();
    var pcm_frames: [3]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    });
    for (0..samples_per_frame) |sample| {
        const phase =
            2.0 * std.math.pi *
            @as(f32, @floatFromInt(sample)) / 37.0;
        pcm_frames[1].channels[0][sample] =
            0.6 * @sin(phase);
        pcm_frames[2].channels[0][sample] =
            0.4 * @sin(phase * 1.7);
    }

    var ordinary = try PcmEncoder.init(config);
    var ordinary_bytes: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var ordinary_length: usize = 0;
    for (pcm_frames) |pcm| {
        const frame = try ordinary.encode(
            pcm,
            ordinary_bytes[ordinary_length..],
        );
        ordinary_length += frame.len;
    }

    var reservoir = try PcmReservoirEncoder.init(config);
    try std.testing.expect(reservoir.valid());
    var reservoir_bytes: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var reservoir_length: usize = 0;
    const primed = try reservoir.append(
        pcm_frames[0],
        reservoir_bytes[0..0],
    );
    try std.testing.expect(reservoir.valid());
    try std.testing.expectEqual(@as(?[]u8, null), primed.frame);
    const pending_snapshot = reservoir.pending;
    const received_snapshot = reservoir.frames_received;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        reservoir.append(
            pcm_frames[1],
            reservoir_bytes[0..0],
        ),
    );
    try std.testing.expectEqual(
        received_snapshot,
        reservoir.frames_received,
    );
    try std.testing.expectEqualSlices(
        u8,
        pending_snapshot[0..reservoir.pending_length],
        reservoir.pending[0..reservoir.pending_length],
    );

    var total_borrowed: u64 = 0;
    for (pcm_frames[1..]) |pcm| {
        const emitted = try reservoir.append(
            pcm,
            reservoir_bytes[reservoir_length..],
        );
        const frame = emitted.frame orelse
            return error.TestMp3ReservoirFrameMissing;
        reservoir_length += frame.len;
        total_borrowed += emitted.borrowed_bytes;
        if (emitted.borrowed_bytes != 0) {
            var mismatched_borrow = reservoir;
            mismatched_borrow.borrowed_bytes -=
                emitted.borrowed_bytes;
            try std.testing.expect(!mismatched_borrow.valid());
            const mismatched_before = mismatched_borrow;
            try std.testing.expectError(
                error.InvalidMp3ReservoirEncoderState,
                mismatched_borrow.finish(&reservoir_bytes),
            );
            try std.testing.expectEqual(
                mismatched_before,
                mismatched_borrow,
            );
        }
    }
    const final_frame = (try reservoir.finish(
        reservoir_bytes[reservoir_length..],
    )) orelse return error.TestMp3ReservoirFrameMissing;
    try std.testing.expect(reservoir.valid());
    reservoir_length += final_frame.len;
    try std.testing.expectEqual(
        ordinary_length,
        reservoir_length,
    );
    try std.testing.expect(total_borrowed > 0);
    try std.testing.expectEqual(
        total_borrowed,
        reservoir.borrowed_bytes,
    );
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        reservoir.frames_received,
    );
    try std.testing.expectEqual(
        reservoir.frames_received,
        reservoir.frames_emitted,
    );
    try std.testing.expect(
        (try reservoir.finish(
            reservoir_bytes[reservoir_length..],
        )) == null,
    );
    try std.testing.expectError(
        error.Mp3ReservoirEncoderFinalized,
        reservoir.append(
            pcm_frames[0],
            reservoir_bytes[reservoir_length..],
        ),
    );

    var ordinary_stream = try Stream.init(
        ordinary_bytes[0..ordinary_length],
    );
    var reservoir_stream = try Stream.init(
        reservoir_bytes[0..reservoir_length],
    );
    var ordinary_decoder = FrameDecoder{};
    var reservoir_decoder = FrameDecoder{};
    var borrowed_frame_seen = false;
    while (try ordinary_stream.next()) |ordinary_frame| {
        const reservoir_frame =
            (try reservoir_stream.next()) orelse
            return error.TestMp3ReservoirFrameMissing;
        const reservoir_side =
            try reservoir_frame.sideInformation();
        borrowed_frame_seen = borrowed_frame_seen or
            reservoir_side.main_data_begin != 0;
        try std.testing.expectEqual(
            @as(?bool, true),
            try reservoir_frame.crcValid(),
        );
        const ordinary_pcm =
            try ordinary_decoder.decode(ordinary_frame);
        const reservoir_pcm =
            try reservoir_decoder.decode(reservoir_frame);
        try std.testing.expectEqual(
            ordinary_pcm.channel_count,
            reservoir_pcm.channel_count,
        );
        try std.testing.expectEqual(
            ordinary_pcm.sample_count,
            reservoir_pcm.sample_count,
        );
        for (
            ordinary_pcm.channels[0][0..ordinary_pcm.sample_count],
            reservoir_pcm.channels[0][0..reservoir_pcm.sample_count],
        ) |expected, actual|
            try std.testing.expectEqual(expected, actual);
    }
    try std.testing.expect(
        (try reservoir_stream.next()) == null,
    );
    try std.testing.expect(borrowed_frame_seen);

    var malformed = try PcmReservoirEncoder.init(config);
    malformed.pending_length =
        maximum_encoded_frame_bytes + 1;
    try std.testing.expect(!malformed.valid());
    const malformed_before = malformed;
    try std.testing.expectError(
        error.InvalidMp3ReservoirEncoderState,
        malformed.finish(&reservoir_bytes),
    );
    try std.testing.expectEqual(malformed_before, malformed);
    var impossible_borrow = try PcmReservoirEncoder.init(config);
    impossible_borrow.borrowed_bytes = 1;
    try std.testing.expect(!impossible_borrow.valid());
    const impossible_borrow_before = impossible_borrow;
    try std.testing.expectError(
        error.InvalidMp3ReservoirEncoderState,
        impossible_borrow.finish(&reservoir_bytes),
    );
    try std.testing.expectEqual(
        impossible_borrow_before,
        impossible_borrow,
    );
    var corrupted = try PcmReservoirEncoder.init(config);
    _ = try corrupted.append(
        pcm_frames[0],
        reservoir_bytes[0..0],
    );
    corrupted.pending[4] ^= 1;
    try std.testing.expect(!corrupted.valid());
    const corrupted_before = corrupted;
    try std.testing.expectError(
        error.InvalidMp3ReservoirEncoderState,
        corrupted.finish(&reservoir_bytes),
    );
    try std.testing.expectEqual(corrupted_before, corrupted);
}

test "repacks MP3 main data across multiple frame boundaries" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    const samples_per_frame =
        (try config.header(false)).samplesPerFrame();
    var pcm_frames: [5]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    });
    for (0..samples_per_frame) |sample| {
        const position: f32 = @floatFromInt(sample);
        pcm_frames[3].channels[0][sample] =
            0.55 * @sin(position * 0.17);
        pcm_frames[4].channels[0][sample] =
            0.35 * @sin(position * 0.31) +
            0.15 * @cos(position * 0.07);
    }

    var encoder = try PcmEncoder.init(config);
    var ordinary: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        @splat(0xa5);
    var ordinary_length: usize = 0;
    for (pcm_frames) |pcm| {
        const frame = try encoder.encode(
            pcm,
            ordinary[ordinary_length..],
        );
        ordinary_length += frame.len;
    }
    const ordinary_stream = ordinary[0..ordinary_length];
    const requirements = try reservoirRepackRequirements(
        ordinary_stream,
    );
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        requirements.frame_count,
    );
    try std.testing.expect(requirements.payload_bytes > 0);
    try std.testing.expect(
        requirements.payload_bytes < requirements.main_data_bytes,
    );

    var repacked = ordinary;
    var encoded_scratch: [maximum_encoded_frame_bytes * pcm_frames.len + 8]u8 =
        @splat(0x4c);
    var payload_scratch: [maximum_encoded_frame_bytes * pcm_frames.len + 8]u8 =
        @splat(0x7d);
    const result = try repackMainDataReservoir(
        repacked[0..ordinary_length],
        511,
        &encoded_scratch,
        &payload_scratch,
    );
    try std.testing.expectEqual(
        requirements.frame_count,
        result.frame_count,
    );
    try std.testing.expect(result.borrowed_bytes > 0);
    const first_frame = try Frame.parse(ordinary_stream, 0);
    const first_capacity =
        first_frame.bytes.len - frameMainDataOffset(first_frame.header);
    try std.testing.expect(result.maximum_backpointer > first_capacity);
    try std.testing.expectEqualSlices(
        u8,
        &@as([8]u8, @splat(0x4c)),
        encoded_scratch[ordinary_length..][0..8],
    );
    try std.testing.expectEqualSlices(
        u8,
        &@as([8]u8, @splat(0x7d)),
        payload_scratch[requirements.payload_bytes..][0..8],
    );

    var ordinary_reader = try Stream.init(ordinary_stream);
    var repacked_reader = try Stream.init(repacked[0..ordinary_length]);
    var ordinary_decoder = FrameDecoder{};
    var repacked_decoder = FrameDecoder{};
    while (try ordinary_reader.next()) |ordinary_frame| {
        const repacked_frame = (try repacked_reader.next()) orelse
            return error.TestMp3ReservoirFrameMissing;
        try std.testing.expectEqual(
            @as(?bool, true),
            try repacked_frame.crcValid(),
        );
        const expected = try ordinary_decoder.decode(ordinary_frame);
        const actual = try repacked_decoder.decode(repacked_frame);
        try std.testing.expectEqual(
            expected.sample_count,
            actual.sample_count,
        );
        try std.testing.expectEqualSlices(
            f32,
            expected.channels[0][0..expected.sample_count],
            actual.channels[0][0..actual.sample_count],
        );
    }
    try std.testing.expect((try repacked_reader.next()) == null);
    try std.testing.expectError(
        error.Mp3ReservoirAlreadyPacked,
        reservoirRepackRequirements(repacked[0..ordinary_length]),
    );

    var independent = ordinary;
    var independent_staged: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var independent_payload: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    const independent_result = try repackMainDataReservoir(
        independent[0..ordinary_length],
        0,
        &independent_staged,
        &independent_payload,
    );
    try std.testing.expectEqual(@as(u64, 0), independent_result.borrowed_bytes);
    try std.testing.expectEqual(@as(u16, 0), independent_result.maximum_backpointer);
    try std.testing.expectEqualSlices(
        u8,
        ordinary_stream,
        independent[0..ordinary_length],
    );

    var rejected = ordinary;
    const rejected_before = rejected;
    try std.testing.expectError(
        error.InvalidMp3ReservoirHistoryLimit,
        repackMainDataReservoir(
            rejected[0..ordinary_length],
            512,
            &encoded_scratch,
            &payload_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected);
    try std.testing.expectError(
        error.Mp3ReservoirEncodedScratchTooSmall,
        repackMainDataReservoir(
            rejected[0..ordinary_length],
            511,
            encoded_scratch[0 .. ordinary_length - 1],
            &payload_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected);
    try std.testing.expectError(
        error.Mp3ReservoirPayloadScratchTooSmall,
        repackMainDataReservoir(
            rejected[0..ordinary_length],
            511,
            &encoded_scratch,
            payload_scratch[0 .. requirements.payload_bytes - 1],
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected);
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        repackMainDataReservoir(
            rejected[0..ordinary_length],
            511,
            rejected[0..ordinary_length],
            &payload_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected);
}

test "encodes PCM with adaptive multi-frame MP3 reservoir credit" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    const samples_per_frame =
        (try config.header(false)).samplesPerFrame();
    const initial_header = try config.header(false);
    var credit = try ReservoirCreditTracker.init(
        initial_header,
        511,
    );
    try std.testing.expect(credit.valid());
    const initial_budget = try credit.budget(initial_header);
    try std.testing.expectEqual(
        initial_budget.physical_bits,
        initial_budget.logical_bits,
    );
    const silent_credit = try credit.commit(initial_header, 0);
    try std.testing.expect(silent_credit.next_history_bytes > 0);
    try std.testing.expectEqual(
        silent_credit.next_history_bytes,
        credit.available_history_bytes,
    );
    var hostile_credit = credit;
    hostile_credit.available_history_bytes = 512;
    try std.testing.expect(!hostile_credit.valid());
    const hostile_credit_before = hostile_credit;
    try std.testing.expectError(
        error.InvalidMp3ReservoirCreditState,
        hostile_credit.commit(initial_header, 0),
    );
    try std.testing.expectEqual(hostile_credit_before, hostile_credit);
    credit.reset();
    try std.testing.expect(credit.valid());
    var pcm_frames: [9]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    });
    for (5..pcm_frames.len) |frame_index| {
        for (0..samples_per_frame) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * samples_per_frame + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.45 * @sin(position * 0.113) +
                0.3 * @cos(position * 0.271) +
                0.15 * @sin(position * 0.419);
        }
    }
    const required_frame_bytes =
        try requiredPcmReservoirBatchFrameBytes(
            config,
            pcm_frames.len,
        );
    var destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        @splat(0xa1);
    var frame_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var pack_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 = undefined;
    const encoded = try encodePcmReservoirBatch(
        config,
        &pcm_frames,
        511,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(required_frame_bytes, encoded.stream.len);
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        encoded.frame_count,
    );
    try std.testing.expect(encoded.borrowed_bytes > 0);
    try std.testing.expect(encoded.maximum_backpointer > 0);
    try std.testing.expect(encoded.retained_history_bytes <= 511);

    var stream = try Stream.init(encoded.stream);
    var decoder = FrameDecoder{};
    var expanded_frame_seen = false;
    var nonzero_pcm_seen = false;
    while (try stream.next()) |frame| {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        const side = try frame.sideInformation();
        const physical_bits =
            (frame.bytes.len - frameMainDataOffset(frame.header)) * 8;
        expanded_frame_seen = expanded_frame_seen or
            side.main_data_bits > physical_bits;
        const decoded = try decoder.decode(frame);
        for (decoded.channels[0]) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            nonzero_pcm_seen = nonzero_pcm_seen or sample != 0;
        }
    }
    try std.testing.expect(expanded_frame_seen);
    try std.testing.expect(nonzero_pcm_seen);

    var rejected_destination = destination;
    const rejected_before = rejected_destination;
    try std.testing.expectError(
        error.InvalidMp3ReservoirHistoryLimit,
        encodePcmReservoirBatch(
            config,
            &pcm_frames,
            512,
            &rejected_destination,
            &frame_scratch,
            &pack_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected_destination);
    try std.testing.expectError(
        error.InsufficientMp3MainDataStorage,
        encodePcmReservoirBatch(
            config,
            &pcm_frames,
            511,
            &rejected_destination,
            &frame_scratch,
            &pack_scratch,
            main_data_scratch[0..0],
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected_destination);
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        encodePcmReservoirBatch(
            config,
            &pcm_frames,
            511,
            &rejected_destination,
            &rejected_destination,
            &pack_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected_destination);
    var pcm_alias_storage: [@sizeOf(PcmFrame)]u8 align(@alignOf(PcmFrame)) =
        undefined;
    const aliased_pcm = std.mem.bytesAsSlice(
        PcmFrame,
        &pcm_alias_storage,
    );
    aliased_pcm[0] = pcm_frames[0];
    const pcm_alias_before = pcm_alias_storage;
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        encodePcmReservoirBatch(
            config,
            aliased_pcm,
            511,
            &rejected_destination,
            &pcm_alias_storage,
            &pack_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(pcm_alias_before, pcm_alias_storage);
    const empty = try encodePcmReservoirBatch(
        config,
        &.{},
        511,
        &rejected_destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(@as(usize, 0), empty.stream.len);
    try std.testing.expectEqual(rejected_before, rejected_destination);
}

test "publishes adaptive MP3 reservoir frames outside future reach" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [12]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (6..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }
    const required_storage =
        try requiredPcmAdaptiveReservoirStorage(config, 511);
    var short_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x72);
    try std.testing.expectError(
        error.Mp3AdaptiveReservoirStorageTooSmall,
        PcmAdaptiveReservoirStreamEncoder.init(
            config,
            511,
            short_storage[0 .. required_storage - 1],
        ),
    );
    var pending_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x81);
    var pending_scratch: [maximum_encoded_frame_bytes * 12]u8 =
        undefined;
    var frame_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes]u8 = undefined;
    var encoder = try PcmAdaptiveReservoirStreamEncoder.init(
        config,
        511,
        pending_storage[0..required_storage],
    );
    try std.testing.expect(encoder.valid());
    var encoded: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var encoded_length: usize = 0;
    var emitted_before_finish = false;
    var first_emission_index: ?usize = null;
    for (pcm_frames, 0..) |pcm, frame_index| {
        const appended = try encoder.append(
            pcm,
            encoded[encoded_length..],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        );
        try std.testing.expect(encoder.valid());
        if (appended.frames.len != 0) {
            emitted_before_finish = true;
            if (first_emission_index == null)
                first_emission_index = frame_index;
        }
        encoded_length += appended.frames.len;
    }
    try std.testing.expect(emitted_before_finish);
    const finished = try encoder.finish(encoded[encoded_length..]);
    encoded_length += finished.frames.len;
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        finished.frame_count,
    );
    try std.testing.expectEqual(
        finished.byte_count,
        encoded_length,
    );
    try std.testing.expect(finished.borrowed_bytes > 0);
    try std.testing.expect(finished.maximum_backpointer > 0);
    var hostile_byte_count = encoder;
    hostile_byte_count.byte_count += 1;
    try std.testing.expect(!hostile_byte_count.valid());
    var hostile_destination: [1]u8 = .{0x5a};
    try std.testing.expectError(
        error.InvalidMp3AdaptiveReservoirState,
        hostile_byte_count.finish(&hostile_destination),
    );
    try std.testing.expectEqual(@as(u8, 0x5a), hostile_destination[0]);
    const repeated = try encoder.finish(encoded[encoded_length..]);
    try std.testing.expectEqual(@as(usize, 0), repeated.frames.len);
    try std.testing.expectEqual(finished.frame_count, repeated.frame_count);

    var batch_destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_frames: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_pack: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_main: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 =
        undefined;
    const batch = try encodePcmReservoirBatch(
        config,
        &pcm_frames,
        511,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
    );
    try std.testing.expectEqualSlices(u8, batch.stream, encoded[0..encoded_length]);
    try std.testing.expectEqual(batch.frame_count, finished.frame_count);
    try std.testing.expectEqual(
        batch.logical_main_data_bits,
        finished.logical_main_data_bits,
    );
    try std.testing.expectEqual(batch.borrowed_bytes, finished.borrowed_bytes);
    try std.testing.expectEqual(
        batch.maximum_backpointer,
        finished.maximum_backpointer,
    );

    var stream = try Stream.init(encoded[0..encoded_length]);
    var decoder = FrameDecoder{};
    var nonzero_pcm_seen = false;
    while (try stream.next()) |frame| {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        const decoded = try decoder.decode(frame);
        for (decoded.channels[0]) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            nonzero_pcm_seen = nonzero_pcm_seen or sample != 0;
        }
    }
    try std.testing.expect(nonzero_pcm_seen);

    var retry_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x93);
    var retry_encoder = try PcmAdaptiveReservoirStreamEncoder.init(
        config,
        511,
        retry_storage[0..required_storage],
    );
    const failure_index = first_emission_index orelse
        return error.TestAdaptiveReservoirEmissionMissing;
    for (pcm_frames[0..failure_index]) |pcm| {
        _ = try retry_encoder.append(
            pcm,
            &encoded,
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        );
    }
    const state_before = retry_encoder;
    const pending_before = retry_storage;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        retry_encoder.append(
            pcm_frames[failure_index],
            encoded[0..0],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(state_before.encoder, retry_encoder.encoder);
    try std.testing.expectEqual(state_before.credit, retry_encoder.credit);
    try std.testing.expectEqual(
        state_before.pending_length,
        retry_encoder.pending_length,
    );
    try std.testing.expectEqual(pending_before, retry_storage);
    try std.testing.expect(retry_encoder.valid());
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        retry_encoder.append(
            pcm_frames[failure_index],
            retry_storage[0..required_storage],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(pending_before, retry_storage);
    try std.testing.expect(retry_encoder.valid());

    const zero_storage_bytes =
        try requiredPcmAdaptiveReservoirStorage(config, 0);
    var zero_pending: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_staging: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_output: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_encoder = try PcmAdaptiveReservoirStreamEncoder.init(
        config,
        0,
        zero_pending[0..zero_storage_bytes],
    );
    const immediate = try zero_encoder.append(
        pcm_frames[0],
        &zero_output,
        zero_staging[0..zero_storage_bytes],
        &frame_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(@as(u16, 1), immediate.frame_count);
    try std.testing.expectEqual(@as(usize, 0), zero_encoder.pending_length);
    var ordinary_encoder = try PcmEncoder.init(config);
    var ordinary_storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const ordinary = try ordinary_encoder.encode(
        pcm_frames[0],
        &ordinary_storage,
    );
    try std.testing.expectEqualSlices(u8, ordinary, immediate.frames);
}

test "combines adaptive VBR selection with multi-frame reservoir credit" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    const samples_per_frame: u16 = 1152;
    var pcm_frames: [9]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    });
    for (5..pcm_frames.len) |frame_index| {
        for (0..samples_per_frame) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * samples_per_frame + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.5 * @sin(position * 0.137) +
                0.25 * @cos(position * 0.293);
        }
    }
    var destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        @splat(0x91);
    var frame_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var pack_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 = undefined;
    const encoded = try encodeVbrPcmReservoirBatch(
        config,
        &pcm_frames,
        511,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        encoded.frame_count,
    );
    try std.testing.expect(encoded.borrowed_bytes > 0);
    try std.testing.expect(encoded.maximum_backpointer > 0);
    try std.testing.expect(std.math.isFinite(
        encoded.maximum_noise_to_mask_ratio,
    ));
    var histogram_frames: u64 = 0;
    for (encoded.bitrate_histogram) |count|
        histogram_frames += count;
    try std.testing.expectEqual(encoded.frame_count, histogram_frames);
    try std.testing.expectEqual(
        encoded.quality_misses != 0,
        encoded.maximum_noise_to_mask_ratio >
            config.maximum_noise_to_mask_ratio,
    );

    var stream = try Stream.init(encoded.stream);
    var decoder = FrameDecoder{};
    var decoded_frames: usize = 0;
    var nonzero_pcm_seen = false;
    while (try stream.next()) |frame| : (decoded_frames += 1) {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        const decoded = try decoder.decode(frame);
        for (decoded.channels[0]) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            nonzero_pcm_seen = nonzero_pcm_seen or sample != 0;
        }
    }
    try std.testing.expectEqual(pcm_frames.len, decoded_frames);
    try std.testing.expect(nonzero_pcm_seen);

    var rejected = destination;
    const rejected_before = rejected;
    try std.testing.expectError(
        error.InvalidMp3ReservoirHistoryLimit,
        encodeVbrPcmReservoirBatch(
            config,
            &pcm_frames,
            512,
            &rejected,
            &frame_scratch,
            &pack_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(rejected_before, rejected);
}

test "publishes adaptive VBR reservoir frames outside future reach" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    var pcm_frames: [12]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (6..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }

    const required_storage =
        try requiredVbrPcmAdaptiveReservoirStorage(config, 511);
    var short_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x72);
    try std.testing.expectError(
        error.Mp3AdaptiveReservoirStorageTooSmall,
        VbrPcmAdaptiveReservoirStreamEncoder.init(
            config,
            511,
            short_storage[0 .. required_storage - 1],
        ),
    );
    var pending_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x81);
    var pending_scratch: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var frame_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes]u8 = undefined;
    var encoder = try VbrPcmAdaptiveReservoirStreamEncoder.init(
        config,
        511,
        pending_storage[0..required_storage],
    );
    var encoded: [maximum_encoded_frame_bytes * pcm_frames.len]u8 = undefined;
    var encoded_length: usize = 0;
    var first_emission_index: ?usize = null;
    for (pcm_frames, 0..) |pcm, frame_index| {
        const appended = try encoder.append(
            pcm,
            encoded[encoded_length..],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        );
        try std.testing.expect(encoder.valid());
        try std.testing.expect(
            appended.selection.bitrate_index >=
                config.minimum_bitrate_index and
                appended.selection.bitrate_index <=
                    config.maximum_bitrate_index,
        );
        try std.testing.expect(std.math.isFinite(
            appended.selection.maximum_noise_to_mask_ratio,
        ));
        if (appended.frames.len != 0 and first_emission_index == null)
            first_emission_index = frame_index;
        encoded_length += appended.frames.len;
    }
    try std.testing.expect(first_emission_index != null);
    const finished = try encoder.finish(encoded[encoded_length..]);
    encoded_length += finished.frames.len;
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        finished.frame_count,
    );
    try std.testing.expectEqual(finished.byte_count, encoded_length);
    try std.testing.expect(finished.borrowed_bytes > 0);
    try std.testing.expect(finished.maximum_backpointer > 0);
    var histogram_frames: u64 = 0;
    for (finished.bitrate_histogram) |count| histogram_frames += count;
    try std.testing.expectEqual(finished.frame_count, histogram_frames);
    const repeated = try encoder.finish(encoded[encoded_length..]);
    try std.testing.expectEqual(@as(usize, 0), repeated.frames.len);

    var batch_destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_frames: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_pack: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_main: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 =
        undefined;
    const batch = try encodeVbrPcmReservoirBatch(
        config,
        &pcm_frames,
        511,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
    );
    try std.testing.expectEqualSlices(u8, batch.stream, encoded[0..encoded_length]);
    try std.testing.expectEqual(batch.frame_count, finished.frame_count);
    try std.testing.expectEqual(
        batch.logical_main_data_bits,
        finished.logical_main_data_bits,
    );
    try std.testing.expectEqual(batch.borrowed_bytes, finished.borrowed_bytes);
    try std.testing.expectEqual(
        batch.maximum_backpointer,
        finished.maximum_backpointer,
    );
    try std.testing.expectEqual(
        batch.bitrate_histogram,
        finished.bitrate_histogram,
    );
    try std.testing.expectEqual(batch.quality_misses, finished.quality_misses);
    try std.testing.expectEqual(
        batch.maximum_noise_to_mask_ratio,
        finished.maximum_noise_to_mask_ratio,
    );

    var stream = try Stream.init(encoded[0..encoded_length]);
    var decoder = FrameDecoder{};
    var decoded_frames: usize = 0;
    var nonzero_pcm_seen = false;
    while (try stream.next()) |frame| : (decoded_frames += 1) {
        try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());
        const decoded = try decoder.decode(frame);
        for (decoded.channels[0]) |sample| {
            try std.testing.expect(std.math.isFinite(sample));
            nonzero_pcm_seen = nonzero_pcm_seen or sample != 0;
        }
    }
    try std.testing.expectEqual(pcm_frames.len, decoded_frames);
    try std.testing.expect(nonzero_pcm_seen);

    var retry_storage: [maximum_encoded_frame_bytes * 12]u8 =
        @splat(0x93);
    var retry_encoder = try VbrPcmAdaptiveReservoirStreamEncoder.init(
        config,
        511,
        retry_storage[0..required_storage],
    );
    const failure_index = first_emission_index orelse
        return error.TestAdaptiveVbrReservoirEmissionMissing;
    for (pcm_frames[0..failure_index]) |pcm| {
        _ = try retry_encoder.append(
            pcm,
            &encoded,
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        );
    }
    const state_before = retry_encoder;
    const pending_before = retry_storage;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        retry_encoder.append(
            pcm_frames[failure_index],
            encoded[0..0],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(state_before.encoder, retry_encoder.encoder);
    try std.testing.expectEqual(state_before.credit, retry_encoder.credit);
    try std.testing.expectEqual(
        state_before.pending_length,
        retry_encoder.pending_length,
    );
    try std.testing.expectEqual(pending_before, retry_storage);
    try std.testing.expect(retry_encoder.valid());
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        retry_encoder.append(
            pcm_frames[failure_index],
            retry_storage[0..required_storage],
            pending_scratch[0..required_storage],
            &frame_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(pending_before, retry_storage);
    try std.testing.expect(retry_encoder.valid());

    const zero_storage_bytes =
        try requiredVbrPcmAdaptiveReservoirStorage(config, 0);
    var zero_pending: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_staging: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_output: [maximum_encoded_frame_bytes]u8 = undefined;
    var zero_encoder = try VbrPcmAdaptiveReservoirStreamEncoder.init(
        config,
        0,
        zero_pending[0..zero_storage_bytes],
    );
    const immediate = try zero_encoder.append(
        pcm_frames[0],
        &zero_output,
        zero_staging[0..zero_storage_bytes],
        &frame_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(@as(u16, 1), immediate.frame_count);
    var ordinary_encoder = try VbrPcmEncoder.init(config);
    var ordinary_storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const ordinary = try ordinary_encoder.encode(
        pcm_frames[0],
        &ordinary_storage,
    );
    try std.testing.expectEqualSlices(u8, ordinary.frame, immediate.frames);
    try std.testing.expectEqual(
        ordinary.bitrate_index,
        immediate.selection.bitrate_index,
    );
}

test "composes exact gapless adaptive reservoir metadata" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [8]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (4..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }
    const maximum_frames = pcm_frames.len + 3;
    var destination: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var frame_scratch: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var pack_scratch: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var main_scratch: [maximum_encoded_main_data_bytes * maximum_frames]u8 =
        undefined;
    var metadata_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    const encoder_identifier: [9]u8 = "Gapless 1".*;
    const encoded = try encodePcmReservoirGaplessBatch(
        config,
        &pcm_frames,
        511,
        encoder_identifier,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_scratch,
        &metadata_scratch,
    );
    try std.testing.expectEqual(encoded.stream.len, encoded.summary.byte_count);
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len * 1152),
        encoded.summary.input_samples,
    );
    try std.testing.expect(encoded.borrowed_bytes > 0);
    const parsed = try Stream.summarize(encoded.stream);
    try std.testing.expectEqual(
        @as(?u32, @intCast(encoded.summary.frame_count)),
        parsed.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(encoded.summary.byte_count)),
        parsed.first_xing.?.stream_bytes,
    );
    try std.testing.expectEqual(
        encoder_identifier,
        parsed.first_xing.?.encoder.?,
    );
    const gapless = try GaplessPlan.fromSummary(parsed);
    try std.testing.expectEqual(
        encoded.summary.input_samples,
        gapless.audible_samples,
    );
    var stream = try Stream.init(encoded.stream);
    var frames: u64 = 0;
    while (try stream.next()) |frame| : (frames += 1)
        try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());
    try std.testing.expectEqual(encoded.summary.frame_count, frames);

    const vbr_config = VbrEncoderConfig{
        .template = config,
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    const vbr = try encodeVbrPcmReservoirGaplessBatch(
        vbr_config,
        &pcm_frames,
        511,
        73,
        encoder_identifier,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_scratch,
        &metadata_scratch,
    );
    try std.testing.expectEqual(vbr.stream.len, vbr.summary.byte_count);
    try std.testing.expect(vbr.borrowed_bytes > 0);
    var histogram_frames: u64 = 0;
    for (vbr.bitrate_histogram) |count| histogram_frames += count;
    try std.testing.expectEqual(vbr.summary.frame_count, histogram_frames);
    const parsed_vbr = try Stream.summarize(vbr.stream);
    try std.testing.expectEqual(
        @as(?XingKind, .variable),
        parsed_vbr.first_xing.?.kind,
    );
    try std.testing.expectEqual(
        @as(?u32, 73),
        parsed_vbr.first_xing.?.quality,
    );
    try std.testing.expect(parsed_vbr.first_xing.?.toc != null);
    const vbr_gapless = try GaplessPlan.fromSummary(parsed_vbr);
    try std.testing.expectEqual(
        vbr.summary.input_samples,
        vbr_gapless.audible_samples,
    );

    const destination_before = destination;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encodePcmReservoirGaplessBatch(
            config,
            &pcm_frames,
            511,
            encoder_identifier,
            destination[0..1],
            &frame_scratch,
            &pack_scratch,
            &main_scratch,
            &metadata_scratch,
        ),
    );
    try std.testing.expectEqual(destination_before, destination);
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        encodePcmReservoirGaplessBatch(
            config,
            &pcm_frames,
            511,
            encoder_identifier,
            &destination,
            &destination,
            &pack_scratch,
            &main_scratch,
            &metadata_scratch,
        ),
    );
    try std.testing.expectEqual(destination_before, destination);
    var pcm_alias_storage: [@sizeOf(PcmFrame)]u8 align(@alignOf(PcmFrame)) =
        undefined;
    const aliased_pcm = std.mem.bytesAsSlice(
        PcmFrame,
        &pcm_alias_storage,
    );
    aliased_pcm[0] = pcm_frames[0];
    const pcm_alias_before = pcm_alias_storage;
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        encodePcmReservoirGaplessBatch(
            config,
            aliased_pcm,
            511,
            encoder_identifier,
            &destination,
            &frame_scratch,
            &pack_scratch,
            &main_scratch,
            &pcm_alias_storage,
        ),
    );
    try std.testing.expectEqual(pcm_alias_before, pcm_alias_storage);

    const prefix = [_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0 };
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "gapless-adaptive.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &prefix, 0);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        writePcmReservoirGaplessBatchFileWithOperations(
            std.testing.io,
            file,
            config,
            &pcm_frames,
            511,
            prefix.len,
            encoder_identifier,
            &destination,
            &frame_scratch,
            &pack_scratch,
            &main_scratch,
            &metadata_scratch,
            faults.operations(),
        ),
    );
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    const written = try writePcmReservoirGaplessBatchFileWithOperations(
        std.testing.io,
        file,
        config,
        &pcm_frames,
        511,
        prefix.len,
        encoder_identifier,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_scratch,
        &metadata_scratch,
        faults.operations(),
    );
    try std.testing.expectEqual(
        written.file_end,
        try file.length(std.testing.io),
    );
    var file_frame: [maximum_encoded_frame_bytes]u8 = undefined;
    const file_summary = try FileReader.summarize(
        std.testing.io,
        file,
        &file_frame,
    );
    try std.testing.expectEqual(
        written.batch.summary.input_samples,
        (try GaplessPlan.fromSummary(.{
            .audio_offset = @intCast(file_summary.audio_offset),
            .audio_bytes = @intCast(file_summary.audio_bytes),
            .frame_count = file_summary.frame_count,
            .sample_count = file_summary.sample_count,
            .sample_rate = file_summary.sample_rate,
            .channels = file_summary.channels,
            .first_xing = file_summary.first_xing,
            .first_vbri = null,
        })).audible_samples,
    );

    var vbr_file = try temporary.dir.createFile(
        std.testing.io,
        "gapless-adaptive-vbr.mp3",
        .{ .read = true },
    );
    defer vbr_file.close(std.testing.io);
    const vbr_written = try writeVbrPcmReservoirGaplessBatchFile(
        std.testing.io,
        vbr_file,
        vbr_config,
        &pcm_frames,
        511,
        0,
        73,
        encoder_identifier,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_scratch,
        &metadata_scratch,
    );
    try std.testing.expectEqual(
        vbr_written.file_end,
        try vbr_file.length(std.testing.io),
    );
    const vbr_file_summary = try FileReader.summarize(
        std.testing.io,
        vbr_file,
        &file_frame,
    );
    try std.testing.expectEqual(
        vbr_written.batch.summary.input_samples,
        (try GaplessPlan.fromSummary(.{
            .audio_offset = @intCast(vbr_file_summary.audio_offset),
            .audio_bytes = @intCast(vbr_file_summary.audio_bytes),
            .frame_count = vbr_file_summary.frame_count,
            .sample_count = vbr_file_summary.sample_count,
            .sample_rate = vbr_file_summary.sample_rate,
            .channels = vbr_file_summary.channels,
            .first_xing = vbr_file_summary.first_xing,
            .first_vbri = null,
        })).audible_samples,
    );
}

test "streams exact gapless adaptive reservoir metadata transactionally" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [8]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (4..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }

    const storage_bytes = maximum_encoded_frame_bytes * 16;
    var pending: [storage_bytes]u8 = undefined;
    var pending_scratch: [storage_bytes]u8 = undefined;
    var rollback: [storage_bytes]u8 = undefined;
    var frame_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes]u8 = undefined;
    var output_scratch: [storage_bytes]u8 = undefined;
    var streamed: [storage_bytes]u8 = @splat(0x5a);
    const identifier: [9]u8 = "GapStrm 1".*;
    var encoder = try PcmAdaptiveReservoirGaplessStreamEncoder.init(
        config,
        511,
        &pending,
    );
    try std.testing.expectError(
        error.Mp3EncoderMetadataNotStarted,
        encoder.append(
            pcm_frames[0],
            &streamed,
            &pending_scratch,
            &frame_scratch,
            &main_data_scratch,
        ),
    );
    var cursor: usize = 0;
    const placeholder = try encoder.startMetadataWithEncoder(
        identifier,
        streamed[cursor..],
        &frame_scratch,
        &main_data_scratch,
    );
    cursor += placeholder.len;
    try std.testing.expect(encoder.valid());
    for (pcm_frames) |pcm| {
        const appended = try encoder.append(
            pcm,
            streamed[cursor..],
            &pending_scratch,
            &frame_scratch,
            &main_data_scratch,
        );
        cursor += appended.frames.len;
    }
    const pending_before = pending;
    const cursor_before = cursor;
    const destination_before = streamed;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.finish(
            streamed[cursor .. cursor + 1],
            &pending_scratch,
            &rollback,
            &frame_scratch,
            &main_data_scratch,
            &output_scratch,
        ),
    );
    try std.testing.expectEqual(pending_before, pending);
    try std.testing.expectEqual(destination_before, streamed);
    try std.testing.expectEqual(cursor_before, cursor);
    try std.testing.expect(encoder.valid());
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        encoder.finish(
            streamed[cursor..],
            &pending_scratch,
            &rollback,
            &frame_scratch,
            &main_data_scratch,
            streamed[cursor..],
        ),
    );
    try std.testing.expectEqual(pending_before, pending);
    try std.testing.expectEqual(destination_before, streamed);

    const finished = try encoder.finish(
        streamed[cursor..],
        &pending_scratch,
        &rollback,
        &frame_scratch,
        &main_data_scratch,
        &output_scratch,
    );
    cursor += finished.frames.len;
    const metadata = try encoder.metadataFrame(streamed[0..placeholder.len]);
    try std.testing.expectEqual(placeholder.len, metadata.len);
    try std.testing.expectEqual(cursor, finished.summary.byte_count);
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len * 1152),
        finished.summary.input_samples,
    );
    try std.testing.expect(finished.borrowed_bytes > 0);
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        (try encoder.finish(
            streamed[cursor..],
            &pending_scratch,
            &rollback,
            &frame_scratch,
            &main_data_scratch,
            &output_scratch,
        )).frames.len,
    );

    const summary = try Stream.summarize(streamed[0..cursor]);
    try std.testing.expectEqual(
        @as(?u32, @intCast(finished.summary.frame_count)),
        summary.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(identifier, summary.first_xing.?.encoder.?);
    try std.testing.expectEqual(
        finished.summary.input_samples,
        (try GaplessPlan.fromSummary(summary)).audible_samples,
    );
    var reader = try Stream.init(streamed[0..cursor]);
    while (try reader.next()) |frame|
        try std.testing.expectEqual(@as(?bool, true), try frame.crcValid());

    var batch_destination: [storage_bytes]u8 = undefined;
    var batch_frames: [storage_bytes]u8 = undefined;
    var batch_pack: [storage_bytes]u8 = undefined;
    var batch_main: [maximum_encoded_main_data_bytes * 16]u8 = undefined;
    var batch_metadata: [maximum_encoded_frame_bytes]u8 = undefined;
    const batch = try encodePcmReservoirGaplessBatch(
        config,
        &pcm_frames,
        511,
        identifier,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
        &batch_metadata,
    );
    try std.testing.expectEqualSlices(u8, batch.stream, streamed[0..cursor]);

    const vbr_config = VbrEncoderConfig{
        .template = config,
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    streamed = @splat(0x5a);
    var vbr_encoder =
        try VbrPcmAdaptiveReservoirGaplessStreamEncoder.init(
            vbr_config,
            511,
            &pending,
        );
    cursor = 0;
    const vbr_placeholder = try vbr_encoder.startMetadataWithEncoder(
        identifier,
        streamed[cursor..],
        &frame_scratch,
    );
    cursor += vbr_placeholder.len;
    for (pcm_frames) |pcm| {
        const appended = try vbr_encoder.append(
            pcm,
            streamed[cursor..],
            &pending_scratch,
            &frame_scratch,
            &main_data_scratch,
        );
        cursor += appended.frames.len;
    }
    const vbr_pending_before = pending;
    const vbr_destination_before = streamed;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        vbr_encoder.finish(
            streamed[cursor .. cursor + 1],
            &pending_scratch,
            &rollback,
            &frame_scratch,
            &main_data_scratch,
            &output_scratch,
        ),
    );
    try std.testing.expectEqual(vbr_pending_before, pending);
    try std.testing.expectEqual(vbr_destination_before, streamed);
    try std.testing.expect(vbr_encoder.valid());
    const vbr_finished = try vbr_encoder.finish(
        streamed[cursor..],
        &pending_scratch,
        &rollback,
        &frame_scratch,
        &main_data_scratch,
        &output_scratch,
    );
    cursor += vbr_finished.frames.len;
    _ = try vbr_encoder.metadataFrame(
        73,
        streamed[0..cursor],
        streamed[0..vbr_placeholder.len],
    );
    const vbr_summary = try Stream.summarize(streamed[0..cursor]);
    try std.testing.expectEqual(
        @as(?u32, 73),
        vbr_summary.first_xing.?.quality,
    );
    try std.testing.expect(vbr_summary.first_xing.?.toc != null);
    try std.testing.expectEqual(
        vbr_finished.summary.input_samples,
        (try GaplessPlan.fromSummary(vbr_summary)).audible_samples,
    );
    const vbr_batch = try encodeVbrPcmReservoirGaplessBatch(
        vbr_config,
        &pcm_frames,
        511,
        73,
        identifier,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
        &batch_metadata,
    );
    try std.testing.expectEqualSlices(
        u8,
        vbr_batch.stream,
        streamed[0..cursor],
    );

    var hostile = encoder;
    hostile.stream.independent_frames = 0;
    try std.testing.expect(!hostile.valid());
}

test "recovers incremental adaptive reservoir file publication" {
    const prefix = [_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0 };
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [12]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (6..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }
    const required = try requiredPcmAdaptiveReservoirStorage(config, 511);
    var pending: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var staging: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var rollback: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var frame_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var main_scratch: [maximum_encoded_main_data_bytes]u8 = undefined;
    var output: [maximum_encoded_frame_bytes * 12]u8 = undefined;

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-incremental.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &prefix, 0);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    var encoder = try PcmAdaptiveReservoirFileEncoder.initAtWithOperations(
        std.testing.io,
        file,
        config,
        511,
        pending[0..required],
        staging[0..required],
        rollback[0..required],
        &frame_scratch,
        &main_scratch,
        output[0..required],
        prefix.len,
        faults.operations(),
    );
    var failed_index: ?usize = null;
    for (pcm_frames, 0..) |pcm, index| {
        _ = encoder.append(pcm) catch |failure| {
            try std.testing.expectEqual(
                error.InjectedMp3FileWriteFailure,
                failure,
            );
            failed_index = index;
            break;
        };
    }
    const retry_index = failed_index orelse
        return error.TestAdaptiveReservoirFileWriteMissing;
    try std.testing.expect(encoder.failed);
    try std.testing.expect(encoder.valid());
    try encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    for (pcm_frames[retry_index..]) |pcm| _ = try encoder.append(pcm);
    const summary = try encoder.finalize();
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        summary.frame_count,
    );
    try std.testing.expectEqual(
        @as(u64, prefix.len) + summary.byte_count,
        summary.file_end,
    );
    try std.testing.expectEqual(
        summary.file_end,
        try file.length(std.testing.io),
    );

    var batch_destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_frames: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_pack: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var batch_main: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 =
        undefined;
    const batch = try encodePcmReservoirBatch(
        config,
        &pcm_frames,
        511,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
    );
    var stored: [maximum_encoded_frame_bytes * pcm_frames.len]u8 = undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        prefix.len,
        stored[0..batch.stream.len],
        error.TestTruncatedAdaptiveIncrementalMp3,
    );
    try std.testing.expectEqualSlices(
        u8,
        batch.stream,
        stored[0..batch.stream.len],
    );

    const vbr_config = VbrEncoderConfig{
        .template = config,
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    const vbr_required =
        try requiredVbrPcmAdaptiveReservoirStorage(vbr_config, 511);
    var vbr_file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-incremental-vbr.mp3",
        .{ .read = true },
    );
    defer vbr_file.close(std.testing.io);
    try vbr_file.writePositionalAll(std.testing.io, &prefix, 0);
    faults.write_calls = 0;
    faults.fail_write_call = 1;
    var vbr_encoder =
        try VbrPcmAdaptiveReservoirFileEncoder.initAtWithOperations(
            std.testing.io,
            vbr_file,
            vbr_config,
            511,
            pending[0..vbr_required],
            staging[0..vbr_required],
            rollback[0..vbr_required],
            &frame_scratch,
            &main_scratch,
            output[0..vbr_required],
            prefix.len,
            faults.operations(),
        );
    failed_index = null;
    for (pcm_frames, 0..) |pcm, index| {
        _ = vbr_encoder.append(pcm) catch |failure| {
            try std.testing.expectEqual(
                error.InjectedMp3FileWriteFailure,
                failure,
            );
            failed_index = index;
            break;
        };
    }
    const vbr_retry_index = failed_index orelse
        return error.TestAdaptiveVbrReservoirFileWriteMissing;
    try std.testing.expect(vbr_encoder.failed);
    try std.testing.expect(vbr_encoder.valid());
    try vbr_encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try vbr_file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    for (pcm_frames[vbr_retry_index..]) |pcm|
        _ = try vbr_encoder.append(pcm);
    const vbr_summary = try vbr_encoder.finalize();
    try std.testing.expect(vbr_encoder.valid());
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        vbr_summary.frame_count,
    );
    var histogram_frames: u64 = 0;
    for (vbr_summary.bitrate_histogram) |count|
        histogram_frames += count;
    try std.testing.expectEqual(vbr_summary.frame_count, histogram_frames);
    try std.testing.expect(std.math.isFinite(
        vbr_summary.maximum_noise_to_mask_ratio,
    ));

    const vbr_batch = try encodeVbrPcmReservoirBatch(
        vbr_config,
        &pcm_frames,
        511,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
    );
    try file_reader_io.readExactAt(
        std.testing.io,
        vbr_file,
        prefix.len,
        stored[0..vbr_batch.stream.len],
        error.TestTruncatedAdaptiveIncrementalVbrMp3,
    );
    try std.testing.expectEqualSlices(
        u8,
        vbr_batch.stream,
        stored[0..vbr_batch.stream.len],
    );
}

test "recovers exact gapless adaptive CBR file publication" {
    const prefix = [_]u8{ 'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0 };
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [8]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (4..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(frame_index * 1152 + sample);
            pcm_frames[frame_index].channels[0][sample] =
                0.48 * @sin(position * 0.131) +
                0.26 * @cos(position * 0.337);
        }
    }
    const required = try requiredPcmAdaptiveReservoirStorage(config, 511);
    const finish_required =
        try requiredPcmAdaptiveReservoirGaplessFileFinishStorage(
            config,
            511,
        );
    try std.testing.expectEqual(
        required + maximum_encoded_frame_bytes,
        finish_required,
    );
    var pending: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var staging: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var rollback: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var frame_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var main_scratch: [maximum_encoded_main_data_bytes]u8 = undefined;
    var output: [maximum_encoded_frame_bytes * 12]u8 = undefined;
    var finish_storage: [maximum_encoded_frame_bytes * 12]u8 = undefined;

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-gapless-cbr.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &prefix, 0);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    var encoder =
        try PcmAdaptiveReservoirGaplessFileEncoder.initAtWithOperations(
            std.testing.io,
            file,
            config,
            511,
            &pending,
            &staging,
            &rollback,
            &frame_scratch,
            &main_scratch,
            output[0..finish_required],
            finish_storage[0..finish_required],
            prefix.len,
            faults.operations(),
        );
    try std.testing.expectError(
        error.InvalidMp3AdaptiveReservoirGaplessFileEncoderState,
        encoder.append(pcm_frames[0]),
    );
    const identifier: [9]u8 = "File CBR ".*;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        encoder.startMetadataWithEncoder(identifier),
    );
    try std.testing.expect(encoder.failed);
    try std.testing.expect(encoder.valid());
    try encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    const placeholder = try encoder.startMetadataWithEncoder(identifier);
    try std.testing.expect(placeholder.len != 0);
    for (pcm_frames) |pcm| _ = try encoder.append(pcm);
    const committed_before = encoder.committed_bytes;
    faults.fail_write_call = faults.write_calls + 2;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        encoder.finalize(),
    );
    try std.testing.expect(encoder.failed);
    try std.testing.expect(encoder.valid());
    try encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len) + committed_before,
        try file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    faults.fail_sync_call = 1;
    try std.testing.expectError(
        error.InjectedMp3FileSyncFailure,
        encoder.finalize(),
    );
    try std.testing.expect(encoder.failed);
    try std.testing.expect(encoder.valid());
    try encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len) + committed_before,
        try file.length(std.testing.io),
    );
    faults.fail_sync_call = null;
    const summary = try encoder.finalize();
    try std.testing.expect(encoder.valid());
    try std.testing.expectEqual(
        @as(u64, prefix.len) + summary.stream.byte_count,
        summary.file_end,
    );

    const maximum_frames = pcm_frames.len + 3;
    var batch_destination: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var batch_frames: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var batch_pack: [maximum_encoded_frame_bytes * maximum_frames]u8 =
        undefined;
    var batch_main: [maximum_encoded_main_data_bytes * maximum_frames]u8 =
        undefined;
    var batch_metadata: [maximum_encoded_frame_bytes]u8 = undefined;
    const batch = try encodePcmReservoirGaplessBatch(
        config,
        &pcm_frames,
        511,
        identifier,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
        &batch_metadata,
    );
    var stored: [maximum_encoded_frame_bytes * maximum_frames]u8 = undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        prefix.len,
        stored[0..batch.stream.len],
        error.TestTruncatedAdaptiveGaplessCbrMp3,
    );
    try std.testing.expectEqualSlices(
        u8,
        batch.stream,
        stored[0..batch.stream.len],
    );

    const vbr_config = VbrEncoderConfig{
        .template = config,
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    const vbr_required =
        try requiredVbrPcmAdaptiveReservoirStorage(vbr_config, 511);
    const vbr_finish_required =
        try requiredVbrPcmAdaptiveReservoirGaplessFileFinishStorage(
            vbr_config,
            511,
        );
    try std.testing.expectEqual(
        vbr_required + maximum_encoded_frame_bytes,
        vbr_finish_required,
    );
    const required_frame_offsets =
        try requiredVbrPcmAdaptiveReservoirGaplessFrameOffsets(
            vbr_config,
            pcm_frames.len,
        );
    try std.testing.expectEqual(
        pcm_frames.len + 2,
        required_frame_offsets,
    );
    var vbr_file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-gapless-vbr.mp3",
        .{ .read = true },
    );
    defer vbr_file.close(std.testing.io);
    try vbr_file.writePositionalAll(std.testing.io, &prefix, 0);
    var frame_offsets: [maximum_frames]u64 = undefined;
    faults = .{};
    try std.testing.expectError(
        error.Mp3VbrFrameIndexStorageTooSmall,
        VbrPcmAdaptiveReservoirGaplessFileEncoder.initAtWithOperations(
            std.testing.io,
            vbr_file,
            vbr_config,
            511,
            &pending,
            &staging,
            &rollback,
            &frame_scratch,
            &main_scratch,
            output[0..vbr_finish_required],
            finish_storage[0..vbr_finish_required],
            frame_offsets[0..0],
            prefix.len,
            faults.operations(),
        ),
    );
    var initial_frame_offsets: [1]u64 = undefined;
    var vbr_encoder =
        try VbrPcmAdaptiveReservoirGaplessFileEncoder.initAtWithOperations(
            std.testing.io,
            vbr_file,
            vbr_config,
            511,
            &pending,
            &staging,
            &rollback,
            &frame_scratch,
            &main_scratch,
            output[0..vbr_finish_required],
            finish_storage[0..vbr_finish_required],
            &initial_frame_offsets,
            prefix.len,
            faults.operations(),
        );
    _ = try vbr_encoder.startMetadataWithEncoder(identifier);
    var retry_index: ?usize = null;
    for (pcm_frames, 0..) |pcm, index| {
        _ = vbr_encoder.append(pcm) catch |failure| {
            try std.testing.expectEqual(
                error.Mp3VbrFrameIndexStorageTooSmall,
                failure,
            );
            retry_index = index;
            break;
        };
    }
    const capacity_retry = retry_index orelse
        return error.TestAdaptiveGaplessVbrCapacityFailureMissing;
    try std.testing.expect(vbr_encoder.valid());
    try std.testing.expectEqual(
        @as(u64, prefix.len) + vbr_encoder.committed_bytes,
        try vbr_file.length(std.testing.io),
    );
    try std.testing.expectError(
        error.Mp3VbrFrameIndexStorageTooSmall,
        vbr_encoder.replaceFrameOffsetStorage(frame_offsets[0..0]),
    );
    try vbr_encoder.replaceFrameOffsetStorage(
        frame_offsets[0..required_frame_offsets],
    );
    for (pcm_frames[capacity_retry..]) |pcm|
        _ = try vbr_encoder.append(pcm);
    const vbr_committed_before = vbr_encoder.committed_bytes;
    faults.fail_write_call = faults.write_calls + 2;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        vbr_encoder.finalize(73),
    );
    try std.testing.expect(vbr_encoder.failed);
    try std.testing.expect(vbr_encoder.valid());
    try vbr_encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len) + vbr_committed_before,
        try vbr_file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    faults.fail_sync_call = 1;
    try std.testing.expectError(
        error.InjectedMp3FileSyncFailure,
        vbr_encoder.finalize(73),
    );
    try std.testing.expect(vbr_encoder.failed);
    try std.testing.expect(vbr_encoder.valid());
    try vbr_encoder.recover();
    try std.testing.expectEqual(
        @as(u64, prefix.len) + vbr_committed_before,
        try vbr_file.length(std.testing.io),
    );
    faults.fail_sync_call = null;
    const vbr_summary = try vbr_encoder.finalize(73);
    try std.testing.expect(vbr_encoder.valid());
    try std.testing.expectEqual(
        @as(u64, prefix.len) + vbr_summary.stream.byte_count,
        vbr_summary.file_end,
    );
    const vbr_batch = try encodeVbrPcmReservoirGaplessBatch(
        vbr_config,
        &pcm_frames,
        511,
        73,
        identifier,
        &batch_destination,
        &batch_frames,
        &batch_pack,
        &batch_main,
        &batch_metadata,
    );
    try file_reader_io.readExactAt(
        std.testing.io,
        vbr_file,
        prefix.len,
        stored[0..vbr_batch.stream.len],
        error.TestTruncatedAdaptiveGaplessVbrMp3,
    );
    try std.testing.expectEqualSlices(
        u8,
        vbr_batch.stream,
        stored[0..vbr_batch.stream.len],
    );
    var hostile_vbr = vbr_encoder;
    hostile_vbr.indexed_frames -= 1;
    try std.testing.expect(!hostile_vbr.valid());
    var hostile_offsets = frame_offsets;
    hostile_vbr = vbr_encoder;
    hostile_vbr.frame_offsets = &hostile_offsets;
    hostile_offsets[1] = 0;
    try std.testing.expect(!hostile_vbr.valid());
    hostile_offsets = frame_offsets;
    hostile_offsets[1] += 1;
    try std.testing.expect(!hostile_vbr.valid());
}

test "writes adaptive MP3 reservoir batches atomically at file offsets" {
    const prefix = [_]u8{
        'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0,
    };
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 32,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    var pcm_frames: [9]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (5..pcm_frames.len) |frame_index| {
        for (0..1152) |sample| {
            const position: f32 = @floatFromInt(
                frame_index * 1152 + sample,
            );
            pcm_frames[frame_index].channels[0][sample] =
                0.47 * @sin(position * 0.119) +
                0.29 * @cos(position * 0.307);
        }
    }
    var destination: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var frame_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var pack_scratch: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    var main_data_scratch: [maximum_encoded_main_data_bytes * pcm_frames.len]u8 = undefined;

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-reservoir.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &prefix, 0);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        writePcmReservoirBatchFileWithOperations(
            std.testing.io,
            file,
            config,
            &pcm_frames,
            511,
            prefix.len,
            &destination,
            &frame_scratch,
            &pack_scratch,
            &main_data_scratch,
            faults.operations(),
        ),
    );
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try file.length(std.testing.io),
    );
    var retained_prefix: [prefix.len]u8 = undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        0,
        &retained_prefix,
        error.TestTruncatedAdaptiveMp3Prefix,
    );
    try std.testing.expectEqualSlices(u8, &prefix, &retained_prefix);

    faults.fail_write_call = null;
    const written = try writePcmReservoirBatchFileWithOperations(
        std.testing.io,
        file,
        config,
        &pcm_frames,
        511,
        prefix.len,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
        faults.operations(),
    );
    try std.testing.expectEqual(
        @as(u64, prefix.len) + written.batch.stream.len,
        written.file_end,
    );
    try std.testing.expectEqual(
        written.file_end,
        try file.length(std.testing.io),
    );
    var stored: [maximum_encoded_frame_bytes * pcm_frames.len]u8 =
        undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        prefix.len,
        stored[0..written.batch.stream.len],
        error.TestTruncatedAdaptiveMp3Batch,
    );
    try std.testing.expectEqualSlices(
        u8,
        written.batch.stream,
        stored[0..written.batch.stream.len],
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 = undefined;
    const summary = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(written.batch.frame_count, summary.frame_count);
    try std.testing.expectEqual(@as(u64, prefix.len), summary.audio_offset);

    var vbr_file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-vbr-reservoir.mp3",
        .{ .read = true },
    );
    defer vbr_file.close(std.testing.io);
    const vbr_written = try writeVbrPcmReservoirBatchFile(
        std.testing.io,
        vbr_file,
        .{
            .template = .{
                .version = .mpeg1,
                .sample_rate = 44_100,
                .channel_mode = .mono,
                .crc_present = true,
            },
            .minimum_bitrate_index = 1,
            .maximum_bitrate_index = 5,
            .maximum_noise_to_mask_ratio = 0.5,
        },
        &pcm_frames,
        511,
        0,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
    );
    try std.testing.expectEqual(
        vbr_written.batch.frame_count,
        (try FileReader.summarize(
            std.testing.io,
            vbr_file,
            &frame_storage,
        )).frame_count,
    );
    try std.testing.expectEqual(
        vbr_written.file_end,
        try vbr_file.length(std.testing.io),
    );

    var metadata_scratch: [maximum_encoded_frame_bytes]u8 = undefined;
    var info_file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-info-reservoir.mp3",
        .{ .read = true },
    );
    defer info_file.close(std.testing.io);
    try info_file.writePositionalAll(std.testing.io, &prefix, 0);
    try info_file.writePositionalAll(
        std.testing.io,
        "stale audio",
        prefix.len,
    );
    var metadata_faults = Mp3FileFaults{
        .fail_write_call = 2,
        .partial_write_bytes = 9,
    };
    const info_encoder: [9]u8 = "BatchCBR1".*;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        writePcmReservoirBatchFileWithInfoAndOperations(
            std.testing.io,
            info_file,
            config,
            &pcm_frames,
            511,
            prefix.len,
            info_encoder,
            &destination,
            &frame_scratch,
            &pack_scratch,
            &main_data_scratch,
            &metadata_scratch,
            metadata_faults.operations(),
        ),
    );
    try std.testing.expectEqual(
        @as(u64, prefix.len),
        try info_file.length(std.testing.io),
    );
    metadata_faults.fail_write_call = null;
    const info_written =
        try writePcmReservoirBatchFileWithInfoAndOperations(
            std.testing.io,
            info_file,
            config,
            &pcm_frames,
            511,
            prefix.len,
            info_encoder,
            &destination,
            &frame_scratch,
            &pack_scratch,
            &main_data_scratch,
            &metadata_scratch,
            metadata_faults.operations(),
        );
    const info_summary = try FileReader.summarize(
        std.testing.io,
        info_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        info_written.batch.frame_count + 1,
        info_summary.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(info_summary.frame_count)),
        info_summary.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(
            info_written.file_end - prefix.len,
        )),
        info_summary.first_xing.?.stream_bytes,
    );
    try std.testing.expectEqual(
        info_encoder,
        info_summary.first_xing.?.encoder.?,
    );
    try std.testing.expect(info_summary.first_xing.?.encoder_delay == null);
    try std.testing.expect(info_summary.first_xing.?.encoder_padding == null);

    var xing_file = try temporary.dir.createFile(
        std.testing.io,
        "adaptive-xing-reservoir.mp3",
        .{ .read = true },
    );
    defer xing_file.close(std.testing.io);
    const xing_encoder: [9]u8 = "BatchVBR1".*;
    const xing_written = try writeVbrPcmReservoirBatchFileWithXing(
        std.testing.io,
        xing_file,
        .{
            .template = .{
                .version = .mpeg1,
                .sample_rate = 44_100,
                .channel_mode = .mono,
                .crc_present = true,
            },
            .minimum_bitrate_index = 1,
            .maximum_bitrate_index = 5,
            .maximum_noise_to_mask_ratio = 0.5,
        },
        &pcm_frames,
        511,
        0,
        73,
        xing_encoder,
        &destination,
        &frame_scratch,
        &pack_scratch,
        &main_data_scratch,
        &metadata_scratch,
    );
    const xing_summary = try FileReader.summarize(
        std.testing.io,
        xing_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        xing_written.batch.frame_count + 1,
        xing_summary.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, 73),
        xing_summary.first_xing.?.quality,
    );
    try std.testing.expect(xing_summary.first_xing.?.toc != null);
    try std.testing.expectEqual(
        xing_encoder,
        xing_summary.first_xing.?.encoder.?,
    );
    try std.testing.expect(xing_summary.first_xing.?.encoder_delay == null);
    try std.testing.expect(xing_summary.first_xing.?.encoder_padding == null);
}

test "bounds cumulative MP3 reservoir borrowing by version" {
    try std.testing.expect(reservoirBorrowedBytesValid(
        .mpeg1,
        2,
        511,
    ));
    try std.testing.expect(!reservoirBorrowedBytesValid(
        .mpeg1,
        2,
        512,
    ));
    try std.testing.expect(reservoirBorrowedBytesValid(
        .mpeg2,
        2,
        255,
    ));
    try std.testing.expect(!reservoirBorrowedBytesValid(
        .mpeg25,
        2,
        256,
    ));
    try std.testing.expect(reservoirBorrowedBytesValid(
        .mpeg1,
        0,
        0,
    ));
    try std.testing.expect(!reservoirBorrowedBytesValid(
        .mpeg1,
        0,
        1,
    ));
    try std.testing.expect(reservoirBorrowedBytesValid(
        .mpeg1,
        std.math.maxInt(u64),
        std.math.maxInt(u64),
    ));
    try std.testing.expect(reservoirPendingBorrowedBytesValid(
        .mpeg1,
        2,
        511,
        511,
    ));
    try std.testing.expect(!reservoirPendingBorrowedBytesValid(
        .mpeg1,
        2,
        510,
        511,
    ));
    try std.testing.expect(reservoirPendingBorrowedBytesValid(
        .mpeg1,
        3,
        700,
        200,
    ));
    try std.testing.expect(!reservoirPendingBorrowedBytesValid(
        .mpeg1,
        3,
        712,
        200,
    ));
}

test "composes VBR selection with MP3 main-data reuse" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 8,
        .maximum_bitrate_index = 11,
    };
    const bitrate_indexes = [_]u4{ 8, 11, 9 };
    var pcm_frames: [3]PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (0..1152) |sample| {
        const position: f32 = @floatFromInt(sample);
        pcm_frames[1].channels[0][sample] =
            0.4 * @sin(position * 0.17) +
            0.2 * @sin(position * 0.41);
        pcm_frames[2].channels[0][sample] =
            0.3 * @sin(position * 0.09);
    }

    var ordinary = try VbrPcmEncoder.init(config);
    var ordinary_bytes: [maximum_encoded_frame_bytes * pcm_frames.len]u8 = undefined;
    var ordinary_length: usize = 0;
    for (pcm_frames, bitrate_indexes) |pcm, index| {
        const selected = try ordinary.encodeAtBitrateIndex(
            pcm,
            ordinary_bytes[ordinary_length..],
            index,
        );
        try std.testing.expectEqual(index, selected.bitrate_index);
        ordinary_length += selected.frame.len;
    }

    var reservoir = try VbrPcmReservoirEncoder.init(config);
    try std.testing.expect(reservoir.valid());
    var reservoir_bytes: [maximum_encoded_frame_bytes * pcm_frames.len]u8 = undefined;
    var reservoir_length: usize = 0;
    var total_borrowed: u64 = 0;
    for (pcm_frames, bitrate_indexes, 0..) |pcm, index, frame_index| {
        const appended = try reservoir.appendAtBitrateIndex(
            pcm,
            reservoir_bytes[reservoir_length..],
            index,
        );
        try std.testing.expect(reservoir.valid());
        try std.testing.expectEqual(
            index,
            appended.selection.bitrate_index,
        );
        try std.testing.expectEqual(
            bitrate(.mpeg1, index),
            appended.selection.header.bitrate_kbps,
        );
        if (frame_index == 0) {
            try std.testing.expect(appended.frame == null);
            const before = reservoir;
            try std.testing.expectError(
                error.InsufficientMp3EncoderStorage,
                reservoir.appendAtBitrateIndex(
                    pcm_frames[1],
                    reservoir_bytes[0..0],
                    bitrate_indexes[1],
                ),
            );
            try std.testing.expectEqual(
                before.encoder,
                reservoir.encoder,
            );
            try std.testing.expectEqual(
                before.frames_received,
                reservoir.frames_received,
            );
            try std.testing.expectEqual(
                before.frames_emitted,
                reservoir.frames_emitted,
            );
            try std.testing.expectEqualSlices(
                u8,
                before.pending[0..before.pending_length],
                reservoir.pending[0..reservoir.pending_length],
            );
        } else {
            const frame = appended.frame orelse
                return error.TestMp3ReservoirFrameMissing;
            reservoir_length += frame.len;
            total_borrowed += appended.borrowed_bytes;
            if (appended.borrowed_bytes != 0) {
                var mismatched_borrow = reservoir;
                mismatched_borrow.borrowed_bytes -=
                    appended.borrowed_bytes;
                try std.testing.expect(!mismatched_borrow.valid());
            }
        }
    }
    const final_frame = (try reservoir.finish(
        reservoir_bytes[reservoir_length..],
    )) orelse return error.TestMp3ReservoirFrameMissing;
    try std.testing.expect(reservoir.valid());
    reservoir_length += final_frame.len;
    try std.testing.expectEqual(
        ordinary_length,
        reservoir_length,
    );
    try std.testing.expect(total_borrowed > 0);
    try std.testing.expectEqual(
        total_borrowed,
        reservoir.borrowed_bytes,
    );
    try std.testing.expectEqual(
        @as(u64, pcm_frames.len),
        reservoir.frames_received,
    );
    try std.testing.expectEqual(
        reservoir.frames_received,
        reservoir.frames_emitted,
    );

    var ordinary_stream = try Stream.init(
        ordinary_bytes[0..ordinary_length],
    );
    var reservoir_stream = try Stream.init(
        reservoir_bytes[0..reservoir_length],
    );
    var ordinary_decoder = FrameDecoder{};
    var reservoir_decoder = FrameDecoder{};
    var borrowed_frame_seen = false;
    while (try ordinary_stream.next()) |ordinary_frame| {
        const reservoir_frame =
            (try reservoir_stream.next()) orelse
            return error.TestMp3ReservoirFrameMissing;
        try std.testing.expectEqual(
            ordinary_frame.header.bitrate_kbps,
            reservoir_frame.header.bitrate_kbps,
        );
        const side = try reservoir_frame.sideInformation();
        borrowed_frame_seen =
            borrowed_frame_seen or side.main_data_begin != 0;
        try std.testing.expectEqual(
            @as(?bool, true),
            try reservoir_frame.crcValid(),
        );
        const ordinary_pcm =
            try ordinary_decoder.decode(ordinary_frame);
        const reservoir_pcm =
            try reservoir_decoder.decode(reservoir_frame);
        for (
            ordinary_pcm.channels[0][0..ordinary_pcm.sample_count],
            reservoir_pcm.channels[0][0..reservoir_pcm.sample_count],
        ) |expected, actual|
            try std.testing.expectEqual(expected, actual);
    }
    try std.testing.expect(
        (try reservoir_stream.next()) == null,
    );
    try std.testing.expect(borrowed_frame_seen);
    try std.testing.expect(
        (try reservoir.finish(
            reservoir_bytes[reservoir_length..],
        )) == null,
    );
    try std.testing.expectError(
        error.Mp3VbrReservoirEncoderFinalized,
        reservoir.append(
            pcm_frames[0],
            reservoir_bytes[reservoir_length..],
        ),
    );

    var malformed = try VbrPcmReservoirEncoder.init(config);
    _ = try malformed.appendAtBitrateIndex(
        pcm_frames[0],
        reservoir_bytes[0..0],
        bitrate_indexes[0],
    );
    malformed.pending[4] ^= 1;
    try std.testing.expect(!malformed.valid());
    const malformed_before = malformed;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirEncoderState,
        malformed.finish(&reservoir_bytes),
    );
    try std.testing.expectEqual(malformed_before, malformed);
    var impossible_borrow = try VbrPcmReservoirEncoder.init(config);
    impossible_borrow.borrowed_bytes = 1;
    try std.testing.expect(!impossible_borrow.valid());
    const impossible_borrow_before = impossible_borrow;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirEncoderState,
        impossible_borrow.finish(&reservoir_bytes),
    );
    try std.testing.expectEqual(
        impossible_borrow_before,
        impossible_borrow,
    );
}

test "finishes reservoir-backed MP3 VBR streams with Xing metadata" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 8,
        .maximum_bitrate_index = 11,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    var offsets: [8]u64 = undefined;
    var encoder = try VbrPcmReservoirStreamEncoder.init(
        config,
        &offsets,
    );
    var encoded: [maximum_encoded_frame_bytes * 6]u8 =
        undefined;
    var cursor: usize = 0;
    const metadata_encoder: [9]u8 = "Reservr 1".*;
    const placeholder = try encoder.startXingMetadataWithEncoder(
        metadata_encoder,
        encoded[cursor..],
    );
    cursor += placeholder.len;
    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };
    const primed = try encoder.append(
        silence,
        encoded[cursor..],
    );
    try std.testing.expect(primed.frame == null);
    var detailed = silence;
    for (&detailed.channels[0], 0..) |*sample, index| {
        const position: f32 = @floatFromInt(index);
        sample.* =
            0.25 * @sin(position * 0.11) +
            0.2 * @sin(position * 0.37);
    }
    const emitted = try encoder.append(
        detailed,
        encoded[cursor..],
    );
    const previous = emitted.frame orelse
        return error.TestMp3ReservoirFrameMissing;
    cursor += previous.len;
    try std.testing.expect(emitted.borrowed_bytes > 0);

    var mismatched_borrow = encoder;
    mismatched_borrow.borrowed_bytes -= emitted.borrowed_bytes;
    try std.testing.expect(!mismatched_borrow.valid());
    const mismatched_before = mismatched_borrow;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirStreamState,
        mismatched_borrow.finish(encoded[cursor..]),
    );
    try std.testing.expectEqual(
        mismatched_before,
        mismatched_borrow,
    );

    const before_finish = encoder;
    var short: [1]u8 = .{0x5a};
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        encoder.finish(&short),
    );
    try std.testing.expectEqual(@as(u8, 0x5a), short[0]);
    try std.testing.expectEqual(
        before_finish.encoder.encoder,
        encoder.encoder.encoder,
    );
    try std.testing.expectEqual(
        before_finish.frames_emitted,
        encoder.frames_emitted,
    );
    try std.testing.expectEqualSlices(
        u8,
        before_finish.pending[0..before_finish.pending_length],
        encoder.pending[0..encoder.pending_length],
    );

    const finished = try encoder.finish(encoded[cursor..]);
    cursor += finished.frames.len;
    try std.testing.expectEqual(@as(u64, 4), finished.summary.frame_count);
    try std.testing.expectEqual(
        @as(u64, 2304),
        finished.summary.input_samples,
    );
    try std.testing.expectEqual(
        @as(u16, 2209),
        finished.summary.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(u16, 95),
        finished.summary.end_padding,
    );
    try std.testing.expectEqual(
        @as(u64, cursor),
        finished.summary.byte_count,
    );
    try std.testing.expect(finished.borrowed_bytes > 0);
    try std.testing.expectEqual(
        finished.summary.frame_count,
        encoder.frames_emitted,
    );

    var final_metadata: [maximum_encoded_frame_bytes]u8 =
        undefined;
    const replacement = try encoder.xingMetadataFrame(
        23,
        &final_metadata,
    );
    try std.testing.expectEqual(placeholder.len, replacement.len);
    @memcpy(encoded[0..replacement.len], replacement);
    const summary = try Stream.summarize(encoded[0..cursor]);
    try std.testing.expectEqual(
        metadata_encoder,
        summary.first_xing.?.encoder.?,
    );
    try std.testing.expectEqual(
        @as(?u32, 4),
        summary.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(cursor)),
        summary.first_xing.?.stream_bytes,
    );
    try std.testing.expectEqual(
        @as(?u32, 23),
        summary.first_xing.?.quality,
    );

    var stream = try Stream.init(encoded[0..cursor]);
    var decoder = FrameDecoder{};
    var frame_count: u64 = 0;
    var borrowed_seen = false;
    while (try stream.next()) |frame| {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        borrowed_seen = borrowed_seen or
            (try frame.sideInformation()).main_data_begin != 0;
        const pcm = try decoder.decode(frame);
        for (pcm.channels[0]) |sample|
            try std.testing.expect(std.math.isFinite(sample));
        frame_count += 1;
    }
    try std.testing.expectEqual(@as(u64, 4), frame_count);
    try std.testing.expect(borrowed_seen);

    const repeated = try encoder.finish(encoded[cursor..]);
    try std.testing.expectEqual(
        @as(usize, 0),
        repeated.frames.len,
    );
    try std.testing.expectEqual(
        finished.borrowed_bytes,
        repeated.borrowed_bytes,
    );

    var corrupted_offsets: [4]u64 = undefined;
    var corrupted = try VbrPcmReservoirStreamEncoder.init(
        config,
        &corrupted_offsets,
    );
    _ = try corrupted.append(silence, encoded[0..0]);
    corrupted.pending[4] ^= 1;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirStreamState,
        corrupted.finish(&encoded),
    );

    var impossible_offsets: [4]u64 = undefined;
    var impossible_borrow = try VbrPcmReservoirStreamEncoder.init(
        config,
        &impossible_offsets,
    );
    impossible_borrow.borrowed_bytes = 1;
    try std.testing.expect(!impossible_borrow.valid());
    const impossible_borrow_before = impossible_borrow;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirStreamState,
        impossible_borrow.finish(&encoded),
    );
    try std.testing.expectEqual(
        impossible_borrow_before.encoder,
        impossible_borrow.encoder,
    );
    try std.testing.expectEqual(
        impossible_borrow_before.borrowed_bytes,
        impossible_borrow.borrowed_bytes,
    );

    var unprotected_config = config;
    unprotected_config.template.crc_present = false;
    var malformed_offsets: [4]u64 = undefined;
    var malformed = try VbrPcmReservoirStreamEncoder.init(
        unprotected_config,
        &malformed_offsets,
    );
    _ = try malformed.append(silence, encoded[0..0]);
    malformed.pending[3] ^= 0xc0;
    try std.testing.expectError(
        error.InvalidMp3VbrReservoirStreamState,
        malformed.finish(&encoded),
    );
}

test "finishes MP3 reservoir streams transactionally" {
    const configs = [_]EncoderConfig{
        .{
            .version = .mpeg1,
            .bitrate_kbps = 128,
            .sample_rate = 44_100,
            .channel_mode = .mono,
        },
        .{
            .version = .mpeg2,
            .bitrate_kbps = 64,
            .sample_rate = 22_050,
            .channel_mode = .mono,
        },
    };
    for (configs) |config| {
        const samples_per_frame =
            (try config.header(false)).samplesPerFrame();
        var pcm = PcmFrame{
            .channel_count = 1,
            .sample_count = samples_per_frame,
        };
        for (0..samples_per_frame) |sample| {
            pcm.channels[0][sample] =
                0.5 * @sin(
                    2.0 * std.math.pi *
                        @as(f32, @floatFromInt(sample)) /
                        41.0,
                );
        }
        var encoder =
            try PcmReservoirStreamEncoder.init(config);
        var encoded: [maximum_encoded_frame_bytes * 6]u8 =
            undefined;
        var encoded_bytes: usize = 0;
        const first = try encoder.append(
            .{
                .channel_count = 1,
                .sample_count = samples_per_frame,
            },
            encoded[0..0],
        );
        try std.testing.expect(first.frame == null);
        const second = try encoder.append(
            pcm,
            encoded[encoded_bytes..],
        );
        const emitted = second.frame orelse
            return error.TestMp3ReservoirFrameMissing;
        encoded_bytes += emitted.len;
        try std.testing.expect(second.borrowed_bytes > 0);
        try std.testing.expectError(
            error.Mp3EncoderStreamIncomplete,
            encoder.summary(),
        );

        var short: [1]u8 = .{0x5a};
        const before_finish = encoder;
        try std.testing.expectError(
            error.InsufficientMp3EncoderStorage,
            encoder.finish(&short),
        );
        try std.testing.expectEqual(
            before_finish.frame_count,
            encoder.frame_count,
        );
        try std.testing.expectEqual(
            before_finish.encoder.pending_length,
            encoder.encoder.pending_length,
        );
        try std.testing.expectEqual(@as(u8, 0x5a), short[0]);

        const finished = try encoder.finish(
            encoded[encoded_bytes..],
        );
        encoded_bytes += finished.frames.len;
        try std.testing.expect(
            finished.borrowed_bytes > 0,
        );
        try std.testing.expectEqual(
            @as(u64, samples_per_frame) * 2,
            finished.summary.input_samples,
        );
        try std.testing.expectEqual(
            @as(u16, encoder_analysis_delay),
            finished.summary.encoder_delay,
        );
        try std.testing.expectEqual(
            @as(u16, 95),
            finished.summary.end_padding,
        );
        try std.testing.expectEqual(
            @as(u64, encoded_bytes),
            finished.summary.byte_count,
        );
        const parsed = try Stream.summarize(
            encoded[0..encoded_bytes],
        );
        try std.testing.expectEqual(
            finished.summary.frame_count,
            parsed.frame_count,
        );
        try std.testing.expectEqual(
            finished.summary.encoded_samples,
            parsed.sample_count,
        );
        const repeated = try encoder.finish(
            encoded[encoded_bytes..],
        );
        try std.testing.expectEqual(
            @as(usize, 0),
            repeated.frames.len,
        );
        try std.testing.expectEqual(
            finished.summary,
            repeated.summary,
        );
    }
}

test "writes and recovers MP3 VBR files" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .maximum_noise_to_mask_ratio = 0.25,
    };
    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };
    var signal = silence;
    for (&signal.channels[0], 0..) |*sample, index| {
        const position: f32 = @floatFromInt(index);
        sample.* =
            0.19 * @sin(position * 0.047) +
            0.13 * @sin(position * 0.233);
        if (index % 43 == 0)
            sample.* -= 0.28;
    }

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "vbr.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var storage: [maximum_encoded_frame_bytes * 2]u8 =
        undefined;
    var offsets: [8]u64 = @splat(0xdead);
    var writer = try VbrPcmFileEncoder.init(
        std.testing.io,
        file,
        config,
        &storage,
        &offsets,
    );
    const metadata_encoder: [9]u8 = "VBRFile 1".*;
    try writer.startXingMetadataWithEncoder(
        61,
        metadata_encoder,
    );
    const quiet = try writer.append(silence);
    const detailed = try writer.append(signal);
    try std.testing.expect(
        detailed.bitrate_index > quiet.bitrate_index,
    );
    const summary = try writer.finalize();
    try std.testing.expectEqual(
        summary.stream.byte_count,
        try file.length(std.testing.io),
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 =
        undefined;
    const parsed = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        XingKind.variable,
        parsed.first_xing.?.kind,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(summary.stream.frame_count)),
        parsed.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, 61),
        parsed.first_xing.?.quality,
    );
    try std.testing.expect(
        parsed.first_xing.?.toc != null,
    );
    try std.testing.expectEqual(
        metadata_encoder,
        parsed.first_xing.?.encoder.?,
    );
    try std.testing.expectEqual(
        summary,
        try writer.finalize(),
    );

    var recovered_file = try temporary.dir.createFile(
        std.testing.io,
        "vbr-recovered.mp3",
        .{ .read = true },
    );
    defer recovered_file.close(std.testing.io);
    var recovered_offsets: [8]u64 = @splat(0xbeef);
    var faults = Mp3FileFaults{};
    var recovered = try VbrPcmFileEncoder.initWithOperations(
        std.testing.io,
        recovered_file,
        config,
        &storage,
        &recovered_offsets,
        faults.operations(),
    );
    const recovered_encoder: [9]u8 = "VBRRecov1".*;
    try recovered.startXingMetadataWithEncoder(
        29,
        recovered_encoder,
    );
    _ = try recovered.append(silence);
    _ = try recovered.append(signal);
    const committed = recovered.committed_bytes;
    const flush_index =
        recovered.stream.encoder.frames.frames_encoded;
    const retained_offset = recovered_offsets[flush_index];
    faults.fail_write_call = faults.write_calls + 2;
    faults.partial_write_bytes = 8;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        recovered.finalize(),
    );
    try std.testing.expect(recovered.failed);
    try std.testing.expectEqual(
        retained_offset,
        recovered_offsets[flush_index],
    );
    faults.fail_write_call = null;
    try recovered.recover();
    try std.testing.expectEqual(
        committed,
        try recovered_file.length(std.testing.io),
    );
    const provisional = try FileReader.summarize(
        std.testing.io,
        recovered_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, 0),
        provisional.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        provisional.first_xing.?.encoder.?,
    );
    const recovered_summary = try recovered.finalize();
    const final = try FileReader.summarize(
        std.testing.io,
        recovered_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(
            recovered_summary.stream.frame_count,
        )),
        final.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        final.first_xing.?.encoder.?,
    );
    try std.testing.expectEqual(
        recovered_summary.stream.byte_count,
        try recovered_file.length(std.testing.io),
    );
}

test "writes and recovers reservoir-backed MP3 VBR files" {
    const config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 8,
        .maximum_bitrate_index = 11,
        .maximum_noise_to_mask_ratio = 0.5,
    };
    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };
    var signal = silence;
    for (&signal.channels[0], 0..) |*sample, index| {
        const position: f32 = @floatFromInt(index);
        sample.* =
            0.23 * @sin(position * 0.071) +
            0.17 * @sin(position * 0.293);
    }

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "vbr-reservoir.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var storage: [maximum_encoded_frame_bytes * 3]u8 =
        undefined;
    var offsets: [8]u64 = @splat(0xdead);
    var writer = try VbrPcmReservoirFileEncoder.init(
        std.testing.io,
        file,
        config,
        &storage,
        &offsets,
    );
    const metadata_encoder: [9]u8 = "VBRResv 1".*;
    try writer.startXingMetadataWithEncoder(
        37,
        metadata_encoder,
    );
    const metadata_bytes = writer.committed_bytes;
    const primed = try writer.append(silence);
    try std.testing.expect(primed.frame == null);
    try std.testing.expectEqual(
        metadata_bytes,
        try file.length(std.testing.io),
    );
    const emitted = try writer.append(signal);
    try std.testing.expect(emitted.frame != null);
    try std.testing.expect(emitted.borrowed_bytes > 0);
    try std.testing.expectEqual(
        writer.committed_bytes,
        try file.length(std.testing.io),
    );
    const summary = try writer.finalize();
    try std.testing.expect(summary.borrowed_bytes > 0);
    try std.testing.expectEqual(
        summary.stream.byte_count,
        try file.length(std.testing.io),
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 =
        undefined;
    const parsed = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(summary.stream.frame_count)),
        parsed.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, 37),
        parsed.first_xing.?.quality,
    );
    try std.testing.expectEqual(
        metadata_encoder,
        parsed.first_xing.?.encoder.?,
    );
    var reader = try FileReader.init(std.testing.io, file);
    var borrowed_seen = false;
    while (try reader.next(&frame_storage)) |frame| {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        borrowed_seen = borrowed_seen or
            (try frame.sideInformation()).main_data_begin != 0;
    }
    try std.testing.expect(borrowed_seen);
    try std.testing.expectEqual(
        summary,
        try writer.finalize(),
    );

    var recovered_file = try temporary.dir.createFile(
        std.testing.io,
        "vbr-reservoir-recovered.mp3",
        .{ .read = true },
    );
    defer recovered_file.close(std.testing.io);
    var recovered_offsets: [8]u64 = @splat(0xbeef);
    var faults = Mp3FileFaults{};
    var recovered =
        try VbrPcmReservoirFileEncoder.initWithOperations(
            std.testing.io,
            recovered_file,
            config,
            &storage,
            &recovered_offsets,
            faults.operations(),
        );
    const recovered_encoder: [9]u8 = "VRRecover".*;
    try recovered.startXingMetadataWithEncoder(
        19,
        recovered_encoder,
    );
    _ = try recovered.append(silence);
    const committed = recovered.committed_bytes;
    const failed_index =
        recovered.stream.encoder.encoder.frames.frames_encoded;
    const retained_offset = recovered_offsets[failed_index];
    faults.fail_write_call = faults.write_calls + 1;
    faults.partial_write_bytes = 7;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        recovered.append(signal),
    );
    try std.testing.expect(recovered.failed);
    try std.testing.expectEqual(
        retained_offset,
        recovered_offsets[failed_index],
    );
    try std.testing.expectEqual(
        committed + 7,
        try recovered_file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    try recovered.recover();
    try std.testing.expectEqual(
        committed,
        try recovered_file.length(std.testing.io),
    );
    const provisional = try FileReader.summarize(
        std.testing.io,
        recovered_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, 0),
        provisional.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        provisional.first_xing.?.encoder.?,
    );
    _ = try recovered.append(signal);
    const recovered_summary = try recovered.finalize();
    try std.testing.expectEqual(
        recovered_summary.stream.byte_count,
        try recovered_file.length(std.testing.io),
    );
}

test "writes and recovers MP3 reservoir files" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    };
    const samples_per_frame =
        (try config.header(false)).samplesPerFrame();
    const silence = PcmFrame{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    };
    var signal = silence;
    for (0..samples_per_frame) |sample| {
        signal.channels[0][sample] =
            0.5 * @sin(
                2.0 * std.math.pi *
                    @as(f32, @floatFromInt(sample)) /
                    43.0,
            );
    }

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "reservoir.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var storage: [maximum_encoded_frame_bytes * 3]u8 =
        undefined;
    var writer = try PcmReservoirFileEncoder.init(
        std.testing.io,
        file,
        config,
        &storage,
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        try writer.append(silence),
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        try file.length(std.testing.io),
    );
    try std.testing.expect(try writer.append(signal) > 0);
    try std.testing.expectEqual(
        writer.committed_bytes,
        try file.length(std.testing.io),
    );
    const summary = try writer.finalize();
    try std.testing.expect(summary.borrowed_bytes > 0);
    try std.testing.expectEqual(
        summary.stream.byte_count,
        try file.length(std.testing.io),
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 =
        undefined;
    var reader = try FileReader.init(std.testing.io, file);
    var borrowed_frame_seen = false;
    while (try reader.next(&frame_storage)) |frame| {
        borrowed_frame_seen = borrowed_frame_seen or
            (try frame.sideInformation())
                .main_data_begin != 0;
    }
    try std.testing.expect(borrowed_frame_seen);
    try std.testing.expectEqual(
        summary,
        try writer.finalize(),
    );

    var metadata_file = try temporary.dir.createFile(
        std.testing.io,
        "reservoir-metadata.mp3",
        .{ .read = true },
    );
    defer metadata_file.close(std.testing.io);
    var metadata_writer = try PcmReservoirFileEncoder.init(
        std.testing.io,
        metadata_file,
        config,
        &storage,
    );
    const metadata_encoder: [9]u8 = "ResFile 1".*;
    try metadata_writer.startGaplessMetadataWithEncoder(
        metadata_encoder,
    );
    _ = try metadata_writer.append(silence);
    try std.testing.expect(
        try metadata_writer.append(signal) > 0,
    );
    const metadata_summary =
        try metadata_writer.finalize();
    const parsed_metadata = try FileReader.summarize(
        std.testing.io,
        metadata_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(
            metadata_summary.stream.frame_count,
        )),
        parsed_metadata.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u12, try storedXingEncoderDelay(
            try config.header(false),
            metadata_summary.stream.encoder_delay,
        )),
        parsed_metadata.first_xing.?.encoder_delay,
    );
    try std.testing.expectEqual(
        metadata_encoder,
        parsed_metadata.first_xing.?.encoder.?,
    );
    const gapless =
        try GaplessPlan.fromSummary(.{
            .audio_offset = 0,
            .audio_bytes = @intCast(
                parsed_metadata.audio_bytes,
            ),
            .frame_count = parsed_metadata.frame_count,
            .sample_count = parsed_metadata.sample_count,
            .sample_rate = parsed_metadata.sample_rate,
            .channels = parsed_metadata.channels,
            .first_xing = parsed_metadata.first_xing,
            .first_vbri = null,
        });
    try std.testing.expectEqual(
        metadata_summary.stream.input_samples,
        gapless.audible_samples,
    );

    var metadata_fault_file = try temporary.dir.createFile(
        std.testing.io,
        "reservoir-metadata-recovered.mp3",
        .{ .read = true },
    );
    defer metadata_fault_file.close(std.testing.io);
    var metadata_faults = Mp3FileFaults{};
    var metadata_failed =
        try PcmReservoirFileEncoder.initWithOperations(
            std.testing.io,
            metadata_fault_file,
            config,
            &storage,
            metadata_faults.operations(),
        );
    const recovered_encoder: [9]u8 = "ResRecov1".*;
    try metadata_failed.startGaplessMetadataWithEncoder(
        recovered_encoder,
    );
    _ = try metadata_failed.append(silence);
    _ = try metadata_failed.append(signal);
    const metadata_committed =
        metadata_failed.committed_bytes;
    metadata_faults.fail_write_call =
        metadata_faults.write_calls + 2;
    metadata_faults.partial_write_bytes = 8;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        metadata_failed.finalize(),
    );
    try std.testing.expect(metadata_failed.failed);
    try std.testing.expectEqual(
        metadata_committed,
        metadata_failed.committed_bytes,
    );
    metadata_faults.fail_write_call = null;
    try metadata_failed.recover();
    try std.testing.expectEqual(
        metadata_committed,
        try metadata_fault_file.length(std.testing.io),
    );
    const provisional = try FileReader.summarize(
        std.testing.io,
        metadata_fault_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, 0),
        provisional.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        provisional.first_xing.?.encoder.?,
    );
    const metadata_recovered =
        try metadata_failed.finalize();
    const final_metadata = try FileReader.summarize(
        std.testing.io,
        metadata_fault_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(
            metadata_recovered.stream.frame_count,
        )),
        final_metadata.first_xing.?.frame_count,
    );

    var failed_file = try temporary.dir.createFile(
        std.testing.io,
        "reservoir-recovered.mp3",
        .{ .read = true },
    );
    defer failed_file.close(std.testing.io);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    var failed =
        try PcmReservoirFileEncoder.initWithOperations(
            std.testing.io,
            failed_file,
            config,
            &storage,
            faults.operations(),
        );
    _ = try failed.append(silence);
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        failed.append(signal),
    );
    try std.testing.expect(failed.failed);
    try std.testing.expectEqual(
        @as(u64, 0),
        failed.committed_bytes,
    );
    try std.testing.expectEqual(
        @as(u64, 1),
        failed.stream.frame_count,
    );
    try std.testing.expectEqual(
        @as(u64, 7),
        try failed_file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    try failed.recover();
    try std.testing.expectEqual(
        @as(u64, 0),
        try failed_file.length(std.testing.io),
    );
    try std.testing.expect(try failed.append(signal) > 0);
    const recovered = try failed.finalize();
    try std.testing.expectEqual(
        recovered.stream.byte_count,
        try failed_file.length(std.testing.io),
    );
}

test "finishes bounded MP3 PCM streams with gapless counts" {
    const configs = [_]EncoderConfig{
        .{
            .version = .mpeg1,
            .bitrate_kbps = 128,
            .sample_rate = 44_100,
            .channel_mode = .mono,
        },
        .{
            .version = .mpeg2,
            .bitrate_kbps = 64,
            .sample_rate = 22_050,
            .channel_mode = .mono,
        },
    };
    for (configs) |config| {
        const samples_per_frame =
            (try config.header(false)).samplesPerFrame();
        var encoder = try PcmStreamEncoder.init(config);
        var encoded: [maximum_encoded_frame_bytes * 4]u8 = undefined;
        var encoded_bytes: usize = 0;
        const pcm = PcmFrame{
            .channel_count = 1,
            .sample_count = samples_per_frame,
        };
        for (0..2) |_| {
            const frame = try encoder.append(
                pcm,
                encoded[encoded_bytes..],
            );
            encoded_bytes += frame.len;
        }
        try std.testing.expectError(
            error.Mp3EncoderStreamIncomplete,
            encoder.summary(),
        );
        const finished = try encoder.finish(
            encoded[encoded_bytes..],
        );
        encoded_bytes += finished.frames.len;
        const flush_frames: u64 =
            if (config.version == .mpeg1) 1 else 2;
        try std.testing.expectEqual(
            @as(u64, 2) + flush_frames,
            finished.summary.frame_count,
        );
        try std.testing.expectEqual(
            @as(u64, samples_per_frame) * 2,
            finished.summary.input_samples,
        );
        try std.testing.expectEqual(
            @as(u16, encoder_analysis_delay),
            finished.summary.encoder_delay,
        );
        try std.testing.expectEqual(
            @as(u16, 95),
            finished.summary.end_padding,
        );
        try std.testing.expectEqual(
            @as(u64, encoded_bytes),
            finished.summary.byte_count,
        );
        var parsed = try Stream.init(encoded[0..encoded_bytes]);
        while (try parsed.next()) |_| {}
        try std.testing.expectEqual(
            finished.summary.frame_count,
            parsed.frame_index,
        );
        try std.testing.expectEqual(
            finished.summary.encoded_samples,
            parsed.sample_offset,
        );
        const repeated = try encoder.finish(
            encoded[encoded_bytes..],
        );
        try std.testing.expectEqual(@as(usize, 0), repeated.frames.len);
        try std.testing.expectEqual(finished.summary, repeated.summary);
        const before_append = encoder;
        try std.testing.expectError(
            error.Mp3EncoderStreamFinalized,
            encoder.append(pcm, encoded[encoded_bytes..]),
        );
        try std.testing.expectEqual(before_append, encoder);
    }

    var short = try PcmStreamEncoder.init(configs[1]);
    var frame_output: [maximum_encoded_frame_bytes]u8 = undefined;
    _ = try short.append(
        .{
            .channel_count = 1,
            .sample_count = 576,
        },
        &frame_output,
    );
    var short_output: [1]u8 = .{0x5a};
    const before_short = short;
    try std.testing.expectError(
        error.InsufficientMp3EncoderStorage,
        short.finish(&short_output),
    );
    try std.testing.expectEqual(before_short, short);
    try std.testing.expectEqual(@as(u8, 0x5a), short_output[0]);
    short.byte_count += 1;
    try std.testing.expectError(
        error.InvalidMp3EncoderStreamState,
        short.finish(&short_output),
    );
}

test "emits exact gapless MP3 stream metadata" {
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
        .crc_present = true,
    };
    const samples_per_frame =
        (try config.header(false)).samplesPerFrame();
    var encoder = try PcmStreamEncoder.init(config);
    var encoded: [maximum_encoded_frame_bytes * 5]u8 = @splat(0x5a);
    const before_invalid = encoder;
    const invalid_destination = encoded;
    try std.testing.expectError(
        error.InvalidMp3EncoderIdentifier,
        encoder.startGaplessMetadataWithEncoder(
            @splat(' '),
            &encoded,
        ),
    );
    try std.testing.expectEqual(before_invalid, encoder);
    try std.testing.expectEqual(invalid_destination, encoded);

    const metadata_encoder: [9]u8 = "Stream 01".*;
    const metadata = try encoder.startGaplessMetadataWithEncoder(
        metadata_encoder,
        &encoded,
    );
    const metadata_bytes = metadata.len;
    const placeholder = try Frame.parse(metadata, 0);
    try std.testing.expectEqual(@as(?u32, 0), placeholder.xing.?.frame_count);
    try std.testing.expectEqual(@as(?u32, 0), placeholder.xing.?.stream_bytes);
    try std.testing.expectEqual(@as(?bool, true), try placeholder.crcValid());
    try std.testing.expectEqual(
        metadata_encoder,
        placeholder.xing.?.encoder.?,
    );
    try std.testing.expectError(
        error.Mp3EncoderMetadataAlreadyStarted,
        encoder.startGaplessMetadata(encoded[metadata_bytes..]),
    );
    try std.testing.expectError(
        error.Mp3EncoderStreamIncomplete,
        encoder.gaplessMetadataFrame(encoded[0..metadata_bytes]),
    );

    var encoded_bytes = metadata_bytes;
    const pcm = PcmFrame{
        .channel_count = 1,
        .sample_count = samples_per_frame,
    };
    for (0..2) |_| {
        const frame = try encoder.append(
            pcm,
            encoded[encoded_bytes..],
        );
        encoded_bytes += frame.len;
    }
    const finished = try encoder.finish(
        encoded[encoded_bytes..],
    );
    encoded_bytes += finished.frames.len;
    const final_metadata = try encoder.gaplessMetadataFrame(
        encoded[0..metadata_bytes],
    );
    try std.testing.expectEqual(metadata_bytes, final_metadata.len);

    const summary = try Stream.summarize(encoded[0..encoded_bytes]);
    const xing = summary.first_xing.?;
    try std.testing.expectEqual(metadata_encoder, xing.encoder.?);
    try std.testing.expectEqual(XingKind.constant, xing.kind);
    try std.testing.expectEqual(
        @as(?u32, @intCast(finished.summary.frame_count)),
        xing.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(finished.summary.byte_count)),
        xing.stream_bytes,
    );
    try std.testing.expectEqual(
        @as(?u12, try storedXingEncoderDelay(
            try config.header(false),
            finished.summary.encoder_delay,
        )),
        xing.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(?u12, try storedXingEncoderPadding(
            finished.summary.end_padding,
        )),
        xing.encoder_padding,
    );
    try std.testing.expectEqual(
        @as(u16, encoder_analysis_delay + samples_per_frame),
        finished.summary.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(u16, 95),
        finished.summary.end_padding,
    );
    const gapless = try GaplessPlan.fromSummary(summary);
    try std.testing.expectEqual(
        finished.summary.input_samples,
        gapless.audible_samples,
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        (try placeholder.sideInformation()).main_data_bits,
    );

    var retained: [maximum_encoded_frame_bytes]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.Mp3EncoderMetadataFrameCountOverflow,
        encodeInfoFrame(
            config,
            .{
                .frame_count = @as(u64, std.math.maxInt(u32)) + 1,
                .input_samples = 0,
                .encoded_samples = 0,
                .byte_count = 0,
                .encoder_delay = 0,
                .end_padding = 0,
            },
            &retained,
        ),
    );
    try std.testing.expectEqual(
        @as(u8, 0x5a),
        retained[0],
    );
    const valid_counts = EncoderStreamSummary{
        .frame_count = 1,
        .input_samples = 0,
        .encoded_samples = samples_per_frame,
        .byte_count = 0,
        .encoder_delay = samples_per_frame - 1,
        .end_padding = 0,
    };
    try std.testing.expectError(
        error.Mp3EncoderMetadataDelayUnderflow,
        encodeInfoFrame(config, valid_counts, &retained),
    );
    var oversized_delay = valid_counts;
    oversized_delay.encoder_delay =
        samples_per_frame +
        decoder_delay_samples +
        std.math.maxInt(u12) +
        1;
    try std.testing.expectError(
        error.Mp3EncoderMetadataGaplessOverflow,
        encodeInfoFrame(config, oversized_delay, &retained),
    );
    var oversized_padding = valid_counts;
    oversized_padding.encoder_delay =
        samples_per_frame + decoder_delay_samples;
    oversized_padding.end_padding =
        std.math.maxInt(u12) - decoder_delay_samples + 1;
    try std.testing.expectError(
        error.Mp3EncoderMetadataGaplessOverflow,
        encodeInfoFrame(config, oversized_padding, &retained),
    );
    try std.testing.expectEqual(@as(u8, 0x5a), retained[0]);
}

test "writes and recovers transactional MP3 PCM files" {
    const config = EncoderConfig{
        .version = .mpeg2,
        .bitrate_kbps = 64,
        .sample_rate = 22_050,
        .channel_mode = .mono,
    };
    const pcm = PcmFrame{
        .channel_count = 1,
        .sample_count = 576,
    };
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "encoded.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var storage: [maximum_encoded_frame_bytes * 2]u8 = undefined;
    var writer = try PcmFileEncoder.init(
        std.testing.io,
        file,
        config,
        &storage,
    );
    const metadata_encoder: [9]u8 = "CBRFile 1".*;
    try writer.startGaplessMetadataWithEncoder(
        metadata_encoder,
    );
    try writer.append(pcm);
    try writer.append(pcm);
    const summary = try writer.finalize();
    try std.testing.expectEqual(
        summary.byte_count,
        try file.length(std.testing.io),
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 = undefined;
    var reader = try FileReader.init(std.testing.io, file);
    var frame_count: u64 = 0;
    while (try reader.next(&frame_storage)) |_| frame_count += 1;
    try std.testing.expectEqual(summary.frame_count, frame_count);
    try std.testing.expectEqual(summary, try writer.finalize());
    const file_summary = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(summary.frame_count)),
        file_summary.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        metadata_encoder,
        file_summary.first_xing.?.encoder.?,
    );
    try std.testing.expectEqual(
        @as(?u12, try storedXingEncoderDelay(
            try config.header(false),
            summary.encoder_delay,
        )),
        file_summary.first_xing.?.encoder_delay,
    );
    try std.testing.expectEqual(
        summary.input_samples,
        file_summary.sample_count -
            (try config.header(false)).samplesPerFrame() -
            file_summary.first_xing.?.encoder_delay.? -
            file_summary.first_xing.?.encoder_padding.?,
    );

    var failed_file = try temporary.dir.createFile(
        std.testing.io,
        "recovered.mp3",
        .{ .read = true },
    );
    defer failed_file.close(std.testing.io);
    var faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    var failed = try PcmFileEncoder.initWithOperations(
        std.testing.io,
        failed_file,
        config,
        &storage,
        faults.operations(),
    );
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        failed.append(pcm),
    );
    try std.testing.expect(failed.failed);
    try std.testing.expectEqual(@as(u64, 0), failed.committed_bytes);
    try std.testing.expectEqual(@as(u64, 0), failed.stream.frame_count);
    try std.testing.expectEqual(
        @as(u64, 7),
        try failed_file.length(std.testing.io),
    );
    faults.fail_write_call = null;
    try failed.recover();
    try std.testing.expect(!failed.failed);
    try std.testing.expectEqual(
        @as(u64, 0),
        try failed_file.length(std.testing.io),
    );
    try failed.append(pcm);
    const committed = failed.committed_bytes;
    faults.fail_write_call = faults.write_calls + 1;
    faults.partial_write_bytes = 5;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        failed.finalize(),
    );
    try std.testing.expectEqual(committed, failed.committed_bytes);
    try std.testing.expect(!failed.stream.finalized);
    try std.testing.expect(
        try failed_file.length(std.testing.io) > committed,
    );
    faults.fail_write_call = null;
    try failed.recover();
    try std.testing.expectEqual(
        committed,
        try failed_file.length(std.testing.io),
    );
    const recovered_summary = try failed.finalize();
    try std.testing.expectEqual(
        recovered_summary.byte_count,
        try failed_file.length(std.testing.io),
    );

    var metadata_file = try temporary.dir.createFile(
        std.testing.io,
        "recovered-metadata.mp3",
        .{ .read = true },
    );
    defer metadata_file.close(std.testing.io);
    var metadata_faults = Mp3FileFaults{};
    var metadata_writer = try PcmFileEncoder.initWithOperations(
        std.testing.io,
        metadata_file,
        config,
        &storage,
        metadata_faults.operations(),
    );
    const recovered_encoder: [9]u8 = "CBRRecov1".*;
    try metadata_writer.startGaplessMetadataWithEncoder(
        recovered_encoder,
    );
    try metadata_writer.append(pcm);
    const metadata_committed = metadata_writer.committed_bytes;
    metadata_faults.fail_write_call =
        metadata_faults.write_calls + 2;
    metadata_faults.partial_write_bytes = 8;
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        metadata_writer.finalize(),
    );
    try std.testing.expect(metadata_writer.failed);
    try std.testing.expectEqual(
        metadata_committed,
        metadata_writer.committed_bytes,
    );
    metadata_faults.fail_write_call = null;
    try metadata_writer.recover();
    try std.testing.expectEqual(
        metadata_committed,
        try metadata_file.length(std.testing.io),
    );
    const recovered_placeholder = try FileReader.summarize(
        std.testing.io,
        metadata_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, 0),
        recovered_placeholder.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        recovered_placeholder.first_xing.?.encoder.?,
    );
    const metadata_summary = try metadata_writer.finalize();
    const recovered_metadata = try FileReader.summarize(
        std.testing.io,
        metadata_file,
        &frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(metadata_summary.frame_count)),
        recovered_metadata.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(metadata_summary.byte_count)),
        recovered_metadata.first_xing.?.stream_bytes,
    );
    try std.testing.expectEqual(
        recovered_encoder,
        recovered_metadata.first_xing.?.encoder.?,
    );
}

test "composes ID3 prefixes and tails with offset MP3 files" {
    const prefix = [_]u8{
        'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0,
    };
    var tail: [128]u8 = @splat(0);
    @memcpy(tail[0..3], "TAG");
    @memcpy(tail[3..8], "title");
    const config = EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 128,
        .sample_rate = 44_100,
        .channel_mode = .mono,
    };
    const pcm = PcmFrame{
        .channel_count = 1,
        .sample_count = 1152,
    };

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "id3-composed.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, "keep", 0);
    try std.testing.expectError(
        error.InvalidMp3Id3v2Prefix,
        writeId3v2FilePrefix(
            std.testing.io,
            file,
            "not a tag",
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 4),
        try file.length(std.testing.io),
    );

    const audio_offset = try writeId3v2FilePrefix(
        std.testing.io,
        file,
        &prefix,
    );
    var storage: [maximum_encoded_frame_bytes * 2]u8 =
        undefined;
    var writer = try PcmFileEncoder.initAt(
        std.testing.io,
        file,
        config,
        &storage,
        audio_offset,
    );
    try writer.startGaplessMetadata();
    try writer.append(pcm);
    const summary = try writer.finalize();
    const audio_end = try fileEncoderOffset(
        audio_offset,
        summary.byte_count,
    );
    try std.testing.expectEqual(
        audio_end,
        try file.length(std.testing.io),
    );
    var frame_storage: [maximum_encoded_frame_bytes]u8 =
        undefined;
    const parsed = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(summary.frame_count, parsed.frame_count);
    try std.testing.expectEqual(audio_offset, parsed.audio_offset);

    const file_end = try appendId3v1FileTail(
        std.testing.io,
        file,
        audio_offset,
        summary.byte_count,
        &tail,
    );
    try std.testing.expectEqual(
        file_end,
        try file.length(std.testing.io),
    );
    const with_tail = try FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(summary.frame_count, with_tail.frame_count);
    try std.testing.expectEqual(
        audio_end,
        with_tail.audio_offset + with_tail.audio_bytes,
    );
    try std.testing.expectEqual(
        file_end,
        try appendId3v1FileTail(
            std.testing.io,
            file,
            audio_offset,
            summary.byte_count,
            &tail,
        ),
    );

    var prefix_bytes: [10]u8 = undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        0,
        &prefix_bytes,
        error.TestTruncatedId3Prefix,
    );
    try std.testing.expectEqualSlices(u8, &prefix, &prefix_bytes);
    var tail_bytes: [128]u8 = undefined;
    try file_reader_io.readExactAt(
        std.testing.io,
        file,
        audio_end,
        &tail_bytes,
        error.TestTruncatedId3Tail,
    );
    try std.testing.expectEqualSlices(u8, &tail, &tail_bytes);

    var variants_file = try temporary.dir.createFile(
        std.testing.io,
        "id3-offset-variants.mp3",
        .{ .read = true },
    );
    defer variants_file.close(std.testing.io);
    _ = try writeId3v2FilePrefix(
        std.testing.io,
        variants_file,
        &prefix,
    );
    var variant_storage: [maximum_encoded_frame_bytes * 3]u8 = undefined;
    var variant_offsets: [4]u64 = undefined;
    const vbr_config = VbrEncoderConfig{
        .template = .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_mode = .mono,
        },
    };
    const vbr_writer = try VbrPcmFileEncoder.initAt(
        std.testing.io,
        variants_file,
        vbr_config,
        &variant_storage,
        &variant_offsets,
        audio_offset,
    );
    try std.testing.expectEqual(
        audio_offset,
        vbr_writer.audio_offset,
    );
    const reservoir_writer =
        try PcmReservoirFileEncoder.initAt(
            std.testing.io,
            variants_file,
            config,
            &variant_storage,
            audio_offset,
        );
    try std.testing.expectEqual(
        audio_offset,
        reservoir_writer.audio_offset,
    );
    const vbr_reservoir_writer =
        try VbrPcmReservoirFileEncoder.initAt(
            std.testing.io,
            variants_file,
            vbr_config,
            &variant_storage,
            &variant_offsets,
            audio_offset,
        );
    try std.testing.expectEqual(
        audio_offset,
        vbr_reservoir_writer.audio_offset,
    );
    try std.testing.expectEqual(
        audio_offset,
        try variants_file.length(std.testing.io),
    );

    try std.testing.expectError(
        error.Mp3FileOffsetOverflow,
        appendId3v1FileTail(
            std.testing.io,
            file,
            std.math.maxInt(u64),
            1,
            &tail,
        ),
    );
    try std.testing.expectEqual(
        file_end,
        try file.length(std.testing.io),
    );

    var failed_prefix = try temporary.dir.createFile(
        std.testing.io,
        "id3-prefix-retry.mp3",
        .{ .read = true },
    );
    defer failed_prefix.close(std.testing.io);
    var prefix_faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 4,
    };
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        writeId3v2FilePrefixWithOperations(
            std.testing.io,
            failed_prefix,
            &prefix,
            prefix_faults.operations(),
        ),
    );
    prefix_faults.fail_write_call = null;
    try std.testing.expectEqual(
        audio_offset,
        try writeId3v2FilePrefixWithOperations(
            std.testing.io,
            failed_prefix,
            &prefix,
            prefix_faults.operations(),
        ),
    );
    try std.testing.expectEqual(
        audio_offset,
        try failed_prefix.length(std.testing.io),
    );

    var tail_faults = Mp3FileFaults{
        .fail_write_call = 1,
        .partial_write_bytes = 7,
    };
    try std.testing.expectError(
        error.InjectedMp3FileWriteFailure,
        appendId3v1FileTailWithOperations(
            std.testing.io,
            file,
            audio_offset,
            summary.byte_count,
            &tail,
            tail_faults.operations(),
        ),
    );
    try std.testing.expectEqual(
        audio_end + 7,
        try file.length(std.testing.io),
    );
    tail_faults.fail_write_call = null;
    try std.testing.expectEqual(
        file_end,
        try appendId3v1FileTailWithOperations(
            std.testing.io,
            file,
            audio_offset,
            summary.byte_count,
            &tail,
            tail_faults.operations(),
        ),
    );
}

const mp3_fuzz_header = [_]u8{ 0xff, 0xfb, 0x90, 0x00 };

test "fuzz bounded MP3 framing and decoding" {
    try std.testing.fuzz({}, fuzzMp3, .{
        .corpus = &.{&mp3_fuzz_header},
    });
}

fn fuzzMp3(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    var storage: [64 * 1024]u8 = undefined;
    var length: usize = switch (smith.valueRangeAtMost(u8, 0, 1)) {
        0 => smith.slice(&storage),
        1 => seed: {
            var end: usize = 0;
            const header = testHeader(3, true, 9, 0, false, .stereo);
            end = try appendFrame(&storage, end, header);
            end = try appendFrame(&storage, end, header);
            break :seed end;
        },
        else => unreachable,
    };
    if (length != 0 and smith.value(bool)) {
        const mutation_count = smith.valueRangeAtMost(u8, 1, 32);
        for (0..mutation_count) |_|
            storage[smith.index(length)] ^= smith.value(u8);
    }
    if (smith.value(bool)) {
        const maximum: u16 = @intCast(@min(length, std.math.maxInt(u16)));
        length = smith.valueRangeAtMost(u16, 0, maximum);
    } else if (length < storage.len and smith.value(bool)) {
        const maximum_append: u16 = @intCast(@min(
            storage.len - length,
            std.math.maxInt(u16),
        ));
        const append_length = smith.valueRangeAtMost(u16, 0, maximum_append);
        smith.bytes(storage[length..][0..append_length]);
        length += append_length;
    }

    const limits = Limits{
        .max_stream_bytes = storage.len,
        .max_frames = 256,
    };
    var stream = Stream.initWithLimits(storage[0..length], limits) catch return;
    var decoder = FrameDecoder{};
    var previous_cursor = stream.cursor;
    while (stream.next() catch return) |frame| {
        if (stream.cursor <= previous_cursor)
            return error.Mp3FuzzParserDidNotAdvance;
        previous_cursor = stream.cursor;
        _ = frame.crcValid() catch return;
        _ = frame.sideInformation() catch return;
        const decoder_before = decoder;
        _ = decoder.decode(frame) catch {
            if (!std.meta.eql(decoder_before, decoder))
                return error.Mp3FuzzDecoderFailureWasNotTransactional;
            continue;
        };
    }
}
