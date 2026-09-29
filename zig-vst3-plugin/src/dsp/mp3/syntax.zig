const std = @import("std");
const huffman_tables = @import("../mp3_huffman_tables.zig");

pub fn byteRangesOverlap(
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

pub const maximum_frame_main_data_bytes: usize =
    (4 * std.math.maxInt(u12) + 7) / 8;
pub const decoder_delay_samples: u16 = 528 + 1;

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
};

pub fn bitrate(version: Version, index: u4) u16 {
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

pub fn bitrateIndex(version: Version, value: u16) ?u4 {
    for (1..15) |index| {
        const encoded_index: u4 = @intCast(index);
        if (bitrate(version, encoded_index) == value)
            return encoded_index;
    }
    return null;
}

pub fn sampleRate(version: Version, index: u2) u32 {
    const base = [_]u32{ 44_100, 48_000, 32_000, 0 };
    return switch (version) {
        .mpeg1 => base[index],
        .mpeg2 => base[index] / 2,
        .mpeg25 => base[index] / 4,
    };
}

pub fn sampleRateIndex(version: Version, value: u32) ?u2 {
    for (0..3) |index| {
        const encoded_index: u2 = @intCast(index);
        if (sampleRate(version, encoded_index) == value)
            return encoded_index;
    }
    return null;
}

pub fn readU32(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
}

pub fn headersCompatible(left: Header, right: Header) bool {
    return left.version == right.version and
        left.sample_rate == right.sample_rate and
        left.free_format == right.free_format and
        left.channels() == right.channels();
}

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

pub const SideInformation = struct {
    channel_count: u2,
    granule_count: u2,
    main_data_begin: u9,
    private_bits: u5,
    scfsi: [2]u4 = @splat(0),
    granules: [2]Granule = @splat(.{}),
    main_data_bits: u16,
};

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

pub const ScaleFactorLayout = struct {
    bands: ScaleFactorBands,
    short_block: bool,
    short_boundary: usize,
    long_factor_count: usize,
};

pub fn scaleFactorValueCount(
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

pub fn scaleFactorLayout(
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

pub fn validateBlockDescription(description: GranuleChannel) !void {
    if (description.window_switching ==
        (description.block_type == 0) or
        description.mixed_block and !description.window_switching)
        return error.InvalidMp3BlockType;
}

pub fn mixedLongSubbands(header: Header) usize {
    return if (header.version == .mpeg25 and
        header.sample_rate == 8_000)
        4
    else
        2;
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

pub fn decodeHuffmanPair(
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

pub const count1_table_a = [16]Count1Code{
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

pub fn quantizedMagnitude(value: i32) !u32 {
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

pub const mpeg1_scale_factor_lengths = [16][2]u3{
    .{ 0, 0 }, .{ 0, 1 }, .{ 0, 2 }, .{ 0, 3 },
    .{ 3, 0 }, .{ 1, 1 }, .{ 1, 2 }, .{ 1, 3 },
    .{ 2, 1 }, .{ 2, 2 }, .{ 2, 3 }, .{ 3, 1 },
    .{ 3, 2 }, .{ 3, 3 }, .{ 4, 2 }, .{ 4, 3 },
};

pub const lsf_scale_factor_counts = [6][3][4]u5{
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

pub fn decodeMpeg1ScaleFactorChannel(
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

pub const LsfScaleFactorPlan = struct {
    lengths: [4]u4,
    table: u3,
    preflag: bool,
    intensity_scale: bool,
};

pub fn lsfScaleFactorPlan(
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

pub fn decodeLsfScaleFactorChannel(
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

pub const MainDataBitWriter = struct {
    bytes: []u8,
    bit_offset: usize = 0,

    pub fn write(
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

pub fn appendMainDataBits(
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

pub const MainDataBitReader = struct {
    bytes: []const u8,
    bit_offset: usize = 0,
    bit_limit: usize,

    pub fn read(self: *@This(), bit_count: u5) !u16 {
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

pub fn parseSideInformation(
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
