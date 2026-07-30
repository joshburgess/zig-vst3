const std = @import("std");
const file_reader_io = @import("file_reader_io.zig");
const huffman_tables = @import("mp3_huffman_tables.zig");

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

    fn compatible(self: Header, other: Header) bool {
        return self.version == other.version and
            self.sample_rate == other.sample_rate and
            self.free_format == other.free_format and
            self.channels() == other.channels();
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
    if (description.window_switching ==
        (description.block_type == 0) or
        description.mixed_block and !short_block)
        return error.InvalidMp3BlockType;
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

fn sampleRate(version: Version, index: u2) u32 {
    const base = [_]u32{ 44_100, 48_000, 32_000, 0 };
    return switch (version) {
        .mpeg1 => base[index],
        .mpeg2 => base[index] / 2,
        .mpeg25 => base[index] / 4,
    };
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
