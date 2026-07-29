const std = @import("std");
const raw = @import("zig-vst3");
const plug = @import("zig-vst3-plugin");
const c_kernel = @import("c-kernel-core");

const frame_count = 512;
const iterations = 20_000;

extern fn zig_vst3_bench_recurrent_tail(f32, f32, u32, usize) callconv(.c) f32;
extern fn zig_vst3_bench_convolution_tail([*]const f32, [*]const f32, usize, usize) callconv(.c) f32;

const Budget = struct {
    raw_stream_ns: f64 = 10_000.0,
    framework_block_ns: f64 = 50_000.0,
    parameter_store_ns: f64 = 1_000.0,
    state_round_trip_ns: f64 = 100_000.0,
    resource_state_round_trip_ns: f64 = 100_000.0,
    resource_identity_mib_per_second: f64 = 20.0,
    scalar_snapshot_ns: f64 = 1_000.0,
    waveform_snapshot_ns: f64 = 50_000.0,
    spectrum_snapshot_ns: f64 = 100_000.0,
    import_mib_per_second: f64 = 50.0,
    sample_decode_ms: f64 = 500.0,
    sample_preview_ns: f64 = 50_000.0,
    sample_publication_ms: f64 = 100.0,
    sample_adoption_ns: f64 = 1_000_000.0,
    sample_playback_ns_per_frame: f64 = 1_000.0,
    playhead_update_ns: f64 = 10_000.0,
    ir_preparation_ms: f64 = 500.0,
    ir_adoption_ns: f64 = 1_000_000.0,
    ir_processing_ns_per_sample: f64 = 20_000.0,
    resampler_ns_per_sample: f64 = 500.0,
    fixed_rate_ns_per_sample: f64 = 2_000.0,
    chebyshev2_design_ns: f64 = 1_000_000.0,
    elliptic_design_ns: f64 = 5_000_000.0,
    complex_jacobi_ns: f64 = 10_000.0,
    inverse_complex_jacobi_ns: f64 = 10_000.0,
    least_squares_design_ns: f64 = 100_000_000.0,
    equiripple_design_ns: f64 = 200_000_000.0,
    mixed_oversampling_design_ns: f64 = 500_000_000.0,
    mixed_oversampling_ns_per_sample: f64 = 5_000.0,
    lookahead_limiter_ns_per_sample: f64 = 2_000.0,
    inter_sample_limiter_ns_per_sample: f64 = 5_000.0,
    multiband_compressor_ns_per_sample: f64 = 5_000.0,
    adm_diffuse_ns_per_output_sample: f64 = 5_000.0,
    snapshot_publication_ns: f64 = 1_000.0,
    snapshot_read_ns: f64 = 1_000.0,
    contended_snapshot_publication_ns: f64 = 2_000.0,
    reference_snapshot_update_ns: f64 = 2_000.0,
    vorbis_mdct_ns_per_sample: f64 = 500.0,
    dispatched_kernel_ns_per_sample: f64 = 100.0,
    dense_kernel_ns: f64 = 500.0,
    recurrent_tail_ns: f64 = 50.0,
    convolution_tail_ns: f64 = 500.0,
};

const budget = Budget{};

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

    fn requireAtMost(self: Benchmark, maximum_ns_per_op: f64) !void {
        self.print();
        const actual = @as(f64, @floatFromInt(self.elapsed_ns)) / @as(f64, @floatFromInt(self.iterations));
        if (actual > maximum_ns_per_op) {
            std.debug.print("benchmark budget exceeded: {s} measured {d:.1} ns/op, budget {d:.1} ns/op\n", .{
                self.name, actual, maximum_ns_per_op,
            });
            return error.BenchmarkBudgetExceeded;
        }
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

    try (try benchRawStream()).requireAtMost(budget.raw_stream_ns);
    try (try benchFrameworkProcess()).requireAtMost(budget.framework_block_ns);
    try (try benchParameterUpdates()).requireAtMost(budget.parameter_store_ns);
    try (try benchStateSaveLoad()).requireAtMost(budget.state_round_trip_ns);
    try (try benchResourceState()).requireAtMost(budget.resource_state_round_trip_ns);
    try benchResourceIdentity();
    try (try benchGuiScalarSnapshot()).requireAtMost(budget.scalar_snapshot_ns);
    try (try benchWaveformCapture()).requireAtMost(budget.waveform_snapshot_ns);
    try (try benchSpectrumAnalyzer()).requireAtMost(budget.spectrum_snapshot_ns);
    try benchAudioFileImport();
    try benchSamplePlayerPipeline();
    try benchIrConvolution();
    try benchStreamingResampler();
    try benchFixedRatePipeline();
    try benchAdvancedFilterDesign();
    try benchAdvancedDynamics();
    try benchAdmDiffuse();
    try benchRealtimePublication();
    try benchVorbisInverseMdct();
    try benchDispatchedKernels();
    try benchDenseKernels();
    try benchDenormalSilenceTails();
}

fn benchAdvancedFilterDesign() !void {
    std.debug.print("\nadvanced filter design\n", .{});

    const iir_iterations = 1_000;
    var timer = try Timer.start();
    var iir_checksum: f64 = 0.0;
    for (0..iir_iterations) |_| {
        const cascade = try plug.dsp.ChebyshevTypeIIDesigner(f64).lowPass(.{
            .order = 6,
            .sample_rate = 48_000.0,
            .stopband_hz = 6_000.0,
            .attenuation_db = 72.0,
        });
        iir_checksum += cascade.sections[0].b0;
    }
    std.mem.doNotOptimizeAway(iir_checksum);
    try requireRate(
        "Chebyshev Type II design",
        try timer.read(),
        iir_iterations,
        budget.chebyshev2_design_ns,
    );

    timer = try Timer.start();
    iir_checksum = 0.0;
    for (0..iir_iterations) |_| {
        const cascade = try plug.dsp.EllipticDesigner(f64).lowPass(.{
            .order = 6,
            .sample_rate = 48_000.0,
            .frequency_hz = 6_000.0,
            .ripple_db = 0.25,
            .attenuation_db = 90.0,
        });
        iir_checksum += cascade.sections[0].b0;
    }
    std.mem.doNotOptimizeAway(iir_checksum);
    try requireRate(
        "elliptic design",
        try timer.read(),
        iir_iterations,
        budget.elliptic_design_ns,
    );

    const Complex = std.math.complex.Complex(f64);
    timer = try Timer.start();
    var complex_checksum: f64 = 0.0;
    for (0..iterations) |index| {
        const offset =
            @as(f64, @floatFromInt(index % 1_024)) * 0.000_001;
        const values = try plug.dsp.complexJacobiElliptic(
            Complex.init(0.75 + offset, 0.4),
            0.5,
        );
        complex_checksum += values.sn.re;
    }
    std.mem.doNotOptimizeAway(complex_checksum);
    try requireRate(
        "complex Jacobi sn/cn/dn",
        try timer.read(),
        iterations,
        budget.complex_jacobi_ns,
    );

    const inverse_source = try plug.dsp.complexJacobiElliptic(
        Complex.init(0.75, 0.4),
        0.5,
    );
    timer = try Timer.start();
    complex_checksum = 0.0;
    for (0..iterations) |index| {
        const offset =
            @as(f64, @floatFromInt(index % 1_024)) * 0.000_000_1;
        const inverse = try plug.dsp.inverseComplexJacobiSn(
            Complex.init(inverse_source.sn.re + offset, inverse_source.sn.im),
            0.5,
        );
        complex_checksum += inverse.re;
    }
    std.mem.doNotOptimizeAway(complex_checksum);
    try requireRate(
        "inverse complex Jacobi sn",
        try timer.read(),
        iterations,
        budget.inverse_complex_jacobi_ns,
    );

    const bands = [_]plug.dsp.FirLeastSquaresBand{
        .{
            .lower_frequency = 0.0,
            .upper_frequency = 0.18,
            .lower_gain = 1.0,
            .upper_gain = 1.0,
        },
        .{
            .lower_frequency = 0.25,
            .upper_frequency = 0.5,
            .lower_gain = 0.0,
            .upper_gain = 0.0,
            .weight = 4.0,
        },
    };
    const least_squares_iterations = 50;
    var taps: [63]f64 = undefined;
    timer = try Timer.start();
    var fir_checksum: f64 = 0.0;
    for (0..least_squares_iterations) |_| {
        try plug.dsp.FirDesigner(f64).leastSquares(&taps, &bands, 1_024);
        fir_checksum += taps[31];
    }
    std.mem.doNotOptimizeAway(fir_checksum);
    try requireRate(
        "least-squares FIR design",
        try timer.read(),
        least_squares_iterations,
        budget.least_squares_design_ns,
    );

    const equiripple_iterations = 25;
    timer = try Timer.start();
    fir_checksum = 0.0;
    for (0..equiripple_iterations) |_| {
        const report = try plug.dsp.FirEquirippleDesigner(f64).design(
            &taps,
            &bands,
            .{ .grid_density = 32, .maximum_iterations = 64 },
        );
        fir_checksum += taps[31] + report.weighted_ripple;
    }
    std.mem.doNotOptimizeAway(fir_checksum);
    try requireRate(
        "equiripple FIR design",
        try timer.read(),
        equiripple_iterations,
        budget.equiripple_design_ns,
    );

    const mixed_configs = [_]plug.dsp.MixedOversamplingStageConfig{
        .{ .fir_equiripple = .{
            .up = .{ .stopband_attenuation_db = -60.0 },
            .down = .{ .stopband_attenuation_db = -70.0 },
        } },
        .{ .polyphase_iir = .{} },
    };
    const Mixed = plug.dsp.MixedOversampler(f32, frame_count, 4);
    const mixed_design_iterations = 5;
    timer = try Timer.start();
    var mixed_checksum: f64 = 0.0;
    for (0..mixed_design_iterations) |_| {
        const mixed = try Mixed.init(&mixed_configs);
        mixed_checksum += try mixed.latencySamples();
    }
    std.mem.doNotOptimizeAway(mixed_checksum);
    try requireRate(
        "mixed oversampling stage design",
        try timer.read(),
        mixed_design_iterations,
        budget.mixed_oversampling_design_ns,
    );

    var mixed = try Mixed.init(&mixed_configs);
    var mixed_input: [frame_count]f32 = undefined;
    fillInput(&mixed_input, 0.75);
    var mixed_output: [frame_count]f32 = undefined;
    const mixed_processing_iterations = 250;
    timer = try Timer.start();
    mixed_checksum = 0.0;
    for (0..mixed_processing_iterations) |_| {
        const high_rate = try mixed.upsample(&mixed_input);
        for (high_rate) |*sample| sample.* *= 0.99;
        try mixed.downsample(&mixed_output);
        mixed_checksum += mixed_output[frame_count - 1];
    }
    std.mem.doNotOptimizeAway(mixed_checksum);
    try requireRate(
        "4x mixed oversampling",
        try timer.read(),
        mixed_processing_iterations * frame_count,
        budget.mixed_oversampling_ns_per_sample,
    );
}

fn benchAdvancedDynamics() !void {
    std.debug.print("\nadvanced dynamics\n", .{});
    const block_iterations = 250;
    const sample_count = block_iterations * frame_count;
    var source: [frame_count]f32 = undefined;
    fillInput(&source, 1.25);

    var limiter = try plug.dsp.LookaheadLimiter(f32, 512).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -1.0,
        .release_ms = 50.0,
        .lookahead_ms = 5.0,
    });
    var samples = source;
    var timer = try Timer.start();
    var checksum: f64 = 0.0;
    for (0..block_iterations) |_| {
        samples = source;
        limiter.process(&samples);
        checksum += samples[frame_count - 1];
    }
    std.mem.doNotOptimizeAway(checksum);
    try requireRate(
        "lookahead limiter",
        try timer.read(),
        sample_count,
        budget.lookahead_limiter_ns_per_sample,
    );

    var inter_sample = try plug.dsp.InterSampleLimiter(
        f32,
        frame_count,
        4,
    ).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -1.0,
        .release_ms = 50.0,
        .reconstruction_guard_db = 0.5,
    });
    timer = try Timer.start();
    checksum = 0.0;
    for (0..block_iterations) |_| {
        samples = source;
        try inter_sample.process(&samples);
        checksum += samples[frame_count - 1];
    }
    std.mem.doNotOptimizeAway(checksum);
    try requireRate(
        "4x inter-sample limiter",
        try timer.read(),
        sample_count,
        budget.inter_sample_limiter_ns_per_sample,
    );

    const compressor = plug.dsp.CompressorConfig{
        .sample_rate = 48_000.0,
        .threshold_db = -18.0,
        .ratio = 4.0,
        .attack_ms = 10.0,
        .release_ms = 100.0,
    };
    var multiband = try plug.dsp.MultibandCompressor(f32, 4).init(.{
        .sample_rate = 48_000.0,
        .crossover_hz = .{ 120.0, 1_200.0, 8_000.0 },
        .bands = .{ compressor, compressor, compressor, compressor },
    });
    timer = try Timer.start();
    checksum = 0.0;
    for (0..block_iterations) |_| {
        samples = source;
        multiband.process(&samples);
        checksum += samples[frame_count - 1];
    }
    std.mem.doNotOptimizeAway(checksum);
    try requireRate(
        "four-band compressor",
        try timer.read(),
        sample_count,
        budget.multiband_compressor_ns_per_sample,
    );
}

fn benchAdmDiffuse() !void {
    std.debug.print("\nADM diffuse processing\n", .{});
    inline for (.{ f32, f64 }) |Sample| {
        inline for (.{ 16, 64, 512 }) |block_frames| {
            try benchAdmDiffuseBlock(Sample, block_frames);
        }
    }
}

fn benchAdmDiffuseBlock(
    comptime Sample: type,
    comptime block_frames: usize,
) !void {
    const layout = [_]plug.dsp.AdmOutputSpeaker{
        admDiffuseSpeaker("M+030", 30, 0, -1, 1, 0),
        admDiffuseSpeaker("M-030", -30, 0, 1, 1, 0),
        admDiffuseSpeaker("M+000", 0, 0, 0, 1, 0),
        admDiffuseSpeaker("M+110", 110, 0, -1, -1, 0),
        admDiffuseSpeaker("M-110", -110, 0, 1, -1, 0),
        admDiffuseSpeaker("M+180", 180, 0, 0, -1, 0),
        admDiffuseSpeaker("U+030", 30, 30, -1, 1, 1),
        admDiffuseSpeaker("U-030", -30, 30, 1, 1, 1),
        admDiffuseSpeaker("U+110", 110, 30, -1, -1, 1),
        admDiffuseSpeaker("U-110", -110, 30, 1, -1, 1),
        admDiffuseSpeaker("U+000", 0, 30, 0, 1, 1),
        admDiffuseSpeaker("UH+180", 180, 45, 0, -1, 1),
    };
    const Processor =
        plug.dsp.AdmObjectDiffuseProcessor(Sample, layout.len);
    var processor = try Processor.init(&layout);
    var direct_storage: [layout.len][block_frames]Sample =
        @splat(@splat(@as(Sample, 0.125)));
    var diffuse_storage: [layout.len][block_frames]Sample =
        @splat(@splat(@as(Sample, 0.25)));
    var output_storage: [layout.len][block_frames]Sample = undefined;
    var direct_inputs: [layout.len][]const Sample = undefined;
    var diffuse_inputs: [layout.len][]const Sample = undefined;
    var outputs: [layout.len][]Sample = undefined;
    for (0..layout.len) |index| {
        direct_inputs[index] = &direct_storage[index];
        diffuse_inputs[index] = &diffuse_storage[index];
        outputs[index] = &output_storage[index];
    }

    const block_iterations = 32_768 / block_frames;
    var timer = try Timer.start();
    var checksum: f64 = 0;
    for (0..block_iterations) |_| {
        try processor.process(
            &direct_inputs,
            &diffuse_inputs,
            &outputs,
        );
        checksum += @floatCast(output_storage[0][block_frames - 1]);
    }
    std.mem.doNotOptimizeAway(checksum);
    try requireRate(
        std.fmt.comptimePrint(
            "12-channel ADM diffuse {s}, {d}-frame blocks",
            .{ @typeName(Sample), block_frames },
        ),
        try timer.read(),
        block_iterations * block_frames * layout.len,
        budget.adm_diffuse_ns_per_output_sample,
    );
}

fn admDiffuseSpeaker(
    label: []const u8,
    azimuth_degrees: f64,
    elevation_degrees: f64,
    x: f64,
    y: f64,
    z: f64,
) plug.dsp.AdmOutputSpeaker {
    return .{
        .label = label,
        .nominal_polar = .{
            .azimuth_degrees = azimuth_degrees,
            .elevation_degrees = elevation_degrees,
        },
        .allocentric = .{ .x = x, .y = y, .z = z },
    };
}

fn benchRealtimePublication() !void {
    std.debug.print("\nrealtime snapshot publication\n", .{});
    const State = struct {
        cutoff_hz: f64,
        resonance: f64,
        mode: u32,
    };
    var publisher = plug.dsp.RealtimeSnapshotPublisher(State).init(.{
        .cutoff_hz = 1_000.0,
        .resonance = 0.5,
        .mode = 0,
    });

    var timer = try Timer.start();
    var checksum: u64 = 0;
    for (0..iterations) |index| {
        checksum +%= try publisher.publish(.{
            .cutoff_hz = @floatFromInt(100 + index % 20_000),
            .resonance = @as(f64, @floatFromInt(index % 100)) / 100.0,
            .mode = @intCast(index % 4),
        });
    }
    std.mem.doNotOptimizeAway(checksum);
    try requireRate(
        "snapshot publication",
        try timer.read(),
        iterations,
        budget.snapshot_publication_ns,
    );

    timer = try Timer.start();
    var value_checksum: f64 = 0.0;
    for (0..iterations) |_| {
        const snapshot =
            publisher.tryRead() orelse return error.BenchmarkSnapshotReadFailed;
        value_checksum += snapshot.value.cutoff_hz;
    }
    std.mem.doNotOptimizeAway(value_checksum);
    try requireRate(
        "snapshot read",
        try timer.read(),
        iterations,
        budget.snapshot_read_ns,
    );

    var references =
        plug.dsp.RealtimeReferencePublisher(State, 8).init(.{
            .cutoff_hz = 1_000.0,
            .resonance = 0.5,
            .mode = 0,
        });
    timer = try Timer.start();
    checksum = 0;
    for (0..iterations) |index| {
        var writer = try references.beginUpdate();
        defer writer.cancel();
        const pending = writer.value() orelse
            return error.BenchmarkReferenceUpdateFailed;
        pending.cutoff_hz = @floatFromInt(100 + index % 20_000);
        pending.mode = @intCast(index % 4);
        checksum +%= try writer.commit();
    }
    std.mem.doNotOptimizeAway(checksum);
    try requireRate(
        "reference snapshot partial update",
        try timer.read(),
        iterations,
        budget.reference_snapshot_update_ns,
    );

    const Shared = struct {
        publisher: plug.dsp.RealtimeSnapshotPublisher(State),
        stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        read_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

        fn read(shared: *@This()) void {
            while (!shared.stop.load(.acquire)) {
                if (shared.publisher.tryRead() != null)
                    _ = shared.read_count.fetchAdd(1, .monotonic);
            }
        }
    };
    var shared = Shared{
        .publisher = plug.dsp.RealtimeSnapshotPublisher(State).init(.{
            .cutoff_hz = 1_000.0,
            .resonance = 0.5,
            .mode = 0,
        }),
    };
    const reader = try std.Thread.spawn(.{}, Shared.read, .{&shared});
    defer {
        shared.stop.store(true, .release);
        reader.join();
    }
    for (0..1_000_000) |_| {
        if (shared.read_count.load(.acquire) != 0) break;
        std.atomic.spinLoopHint();
    } else {
        return error.BenchmarkSnapshotReaderDidNotStart;
    }

    timer = try Timer.start();
    checksum = 0;
    for (0..iterations) |index| {
        checksum +%= try shared.publisher.publish(.{
            .cutoff_hz = @floatFromInt(100 + index % 20_000),
            .resonance = @as(f64, @floatFromInt(index % 100)) / 100.0,
            .mode = @intCast(index % 4),
        });
    }
    const contended_elapsed_ns = try timer.read();
    std.mem.doNotOptimizeAway(checksum);
    if (shared.read_count.load(.acquire) == 0)
        return error.BenchmarkSnapshotReaderStopped;
    try requireRate(
        "snapshot publication with concurrent reader",
        contended_elapsed_ns,
        iterations,
        budget.contended_snapshot_publication_ns,
    );
}

fn requireRate(
    name: []const u8,
    elapsed_ns: u64,
    operation_count: usize,
    maximum_ns_per_operation: f64,
) !void {
    const benchmark = Benchmark{
        .name = name,
        .iterations = operation_count,
        .elapsed_ns = elapsed_ns,
    };
    try benchmark.requireAtMost(maximum_ns_per_operation);
}

fn benchVorbisInverseMdct() !void {
    std.debug.print("\nVorbis MDCT\n", .{});
    inline for (.{ 64, 256, 2048 }) |block_size| {
        var plan = plug.dsp.VorbisInverseMdct(f32, block_size).init();
        var spectrum: [block_size / 2]f32 = undefined;
        for (&spectrum, 0..) |*coefficient, index| {
            coefficient.* = @floatCast(@sin(
                @as(f64, @floatFromInt(index + 1)) * 0.173,
            ));
        }
        var output: [block_size]f32 = undefined;
        const benchmark_iterations: usize =
            @max(@as(usize, 100), iterations * 64 / block_size);
        var timer = try Timer.start();
        var checksum: f32 = 0;
        for (0..benchmark_iterations) |_| {
            try plan.process(&spectrum, &output);
            checksum += output[benchmark_iterations % block_size];
        }
        const elapsed_ns = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        const ns_per_sample =
            @as(f64, @floatFromInt(elapsed_ns)) /
            @as(f64, @floatFromInt(benchmark_iterations * block_size));
        std.debug.print(
            "inverse {d}-sample block: {d:.2} ns/sample\n",
            .{ block_size, ns_per_sample },
        );
        if (ns_per_sample > budget.vorbis_mdct_ns_per_sample)
            return error.BenchmarkBudgetExceeded;
    }
    inline for (.{ 64, 256, 2048 }) |block_size| {
        var plan = plug.dsp.VorbisForwardMdct(f32, block_size).init();
        var input: [block_size]f32 = undefined;
        for (&input, 0..) |*sample, index| {
            sample.* = @floatCast(@sin(
                @as(f64, @floatFromInt(index + 1)) * 0.173,
            ));
        }
        var output: [block_size / 2]f32 = undefined;
        const benchmark_iterations: usize =
            @max(@as(usize, 100), iterations * 64 / block_size);
        var timer = try Timer.start();
        var checksum: f32 = 0;
        for (0..benchmark_iterations) |_| {
            try plan.process(&input, &output);
            checksum += output[
                benchmark_iterations % (block_size / 2)
            ];
        }
        const elapsed_ns = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        const ns_per_sample =
            @as(f64, @floatFromInt(elapsed_ns)) /
            @as(f64, @floatFromInt(benchmark_iterations * block_size));
        std.debug.print(
            "forward {d}-sample block: {d:.2} ns/sample\n",
            .{ block_size, ns_per_sample },
        );
        if (ns_per_sample > budget.vorbis_mdct_ns_per_sample)
            return error.BenchmarkBudgetExceeded;
    }
}

fn benchDispatchedKernels() !void {
    std.debug.print("\ndispatched buffer kernels\n", .{});
    inline for (.{ 8, 32, 128, 512 }) |sample_count| {
        try benchDispatchedKernelSize(sample_count);
    }
}

fn benchDispatchedKernelSize(comptime sample_count: usize) !void {
    var left: [sample_count]f32 = undefined;
    var right: [sample_count]f32 = undefined;
    for (&left, &right, 0..) |*left_sample, *right_sample, index| {
        const phase =
            std.math.tau * @as(f64, @floatFromInt(index)) /
            @as(f64, @floatFromInt(sample_count));
        left_sample.* = @floatCast(@sin(phase) * 0.5);
        right_sample.* = @floatCast(@cos(phase) * 0.5);
    }
    const detected = plug.dsp.KernelDispatcher.initDetected();
    const dispatchers = [_]plug.dsp.KernelDispatcher{
        plug.dsp.KernelDispatcher.init(.{}),
        detected,
    };
    for (dispatchers, 0..) |dispatcher, dispatcher_index| {
        if (dispatcher_index == 1 and detected.backend == .scalar) continue;
        const benchmark_iterations = if (sample_count <= 32)
            iterations * 4
        else
            iterations;
        var working = left;
        var timer = try Timer.start();
        var checksum: f32 = 0.0;
        for (0..benchmark_iterations) |_| {
            try dispatcher.processGain(f32, &working, 0.999_9);
            checksum += working[0];
        }
        const gain_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "gain",
            sample_count,
            benchmark_iterations,
            gain_elapsed,
        );

        working = left;
        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_| {
            try dispatcher.processAffine(
                f32,
                &working,
                0.999_9,
                0.000_01,
            );
            checksum += working[0];
        }
        const affine_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "affine",
            sample_count,
            benchmark_iterations,
            affine_elapsed,
        );

        working = left;
        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_| {
            try dispatcher.applyFastMath(f32, .sine, &working);
            checksum += working[0];
        }
        const fast_math_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "fast sine",
            sample_count,
            benchmark_iterations,
            fast_math_elapsed,
        );

        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_| {
            try dispatcher.copyBuffer(f32, &working, &left);
            checksum += working[0];
        }
        const copy_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "copy",
            sample_count,
            benchmark_iterations,
            copy_elapsed,
        );

        working = left;
        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_| {
            try dispatcher.addBuffer(f32, &working, &right);
            checksum += working[0];
        }
        const add_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "add",
            sample_count,
            benchmark_iterations,
            add_elapsed,
        );

        working = left;
        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_| {
            try dispatcher.multiplyBuffer(f32, &working, &right);
            checksum += working[0];
        }
        const multiply_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "multiply",
            sample_count,
            benchmark_iterations,
            multiply_elapsed,
        );

        var complex_real = left;
        var complex_imaginary = right;
        const complex_multiplier_real =
            [_]f32{0.999_9} ** sample_count;
        const complex_multiplier_imaginary =
            [_]f32{0.000_1} ** sample_count;
        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_| {
            try dispatcher.multiplyComplexBuffer(
                f32,
                &complex_real,
                &complex_imaginary,
                &complex_multiplier_real,
                &complex_multiplier_imaginary,
            );
            checksum += complex_real[0] + complex_imaginary[0];
        }
        const complex_multiply_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "complex multiply",
            sample_count,
            benchmark_iterations,
            complex_multiply_elapsed,
        );

        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_|
            checksum += try dispatcher.sum(f32, &left);
        const sum_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "sum",
            sample_count,
            benchmark_iterations,
            sum_elapsed,
        );

        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_|
            checksum += try dispatcher.innerProduct(
                f32,
                &left,
                &right,
            );
        const inner_product_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "inner product",
            sample_count,
            benchmark_iterations,
            inner_product_elapsed,
        );

        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_|
            checksum += try dispatcher.peakAbsolute(f32, &left);
        const peak_absolute_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "absolute peak",
            sample_count,
            benchmark_iterations,
            peak_absolute_elapsed,
        );

        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_|
            checksum += try dispatcher.minimum(f32, &left);
        const minimum_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "minimum",
            sample_count,
            benchmark_iterations,
            minimum_elapsed,
        );

        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_|
            checksum += try dispatcher.maximum(f32, &left);
        const maximum_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "maximum",
            sample_count,
            benchmark_iterations,
            maximum_elapsed,
        );

        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_|
            checksum += try dispatcher.sumSquares(f32, &left);
        const sum_squares_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "sum squares",
            sample_count,
            benchmark_iterations,
            sum_squares_elapsed,
        );

        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_|
            checksum += try dispatcher.rootMeanSquare(f32, &left);
        const rms_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "RMS",
            sample_count,
            benchmark_iterations,
            rms_elapsed,
        );

        var mixed: [sample_count]f32 = undefined;
        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_| {
            try dispatcher.mixBuffers(
                f32,
                &mixed,
                &left,
                &right,
                0.375,
                0.625,
            );
            checksum += mixed[0];
        }
        const mix_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "weighted mix",
            sample_count,
            benchmark_iterations,
            mix_elapsed,
        );

        var interleaved: [sample_count * 2]f32 = undefined;
        var restored_left: [sample_count]f32 = undefined;
        var restored_right: [sample_count]f32 = undefined;
        timer = try Timer.start();
        checksum = 0.0;
        for (0..benchmark_iterations) |_| {
            try dispatcher.interleaveStereo(
                f32,
                &interleaved,
                &left,
                &right,
            );
            try dispatcher.deinterleaveStereo(
                f32,
                &restored_left,
                &restored_right,
                &interleaved,
            );
            checksum += restored_left[0] + restored_right[0];
        }
        const layout_elapsed = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        try reportDispatchedKernel(
            dispatcher,
            "stereo layout round trip",
            sample_count * 2,
            benchmark_iterations,
            layout_elapsed,
        );
    }
}

fn reportDispatchedKernel(
    dispatcher: plug.dsp.KernelDispatcher,
    operation: []const u8,
    sample_count: usize,
    benchmark_iterations: usize,
    elapsed_ns: u64,
) !void {
    const total_samples = benchmark_iterations * sample_count;
    const ns_per_sample =
        @as(f64, @floatFromInt(elapsed_ns)) /
        @as(f64, @floatFromInt(total_samples));
    std.debug.print(
        "{s} {s}, {d} samples: {d:.2} ns/sample\n",
        .{ @tagName(dispatcher.backend), operation, sample_count, ns_per_sample },
    );
    if (ns_per_sample > budget.dispatched_kernel_ns_per_sample)
        return error.BenchmarkBudgetExceeded;
}

fn benchDenormalSilenceTails() !void {
    if (!plug.dsp.denormals.supported) return;
    const benchmark_iterations = iterations * 10;
    const minimum_normal = std.math.floatMin(f32);
    const decay: f32 = 0.5;
    const input: [16]f32 = @splat(std.math.floatMin(f32));
    const impulse_tail: [16]f32 = @splat(0.5);

    var recurrent_timer = try Timer.start();
    const unscoped_recurrent = zig_vst3_bench_recurrent_tail(minimum_normal, decay, 32, benchmark_iterations);
    const recurrent_unscoped_elapsed = try recurrent_timer.read();
    std.mem.doNotOptimizeAway(unscoped_recurrent);
    (Benchmark{
        .name = "host-policy recurrent silence tail",
        .iterations = benchmark_iterations * 32,
        .elapsed_ns = recurrent_unscoped_elapsed,
    }).print();

    var convolution_timer = try Timer.start();
    const unscoped_convolution = zig_vst3_bench_convolution_tail(&input, &impulse_tail, input.len, benchmark_iterations);
    const convolution_unscoped_elapsed = try convolution_timer.read();
    std.mem.doNotOptimizeAway(unscoped_convolution);
    (Benchmark{
        .name = "host-policy convolution silence tail",
        .iterations = benchmark_iterations,
        .elapsed_ns = convolution_unscoped_elapsed,
    }).print();

    var scope = plug.dsp.DenormalScope.enter();
    defer scope.leave();

    recurrent_timer = try Timer.start();
    const recurrent_checksum = zig_vst3_bench_recurrent_tail(minimum_normal, decay, 32, benchmark_iterations);
    const recurrent_elapsed = try recurrent_timer.read();
    std.mem.doNotOptimizeAway(recurrent_checksum);
    try (Benchmark{
        .name = "flush-to-zero recurrent silence tail",
        .iterations = benchmark_iterations * 32,
        .elapsed_ns = recurrent_elapsed,
    }).requireAtMost(budget.recurrent_tail_ns);

    convolution_timer = try Timer.start();
    const convolution_checksum = zig_vst3_bench_convolution_tail(&input, &impulse_tail, input.len, benchmark_iterations);
    const convolution_elapsed = try convolution_timer.read();
    std.mem.doNotOptimizeAway(convolution_checksum);
    try (Benchmark{
        .name = "flush-to-zero convolution silence tail",
        .iterations = benchmark_iterations,
        .elapsed_ns = convolution_elapsed,
    }).requireAtMost(budget.convolution_tail_ns);
}

fn benchDenseKernels() !void {
    const weights = [16]f32{
        0.25,   -0.5,  0.75,   1.0,
        -1.5,   0.125, 0.5,    -0.25,
        2.0,    -0.75, 0.0625, 0.5,
        -0.125, 0.25,  -0.5,   1.25,
    };
    const bias = [4]f32{ 0.1, -0.2, 0.3, -0.4 };
    const input = [4]f32{ 1, -1, 0.5, -0.25 };
    const native = c_kernel.DenseKernel.initNative();
    const backends = [_]c_kernel.Backend{ .zig, .portable_c, native.backend };
    const benchmark_iterations = iterations * 20;
    for (backends, 0..) |backend, index| {
        if (index == 2 and (backend == .zig or backend == .portable_c)) continue;
        const kernel = try c_kernel.DenseKernel.init(backend);
        var timer = try Timer.start();
        var checksum: f32 = 0;
        for (0..benchmark_iterations) |_| {
            checksum += kernel.run(&weights, &bias, &input)[0];
        }
        const elapsed_ns = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        const result = Benchmark{
            .name = kernel.name(),
            .iterations = benchmark_iterations,
            .elapsed_ns = elapsed_ns,
        };
        try result.requireAtMost(budget.dense_kernel_ns);
    }
}

fn benchResourceState() !Benchmark {
    const Reference = plug.resource.Reference(1024, 96);
    const State = plug.resource.ReferenceState(1024, 96);
    const reference = try Reference.init(
        "/models/production/amplifier-model.json",
        plug.resource.Identity.fromBytes("bounded model fixture"),
        1,
        "Linear, 48000 Hz, gain 1.000",
    );
    const state: State = .{ .linked = reference };
    var bytes: [State.maximum_encoded_size]u8 = undefined;
    var timer = try Timer.start();
    var checksum: u64 = 0;
    for (0..iterations) |_| {
        var writer = std.Io.Writer.fixed(&bytes);
        try state.write(&writer);
        var reader = std.Io.Reader.fixed(writer.buffered());
        const restored = try State.read(&reader);
        checksum +%= restored.linked.identity.byte_length;
    }
    std.mem.doNotOptimizeAway(checksum);
    return .{ .name = "resource reference state save/load", .iterations = iterations, .elapsed_ns = try timer.read() };
}

fn benchResourceIdentity() !void {
    var bytes: [4096]u8 = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @truncate(index *% 131);
    var timer = try Timer.start();
    var checksum: u64 = 0;
    for (0..iterations) |_| {
        const identity = plug.resource.Identity.fromBytes(&bytes);
        checksum +%= identity.sha256[0];
    }
    const elapsed_ns = try timer.read();
    std.mem.doNotOptimizeAway(checksum);
    const total_bytes = iterations * bytes.len;
    const mib_per_second = @as(f64, @floatFromInt(total_bytes)) /
        (@as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s) /
        (1024.0 * 1024.0);
    std.debug.print("resource SHA-256 identity: {d:.1} MiB/s ({d} bytes)\n", .{ mib_per_second, total_bytes });
    if (mib_per_second < budget.resource_identity_mib_per_second) return error.BenchmarkBudgetExceeded;
}

fn benchStreamingResampler() !void {
    const Resampler = plug.dsp.StreamingResampler(f32);
    const native_backend = plug.dsp.KernelDispatcher.initDetected().backend;
    var input: [frame_count]f32 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* = @floatCast(@sin(
            std.math.tau * 997.0 *
                @as(f64, @floatFromInt(index)) / 44_100.0,
        ));
    }
    var output: [600]f32 = undefined;
    for ([_]plug.dsp.KernelBackend{ .scalar, native_backend }) |backend| {
        var resampler = try Resampler.initBackend(.{
            .input_rate = 44_100,
            .output_rate = 48_000,
        }, backend);
        var timer = try Timer.start();
        var checksum: f64 = 0.0;
        const benchmark_iterations = iterations / 10;
        for (0..benchmark_iterations) |_| {
            resampler.reset();
            const result = try resampler.process(&input, &output);
            checksum += output[result.produced - 1];
        }
        const elapsed_ns = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        const sample_count = benchmark_iterations * input.len;
        const ns_per_sample = @as(f64, @floatFromInt(elapsed_ns)) /
            @as(f64, @floatFromInt(sample_count));
        std.debug.print(
            "streaming resampler ({s}): {d:.1} ns/input sample\n",
            .{ @tagName(backend), ns_per_sample },
        );
        if (ns_per_sample > budget.resampler_ns_per_sample)
            return error.BenchmarkBudgetExceeded;
    }
}

fn benchFixedRatePipeline() !void {
    const Pipeline = plug.dsp.FixedRatePipeline(f32);
    const rates = [_]f64{ 44_100, 48_000, 88_200, 96_000 };
    var input: [frame_count]f32 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* = @floatCast(@sin(std.math.tau * 997.0 * @as(f64, @floatFromInt(index)) / 48_000.0));
    }
    var model: [600]f32 = undefined;
    var output: [frame_count]f32 = undefined;
    for (rates) |host_rate| {
        var pipeline = try Pipeline.init(.{ .host_rate = host_rate, .model_rate = 48_000 });
        var timer = try Timer.start();
        var checksum: f64 = 0.0;
        const benchmark_iterations = iterations / 10;
        for (0..benchmark_iterations) |_| {
            const model_frames = try pipeline.convertInput(&input, &model);
            for (model[0..model_frames]) |*sample| sample.* *= 0.5;
            try pipeline.convertOutput(model[0..model_frames], &output);
            checksum += output[output.len - 1];
        }
        const elapsed_ns = try timer.read();
        std.mem.doNotOptimizeAway(checksum);
        const sample_count = benchmark_iterations * frame_count;
        const ns_per_sample = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(sample_count));
        std.debug.print("fixed-rate 48 kHz model at {d:.1} Hz: {d:.1} ns/sample\n", .{ host_rate, ns_per_sample });
        if (ns_per_sample > budget.fixed_rate_ns_per_sample) return error.BenchmarkBudgetExceeded;
    }
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
    if (mebibytes_per_second < budget.import_mib_per_second) return error.BenchmarkBudgetExceeded;
}

fn benchSamplePlayerPipeline() !void {
    const maximum_frames = 262_144;
    const voice_count = 8;
    const path = ".zig-cache/sample-player-benchmark.wav";
    const io = std.Io.Threaded.global_single_threaded.io();
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};
    var header: [44]u8 = undefined;
    var header_writer = std.Io.Writer.fixed(&header);
    try header_writer.writeAll("RIFF");
    try header_writer.writeInt(u32, 36 + maximum_frames * 2, .little);
    try header_writer.writeAll("WAVEfmt ");
    try header_writer.writeInt(u32, 16, .little);
    try header_writer.writeInt(u16, 1, .little);
    try header_writer.writeInt(u16, 1, .little);
    try header_writer.writeInt(u32, 48_000, .little);
    try header_writer.writeInt(u32, 96_000, .little);
    try header_writer.writeInt(u16, 2, .little);
    try header_writer.writeInt(u16, 16, .little);
    try header_writer.writeAll("data");
    try header_writer.writeInt(u32, maximum_frames * 2, .little);
    {
        var file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, header_writer.buffered());
        var samples: [1024]i16 = undefined;
        for (&samples, 0..) |*sample, index| {
            sample.* = @intFromFloat(std.math.sin(std.math.tau * @as(f64, @floatFromInt(index)) / 64.0) * 16_000.0);
        }
        var written: usize = 0;
        while (written < maximum_frames) : (written += samples.len) {
            try file.writeStreamingAll(io, std.mem.sliceAsBytes(&samples));
        }
    }

    const Importer = plug.gui_audio_file_importer.DecodedImporter(maximum_frames);
    const allocator = std.heap.page_allocator;
    const importer = try allocator.create(Importer);
    defer allocator.destroy(importer);
    importer.* = Importer.init();
    defer importer.deinit();
    var decode_timer = try Timer.start();
    if (!importer.begin(.picker, &.{path})) return error.BenchmarkSampleImportStartFailed;
    while (true) {
        const snapshot = importer.snapshot();
        if (snapshot.import.status == .ready) break;
        if (snapshot.import.status != .validating and snapshot.import.status != .importing) {
            return error.BenchmarkSampleImportFailed;
        }
        std.Thread.yield() catch {};
    }
    const decode_ns = try decode_timer.read();
    var preview: [256]plug.gui_audio_file_importer.PreviewPoint = undefined;
    var preview_timer = try Timer.start();
    var preview_checksum: usize = 0;
    for (0..iterations) |_| preview_checksum +%= importer.copyPreview(&preview);
    const preview_ns = try preview_timer.read();
    std.mem.doNotOptimizeAway(preview_checksum);
    const preview_count = importer.copyPreview(&preview);
    if (preview_count == 0) return error.BenchmarkSamplePreviewMissing;

    const Player = plug.gui_sample_player.Player(maximum_frames, voice_count);
    const player = try allocator.create(Player);
    defer allocator.destroy(player);
    player.* = .{};
    player.prepare(48_000.0);
    var chunk: [1024]f32 = undefined;
    for (&chunk, 0..) |*sample, index| {
        sample.* = @floatCast(std.math.sin(std.math.tau * @as(f64, @floatFromInt(index)) / 64.0) * 0.5);
    }
    var publication_timer = try Timer.start();
    try player.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = maximum_frames });
    var offset: usize = 0;
    while (offset < maximum_frames) : (offset += chunk.len) try player.store.write(1, offset, &chunk);
    try player.store.commit(1);
    const publication_ns = try publication_timer.read();
    var adoption_timer = try Timer.start();
    if (!player.adoptPending()) return error.BenchmarkSampleAdoptionFailed;
    const adoption_ns = try adoption_timer.read();

    const playback = plug.gui_sample_player.Playback{
        .loop_enabled = true,
        .envelope = .{ .attack_seconds = 0.0, .decay_seconds = 0.0, .sustain = 1.0 },
    };
    player.noteOn(60, 1.0, playback);
    const processed_frames = iterations * frame_count;
    var processing_timer = try Timer.start();
    var checksum: f32 = 0.0;
    for (0..processed_frames) |_| {
        const output = player.processFrame(playback);
        checksum += output[0] + output[1];
    }
    const processing_ns = try processing_timer.read();
    std.mem.doNotOptimizeAway(checksum);

    var playhead = plug.gui_graph.SnapshotSeries(2).init();
    playhead.editorOpened();
    defer playhead.editorClosed();
    var points: [2]plug.gui_graph.Point = undefined;
    var playhead_timer = try Timer.start();
    var read_count: usize = 0;
    for (0..iterations) |index| {
        const position = @as(f64, @floatFromInt(index % 1000)) / 1000.0;
        if (!playhead.publish(&.{ .{ .x = position, .y = -1.0 }, .{ .x = position, .y = 1.0 } })) {
            return error.BenchmarkPlayheadPublishFailed;
        }
        read_count += playhead.read(&points) orelse return error.BenchmarkPlayheadReadFailed;
    }
    const playhead_ns = try playhead_timer.read();
    std.mem.doNotOptimizeAway(read_count);

    const decode_ms = @as(f64, @floatFromInt(decode_ns)) / std.time.ns_per_ms;
    const publication_ms = @as(f64, @floatFromInt(publication_ns)) / std.time.ns_per_ms;
    const ns_per_frame = @as(f64, @floatFromInt(processing_ns)) / @as(f64, @floatFromInt(processed_frames));
    const playhead_ns_per_update = @as(f64, @floatFromInt(playhead_ns)) / iterations;
    std.debug.print("sample decode and waveform construction: {d:.2} ms ({d} frames, {d} preview points)\n", .{
        decode_ms, maximum_frames, preview_count,
    });
    std.debug.print("sample preview snapshot: {d:.1} ns/read; bounded publication: {d:.2} ms; adoption: {d} ns\n", .{
        @as(f64, @floatFromInt(preview_ns)) / iterations, publication_ms, adoption_ns,
    });
    std.debug.print("sample playback: {d:.1} ns/frame ({d} voices available); playhead publish/read: {d:.1} ns/update\n", .{
        ns_per_frame, voice_count, playhead_ns_per_update,
    });
    std.debug.print("sample fixed storage: {d:.2} MiB importer + {d:.2} MiB player\n", .{
        @as(f64, @floatFromInt(@sizeOf(Importer))) / (1024.0 * 1024.0),
        @as(f64, @floatFromInt(@sizeOf(Player))) / (1024.0 * 1024.0),
    });
    if (decode_ms > budget.sample_decode_ms or
        @as(f64, @floatFromInt(preview_ns)) / iterations > budget.sample_preview_ns or
        publication_ms > budget.sample_publication_ms or
        @as(f64, @floatFromInt(adoption_ns)) > budget.sample_adoption_ns or
        ns_per_frame > budget.sample_playback_ns_per_frame or
        playhead_ns_per_update > budget.playhead_update_ns)
    {
        return error.BenchmarkBudgetExceeded;
    }
}

fn benchIrConvolution() !void {
    const maximum_frames = 131_072;
    const partition_size = 512;
    const Convolver = plug.gui_ir_convolution.PartitionedConvolver(maximum_frames, partition_size);
    const Importer = plug.gui_audio_file_importer.DecodedImporter(maximum_frames);
    const Editor = plug.gui_ir_editor.Editor(maximum_frames);
    const allocator = std.heap.page_allocator;
    const convolver = try allocator.create(Convolver);
    defer allocator.destroy(convolver);
    convolver.initInPlace(48_000);

    const impulse = try allocator.alloc(f32, maximum_frames);
    defer allocator.free(impulse);
    for (impulse, 0..) |*sample, index| {
        const decay = @exp(-8.0 * @as(f32, @floatFromInt(index)) / @as(f32, maximum_frames));
        sample.* = if (index == 0) 1.0 else decay * 0.05;
    }

    var preparation_timer = try Timer.start();
    try convolver.begin(.{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = maximum_frames,
    });
    var offset: usize = 0;
    while (offset < impulse.len) {
        const end = @min(offset + 1024, impulse.len);
        try convolver.write(1, offset, impulse[offset..end]);
        offset = end;
    }
    try convolver.commit(1);
    const preparation_ns = try preparation_timer.read();

    var adoption_timer = try Timer.start();
    if (!convolver.adoptPending()) return error.BenchmarkConvolutionAdoptionFailed;
    const adoption_ns = try adoption_timer.read();

    var checksum: f32 = 0.0;
    var processing_timer = try Timer.start();
    for (0..partition_size) |index| {
        const input: f32 = if (index == 0) 1.0 else 0.0;
        const output = convolver.processFrame(input, input);
        checksum += output[0] + output[1];
    }
    const processing_ns = try processing_timer.read();
    std.mem.doNotOptimizeAway(checksum);

    const mib = @as(f64, @floatFromInt(@sizeOf(Convolver))) / (1024.0 * 1024.0);
    const importer_mib = @as(f64, @floatFromInt(@sizeOf(Importer))) / (1024.0 * 1024.0);
    const editor_mib = @as(f64, @floatFromInt(@sizeOf(Editor))) / (1024.0 * 1024.0);
    const preparation_ms = @as(f64, @floatFromInt(preparation_ns)) / std.time.ns_per_ms;
    const ns_per_sample = @as(f64, @floatFromInt(processing_ns)) / partition_size;
    const realtime_cpu = ns_per_sample * 48_000.0 * 100.0 / std.time.ns_per_s;
    std.debug.print("IR convolver fixed storage: {d:.2} MiB ({d} frames, {d}-sample partitions)\n", .{
        mib, maximum_frames, partition_size,
    });
    std.debug.print("IR controller fixed storage: {d:.2} MiB importer + {d:.2} MiB editor\n", .{
        importer_mib, editor_mib,
    });
    std.debug.print("IR preparation and publication: {d:.2} ms; pending adoption: {d} ns\n", .{
        preparation_ms, adoption_ns,
    });
    std.debug.print("IR convolution: {d:.1} ns/sample, {d:.1}% of one 48 kHz core\n", .{
        ns_per_sample, realtime_cpu,
    });
    if (preparation_ms > budget.ir_preparation_ms or
        @as(f64, @floatFromInt(adoption_ns)) > budget.ir_adoption_ns or
        ns_per_sample > budget.ir_processing_ns_per_sample)
    {
        return error.BenchmarkBudgetExceeded;
    }
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
