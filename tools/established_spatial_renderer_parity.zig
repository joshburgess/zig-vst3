const plugin = @import("zig-vst3-plugin");
const std = @import("std");

extern fn established_hrtf_filter(
    path: [*:0]const u8,
    sample_rate: f32,
    x: f32,
    y: f32,
    z: f32,
    interpolate: c_int,
    interleaved_output: [*]f32,
    output_count: usize,
    frame_count_output: *usize,
    left_delay_output: *f32,
    right_delay_output: *f32,
) c_int;

extern fn established_hoa_render(
    order: c_uint,
    layout: c_uint,
    sample_rate: c_uint,
    channel_major_inputs: [*]const f32,
    input_count: usize,
    sample_count: usize,
    output_major_coefficients: [*]f32,
    coefficient_count: usize,
    channel_major_outputs: [*]f32,
    output_count: usize,
) c_int;

const maximum_hrtf_frames = 512;
const maximum_hoa_inputs = 16;
const maximum_hoa_outputs = 8;
const hoa_sample_count = 257;
const HoaComponent = struct {
    order: u32,
    degree: i32,
};
const ErrorMetrics = struct {
    sample_count: usize = 0,
    peak_error: f64 = 0.0,
    squared_error: f64 = 0.0,
    squared_reference: f64 = 0.0,

    fn add(self: *ErrorMetrics, actual: f64, reference: f64) void {
        const difference = actual - reference;
        self.sample_count += 1;
        self.peak_error = @max(self.peak_error, @abs(difference));
        self.squared_error += difference * difference;
        self.squared_reference += reference * reference;
    }

    fn merge(self: *ErrorMetrics, other: ErrorMetrics) void {
        self.sample_count += other.sample_count;
        self.peak_error = @max(self.peak_error, other.peak_error);
        self.squared_error += other.squared_error;
        self.squared_reference += other.squared_reference;
    }

    fn normalizedRms(self: ErrorMetrics) f64 {
        return @sqrt(self.squared_error / self.squared_reference);
    }
};
const HrtfSummary = struct {
    comparison_count: usize = 0,
    metrics: ErrorMetrics = .{},
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.InvalidArguments;

    const hrtf = try compareHrtfDatasets(
        allocator,
        args[1],
        args[2],
    );
    const hoa = try compareHoaRenderers();

    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try stdout.interface.print(
        "matched {d} libmysofa full filters across {d} checked samples (peak {e:.3}, normalized RMS {e:.3})\n",
        .{
            hrtf.comparison_count,
            hrtf.metrics.sample_count,
            hrtf.metrics.peak_error,
            hrtf.metrics.normalizedRms(),
        },
    );
    try stdout.interface.print(
        "matched {d} libspatialaudio rendered HOA samples (peak {e:.3}, normalized RMS {e:.3})\n",
        .{ hoa.sample_count, hoa.peak_error, hoa.normalizedRms() },
    );
}

fn compareHrtfDatasets(
    allocator: std.mem.Allocator,
    viking_path: []const u8,
    hutubs_path: []const u8,
) !HrtfSummary {
    var summary = try compareHrtfDataset(
        1_513,
        128,
        allocator,
        viking_path,
    );
    const hutubs = try compareHrtfDataset(
        440,
        256,
        allocator,
        hutubs_path,
    );
    summary.comparison_count += hutubs.comparison_count;
    summary.metrics.merge(hutubs.metrics);
    return summary;
}

fn compareHrtfDataset(
    comptime maximum_measurements: usize,
    comptime dataset_maximum_frames: usize,
    allocator: std.mem.Allocator,
    path: []const u8,
) !HrtfSummary {
    const Loader = plugin.dsp.HrtfSofaLoader(
        maximum_measurements,
        dataset_maximum_frames,
    );
    var loader = try Loader.openDefault();
    defer loader.deinit();
    const Database = plugin.dsp.HrtfDatabase(
        maximum_measurements,
        dataset_maximum_frames,
    );
    const database = try allocator.create(Database);
    try loader.loadFileInto(allocator, path, database);
    if (database.response_frame_count > maximum_hrtf_frames)
        return error.EstablishedHrtfFrameCapacityExceeded;

    var reference: [maximum_hrtf_frames * 2]f32 = @splat(0.0);
    const terminated_path = try allocator.dupeZ(u8, path);
    try verifyHrtfRejection(
        terminated_path,
        @floatFromInt(database.sample_rate),
        &reference,
        database.response_frame_count,
    );

    const indices = [_]usize{
        0,
        database.measurement_count / 4,
        database.measurement_count / 2,
        database.measurement_count - 1,
    };
    var metrics = ErrorMetrics{};
    for (indices, 1..) |measurement_index, generation| {
        const direction = database.directions[measurement_index];
        const radius = database.distances_metres[measurement_index];
        const position = cartesian(direction, radius);
        const raw = reference[0 .. database.response_frame_count * 2];
        @memset(raw, 0.0);
        var reference_frames: usize = 0;
        var left_delay: f32 = 0.0;
        var right_delay: f32 = 0.0;
        const status = established_hrtf_filter(
            terminated_path,
            @floatFromInt(database.sample_rate),
            position[0],
            position[1],
            position[2],
            0,
            raw.ptr,
            raw.len,
            &reference_frames,
            &left_delay,
            &right_delay,
        );
        if (status != 0) return error.EstablishedHrtfRendererFailed;
        if (reference_frames != database.response_frame_count)
            return error.EstablishedHrtfShapeMismatch;
        try requireSignal(raw, error.EmptyEstablishedHrtfResponse);
        try compareDelay(
            database.delays_samples[measurement_index][0],
            left_delay,
        );
        try compareDelay(
            database.delays_samples[measurement_index][1],
            right_delay,
        );
        for (0..database.response_frame_count) |frame| {
            inline for (0..2) |channel| {
                try expectClose(
                    database.responses[measurement_index][frame][channel],
                    raw[frame * 2 + channel],
                    3.0e-5,
                    error.EstablishedHrtfFilterMismatch,
                );
                metrics.add(
                    database.responses[measurement_index][frame][channel],
                    raw[frame * 2 + channel],
                );
            }
        }

        const Renderer = plugin.dsp.HrtfRenderer(
            maximum_hrtf_frames,
            8,
        );
        var renderer = try Renderer.init(database.sample_rate, .zero);
        try renderer.prepareInterleavedResponse(
            database.sample_rate,
            raw,
            generation,
        );
        if (!renderer.adoptPending())
            return error.EstablishedHrtfResponseNotAdopted;
        for (0..database.response_frame_count) |frame| {
            const rendered = renderer.processSample(
                if (frame == 0) 1.0 else 0.0,
            );
            inline for (0..2) |channel| {
                try expectClose(
                    rendered[channel],
                    raw[frame * 2 + channel],
                    2.0e-5,
                    error.EstablishedHrtfConvolutionMismatch,
                );
                metrics.add(rendered[channel], raw[frame * 2 + channel]);
            }
        }
    }
    return .{
        .comparison_count = indices.len,
        .metrics = metrics,
    };
}

fn verifyHrtfRejection(
    path: [:0]const u8,
    sample_rate: f32,
    storage: []f32,
    frame_count: usize,
) !void {
    const sentinel: f32 = 123.25;
    @memset(storage, sentinel);
    var rejected_frames: usize = 41;
    var left_delay: f32 = 43.0;
    var right_delay: f32 = 47.0;
    const short_status = established_hrtf_filter(
        path,
        sample_rate,
        1.0,
        0.0,
        0.0,
        0,
        storage.ptr,
        frame_count * 2 - 1,
        &rejected_frames,
        &left_delay,
        &right_delay,
    );
    if (short_status != 3 or rejected_frames != 41 or
        left_delay != 43.0 or right_delay != 47.0 or
        !allEqual(storage, sentinel))
    {
        return error.NonTransactionalEstablishedHrtfRejection;
    }
    const invalid_status = established_hrtf_filter(
        path,
        sample_rate,
        std.math.nan(f32),
        0.0,
        0.0,
        0,
        storage.ptr,
        frame_count * 2,
        &rejected_frames,
        &left_delay,
        &right_delay,
    );
    if (invalid_status != 1 or !allEqual(storage, sentinel))
        return error.NonTransactionalEstablishedHrtfRejection;
}

fn cartesian(
    direction: plugin.dsp.HrtfDirection,
    radius: f64,
) [3]f32 {
    const azimuth = direction.azimuth_degrees * std.math.pi / 180.0;
    const elevation = direction.elevation_degrees * std.math.pi / 180.0;
    const horizontal = radius * @cos(elevation);
    return .{
        @floatCast(horizontal * @cos(azimuth)),
        @floatCast(horizontal * @sin(azimuth)),
        @floatCast(radius * @sin(elevation)),
    };
}

fn compareDelay(actual_samples: f64, reference_samples: f32) !void {
    try expectClose(
        actual_samples,
        reference_samples,
        2.0e-4,
        error.EstablishedHrtfDelayMismatch,
    );
}

fn compareHoaRenderers() !ErrorMetrics {
    var metrics = ErrorMetrics{};
    const cases = [_]struct {
        order: u32,
        layout: u32,
        output_count: usize,
        sample_rate: u32,
        normalization: plugin.dsp.AdmXmlHoaNormalization,
        permuted: bool,
    }{
        .{ .order = 1, .layout = 1, .output_count = 6, .sample_rate = 44_100, .normalization = .fuma, .permuted = false },
        .{ .order = 2, .layout = 2, .output_count = 8, .sample_rate = 48_000, .normalization = .n3d, .permuted = true },
        .{ .order = 3, .layout = 2, .output_count = 8, .sample_rate = 96_000, .normalization = .sn3d, .permuted = false },
    };
    for (cases) |case| {
        metrics.merge(try compareHoaCase(
            case.order,
            case.layout,
            case.output_count,
            case.sample_rate,
            case.normalization,
            case.permuted,
        ));
    }
    return metrics;
}

fn compareHoaCase(
    order: u32,
    layout: u32,
    output_count: usize,
    sample_rate: u32,
    normalization: plugin.dsp.AdmXmlHoaNormalization,
    permuted: bool,
) !ErrorMetrics {
    const input_count = @as(usize, order + 1) * @as(usize, order + 1);
    var project_inputs: [maximum_hoa_inputs][hoa_sample_count]f32 = undefined;
    var external_inputs: [maximum_hoa_inputs * hoa_sample_count]f32 = @splat(0.0);
    for (0..input_count) |channel| {
        const component = componentForIndex(channel);
        const scale = normalizationScale(
            normalization,
            component.order,
            component.degree,
        );
        for (0..hoa_sample_count) |sample_index| {
            const phase: f32 = @floatFromInt(
                (channel + 1) * (sample_index + 3),
            );
            const value = 0.45 * @sin(phase * 0.013) +
                0.17 * @cos(phase * 0.037);
            project_inputs[channel][sample_index] = value;
            external_inputs[channel * hoa_sample_count + sample_index] =
                value * scale;
        }
    }

    var coefficients: [maximum_hoa_inputs * maximum_hoa_outputs]f32 =
        @splat(123.25);
    var reference_outputs: [maximum_hoa_outputs * hoa_sample_count]f32 =
        @splat(123.25);
    const status = established_hoa_render(
        order,
        layout,
        sample_rate,
        &external_inputs,
        input_count,
        hoa_sample_count,
        &coefficients,
        output_count * input_count,
        &reference_outputs,
        output_count * hoa_sample_count,
    );
    if (status != 0) return error.EstablishedHoaRendererFailed;
    try requireSignal(
        reference_outputs[0 .. output_count * hoa_sample_count],
        error.EmptyEstablishedHoaResponse,
    );
    try verifyHoaRejection(
        order,
        layout,
        sample_rate,
        &external_inputs,
        input_count,
        output_count,
    );

    const document = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>0</order><degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    const prototype = (try iterator.next()) orelse
        return error.MissingHoaPrototype;
    var blocks: [maximum_hoa_inputs]plugin.dsp.AdmXmlBlockFormat = undefined;
    var adjusted_coefficients: [maximum_hoa_inputs * maximum_hoa_outputs]f32 =
        @splat(0.0);
    var project_input_slices: [maximum_hoa_inputs][]const f32 = undefined;
    for (0..input_count) |destination| {
        const source = if (permuted)
            (destination * 5) % input_count
        else
            destination;
        const component = componentForIndex(source);
        blocks[destination] = prototype;
        blocks[destination].hoa_order = component.order;
        blocks[destination].hoa_degree = component.degree;
        blocks[destination].hoa_normalization = normalization;
        project_input_slices[destination] = &project_inputs[source];
        const scale = normalizationScale(
            normalization,
            component.order,
            component.degree,
        );
        for (0..output_count) |output| {
            adjusted_coefficients[output * input_count + destination] =
                coefficients[output * input_count + source] * scale;
        }
    }
    const Decoder = plugin.dsp.AdmHoaMatrixDecoder(
        f32,
        maximum_hoa_inputs,
        maximum_hoa_outputs,
    );
    const decoder = try Decoder.init(
        blocks[0..input_count],
        output_count,
        adjusted_coefficients[0 .. output_count * input_count],
    );
    var project_outputs: [maximum_hoa_outputs][hoa_sample_count]f32 = undefined;
    var project_output_slices: [maximum_hoa_outputs][]f32 = undefined;
    for (0..output_count) |output|
        project_output_slices[output] = &project_outputs[output];
    try decoder.process(
        project_input_slices[0..input_count],
        project_output_slices[0..output_count],
    );

    var metrics = ErrorMetrics{};
    for (0..output_count) |output| {
        for (0..hoa_sample_count) |sample_index| {
            const actual = project_outputs[output][sample_index];
            const reference = reference_outputs[
                output * hoa_sample_count + sample_index
            ];
            if (!std.math.isFinite(actual) or
                !std.math.isFinite(reference))
            {
                return error.NonFiniteEstablishedHoaResponse;
            }
            metrics.add(actual, reference);
        }
    }
    if (metrics.peak_error > 2.0e-5 or metrics.normalizedRms() > 2.0e-6)
        return error.EstablishedHoaRenderMismatch;
    return metrics;
}

fn verifyHoaRejection(
    order: u32,
    layout: u32,
    sample_rate: u32,
    inputs: []const f32,
    input_count: usize,
    output_count: usize,
) !void {
    var coefficients: [maximum_hoa_inputs * maximum_hoa_outputs]f32 =
        @splat(123.25);
    var outputs: [maximum_hoa_outputs * hoa_sample_count]f32 =
        @splat(123.25);
    const status = established_hoa_render(
        order,
        layout,
        sample_rate,
        inputs.ptr,
        input_count,
        hoa_sample_count,
        &coefficients,
        output_count * input_count - 1,
        &outputs,
        output_count * hoa_sample_count,
    );
    if (status != 5 or !allEqual(&coefficients, 123.25) or
        !allEqual(&outputs, 123.25))
    {
        return error.NonTransactionalEstablishedHoaRejection;
    }
}

fn componentForIndex(index: usize) HoaComponent {
    var order: usize = 0;
    while ((order + 1) * (order + 1) <= index) : (order += 1) {}
    return .{
        .order = @intCast(order),
        .degree = @as(i32, @intCast(index)) -
            @as(i32, @intCast(order * order + order)),
    };
}

fn normalizationScale(
    normalization: plugin.dsp.AdmXmlHoaNormalization,
    order: u32,
    degree: i32,
) f32 {
    const scale: f64 = switch (normalization) {
        .sn3d => 1.0,
        .n3d => @sqrt(@as(f64, @floatFromInt(2 * order + 1))),
        .fuma => switch (order) {
            0 => 1.0 / @sqrt(2.0),
            1 => 1.0,
            2 => if (@abs(degree) == 0) 1.0 else 2.0 / @sqrt(3.0),
            3 => switch (@abs(degree)) {
                0 => 1.0,
                1 => @sqrt(45.0 / 32.0),
                2 => 3.0 / @sqrt(5.0),
                3 => @sqrt(8.0 / 5.0),
                else => unreachable,
            },
            else => unreachable,
        },
    };
    return @floatCast(scale);
}

fn requireSignal(samples: []const f32, comptime empty_error: anyerror) !void {
    var energy: f64 = 0.0;
    for (samples) |sample| {
        if (!std.math.isFinite(sample)) return error.NonFiniteEstablishedResponse;
        energy += @as(f64, sample) * sample;
    }
    if (!std.math.isFinite(energy) or energy <= 1.0e-20)
        return empty_error;
}

fn allEqual(samples: []const f32, expected: f32) bool {
    for (samples) |sample| {
        if (sample != expected) return false;
    }
    return true;
}

fn expectClose(
    actual: anytype,
    reference: anytype,
    tolerance: f64,
    comptime mismatch_error: anyerror,
) !void {
    const actual_f64: f64 = @floatCast(actual);
    const reference_f64: f64 = @floatCast(reference);
    if (!std.math.isFinite(actual_f64) or
        !std.math.isFinite(reference_f64))
    {
        return error.NonFiniteEstablishedResponse;
    }
    const scale = @max(@max(@abs(actual_f64), @abs(reference_f64)), 1.0);
    if (@abs(actual_f64 - reference_f64) > tolerance * scale)
        return mismatch_error;
}
