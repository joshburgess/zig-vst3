const std = @import("std");
const file_writer_io = @import("file_writer_io.zig");
const pcm_dither = @import("pcm_dither.zig");

pub const Endian = std.builtin.Endian;

pub const Encoding = enum {
    pcm_i16,
    pcm_i24,
    pcm_i32,
    ieee_f32,
};

pub fn byteCount(encoding: Encoding) usize {
    return switch (encoding) {
        .pcm_i16 => 2,
        .pcm_i24 => 3,
        .pcm_i32, .ieee_f32 => 4,
    };
}

pub fn bitCount(encoding: Encoding) u6 {
    return switch (encoding) {
        .pcm_i16 => 16,
        .pcm_i24 => 24,
        .pcm_i32, .ieee_f32 => 32,
    };
}

pub fn encodeValidated(
    comptime Sample: type,
    destination: []u8,
    samples: []const Sample,
    encoding: Encoding,
    endian: Endian,
) void {
    if (Sample != f32 and Sample != f64)
        @compileError("PCM encoding supports f32 and f64 input");
    const bytes_per_sample = byteCount(encoding);
    std.debug.assert(destination.len == samples.len * bytes_per_sample);

    var offset: usize = 0;
    for (samples) |sample| {
        const normalized: f64 = @floatCast(sample);
        switch (encoding) {
            .pcm_i16 => writeSigned(
                destination[offset..][0..2],
                @intFromFloat(@round(
                    std.math.clamp(normalized, -1.0, 1.0) * 32_767.0,
                )),
                endian,
            ),
            .pcm_i24 => writeSigned(
                destination[offset..][0..3],
                @intFromFloat(@round(
                    std.math.clamp(normalized, -1.0, 1.0) * 8_388_607.0,
                )),
                endian,
            ),
            .pcm_i32 => writeSigned(
                destination[offset..][0..4],
                @intFromFloat(@round(
                    std.math.clamp(normalized, -1.0, 1.0) *
                        2_147_483_647.0,
                )),
                endian,
            ),
            .ieee_f32 => std.mem.writeInt(
                u32,
                destination[offset..][0..4],
                @bitCast(@as(f32, @floatCast(sample))),
                endian,
            ),
        }
        offset += bytes_per_sample;
    }
}

pub fn writeValidatedWithOperations(
    operations: file_writer_io.Operations,
    io: std.Io,
    file: std.Io.File,
    initial_offset: u64,
    comptime Sample: type,
    samples: []const Sample,
    encoding: Encoding,
    endian: Endian,
) !void {
    var staging: [4_096]u8 = undefined;
    const bytes_per_sample = byteCount(encoding);
    const samples_per_chunk = staging.len / bytes_per_sample;
    var sample_offset: usize = 0;
    var file_offset = initial_offset;
    while (sample_offset < samples.len) {
        const chunk_samples = @min(
            samples_per_chunk,
            samples.len - sample_offset,
        );
        const byte_length = chunk_samples * bytes_per_sample;
        encodeValidated(
            Sample,
            staging[0..byte_length],
            samples[sample_offset..][0..chunk_samples],
            encoding,
            endian,
        );
        try operations.writeAt(
            io,
            file,
            file_offset,
            staging[0..byte_length],
        );
        sample_offset += chunk_samples;
        file_offset += byte_length;
    }
}

pub fn decode(
    bytes: []const u8,
    encoding: Encoding,
    endian: Endian,
) f64 {
    std.debug.assert(bytes.len == byteCount(encoding));
    return switch (encoding) {
        .pcm_i16 => @as(f64, @floatFromInt(@as(i16, @bitCast(
            std.mem.readInt(u16, bytes[0..2], endian),
        )))) / 32_768.0,
        .pcm_i24 => blk: {
            const unsigned: u32 = switch (endian) {
                .little => @as(u32, bytes[0]) |
                    (@as(u32, bytes[1]) << 8) |
                    (@as(u32, bytes[2]) << 16),
                .big => (@as(u32, bytes[0]) << 16) |
                    (@as(u32, bytes[1]) << 8) |
                    bytes[2],
            };
            const signed: i32 = if (unsigned & 0x0080_0000 != 0)
                @bitCast(unsigned | 0xff00_0000)
            else
                @intCast(unsigned);
            break :blk @as(f64, @floatFromInt(signed)) / 8_388_608.0;
        },
        .pcm_i32 => @as(f64, @floatFromInt(@as(i32, @bitCast(
            std.mem.readInt(u32, bytes[0..4], endian),
        )))) / 2_147_483_648.0,
        .ieee_f32 => @as(f32, @bitCast(
            std.mem.readInt(u32, bytes[0..4], endian),
        )),
    };
}

pub fn encodeDithered(
    comptime Sample: type,
    destination: []u8,
    samples: []const Sample,
    endian: Endian,
    dither: *pcm_dither.PcmDither,
) !void {
    if (Sample != f32 and Sample != f64)
        @compileError("dithered PCM encoding supports f32 and f64 input");
    const bytes_per_sample = try byteCountForBits(dither.bitsPerSample());
    const required = std.math.mul(
        usize,
        samples.len,
        bytes_per_sample,
    ) catch return error.PcmSizeOverflow;
    if (destination.len != required)
        return error.PcmBufferLengthMismatch;
    if (samples.len % dither.channelCount() != 0)
        return error.IncompleteDitherFrame;
    for (samples) |sample| {
        if (!std.math.isFinite(sample))
            return error.InvalidDitherSample;
    }

    var offset: usize = 0;
    for (samples, 0..) |sample, index| {
        const encoded = try dither.quantize(
            @floatCast(sample),
            index % dither.channelCount(),
        );
        writeSigned(
            destination[offset..][0..bytes_per_sample],
            encoded,
            endian,
        );
        offset += bytes_per_sample;
    }
}

pub fn writeDithered(
    io: std.Io,
    file: std.Io.File,
    initial_offset: u64,
    comptime Sample: type,
    samples: []const Sample,
    endian: Endian,
    dither: *pcm_dither.PcmDither,
) !void {
    try writeDitheredWithOperations(
        .{},
        io,
        file,
        initial_offset,
        Sample,
        samples,
        endian,
        dither,
    );
}

pub fn writeDitheredWithOperations(
    operations: file_writer_io.Operations,
    io: std.Io,
    file: std.Io.File,
    initial_offset: u64,
    comptime Sample: type,
    samples: []const Sample,
    endian: Endian,
    dither: *pcm_dither.PcmDither,
) !void {
    const bytes_per_sample = try byteCountForBits(dither.bitsPerSample());
    const frame_bytes = std.math.mul(
        usize,
        bytes_per_sample,
        dither.channelCount(),
    ) catch return error.PcmSizeOverflow;
    var staging: [4_096]u8 = undefined;
    const frames_per_chunk = staging.len / frame_bytes;
    if (frames_per_chunk == 0)
        return error.PcmFrameTooLarge;
    const samples_per_chunk = frames_per_chunk * dither.channelCount();

    var sample_offset: usize = 0;
    var file_offset = initial_offset;
    while (sample_offset < samples.len) {
        const chunk_samples = @min(
            samples_per_chunk,
            samples.len - sample_offset,
        );
        const byte_length = chunk_samples * bytes_per_sample;
        try encodeDithered(
            Sample,
            staging[0..byte_length],
            samples[sample_offset..][0..chunk_samples],
            endian,
            dither,
        );
        try operations.writeAt(
            io,
            file,
            file_offset,
            staging[0..byte_length],
        );
        sample_offset += chunk_samples;
        file_offset += byte_length;
    }
}

fn byteCountForBits(bits_per_sample: u6) !usize {
    return switch (bits_per_sample) {
        16 => 2,
        24 => 3,
        32 => 4,
        else => error.UnsupportedPcmBitDepth,
    };
}

fn writeSigned(
    destination: []u8,
    encoded: i32,
    endian: Endian,
) void {
    const bits: u32 = @bitCast(encoded);
    switch (destination.len) {
        2 => {
            const narrowed: i16 = @intCast(encoded);
            std.mem.writeInt(
                u16,
                destination[0..2],
                @bitCast(narrowed),
                if (endian == .little) .little else .big,
            );
        },
        3 => switch (endian) {
            .little => {
                destination[0] = @truncate(bits);
                destination[1] = @truncate(bits >> 8);
                destination[2] = @truncate(bits >> 16);
            },
            .big => {
                destination[0] = @truncate(bits >> 16);
                destination[1] = @truncate(bits >> 8);
                destination[2] = @truncate(bits);
            },
        },
        4 => std.mem.writeInt(
            u32,
            destination[0..4],
            bits,
            if (endian == .little) .little else .big,
        ),
        else => unreachable,
    }
}

test "direct PCM encoding and decoding cover formats and byte orders" {
    const samples = [_]f64{ -1.0, 0.0, 1.0 };
    const Case = struct {
        encoding: Encoding,
        little: []const u8,
        big: []const u8,
    };
    const cases = [_]Case{
        .{
            .encoding = .pcm_i16,
            .little = &.{ 0x01, 0x80, 0, 0, 0xff, 0x7f },
            .big = &.{ 0x80, 0x01, 0, 0, 0x7f, 0xff },
        },
        .{
            .encoding = .pcm_i24,
            .little = &.{
                0x01, 0x00, 0x80,
                0,    0,    0,
                0xff, 0xff, 0x7f,
            },
            .big = &.{
                0x80, 0x00, 0x01,
                0,    0,    0,
                0x7f, 0xff, 0xff,
            },
        },
        .{
            .encoding = .pcm_i32,
            .little = &.{
                0x01, 0x00, 0x00, 0x80,
                0,    0,    0,    0,
                0xff, 0xff, 0xff, 0x7f,
            },
            .big = &.{
                0x80, 0x00, 0x00, 0x01,
                0,    0,    0,    0,
                0x7f, 0xff, 0xff, 0xff,
            },
        },
        .{
            .encoding = .ieee_f32,
            .little = &.{
                0, 0, 0x80, 0xbf,
                0, 0, 0,    0,
                0, 0, 0x80, 0x3f,
            },
            .big = &.{
                0xbf, 0x80, 0, 0,
                0,    0,    0, 0,
                0x3f, 0x80, 0, 0,
            },
        },
    };

    for (cases) |case| {
        inline for ([_]Endian{ .little, .big }) |endian| {
            var encoded: [12]u8 = undefined;
            const byte_count = byteCount(case.encoding);
            const destination = encoded[0 .. samples.len * byte_count];
            encodeValidated(
                f64,
                destination,
                &samples,
                case.encoding,
                endian,
            );
            const expected = if (endian == .little)
                case.little
            else
                case.big;
            try std.testing.expectEqualSlices(u8, expected, destination);

            for (samples, 0..) |sample, index| {
                const offset = index * byte_count;
                const decoded = decode(
                    destination[offset..][0..byte_count],
                    case.encoding,
                    endian,
                );
                const tolerance: f64 = switch (case.encoding) {
                    .pcm_i16 => 1.0 / 32_768.0,
                    .pcm_i24 => 1.0 / 8_388_608.0,
                    .pcm_i32 => 1.0 / 2_147_483_648.0,
                    .ieee_f32 => 0,
                };
                try std.testing.expectApproxEqAbs(
                    sample,
                    decoded,
                    tolerance,
                );
            }
        }
    }
}

test "direct PCM file staging preserves three-byte samples across chunks" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "direct.pcm",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const sample_count = 2_735;
    var samples: [sample_count]f32 = undefined;
    for (&samples, 0..) |*sample, index| {
        sample.* = @as(f32, @floatFromInt(index % 257)) / 128.0 - 1.0;
    }
    try writeValidatedWithOperations(
        .{},
        std.testing.io,
        file,
        7,
        f32,
        &samples,
        .pcm_i24,
        .big,
    );

    var expected: [sample_count * 3]u8 = undefined;
    encodeValidated(f32, &expected, &samples, .pcm_i24, .big);
    var actual: [sample_count * 3]u8 = undefined;
    try std.testing.expectEqual(
        actual.len,
        try file.readPositionalAll(std.testing.io, &actual, 7),
    );
    try std.testing.expectEqualSlices(u8, &expected, &actual);
}

test "dithered PCM encoding supports integer widths and endianness" {
    inline for ([_]u6{ 16, 24, 32 }) |bits| {
        inline for ([_]Endian{ .little, .big }) |endian| {
            var dither = try pcm_dither.PcmDither.init(.{
                .channel_count = 1,
                .bits_per_sample = bits,
                .mode = .none,
            });
            var storage: [12]u8 = undefined;
            const bytes = @as(usize, bits) / 8;
            try encodeDithered(
                f64,
                storage[0 .. 3 * bytes],
                &.{ -1.0, 0.0, 1.0 },
                endian,
                &dither,
            );
            const negative: i32 = switch (bits) {
                16 => -32_768,
                24 => -8_388_608,
                32 => std.math.minInt(i32),
                else => unreachable,
            };
            const positive: i32 = switch (bits) {
                16 => 32_767,
                24 => 8_388_607,
                32 => std.math.maxInt(i32),
                else => unreachable,
            };
            var expected: [12]u8 = undefined;
            writeSigned(expected[0..bytes], negative, endian);
            writeSigned(expected[bytes .. 2 * bytes], 0, endian);
            writeSigned(
                expected[2 * bytes .. 3 * bytes],
                positive,
                endian,
            );
            try std.testing.expectEqualSlices(
                u8,
                expected[0 .. 3 * bytes],
                storage[0 .. 3 * bytes],
            );
        }
    }
}

test "dithered PCM encoding validates before advancing state" {
    var dither = try pcm_dither.PcmDither.init(.{
        .channel_count = 2,
        .bits_per_sample = 16,
        .seed = 123,
    });
    const original = dither;
    var storage: [3]u8 = undefined;
    try std.testing.expectError(
        error.PcmBufferLengthMismatch,
        encodeDithered(f32, &storage, &.{ 0.0, 0.0 }, .little, &dither),
    );
    try std.testing.expectEqualDeep(original, dither);
}

test "file encoding preserves channel phase across staging chunks" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "dithered.pcm",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const sample_count = 6_006;
    var samples: [sample_count]f32 = undefined;
    for (&samples, 0..) |*sample, index| {
        sample.* = @as(f32, @floatFromInt(index % 101)) / 101.0 - 0.5;
    }
    const config = pcm_dither.Config{
        .channel_count = 3,
        .bits_per_sample = 24,
        .mode = .noise_shaped,
        .seed = 456,
    };
    var file_dither = try pcm_dither.PcmDither.init(config);
    try writeDithered(
        std.testing.io,
        file,
        0,
        f32,
        &samples,
        .little,
        &file_dither,
    );

    var expected: [sample_count * 3]u8 = undefined;
    var expected_dither = try pcm_dither.PcmDither.init(config);
    try encodeDithered(
        f32,
        &expected,
        &samples,
        .little,
        &expected_dither,
    );
    var actual: [sample_count * 3]u8 = undefined;
    try std.testing.expectEqual(
        actual.len,
        try file.readPositionalAll(std.testing.io, &actual, 0),
    );
    try std.testing.expectEqualSlices(u8, &expected, &actual);
    try std.testing.expectEqualDeep(expected_dither, file_dither);
}
