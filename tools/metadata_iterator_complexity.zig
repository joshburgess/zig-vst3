const std = @import("std");
const builtin = @import("builtin");
const plug = @import("zig-vst3-plugin-core");

const Timer = struct {
    start_ns: u64,

    fn start() !Timer {
        return .{ .start_ns = try monotonicNowNs() };
    }

    fn read(self: Timer) !u64 {
        return (try monotonicNowNs()) - self.start_ns;
    }
};

const Inputs = struct {
    vorbis: []const u8,
    flac: []const u8,
    id3_v23: []const u8,
    id3_v24: []const u8,
    riff_info: []const u8,
    aiff_text: []const u8,
};

const Measurement = struct {
    entries: usize,
    ns_per_entry: [6]f64,
    maximum_ns_per_entry: f64,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const enforce = switch (args.len) {
        1 => true,
        2 => if (std.mem.eql(u8, args[1], "--report-only")) false else return error.InvalidArguments,
        else => return error.InvalidArguments,
    };
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    try stdout.print("optimize={s}\n", .{@tagName(builtin.mode)});
    var baseline: ?Measurement = null;
    for ([_]struct { entries: usize, iterations: usize }{
        .{ .entries = 256, .iterations = 512 },
        .{ .entries = 512, .iterations = 256 },
        .{ .entries = 1_024, .iterations = 128 },
    }) |config| {
        const measurement = try measure(
            allocator,
            config.entries,
            config.iterations,
        );
        try stdout.print(
            "entries={} vorbis={d:.2} flac={d:.2} id3v23={d:.2} " ++
                "id3v24={d:.2} riff_info={d:.2} aiff_text={d:.2} " ++
                "maximum={d:.2}\n",
            .{
                measurement.entries,
                measurement.ns_per_entry[0],
                measurement.ns_per_entry[1],
                measurement.ns_per_entry[2],
                measurement.ns_per_entry[3],
                measurement.ns_per_entry[4],
                measurement.ns_per_entry[5],
                measurement.maximum_ns_per_entry,
            },
        );
        if (enforce) {
            for (measurement.ns_per_entry) |value| {
                if (value > 5_000.0)
                    return error.MetadataIteratorWorkLimitExceeded;
            }
            if (baseline) |initial| {
                for (measurement.ns_per_entry, initial.ns_per_entry) |
                    current_value,
                    initial_value,
                | {
                    if (current_value > initial_value * 2.0)
                        return error.MetadataIteratorScalingRegression;
                }
            }
        }
        if (baseline == null) baseline = measurement;
    }
}

fn measure(
    allocator: std.mem.Allocator,
    entries: usize,
    iterations: usize,
) !Measurement {
    const inputs = try makeInputs(allocator, entries);
    const elapsed = [_]u64{
        minimumElapsed(.{
            try traverseVorbis(inputs.vorbis, entries, iterations),
            try traverseVorbis(inputs.vorbis, entries, iterations),
            try traverseVorbis(inputs.vorbis, entries, iterations),
        }),
        minimumElapsed(.{
            try traverseFlac(inputs.flac, entries, iterations),
            try traverseFlac(inputs.flac, entries, iterations),
            try traverseFlac(inputs.flac, entries, iterations),
        }),
        minimumElapsed(.{
            try traverseId3V23(inputs.id3_v23, entries, iterations),
            try traverseId3V23(inputs.id3_v23, entries, iterations),
            try traverseId3V23(inputs.id3_v23, entries, iterations),
        }),
        minimumElapsed(.{
            try traverseId3V24(inputs.id3_v24, entries, iterations),
            try traverseId3V24(inputs.id3_v24, entries, iterations),
            try traverseId3V24(inputs.id3_v24, entries, iterations),
        }),
        minimumElapsed(.{
            try traverseRiffInfo(inputs.riff_info, entries, iterations),
            try traverseRiffInfo(inputs.riff_info, entries, iterations),
            try traverseRiffInfo(inputs.riff_info, entries, iterations),
        }),
        minimumElapsed(.{
            try traverseAiffText(inputs.aiff_text, entries, iterations),
            try traverseAiffText(inputs.aiff_text, entries, iterations),
            try traverseAiffText(inputs.aiff_text, entries, iterations),
        }),
    };
    var maximum: u64 = 0;
    for (elapsed) |value| maximum = @max(maximum, value);
    var ns_per_entry: [elapsed.len]f64 = undefined;
    for (elapsed, 0..) |value, index| {
        ns_per_entry[index] = @as(f64, @floatFromInt(value)) /
            @as(f64, @floatFromInt(entries * iterations));
    }
    return .{
        .entries = entries,
        .ns_per_entry = ns_per_entry,
        .maximum_ns_per_entry = @as(f64, @floatFromInt(maximum)) /
            @as(f64, @floatFromInt(entries * iterations)),
    };
}

fn minimumElapsed(values: [3]u64) u64 {
    return @min(values[0], @min(values[1], values[2]));
}

fn makeInputs(allocator: std.mem.Allocator, entries: usize) !Inputs {
    return .{
        .vorbis = try makeVorbis(allocator, entries),
        .flac = try makeFlac(allocator, entries),
        .id3_v23 = try makeId3(allocator, entries, 3),
        .id3_v24 = try makeId3(allocator, entries, 4),
        .riff_info = try makeRiffInfo(allocator, entries),
        .aiff_text = try makeAiffText(allocator, entries),
    };
}

fn makeVorbis(allocator: std.mem.Allocator, entries: usize) ![]u8 {
    const bytes = try allocator.alloc(u8, 16 + entries * 7);
    bytes[0] = 3;
    @memcpy(bytes[1..7], "vorbis");
    std.mem.writeInt(u32, bytes[7..11], 0, .little);
    std.mem.writeInt(u32, bytes[11..15], @intCast(entries), .little);
    var offset: usize = 15;
    for (0..entries) |_| {
        std.mem.writeInt(u32, bytes[offset..][0..4], 3, .little);
        @memcpy(bytes[offset + 4 ..][0..3], "A=x");
        offset += 7;
    }
    bytes[offset] = 1;
    return bytes;
}

fn makeFlac(allocator: std.mem.Allocator, entries: usize) ![]u8 {
    const payload_bytes = 8 + entries * 7;
    const bytes = try allocator.alloc(u8, 46 + payload_bytes);
    @memcpy(bytes[0..4], "fLaC");
    bytes[4] = 0;
    writeU24(bytes[5..8], 34);
    @memset(bytes[8..42], 0);
    bytes[42] = 0x84;
    writeU24(bytes[43..46], payload_bytes);
    std.mem.writeInt(u32, bytes[46..50], 0, .little);
    std.mem.writeInt(u32, bytes[50..54], @intCast(entries), .little);
    var offset: usize = 54;
    for (0..entries) |_| {
        std.mem.writeInt(u32, bytes[offset..][0..4], 3, .little);
        @memcpy(bytes[offset + 4 ..][0..3], "A=x");
        offset += 7;
    }
    return bytes;
}

fn makeId3(
    allocator: std.mem.Allocator,
    entries: usize,
    version: u8,
) ![]u8 {
    const body_bytes = entries * 11;
    const bytes = try allocator.alloc(u8, 10 + body_bytes);
    @memcpy(bytes[0..3], "ID3");
    bytes[3] = version;
    bytes[4] = 0;
    bytes[5] = 0;
    writeSyncsafe28(bytes[6..10], body_bytes);
    var offset: usize = 10;
    for (0..entries) |_| {
        @memcpy(bytes[offset..][0..4], "TIT2");
        if (version == 3) {
            std.mem.writeInt(u32, bytes[offset + 4 ..][0..4], 1, .big);
        } else {
            writeSyncsafe28(bytes[offset + 4 ..][0..4], 1);
        }
        bytes[offset + 8] = 0;
        bytes[offset + 9] = 0;
        bytes[offset + 10] = 0;
        offset += 11;
    }
    return bytes;
}

fn makeRiffInfo(allocator: std.mem.Allocator, entries: usize) ![]u8 {
    const bytes = try allocator.alloc(u8, 12 + entries * 10);
    @memcpy(bytes[0..4], "LIST");
    std.mem.writeInt(u32, bytes[4..8], @intCast(bytes.len - 8), .little);
    @memcpy(bytes[8..12], "INFO");
    var offset: usize = 12;
    for (0..entries) |_| {
        @memcpy(bytes[offset..][0..4], "INAM");
        std.mem.writeInt(u32, bytes[offset + 4 ..][0..4], 2, .little);
        bytes[offset + 8] = 'x';
        bytes[offset + 9] = 0;
        offset += 10;
    }
    return bytes;
}

fn makeAiffText(allocator: std.mem.Allocator, entries: usize) ![]u8 {
    const bytes = try allocator.alloc(u8, entries * 10);
    var offset: usize = 0;
    for (0..entries) |_| {
        @memcpy(bytes[offset..][0..4], "NAME");
        std.mem.writeInt(u32, bytes[offset + 4 ..][0..4], 1, .big);
        bytes[offset + 8] = 'x';
        bytes[offset + 9] = 0;
        offset += 10;
    }
    return bytes;
}

fn traverseVorbis(encoded: []const u8, expected: usize, count: usize) !u64 {
    const timer = try Timer.start();
    for (0..count) |_| {
        var iterator = try plug.dsp.VorbisCommentIterator.init(encoded);
        var actual: usize = 0;
        while (try iterator.next()) |_| actual += 1;
        if (actual != expected) return error.UnexpectedEntryCount;
        std.mem.doNotOptimizeAway(iterator);
    }
    return timer.read();
}

fn traverseFlac(encoded: []const u8, expected: usize, count: usize) !u64 {
    const timer = try Timer.start();
    for (0..count) |_| {
        var iterator = (try plug.dsp.FlacCommentIterator.init(encoded)) orelse
            return error.MissingFlacComments;
        var actual: usize = 0;
        while (try iterator.next()) |_| actual += 1;
        if (actual != expected) return error.UnexpectedEntryCount;
        std.mem.doNotOptimizeAway(iterator);
    }
    return timer.read();
}

fn traverseId3V23(encoded: []const u8, expected: usize, count: usize) !u64 {
    const timer = try Timer.start();
    for (0..count) |_| {
        const view = try plug.dsp.Id3V23View.init(encoded, &.{});
        var iterator = view.iterator();
        var actual: usize = 0;
        while (try iterator.next()) |_| actual += 1;
        if (actual != expected) return error.UnexpectedEntryCount;
        std.mem.doNotOptimizeAway(iterator);
    }
    return timer.read();
}

fn traverseId3V24(encoded: []const u8, expected: usize, count: usize) !u64 {
    const timer = try Timer.start();
    for (0..count) |_| {
        const view = try plug.dsp.Id3View.init(encoded);
        var iterator = view.iterator();
        var actual: usize = 0;
        while (try iterator.next()) |_| actual += 1;
        if (actual != expected) return error.UnexpectedEntryCount;
        std.mem.doNotOptimizeAway(iterator);
    }
    return timer.read();
}

fn traverseRiffInfo(encoded: []const u8, expected: usize, count: usize) !u64 {
    const timer = try Timer.start();
    for (0..count) |_| {
        const view = try plug.dsp.RiffInfoMetadataView.init(encoded);
        var iterator = view.iterator();
        var actual: usize = 0;
        while (try iterator.next()) |_| actual += 1;
        if (actual != expected) return error.UnexpectedEntryCount;
        std.mem.doNotOptimizeAway(iterator);
    }
    return timer.read();
}

fn traverseAiffText(encoded: []const u8, expected: usize, count: usize) !u64 {
    const timer = try Timer.start();
    for (0..count) |_| {
        var iterator = try plug.dsp.AiffTextMetadataIterator.init(encoded);
        var actual: usize = 0;
        while (try iterator.next()) |_| actual += 1;
        if (actual != expected) return error.UnexpectedEntryCount;
        std.mem.doNotOptimizeAway(iterator);
    }
    return timer.read();
}

fn writeU24(bytes: *[3]u8, value: usize) void {
    bytes[0] = @intCast((value >> 16) & 0xff);
    bytes[1] = @intCast((value >> 8) & 0xff);
    bytes[2] = @intCast(value & 0xff);
}

fn writeSyncsafe28(bytes: *[4]u8, value: usize) void {
    bytes[0] = @intCast((value >> 21) & 0x7f);
    bytes[1] = @intCast((value >> 14) & 0x7f);
    bytes[2] = @intCast((value >> 7) & 0x7f);
    bytes[3] = @intCast(value & 0x7f);
}

fn monotonicNowNs() !u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &timestamp) != 0)
        return error.BenchmarkClockUnavailable;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}
