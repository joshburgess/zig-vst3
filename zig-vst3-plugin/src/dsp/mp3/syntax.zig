const std = @import("std");

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
