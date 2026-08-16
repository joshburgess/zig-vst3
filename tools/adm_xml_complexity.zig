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

const Measurement = struct {
    pairs: usize,
    parse_ns_per_pair: f64,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const enforce = switch (args.len) {
        1 => true,
        2 => if (std.mem.eql(u8, args[1], "--report-only"))
            false
        else
            return error.InvalidArguments,
        else => return error.InvalidArguments,
    };
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    try stdout.print("optimize={s}\n", .{@tagName(builtin.mode)});

    var previous: ?Measurement = null;
    for ([_]struct { pairs: usize, iterations: usize }{
        .{ .pairs = 128, .iterations = 4 },
        .{ .pairs = 256, .iterations = 2 },
        .{ .pairs = 512, .iterations = 1 },
    }) |config| {
        const measurement = try measure(
            allocator,
            config.pairs,
            config.iterations,
        );
        try stdout.print(
            "pairs={} parse_ns_per_pair={d:.2}\n",
            .{ measurement.pairs, measurement.parse_ns_per_pair },
        );
        if (enforce) {
            try requireBounded(measurement);
            if (previous) |prior| try requireLinearGrowth(prior, measurement);
        }
        previous = measurement;
    }
}

fn measure(
    allocator: std.mem.Allocator,
    pair_count: usize,
    iterations: usize,
) !Measurement {
    const storage = try allocator.alloc(u8, 192 * pair_count + 64);
    var writer = std.Io.Writer.fixed(storage);
    try writer.writeAll("<audioFormatExtended>");
    for (0..pair_count) |index| {
        const identifier = 0x1001 + index;
        try writer.print(
            "<audioContent audioContentID=\"ACO_{X:0>4}\">" ++
                "<audioObjectIDRef>AO_{X:0>4}</audioObjectIDRef>" ++
                "</audioContent>" ++
                "<audioObject audioObjectID=\"AO_{X:0>4}\"/>",
            .{ identifier, identifier, identifier },
        );
    }
    try writer.writeAll("</audioFormatExtended>");
    const encoded = writer.buffered();

    var checksum: usize = 0;
    const timer = try Timer.start();
    for (0..iterations) |_| {
        const document = try plug.dsp.AdmXmlDocument.init(encoded);
        checksum +%= document.declaration_count;
        checksum +%= document.reference_count;
        std.mem.doNotOptimizeAway(document);
    }
    const elapsed_ns = try timer.read();
    std.mem.doNotOptimizeAway(checksum);

    const operations: f64 = @floatFromInt(iterations * pair_count);
    return .{
        .pairs = pair_count,
        .parse_ns_per_pair = @as(f64, @floatFromInt(elapsed_ns)) / operations,
    };
}

fn requireBounded(measurement: Measurement) !void {
    if (measurement.parse_ns_per_pair > 1_000_000.0)
        return error.AdmXmlComplexityBudgetExceeded;
}

fn requireLinearGrowth(previous: Measurement, current: Measurement) !void {
    const maximum_per_pair_growth = 1.6;
    if (current.parse_ns_per_pair >
        previous.parse_ns_per_pair * maximum_per_pair_growth)
    {
        return error.AdmXmlComplexityGrowthExceeded;
    }
}

fn monotonicNowNs() !u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &timestamp) != 0)
        return error.BenchmarkClockUnavailable;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}
