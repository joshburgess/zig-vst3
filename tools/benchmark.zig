const std = @import("std");
const raw = @import("zig-vst3");
const plug = @import("zig-vst3-plugin");

const frame_count = 512;
const iterations = 20_000;

const BenchPlugin = struct {
    pub const name = "Benchmark Plugin";
    pub const vendor = "zig-vst3";

    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 1.0,
            .default = 0.5,
        },
        mix: plug.parameters.FloatParam = .{
            .id = 1,
            .name = "Mix",
            .min = 0.0,
            .max = 1.0,
            .default = 1.0,
        },
    };

    pub fn process(_: *BenchPlugin, context: *plug.process.ProcessContext(f32)) void {
        const gain: f32 = @floatCast(context.parameterNormalizedAtOrBeforeOr(0, 0, 0.5));
        const mix: f32 = @floatCast(context.parameterNormalizedAtOrBeforeOr(1, 0, 1.0));
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain * mix;
            }
        }
    }
};

const ParameterSet = plug.parameters.ParameterSet(BenchPlugin.Params);
const ParameterValues = plug.parameters.ParameterValues(BenchPlugin.Params);

const Benchmark = struct {
    name: []const u8,
    iterations: usize,
    elapsed_ns: u64,

    fn print(self: Benchmark) void {
        const ns_per_op = @as(f64, @floatFromInt(self.elapsed_ns)) / @as(f64, @floatFromInt(self.iterations));
        std.debug.print("{s}: {d:.1} ns/op ({d} iterations)\n", .{ self.name, ns_per_op, self.iterations });
    }
};

const Timer = struct {
    start_ns: u64,

    fn start() !Timer {
        return .{ .start_ns = try monotonicNowNs() };
    }

    fn read(self: Timer) !u64 {
        return (try monotonicNowNs()) - self.start_ns;
    }
};

pub fn main() !void {
    std.debug.print("zig-vst3 local microbenchmarks\n", .{});
    std.debug.print("iterations: {d}, frames: {d}\n\n", .{ iterations, frame_count });

    (try benchRawStream()).print();
    (try benchFrameworkProcess()).print();
    (try benchParameterUpdates()).print();
    (try benchStateSaveLoad()).print();
    (try benchGuiScalarSnapshot()).print();
    (try benchWaveformCapture()).print();
    (try benchSpectrumAnalyzer()).print();
    try benchAudioFileImport();
}

fn benchRawStream() !Benchmark {
    const Stream = raw.vst_stream.FixedBufferStream(64);
    var stream = Stream{};
    const iface = stream.asStream();
    var input = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var output = [_]u8{0} ** input.len;

    var timer = try Timer.start();
    var checksum: u64 = 0;
    for (0..iterations) |_| {
        var written: raw.pluginterfaces.base.types.int32 = 0;
        var read: raw.pluginterfaces.base.types.int32 = 0;
        var pos: raw.pluginterfaces.base.types.int64 = 0;

        if (iface.vtable.seek(iface, 0, @intFromEnum(raw.pluginterfaces.base.ibstream.IStreamSeekMode.kIBSeekSet), &pos) != raw.pluginterfaces.base.types.kResultOk) {
            return error.BenchmarkStreamSeekFailed;
        }
        if (iface.vtable.write(iface, &input, input.len, &written) != raw.pluginterfaces.base.types.kResultOk) {
            return error.BenchmarkStreamWriteFailed;
        }
        if (iface.vtable.seek(iface, 0, @intFromEnum(raw.pluginterfaces.base.ibstream.IStreamSeekMode.kIBSeekSet), &pos) != raw.pluginterfaces.base.types.kResultOk) {
            return error.BenchmarkStreamSeekFailed;
        }
        if (iface.vtable.read(iface, &output, output.len, &read) != raw.pluginterfaces.base.types.kResultOk) {
            return error.BenchmarkStreamReadFailed;
        }
        checksum +%= output[0] + @as(u64, @intCast(written)) + @as(u64, @intCast(read));
    }
    std.mem.doNotOptimizeAway(checksum);
    return .{ .name = "raw IBStream seek/write/read", .iterations = iterations, .elapsed_ns = try timer.read() };
}

fn benchFrameworkProcess() !Benchmark {
    var left_in: [frame_count]f32 = undefined;
    var right_in: [frame_count]f32 = undefined;
    var left_out: [frame_count]f32 = undefined;
    var right_out: [frame_count]f32 = undefined;
    fillInput(&left_in, 0.25);
    fillInput(&right_in, 0.5);

    const inputs = [_][]const f32{ &left_in, &right_in };
    var outputs = [_][]f32{ &left_out, &right_out };
    const changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.7 },
        .{ .id = 1, .sample_offset = 128, .normalized = 0.9 },
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &inputs, &outputs, .{
        .parameter_changes = &changes,
    });
    var plugin = BenchPlugin{};

    var timer = try Timer.start();
    var checksum: f32 = 0.0;
    for (0..iterations) |_| {
        plugin.process(&context);
        checksum += left_out[0] + right_out[frame_count - 1];
    }
    std.mem.doNotOptimizeAway(checksum);
    return .{ .name = "framework process block", .iterations = iterations, .elapsed_ns = try timer.read() };
}

fn benchParameterUpdates() !Benchmark {
    const set = ParameterSet.init(.{});
    var values = ParameterValues.init(&set);

    var timer = try Timer.start();
    var changed: usize = 0;
    for (0..iterations) |index| {
        const value = @as(f64, @floatFromInt(index % 1000)) / 1000.0;
        changed += values.storeCount(0, value) orelse return error.BenchmarkParameterStoreFailed;
        changed += values.storeCount(1, 1.0 - value) orelse return error.BenchmarkParameterStoreFailed;
    }
    std.mem.doNotOptimizeAway(changed);
    return .{ .name = "parameter value stores", .iterations = iterations * 2, .elapsed_ns = try timer.read() };
}

fn benchStateSaveLoad() !Benchmark {
    const set = ParameterSet.init(.{});
    var values = ParameterValues.init(&set);
    _ = values.store(0, 0.7);
    _ = values.store(1, 0.9);

    var restored_values = ParameterValues.init(&set);

    var buffer: [plug.state.encodedSize(BenchPlugin.Params)]u8 = undefined;
    var timer = try Timer.start();
    var restored: usize = 0;
    for (0..iterations) |_| {
        var writer = std.Io.Writer.fixed(&buffer);
        try plug.state.writeParameterState(BenchPlugin.Params, &set, &values, &writer);
        var reader = std.Io.Reader.fixed(writer.buffered());
        const report = try plug.state.readParameterStateReport(BenchPlugin.Params, &set, &restored_values, &reader);
        restored += report.restoredCount();
    }
    std.mem.doNotOptimizeAway(restored);
    return .{ .name = "state save/load", .iterations = iterations, .elapsed_ns = try timer.read() };
}

fn benchGuiScalarSnapshot() !Benchmark {
    var snapshot = plug.gui_telemetry.ScalarSnapshot(f64).init(0.0);

    var timer = try Timer.start();
    var checksum: u64 = 0;
    for (0..iterations) |index| {
        const value = @as(f64, @floatFromInt(index % 1000)) / 1000.0;
        snapshot.store(value);
        checksum +%= @bitCast(snapshot.load());
    }
    std.mem.doNotOptimizeAway(checksum);
    return .{ .name = "GUI scalar snapshot store/load", .iterations = iterations, .elapsed_ns = try timer.read() };
}

fn benchWaveformCapture() !Benchmark {
    var capture = plug.gui_graph.WaveformCapture(128).init();
    capture.editorOpened();
    defer capture.editorClosed();
    var input: [frame_count]f32 = undefined;
    fillInput(&input, 0.01);
    var output: [128]plug.gui_graph.Point = undefined;

    var timer = try Timer.start();
    var checksum: f64 = 0.0;
    for (0..iterations) |_| {
        if (!capture.capture(&input)) return error.BenchmarkWaveformPublishFailed;
        const count = capture.read(&output) orelse return error.BenchmarkWaveformReadFailed;
        checksum += output[count - 1].y;
    }
    std.mem.doNotOptimizeAway(checksum);
    return .{ .name = "GUI waveform capture/read", .iterations = iterations, .elapsed_ns = try timer.read() };
}

fn benchSpectrumAnalyzer() !Benchmark {
    var analyzer = plug.gui_graph.SpectrumAnalyzer(128).init();
    analyzer.editorOpened();
    defer analyzer.editorClosed();
    var input: [frame_count]f32 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* = @floatCast(std.math.sin(std.math.tau * 8.0 * @as(f64, @floatFromInt(index)) / 128.0));
    }
    var output: [64]plug.gui_graph.Point = undefined;

    var timer = try Timer.start();
    var checksum: f64 = 0.0;
    for (0..iterations) |_| {
        if (!analyzer.push(&input, 48_000.0)) return error.BenchmarkSpectrumPublishFailed;
        const count = analyzer.read(&output) orelse return error.BenchmarkSpectrumReadFailed;
        checksum += output[count - 1].y;
    }
    std.mem.doNotOptimizeAway(checksum);
    return .{ .name = "GUI 128-point spectrum analysis/read", .iterations = iterations, .elapsed_ns = try timer.read() };
}

fn benchAudioFileImport() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = ".zig-cache/audio-import-benchmark.wav";
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};
    const data_bytes = 8 * 1024 * 1024;
    var header: [44]u8 = undefined;
    var header_writer = std.Io.Writer.fixed(&header);
    try header_writer.writeAll("RIFF");
    try header_writer.writeInt(u32, 36 + data_bytes, .little);
    try header_writer.writeAll("WAVEfmt ");
    try header_writer.writeInt(u32, 16, .little);
    try header_writer.writeInt(u16, 1, .little);
    try header_writer.writeInt(u16, 1, .little);
    try header_writer.writeInt(u32, 48_000, .little);
    try header_writer.writeInt(u32, 96_000, .little);
    try header_writer.writeInt(u16, 2, .little);
    try header_writer.writeInt(u16, 16, .little);
    try header_writer.writeAll("data");
    try header_writer.writeInt(u32, data_bytes, .little);
    {
        var file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, header_writer.buffered());
        const samples = [_]u8{0} ** 4096;
        var written: usize = 0;
        while (written < data_bytes) : (written += samples.len) try file.writeStreamingAll(io, &samples);
    }

    var importer = plug.gui_audio_file_importer.Importer.init();
    defer importer.deinit();
    var timer = try Timer.start();
    if (!importer.begin(.picker, &.{path})) return error.BenchmarkImportStartFailed;
    while (true) {
        const snapshot = importer.snapshot();
        if (snapshot.import.status == .ready) break;
        if (snapshot.import.status != .validating and snapshot.import.status != .importing) {
            return error.BenchmarkImportFailed;
        }
        std.Thread.yield() catch {};
    }
    const elapsed_ns = try timer.read();
    const mebibytes_per_second = @as(f64, @floatFromInt(data_bytes)) * @as(f64, std.time.ns_per_s) /
        (@as(f64, @floatFromInt(elapsed_ns)) * 1024.0 * 1024.0);
    std.debug.print("bounded PCM WAV worker: {d:.1} MiB/s ({d} bytes)\n", .{ mebibytes_per_second, data_bytes });
}

fn fillInput(buffer: []f32, scale: f32) void {
    for (buffer, 0..) |*sample, index| {
        sample.* = scale * @as(f32, @floatFromInt(index % 17));
    }
}

fn monotonicNowNs() !u64 {
    var timestamp: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &timestamp) != 0) {
        return error.BenchmarkClockUnavailable;
    }
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(timestamp.nsec));
}
