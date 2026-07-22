const builtin = @import("builtin");
const plug = @import("zig-vst3-plugin");
const std = @import("std");

const maximum_frames = 8192;
const maximum_file_bytes = 44 + maximum_frames * @sizeOf(f64);
const maximum_nanoseconds_per_sample = 100.0;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) return error.InvalidArguments;

    var input_bytes: [maximum_file_bytes]u8 = undefined;
    var reference_f32_bytes: [maximum_file_bytes]u8 = undefined;
    var reference_f64_bytes: [maximum_file_bytes]u8 = undefined;
    const input_wav = try loadFile(init.io, args[1], &input_bytes);
    const reference_f32_wav = try loadFile(init.io, args[2], &reference_f32_bytes);
    const reference_f64_wav = try loadFile(init.io, args[3], &reference_f64_bytes);

    try runCase(f32, init.io, input_wav, reference_f32_wav, .{
        .maximum_absolute = 2.0e-6,
        .maximum_relative = 2.0e-5,
        .maximum_rms = 2.0e-7,
        .relative_floor = 1.0e-5,
    });
    try runCase(f64, init.io, input_wav, reference_f64_wav, .{
        .maximum_absolute = 1.0e-12,
        .maximum_relative = 1.0e-10,
        .maximum_rms = 1.0e-13,
        .relative_floor = 1.0e-12,
    });
}

fn runCase(
    comptime Sample: type,
    io: std.Io,
    input_wav: []const u8,
    reference_wav: []const u8,
    tolerance: plug.dsp.fixture_runner.Tolerance,
) !void {
    var input: [maximum_frames]Sample = undefined;
    var reference: [maximum_frames]Sample = undefined;
    const input_info = try plug.dsp.fixture_runner.decodeMonoWav(Sample, input_wav, &input);
    const reference_info = try plug.dsp.fixture_runner.decodeMonoWav(Sample, reference_wav, &reference);
    if (input_info.sample_rate != reference_info.sample_rate or input_info.frames != reference_info.frames) {
        return error.FixtureFormatMismatch;
    }
    const frames = input_info.frames;
    var fixed: [maximum_frames]Sample = undefined;
    var randomized: [maximum_frames]Sample = undefined;
    var model = ReferenceModel(Sample){};
    const processor = plug.dsp.BlockProcessor(Sample).init(ReferenceModel(Sample), &model);
    var denormals = plug.dsp.DenormalScope.enter();
    defer denormals.leave();

    const fixed_start = std.Io.Clock.awake.now(io).nanoseconds;
    try plug.dsp.fixture_runner.renderFixed(Sample, processor, input[0..frames], fixed[0..frames], 64);
    const fixed_elapsed = std.Io.Clock.awake.now(io).nanoseconds - fixed_start;
    const randomized_start = std.Io.Clock.awake.now(io).nanoseconds;
    try plug.dsp.fixture_runner.renderRandomized(Sample, processor, input[0..frames], randomized[0..frames], 257, 0x4e414d5f50415249);
    const randomized_elapsed = std.Io.Clock.awake.now(io).nanoseconds - randomized_start;

    const fixed_comparison = try plug.dsp.fixture_runner.compare(Sample, reference[0..frames], fixed[0..frames], tolerance);
    const randomized_comparison = try plug.dsp.fixture_runner.compare(Sample, reference[0..frames], randomized[0..frames], tolerance);
    const block_comparison = try plug.dsp.fixture_runner.compare(Sample, fixed[0..frames], randomized[0..frames], .{
        .maximum_absolute = 0.0,
        .maximum_relative = 0.0,
        .maximum_rms = 0.0,
    });
    if (!fixed_comparison.passed or !randomized_comparison.passed or !block_comparison.passed) {
        printComparison(Sample, "fixed", fixed_comparison);
        printComparison(Sample, "randomized", randomized_comparison);
        printComparison(Sample, "block-invariance", block_comparison);
        return error.ReferenceMismatch;
    }

    const fixed_ns = @as(f64, @floatFromInt(fixed_elapsed)) / @as(f64, @floatFromInt(frames));
    const randomized_ns = @as(f64, @floatFromInt(randomized_elapsed)) / @as(f64, @floatFromInt(frames));
    if (fixed_ns > maximum_nanoseconds_per_sample or randomized_ns > maximum_nanoseconds_per_sample) {
        return error.PerformanceRegression;
    }
    std.debug.print(
        "DSP parity: arch={s} model=linear-recurrent sample={s} rate={d} backend=zig fixed={d:.2} ns/sample randomized={d:.2} ns/sample max_abs={e:.3} max_rel={e:.3} rms={e:.3}\n",
        .{
            @tagName(builtin.cpu.arch),
            @typeName(Sample),
            input_info.sample_rate,
            fixed_ns,
            randomized_ns,
            fixed_comparison.metrics.maximum_absolute,
            fixed_comparison.metrics.maximum_relative,
            fixed_comparison.metrics.rms,
        },
    );
}

fn ReferenceModel(comptime Sample: type) type {
    return struct {
        state: Sample = 0.0,

        pub fn reset(self: *@This()) void {
            self.state = 0.0;
        }

        pub fn processBlock(self: *@This(), input: []const Sample, output: []Sample) void {
            for (input, output) |sample, *destination| {
                self.state = @as(Sample, 0.85) * self.state + @as(Sample, 0.15) * sample;
                destination.* = @as(Sample, 0.7) * sample + @as(Sample, 0.3) * self.state;
            }
        }
    };
}

fn loadFile(io: std.Io, path: []const u8, storage: []u8) ![]const u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const length = try file.length(io);
    if (length > storage.len) return error.FixtureTooLarge;
    const byte_count: usize = @intCast(length);
    if (try file.readPositionalAll(io, storage[0..byte_count], 0) != byte_count) return error.TruncatedFixture;
    return storage[0..byte_count];
}

fn printComparison(comptime Sample: type, name: []const u8, comparison: plug.dsp.fixture_runner.Comparison) void {
    std.debug.print(
        "DSP parity failure: sample={s} render={s} max_abs={e:.3} max_rel={e:.3} rms={e:.3}\n",
        .{
            @typeName(Sample),
            name,
            comparison.metrics.maximum_absolute,
            comparison.metrics.maximum_relative,
            comparison.metrics.rms,
        },
    );
}
