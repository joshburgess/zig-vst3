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
    packets: usize,
    traversal_ns_per_packet: f64,
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
    for ([_]struct { packets: usize, iterations: usize }{
        .{ .packets = 1_024, .iterations = 1_024 },
        .{ .packets = 2_048, .iterations = 512 },
        .{ .packets = 4_096, .iterations = 256 },
    }) |config| {
        const measurement = try measure(
            allocator,
            config.packets,
            config.iterations,
        );
        try stdout.print(
            "packets={} traversal_ns_per_packet={d:.2}\n",
            .{ measurement.packets, measurement.traversal_ns_per_packet },
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
    packet_count: usize,
    iterations: usize,
) !Measurement {
    const words = try allocator.alloc(u32, packet_count);
    @memset(words, 0x2090_3c7f);

    var checksum: usize = 0;
    const timer = try Timer.start();
    for (0..iterations) |_| {
        var iterator = plug.process.UmpIterator{ .source = words };
        while (try iterator.next()) |packet| {
            checksum +%= packet.words().len;
        }
        std.mem.doNotOptimizeAway(iterator);
    }
    const elapsed_ns = try timer.read();
    std.mem.doNotOptimizeAway(checksum);

    const operations: f64 = @floatFromInt(iterations * packet_count);
    return .{
        .packets = packet_count,
        .traversal_ns_per_packet = @as(f64, @floatFromInt(elapsed_ns)) / operations,
    };
}

fn requireBounded(measurement: Measurement) !void {
    if (measurement.traversal_ns_per_packet > 2_000.0)
        return error.UmpStreamComplexityBudgetExceeded;
}

fn requireLinearGrowth(previous: Measurement, current: Measurement) !void {
    if (current.traversal_ns_per_packet >
        previous.traversal_ns_per_packet * 1.75)
    {
        return error.UmpStreamComplexityGrowthExceeded;
    }
}

fn monotonicNowNs() !u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &timestamp) != 0)
        return error.BenchmarkClockUnavailable;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}
