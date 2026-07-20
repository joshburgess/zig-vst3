const std = @import("std");

const frame_count = 64;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const directory = "zig-out/fixtures";
    try std.Io.Dir.cwd().createDirPath(io, directory);

    const wav = pcm16WavFixture(frame_count);
    try writeFixture(io, directory ++ "/sample-player.wav", &wav);

    const aiff = pcm16AiffFixture(frame_count);
    try writeFixture(io, directory ++ "/sample-player.aiff", &aiff);
}

fn writeFixture(io: std.Io, path: []const u8, bytes: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
}

fn pcm16WavFixture(comptime frames: usize) [44 + frames * 4]u8 {
    var bytes: [44 + frames * 4]u8 = @splat(0);
    @memcpy(bytes[0..4], "RIFF");
    writeU32Le(bytes[4..8], bytes.len - 8);
    @memcpy(bytes[8..12], "WAVE");
    @memcpy(bytes[12..16], "fmt ");
    writeU32Le(bytes[16..20], 16);
    writeU16Le(bytes[20..22], 1);
    writeU16Le(bytes[22..24], 2);
    writeU32Le(bytes[24..28], 48_000);
    writeU32Le(bytes[28..32], 48_000 * 4);
    writeU16Le(bytes[32..34], 4);
    writeU16Le(bytes[34..36], 16);
    @memcpy(bytes[36..40], "data");
    writeU32Le(bytes[40..44], frames * 4);
    writeSamples(&bytes, 44, frames, .little);
    return bytes;
}

fn pcm16AiffFixture(comptime frames: usize) [54 + frames * 4]u8 {
    var bytes: [54 + frames * 4]u8 = @splat(0);
    @memcpy(bytes[0..4], "FORM");
    writeU32Be(bytes[4..8], bytes.len - 8);
    @memcpy(bytes[8..12], "AIFF");
    @memcpy(bytes[12..16], "COMM");
    writeU32Be(bytes[16..20], 18);
    writeU16Be(bytes[20..22], 2);
    writeU32Be(bytes[22..26], frames);
    writeU16Be(bytes[26..28], 16);
    writeU16Be(bytes[28..30], 0x400e);
    bytes[30] = 0xbb;
    bytes[31] = 0x80;
    @memcpy(bytes[38..42], "SSND");
    writeU32Be(bytes[42..46], 8 + frames * 4);
    writeSamples(&bytes, 54, frames, .big);
    return bytes;
}

fn writeSamples(bytes: []u8, offset: usize, frames: usize, endian: std.builtin.Endian) void {
    for (0..frames) |frame| {
        const phase = @as(i32, @intCast(frame % 32)) - 16;
        const sample: i16 = @intCast(phase * 1_500);
        const bits: u16 = @bitCast(sample);
        const frame_offset = offset + frame * 4;
        switch (endian) {
            .little => {
                writeU16Le(bytes[frame_offset .. frame_offset + 2], bits);
                writeU16Le(bytes[frame_offset + 2 .. frame_offset + 4], bits);
            },
            .big => {
                writeU16Be(bytes[frame_offset .. frame_offset + 2], bits);
                writeU16Be(bytes[frame_offset + 2 .. frame_offset + 4], bits);
            },
        }
    }
}

fn writeU16Le(bytes: []u8, value: anytype) void {
    const narrowed: u16 = @intCast(value);
    bytes[0] = @truncate(narrowed);
    bytes[1] = @truncate(narrowed >> 8);
}

fn writeU32Le(bytes: []u8, value: anytype) void {
    const narrowed: u32 = @intCast(value);
    bytes[0] = @truncate(narrowed);
    bytes[1] = @truncate(narrowed >> 8);
    bytes[2] = @truncate(narrowed >> 16);
    bytes[3] = @truncate(narrowed >> 24);
}

fn writeU16Be(bytes: []u8, value: anytype) void {
    const narrowed: u16 = @intCast(value);
    bytes[0] = @truncate(narrowed >> 8);
    bytes[1] = @truncate(narrowed);
}

fn writeU32Be(bytes: []u8, value: anytype) void {
    const narrowed: u32 = @intCast(value);
    bytes[0] = @truncate(narrowed >> 24);
    bytes[1] = @truncate(narrowed >> 16);
    bytes[2] = @truncate(narrowed >> 8);
    bytes[3] = @truncate(narrowed);
}
