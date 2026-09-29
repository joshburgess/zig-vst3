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
    events: usize,
    parse_ns_per_event: f64,
    traversal_ns_per_event: f64,
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
    for ([_]struct { events: usize, iterations: usize }{
        .{ .events = 1_000, .iterations = 512 },
        .{ .events = 2_000, .iterations = 256 },
        .{ .events = 4_000, .iterations = 128 },
    }) |config| {
        const measurement = try measure(
            allocator,
            config.events,
            config.iterations,
        );
        try stdout.print(
            "events={} parse_ns_per_event={d:.2} traversal_ns_per_event={d:.2}\n",
            .{
                measurement.events,
                measurement.parse_ns_per_event,
                measurement.traversal_ns_per_event,
            },
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
    event_count: usize,
    iterations: usize,
) !Measurement {
    const capacity = 32 + event_count * 4;
    const storage = try allocator.alloc(u8, capacity);
    var writer = try plug.process.MidiFileWriter.init(
        storage,
        .single_track,
        1,
        .{ .ticks_per_quarter_note = 480 },
    );
    try writer.beginTrack();
    for (0..event_count) |_| try writer.writeMeta(0, 0x01, "");
    try writer.endTrack(0);
    const encoded = try writer.finish();

    var checksum: usize = 0;
    const parse_timer = try Timer.start();
    for (0..iterations) |_| {
        const file = try plug.process.MidiFile.parse(encoded);
        checksum +%= file.track_count;
        std.mem.doNotOptimizeAway(file);
    }
    const parse_ns = try parse_timer.read();

    const file = try plug.process.MidiFile.parse(encoded);
    const traversal_timer = try Timer.start();
    for (0..iterations) |_| {
        const track = file.track(0) orelse return error.MissingMidiTrack;
        var iterator = track.iterator();
        while (try iterator.next()) |event| {
            checksum +%= @intCast(event.absolute_ticks);
            checksum +%= 1;
        }
        std.mem.doNotOptimizeAway(iterator);
    }
    const traversal_ns = try traversal_timer.read();
    std.mem.doNotOptimizeAway(checksum);

    const operations: f64 = @floatFromInt(iterations * (event_count + 1));
    return .{
        .events = event_count,
        .parse_ns_per_event = @as(f64, @floatFromInt(parse_ns)) / operations,
        .traversal_ns_per_event = @as(f64, @floatFromInt(traversal_ns)) / operations,
    };
}

fn requireBounded(measurement: Measurement) !void {
    const maximum_ns_per_event = 2_000.0;
    if (measurement.parse_ns_per_event > maximum_ns_per_event or
        measurement.traversal_ns_per_event > maximum_ns_per_event)
    {
        return error.MidiFileComplexityBudgetExceeded;
    }
}

fn requireLinearGrowth(previous: Measurement, current: Measurement) !void {
    const maximum_per_event_growth = 1.75;
    if (current.parse_ns_per_event >
        previous.parse_ns_per_event * maximum_per_event_growth or
        current.traversal_ns_per_event >
            previous.traversal_ns_per_event * maximum_per_event_growth)
    {
        return error.MidiFileComplexityGrowthExceeded;
    }
}

fn monotonicNowNs() !u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &timestamp) != 0)
        return error.BenchmarkClockUnavailable;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}
