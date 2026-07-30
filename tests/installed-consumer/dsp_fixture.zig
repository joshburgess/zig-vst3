const plugin = @import("zig-vst3-plugin");
const std = @import("std");

const GainModel = struct {
    gain: f32,

    pub fn reset(_: *GainModel) void {}

    pub fn processBlock(self: *GainModel, input: []const f32, output: []f32) void {
        for (input, output) |sample, *destination| destination.* = sample * self.gain;
    }
};

const Runtime = struct { state: f32 };

const InstalledSharedState = struct {
    gain: f32,

    pub fn valid(self: *const InstalledSharedState) bool {
        return std.math.isFinite(self.gain);
    }
};

const InstalledSharedProcessor = struct {
    previous: f32 = 0.0,

    pub fn processSample(
        self: *InstalledSharedProcessor,
        input: f32,
        state: *const InstalledSharedState,
    ) f32 {
        const output = (input + self.previous) * state.gain;
        self.previous = input;
        return output;
    }

    pub fn valid(self: *const InstalledSharedProcessor) bool {
        return std.math.isFinite(self.previous);
    }
};

const RuntimeExchange = plugin.resource.exchange.Exchange(struct {
    pub const Resource = Runtime;
    pub const slot_capacity = 2;
    pub const mutable_active = true;

    pub fn destroy(runtime: *Runtime) void {
        std.testing.allocator.destroy(runtime);
    }
});

const InstalledRecovery = plugin.resource.ResourceRecovery(struct {
    pub const Resource = u8;
    pub const Failure = enum { unavailable };
    pub const path_capacity = 64;
    pub const metadata_capacity = 32;
    pub const slot_capacity = 2;
    pub const maximum_work_units = 1;
    pub const maximum_result_units = 1;

    pub fn prepare(_: plugin.resource.BoundedPath(path_capacity), _: *plugin.resource.job.WorkerContext) plugin.resource.job.Outcome(
        plugin.resource.PreparedResource(Resource, metadata_capacity),
        Failure,
    ) {
        return .{ .failure = .unavailable };
    }

    pub fn destroy(resource: *Resource) void {
        std.testing.allocator.destroy(resource);
    }

    pub fn failureStatus(_: Failure) plugin.resource.RecoveryStatus {
        return .failed;
    }
});

test "installed package exposes dispatched reductions" {
    try std.testing.expect(@hasDecl(plugin, "lv2"));
    const dispatcher = plugin.dsp.KernelDispatcher.initDetected();
    const left = [_]f32{ 1.0, -2.0, 3.0, -4.0, 5.0 };
    const right = [_]f32{ 0.5, 0.25, -0.5, -0.25, 1.0 };
    try std.testing.expectEqual(
        @as(f32, 3.0),
        try dispatcher.sum(f32, &left),
    );
    try std.testing.expectEqual(
        @as(f32, 4.5),
        try dispatcher.innerProduct(f32, &left, &right),
    );
    try std.testing.expectEqual(
        @as(f32, 5.0),
        try dispatcher.peakAbsolute(f32, &left),
    );
    try std.testing.expectEqual(
        @as(f32, -4.0),
        try dispatcher.minimum(f32, &left),
    );
    try std.testing.expectEqual(
        @as(f32, 5.0),
        try dispatcher.maximum(f32, &left),
    );
    try std.testing.expectEqual(
        @as(f32, 55.0),
        try dispatcher.sumSquares(f32, &left),
    );
    try std.testing.expectApproxEqAbs(
        @sqrt(@as(f32, 11.0)),
        try dispatcher.rootMeanSquare(f32, &left),
        1.0e-6,
    );
}

test "installed package exposes complex SIMD and dispatch" {
    const Complex = plugin.dsp.NativeComplexSimdRegister(f32);
    var register_real: [Complex.lanes]f32 align(Complex.alignment) =
        @splat(1.0);
    var register_imaginary: [Complex.lanes]f32 align(Complex.alignment) =
        @splat(2.0);
    const register = try Complex.loadAligned(
        &register_real,
        &register_imaginary,
    );
    try register.storeAligned(
        &register_real,
        &register_imaginary,
    );
    const ComplexValue = std.math.Complex(f32);
    var interleaved: [Complex.lanes]ComplexValue = undefined;
    try register.storeInterleaved(&interleaved);
    const interleaved_register = try Complex.loadInterleaved(&interleaved);
    try std.testing.expectEqual(
        @as(f32, 1.0),
        try interleaved_register.real.getLane(0),
    );
    try std.testing.expectEqual(
        @as(f32, 2.0),
        try interleaved_register.imaginary.getLane(0),
    );

    const dispatcher = plugin.dsp.KernelDispatcher.initDetected();
    var real = [_]f32{ 1, 2, 3, 4, 5 };
    var imaginary = [_]f32{ 5, 4, 3, 2, 1 };
    try dispatcher.multiplyComplexBuffer(
        f32,
        &real,
        &imaginary,
        &.{ 0, 1, 0, 1, 0 },
        &.{ 1, 0, 1, 0, 1 },
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ -5, 2, -3, 4, -1 },
        &real,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1, 4, 3, 2, 5 },
        &imaginary,
    );
}

test "installed package exposes buffer processor dispatch" {
    const Context = struct {
        calls: usize = 0,

        fn process(
            self: *@This(),
            destination: []f32,
            source: []const f32,
        ) void {
            self.calls += 1;
            for (destination, source) |*output, input|
                output.* = input * 0.5;
        }
    };
    const Processor =
        plugin.dsp.BufferProcessorDispatcher(f32, Context);
    const dispatcher = Processor.initDetected(.{
        .scalar = Context.process,
    });
    var context = Context{};
    var output: [5]f32 = undefined;
    try dispatcher.process(
        &context,
        &output,
        &.{ 2, 4, 6, 8, 10 },
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1, 2, 3, 4, 5 },
        &output,
    );
    try std.testing.expectEqual(@as(usize, 1), context.calls);
}

test "installed package exposes deterministic dithered PCM conversion" {
    var dither = try plugin.dsp.PcmDither.init(.{
        .channel_count = 1,
        .bits_per_sample = 16,
        .mode = .noise_shaped,
        .seed = 123,
    });
    var bytes: [50]u8 = undefined;
    const wav = try plugin.dsp.writeInterleavedWavDithered(
        f64,
        &bytes,
        &.{ -1.0, 0.0, 1.0 },
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
        &dither,
    );
    try std.testing.expectEqualStrings("RIFF", wav[0..4]);
    try std.testing.expectEqual(@as(usize, 50), wav.len);
}

test "installed package exposes file writer operations" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "operations.wav",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const operations = plugin.dsp.FileWriterOperations{};
    var writer = try plugin.dsp.WavFileWriter.initWithOperations(
        std.testing.io,
        file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
        operations,
    );
    try writer.append(f32, &.{ 0.25, -0.25 });
    try writer.finalize();
    try std.testing.expectEqual(
        @as(u64, 48),
        try file.length(std.testing.io),
    );
    try plugin.dsp.FileWriterCheckpoint.exact(48).restore(
        operations,
        std.testing.io,
        file,
    );

    var flac_file = try temporary.dir.createFile(
        std.testing.io,
        "operations.flac",
        .{ .read = true },
    );
    defer flac_file.close(std.testing.io);
    var pending: [16]i32 = undefined;
    var frame_storage: [64]u8 = undefined;
    var flac_writer = try plugin.dsp.FlacFileWriter.initWithOperations(
        std.testing.io,
        flac_file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
            .block_size = 16,
        },
        &pending,
        &frame_storage,
        operations,
    );
    try flac_writer.append(&.{ 1, -2, 3, -4 });
    try flac_writer.finalize();
    try std.testing.expect(flac_writer.byte_count > 42);
}

test "installed package exposes file-backed Ogg streaming" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "stream.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    var page_storage: [plugin.dsp.ogg.maximum_page_bytes]u8 = undefined;
    var writer = try plugin.dsp.OggFileWriter.init(
        std.testing.io,
        file,
        &page_storage,
        0x10203040,
    );
    try writer.appendPacket("installed", 8, true, true);
    try writer.finalize();

    var reader = try plugin.dsp.OggFilePacketReader.init(
        std.testing.io,
        file,
    );
    var reader_page_storage: [plugin.dsp.ogg.maximum_page_bytes]u8 = undefined;
    var packet_storage: [9]u8 = undefined;
    const packet = (try reader.next(
        &reader_page_storage,
        &packet_storage,
    )).?;
    try std.testing.expect(packet.beginning);
    try std.testing.expect(packet.end);
    try std.testing.expectEqualStrings("installed", packet.bytes);
}

test "installed package exposes selectable dummy oversampling" {
    const Oversampler =
        plugin.dsp.SelectableOversampler(f32, 4, 2);
    var oversampler = try Oversampler.init(.dummy);
    const input = [_]f32{ 0.25, -0.5, 0.75, -1.0 };
    const processing = try oversampler.upsample(&input);
    try std.testing.expectEqual(@as(usize, input.len), processing.len);
    for (processing) |*sample| sample.* *= 0.5;
    var output: [4]f32 = undefined;
    try oversampler.downsample(&output);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.125, -0.25, 0.375, -0.5 },
        &output,
    );
    try oversampler.setSelection(.filtered);
    try std.testing.expectEqual(
        @as(usize, 2),
        oversampler.oversamplingFactor(),
    );
}

test "installed package exposes runtime polyphase IIR stage sequences" {
    const RuntimeOversamplerType =
        plugin.dsp.RuntimePolyphaseIirOversampler(f32, 8, 4);
    var runtime = try RuntimeOversamplerType.init(&.{ .{}, .{} });
    try std.testing.expectEqual(
        @as(usize, 4),
        try runtime.oversamplingFactor(),
    );
    var input: [8]f32 = @splat(0.25);
    const high_rate = try runtime.upsample(&input);
    try std.testing.expectEqual(@as(usize, 32), high_rate.len);
    var output: [8]f32 = undefined;
    try runtime.downsample(&output);

    const Multichannel =
        plugin.dsp.RuntimeMultichannelPolyphaseIirOversampler(
            f32,
            8,
            4,
            2,
        );
    var multichannel = try Multichannel.init(2, &.{});
    try std.testing.expectEqual(
        @as(usize, 1),
        try multichannel.oversamplingFactor(),
    );
    var left: [8]f32 = @splat(0.25);
    var right: [8]f32 = @splat(-0.25);
    _ = try multichannel.upsample(&.{ left[0..], right[0..] });
    var output_left: [8]f32 = undefined;
    var output_right: [8]f32 = undefined;
    try multichannel.downsample(&.{
        output_left[0..],
        output_right[0..],
    });
}

test "installed package exposes mixed runtime oversampling stages" {
    const Mixed = plugin.dsp.MixedOversampler(f32, 8, 4);
    var mixed = try Mixed.init(&.{
        .{ .fir_equiripple = .{
            .up = .{ .stopband_attenuation_db = -60.0 },
            .down = .{ .stopband_attenuation_db = -70.0 },
        } },
        .dummy,
        .{ .polyphase_iir = .{} },
    });
    try std.testing.expectEqual(
        @as(usize, 4),
        try mixed.oversamplingFactor(),
    );
    var input: [8]f32 = @splat(0.25);
    const high_rate = try mixed.upsample(&input);
    try std.testing.expectEqual(@as(usize, 32), high_rate.len);
    var output: [8]f32 = undefined;
    try mixed.downsample(&output);

    const Multichannel =
        plugin.dsp.MixedMultichannelOversampler(f32, 8, 4, 2);
    var multichannel = try Multichannel.init(2, &.{.dummy});
    var left: [8]f32 = @splat(0.25);
    var right: [8]f32 = @splat(-0.25);
    _ = try multichannel.upsample(&.{ left[0..], right[0..] });
    var output_left: [8]f32 = undefined;
    var output_right: [8]f32 = undefined;
    try multichannel.downsample(&.{
        output_left[0..],
        output_right[0..],
    });
}

test "installed package exposes DSP fixture rendering and comparison" {
    const input = [_]f32{ -1.0, -0.5, 0.0, 0.5, 1.0 };
    const expected = [_]f32{ -0.25, -0.125, 0.0, 0.125, 0.25 };
    var output: [input.len]f32 = undefined;
    var model = GainModel{ .gain = 0.25 };
    const processor = plugin.dsp.BlockProcessor(f32).init(GainModel, &model);

    try plugin.dsp.fixture_runner.renderFixed(f32, processor, &input, &output, 2);
    const comparison = try plugin.dsp.fixture_runner.compare(f32, &expected, &output, .{
        .maximum_absolute = 0.0,
        .maximum_relative = 0.0,
        .maximum_rms = 0.0,
    });
    try std.testing.expect(comparison.passed);
}

test "installed package exposes exclusive mutable runtime adoption" {
    var exchange: RuntimeExchange = .{};
    defer exchange.deinit();
    const runtime = try std.testing.allocator.create(Runtime);
    runtime.* = .{ .state = 0.0 };
    try exchange.publish(1, runtime);
    _ = exchange.adoptPending();
    exchange.activeMutable().?.resource.state = 0.5;
    try std.testing.expectEqual(@as(f32, 0.5), exchange.activeMutable().?.resource.state);
    try std.testing.expect(exchange.retireActiveAtBlockBoundary());
}

test "installed package exposes bounded resource presentation" {
    var recovery = InstalledRecovery.init();
    defer recovery.deinit();
    const retained = recovery.snapshot();
    try retained.validate();
    try std.testing.expect(retained.valid());
    const presentation = recovery.presentationSnapshot();
    try std.testing.expectEqual(plugin.resource.RecoveryStatus.empty, presentation.status);
    try std.testing.expectEqual(plugin.gui_progress.State.idle, presentation.progress.state);
    try std.testing.expectEqualStrings("empty", presentation.statusText());
    try std.testing.expectEqualStrings("", presentation.metadata());
    try presentation.progress.validate();
}

test "installed package exposes validated DSP and telemetry state" {
    try std.testing.expectError(
        error.InvalidBiquadConfig,
        (plugin.dsp.BiquadConfig{
            .kind = .low_pass,
            .sample_rate = 0.0,
            .frequency_hz = 1_000.0,
            .gain_db = 0.0,
            .q = 1.0,
        }).coefficients(),
    );
    var filter = plugin.dsp.SmoothedBiquad(f64){};
    filter.setImmediate(.{ .b0 = std.math.nan(f64) });
    try std.testing.expect(filter.current.valid());
    try std.testing.expectEqual(@as(f64, 0.5), filter.process(0.5));

    const Resampler = plugin.dsp.StreamingResampler(f64);
    try std.testing.expectError(
        error.InvalidResamplerConfig,
        Resampler.init(.{
            .input_rate = 0.0,
            .output_rate = 48_000.0,
        }),
    );
    var resampler = try Resampler.init(.{ .input_rate = 48_000, .output_rate = 48_000 });
    try std.testing.expect(resampler.validState());
    const phase_before = resampler.next_input_position;
    try resampler.setRateCorrectionPpm(
        plugin.dsp.maximum_resampler_rate_correction_ppm / 2.0,
    );
    try std.testing.expectEqual(
        phase_before,
        resampler.next_input_position,
    );
    try std.testing.expectEqual(
        @as(f64, 1_000.0),
        resampler.rate_correction_ppm,
    );
    var drift = try plugin.plugin.ClockDriftController.init(.{
        .target_buffer_frames = 512,
    });
    const corrected_phase = resampler.next_input_position;
    const correction = try drift.updateResampler(
        &resampler,
        544,
        480,
        48_000.0,
    );
    try std.testing.expect(correction > 0.0);
    try std.testing.expectEqual(
        corrected_phase,
        resampler.next_input_position,
    );
    try std.testing.expectEqual(
        correction,
        resampler.rate_correction_ppm,
    );
    const CaptureFifo = plugin.plugin.BoundedCaptureFifo(f64, 2, 8);
    var capture_fifo = try CaptureFifo.init(2);
    const capture_left = [_]f64{ 1, 2, 3, 4, 5 };
    const capture_right = [_]f64{ 11, 12, 13, 14, 15 };
    const capture_channels = [_][]const f64{
        &capture_left,
        &capture_right,
    };
    const capture_write = try capture_fifo.write(&capture_channels);
    try std.testing.expectEqual(
        @as(usize, 5),
        capture_write.written_frames,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        capture_write.dropped_frames,
    );
    var capture_drift = try plugin.plugin.ClockDriftController.init(.{
        .target_buffer_frames = 4,
    });
    const fifo_phase = resampler.next_input_position;
    _ = try capture_fifo.updateDriftCorrection(
        &capture_drift,
        &resampler,
        4,
        48_000.0,
    );
    try std.testing.expectEqual(
        fifo_phase,
        resampler.next_input_position,
    );
    var captured_left: [6]f64 = @splat(-1);
    var captured_right: [6]f64 = @splat(-1);
    const captured_channels = [_][]f64{
        &captured_left,
        &captured_right,
    };
    const capture_read = try capture_fifo.read(&captured_channels);
    try std.testing.expectEqual(
        plugin.plugin.CaptureFifoReadReport{
            .read_frames = 5,
            .silent_frames = 1,
        },
        capture_read,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, 2, 3, 4, 5, 0 },
        &captured_left,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 11, 12, 13, 14, 15, 0 },
        &captured_right,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        (try capture_fifo.statistics()).silent_frames,
    );
    const CaptureBridge = plugin.plugin.BoundedCaptureRateBridge(
        f64,
        2,
        16,
        3,
        4,
    );
    var capture_bridge = try CaptureBridge.init(.{
        .channel_count = 2,
        .capture_sample_rate = 44_100.0,
        .render_sample_rate = 48_000.0,
        .drift = .{
            .target_buffer_frames = 8,
        },
    });
    _ = try capture_bridge.capture(&capture_channels);
    var bridge_left: [4]f64 = undefined;
    var bridge_right: [4]f64 = undefined;
    const bridge_output = [_][]f64{
        &bridge_left,
        &bridge_right,
    };
    const bridge_report = try capture_bridge.render(&bridge_output);
    try std.testing.expectEqual(
        @as(usize, 4),
        bridge_report.output_frames,
    );
    try std.testing.expect(bridge_report.capture_frames > 0);
    try std.testing.expect(
        bridge_report.silent_capture_frames <=
            bridge_report.capture_frames,
    );
    try std.testing.expectEqual(
        bridge_report.buffered_before -
            (bridge_report.capture_frames -
                bridge_report.silent_capture_frames),
        bridge_report.buffered_after,
    );
    try std.testing.expect(capture_bridge.valid());
    const AdapterProbe = struct {
        fn process(
            context: *anyopaque,
            block: plugin.plugin.CallbackBlock(f64),
        ) void {
            const observed: *usize =
                @ptrCast(@alignCast(context));
            observed.* = if (block.input_channels.len == 0)
                0
            else
                block.input_channels[0].len;
        }
    };
    const CaptureAdapter =
        plugin.plugin.BoundedCaptureRateCallbackAdapter(
            f64,
            2,
            16,
            3,
            4,
            1,
        );
    var observed_adapter_frames: usize = 0;
    var capture_adapter = try CaptureAdapter.init(
        .{
            .main_input_channel_count = 2,
            .capture_sample_rate = 44_100.0,
            .render_sample_rate = 48_000.0,
            .drift = .{
                .target_buffer_frames = 8,
            },
        },
        .{
            .context = &observed_adapter_frames,
            .process_block = AdapterProbe.process,
        },
    );
    const split_callback = capture_adapter.splitCallback();
    split_callback.capture_block(
        split_callback.context,
        &capture_channels,
    );
    split_callback.render_block(split_callback.context, .{
        .frame_count = 4,
    });
    try std.testing.expectEqual(
        @as(usize, 4),
        observed_adapter_frames,
    );
    const adapter_statistics = try capture_adapter.statistics();
    try std.testing.expectEqual(
        @as(usize, 0),
        adapter_statistics.capture_failures,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        adapter_statistics.render_failures,
    );
    var forced = try Resampler.initBackend(
        .{ .input_rate = 44_100, .output_rate = 48_000 },
        .neon,
    );
    const resampler_input: [64]f64 = @splat(0.25);
    var resampler_output: [80]f64 = undefined;
    const resampler_result = try forced.process(
        &resampler_input,
        &resampler_output,
    );
    try std.testing.expectEqual(resampler_input.len, resampler_result.consumed);
    try std.testing.expect(resampler_result.produced > 0);
    try std.testing.expectEqual(plugin.dsp.KernelBackend.neon, forced.backend);
    resampler.next_output_index = plugin.dsp.resampler.maximum_timeline_index;
    resampler.input_rate = 2_000_000;
    resampler.output_rate = 1_000;
    try std.testing.expect(!resampler.validState());

    const Pipeline = plugin.dsp.FixedRatePipeline(f64);
    try std.testing.expectError(
        error.InvalidFixedRateConfig,
        Pipeline.init(.{
            .host_rate = 1_000.0,
            .model_rate = 96_000.0,
        }),
    );
    var pipeline = try Pipeline.init(.{ .host_rate = 48_000, .model_rate = 48_000 });
    try std.testing.expect(pipeline.validState());
    pipeline.latency_samples +%= 1;
    try std.testing.expect(!pipeline.validState());

    var snapshot = plugin.gui_telemetry.ScalarSnapshot(f64).init(std.math.nan(f64));
    try std.testing.expectEqual(@as(f64, 0.0), snapshot.load());
    snapshot.store(0.75);
    snapshot.store(std.math.inf(f64));
    try std.testing.expectEqual(@as(f64, 0.75), snapshot.load());
}

test "installed package exposes DSP blocks contexts and math primitives" {
    try std.testing.expectEqual(
        plugin.dsp.equiripple_design.maximum_bands,
        plugin.dsp.maximum_fir_equiripple_bands,
    );
    try std.testing.expectEqual(
        plugin.dsp.equiripple_design.maximum_grid_density,
        plugin.dsp.maximum_fir_equiripple_grid_density,
    );
    try std.testing.expectEqual(
        plugin.dsp.equiripple_design.maximum_taps,
        plugin.dsp.maximum_fir_equiripple_taps,
    );
    try std.testing.expectEqual(
        plugin.dsp.fixed_rate.maximum_rate_ratio,
        plugin.dsp.maximum_fixed_rate_ratio,
    );
    try std.testing.expectEqual(
        plugin.dsp.ogg.maximum_page_body_bytes,
        plugin.dsp.maximum_ogg_page_body_bytes,
    );
    try std.testing.expectEqual(
        plugin.dsp.ogg.maximum_page_bytes,
        plugin.dsp.maximum_ogg_page_bytes,
    );
    try std.testing.expectEqual(
        plugin.dsp.ogg.maximum_page_segments,
        plugin.dsp.maximum_ogg_page_segments,
    );
    try std.testing.expectEqual(
        plugin.dsp.pcm_dither.maximum_channels,
        plugin.dsp.maximum_pcm_dither_channels,
    );
    var left = [_]f32{ 0.25, 0.5 };
    var right = [_]f32{ 0.75, 1.0 };
    const block = try plugin.dsp.AudioBlock(f32, 2).init(
        &.{ left[0..], right[0..] },
    );
    var replacing = try plugin.dsp.ProcessContextReplacing(f32, 2).init(block);
    try replacing.output().multiply(2.0);
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 1.0 }, &left);
    try std.testing.expectEqualSlices(f32, &.{ 1.5, 2.0 }, &right);
    const added_left = [_]f32{ 0.25, 0.5 };
    const added_right = [_]f32{ 0.5, 0.25 };
    const added = try plugin.dsp.ConstAudioBlock(f32, 2).init(
        &.{ added_left[0..], added_right[0..] },
    );
    try replacing.output().addFrom(added);
    try std.testing.expectEqualSlices(f32, &.{ 0.75, 1.5 }, &left);
    try std.testing.expectEqualSlices(f32, &.{ 2.0, 2.25 }, &right);
    const block_analysis = replacing.input();
    try std.testing.expectEqual(
        @as(f32, 2.25),
        try block_analysis.peakMagnitude(),
    );
    try std.testing.expectEqual(
        @as(f32, 11.875),
        try block_analysis.sumSquares(),
    );

    const spec = plugin.dsp.ProcessSpec{
        .sample_rate = 48_000.0,
        .maximum_frames = 512,
        .channel_count = 2,
    };
    try spec.validate();

    var frequency = try plugin.dsp.MultiplicativeSmoothedValue.init(
        1_000.0,
        100.0,
        20.0,
        20_000.0,
    );
    try frequency.setTarget(1_000.0, 1_600.0, 0.004);
    try std.testing.expectEqual(@as(f64, 100.0), frequency.next());
    try std.testing.expectEqual(@as(f64, 400.0), frequency.skip(1));
    try std.testing.expectEqual(@as(f64, 1_600.0), frequency.skip(2));

    const M = plugin.dsp.Matrix(f32, 2, 2);
    const matrix = try M.init(.{
        .{ 1.0, 2.0 },
        .{ 3.0, 4.0 },
    });
    const product = try matrix.multiply(2, M.identity());
    try std.testing.expectEqualDeep(matrix.values, product.values);
    const solution = try matrix.solve(.{ 5.0, 11.0 });
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        solution[0],
        0.000_001,
    );
    const decomposition = try matrix.decompose();
    const inverse = try decomposition.inverse();
    const identity = try matrix.multiply(2, inverse);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        identity.values[1][1],
        0.000_001,
    );
    const vector = try plugin.dsp.Vector(f32, 2).init(.{ 5.0, 11.0 });
    const vector_solution = try decomposition.solveVector(vector);
    try std.testing.expectApproxEqAbs(
        @as(f32, 2.0),
        vector_solution.values[1],
        0.000_001,
    );
    const rectangular = try plugin.dsp.Matrix(f32, 3, 2).init(.{
        .{ 1.0, 1.0 },
        .{ 1.0, 2.0 },
        .{ 1.0, 3.0 },
    });
    const qr: plugin.dsp.QrDecomposition(f32, 3, 2) =
        try rectangular.decomposeQr();
    const fitted = try qr.solveLeastSquares(.{ 1.0, 2.0, 2.0 });
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        fitted[1],
        0.000_001,
    );
    const deficient_matrix =
        try plugin.dsp.Matrix(f32, 3, 2).init(.{
            .{ 1.0, 2.0 },
            .{ 2.0, 4.0 },
            .{ 3.0, 6.0 },
        });
    const svd: plugin.dsp.SvdDecomposition(f32, 3, 2) =
        try deficient_matrix.decomposeSvd(.{});
    try std.testing.expectEqual(@as(usize, 1), svd.rank);
    const minimum_norm =
        try svd.solveLeastSquares(.{ 1.0, 2.0, 3.0 });
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.2),
        minimum_norm[0],
        0.000_1,
    );
    const pseudoinverse = try svd.pseudoinverse();
    try std.testing.expect(pseudoinverse.valid());
    const wide_matrix = try plugin.dsp.Matrix(f32, 2, 3).init(.{
        .{ 1.0, 0.0, 1.0 },
        .{ 0.0, 1.0, 1.0 },
    });
    const wide_svd: plugin.dsp.SvdDecomposition(f32, 2, 3) =
        try wide_matrix.decomposeSvd(.{});
    const underdetermined =
        try wide_svd.solveLeastSquares(.{ 1.0, 1.0 });
    try std.testing.expectApproxEqAbs(
        @as(f32, 2.0 / 3.0),
        underdetermined[2],
        0.000_1,
    );
    try std.testing.expect(
        (try wide_svd.pseudoinverse()).valid(),
    );
    const odd_butterworth = try plugin.dsp.ButterworthDesigner(
        f32,
    ).highPassOrder(3, 48_000.0, 1_000.0);
    try std.testing.expect(odd_butterworth.valid());
    try std.testing.expectEqual(@as(usize, 2), odd_butterworth.section_count);
    const chebyshev = try plugin.dsp.ChebyshevDesigner(f32).lowPass(.{
        .order = 5,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
        .ripple_db = 1.0,
    });
    try std.testing.expectApproxEqAbs(
        std.math.pow(f64, 10.0, -1.0 / 20.0),
        chebyshev.magnitude(48_000.0, 1_000.0),
        0.000_001,
    );
    const specified_chebyshev =
        try plugin.dsp.ChebyshevDesigner(f32).lowPassForSpecification(.{
            .sample_rate = 48_000.0,
            .passband_hz = 1_000.0,
            .stopband_hz = 2_000.0,
            .maximum_passband_loss_db = 1.0,
            .minimum_stopband_attenuation_db = 40.0,
        });
    try std.testing.expect(specified_chebyshev.valid());
    var least_squares: [31]f32 = undefined;
    try plugin.dsp.FirDesigner(f32).leastSquares(
        &least_squares,
        &.{
            plugin.dsp.FirLeastSquaresBand{
                .lower_frequency = 0.0,
                .upper_frequency = 0.15,
                .lower_gain = 1.0,
                .upper_gain = 1.0,
            },
            plugin.dsp.FirLeastSquaresBand{
                .lower_frequency = 0.25,
                .upper_frequency = 0.5,
                .lower_gain = 0.0,
                .upper_gain = 0.0,
            },
        },
        8,
    );
    try std.testing.expect(
        plugin.dsp.FirDesigner(f32).magnitude(&least_squares, 0.4) < 0.01,
    );
    var equiripple: [31]f32 = undefined;
    const equiripple_report = try plugin.dsp.FirEquirippleDesigner(
        f32,
    ).design(
        &equiripple,
        &.{
            plugin.dsp.FirEquirippleBand{
                .lower_frequency = 0.0,
                .upper_frequency = 0.18,
                .lower_gain = 1.0,
                .upper_gain = 1.0,
            },
            plugin.dsp.FirEquirippleBand{
                .lower_frequency = 0.25,
                .upper_frequency = 0.5,
                .lower_gain = 0.0,
                .upper_gain = 0.0,
                .weight = 4.0,
            },
        },
        .{},
    );
    try std.testing.expect(equiripple_report.weighted_ripple < 0.02);
    try std.testing.expect(
        plugin.dsp.FirDesigner(f32).magnitude(&equiripple, 0.4) < 0.005,
    );
    var differentiator: [16]f32 = undefined;
    _ = try plugin.dsp.FirEquirippleDesigner(
        f32,
    ).designWithSymmetry(
        &differentiator,
        &.{
            plugin.dsp.FirEquirippleBand{
                .lower_frequency = 0.0,
                .upper_frequency = 0.45,
                .lower_gain = 0.0,
                .upper_gain = 0.9,
            },
        },
        plugin.dsp.FirEquirippleSymmetry.odd,
        .{},
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        plugin.dsp.FirDesigner(f32).magnitude(
            &differentiator,
            0.25,
        ),
        0.002,
    );
    const polyphase = try plugin.dsp.PolyphaseFirBank(
        f32,
        2,
        4,
    ).init(&.{ 0.25, 0.5, 0.25 });
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.375),
        try polyphase.processPhase(0, &.{ 1.0, 0.5 }),
        0.000_001,
    );
    const allpass_design =
        try plugin.dsp.PolyphaseAllpassDesigner(
            f32,
        ).halfBandLowPass(0.08, -72.0);
    try std.testing.expect(
        try allpass_design.magnitude(0.4) < 0.000_3,
    );
    var allpass_filter =
        try plugin.dsp.PolyphaseAllpassHalfBandFilter(
            f32,
        ).init(allpass_design);
    var allpass_impulse: [64]f32 = @splat(0.0);
    allpass_impulse[0] = 1.0;
    try allpass_filter.processBlock(&allpass_impulse);
    try std.testing.expect(std.math.isFinite(allpass_impulse[63]));
    var polyphase_oversampler =
        try plugin.dsp.PolyphaseIirOversampler(
            f32,
            16,
            4,
        ).initStages(.{
            .{
                .normalized_transition_width = 0.12,
                .stopband_attenuation_db = -72.0,
            },
            .{
                .normalized_transition_width = 0.08,
                .stopband_attenuation_db = -90.0,
            },
        });
    var polyphase_input: [16]f32 = @splat(0.125);
    const polyphase_high_rate =
        try polyphase_oversampler.upsample(&polyphase_input);
    try std.testing.expectEqual(
        @as(usize, 64),
        polyphase_high_rate.len,
    );
    var polyphase_output: [16]f32 = undefined;
    try polyphase_oversampler.downsample(&polyphase_output);
    try std.testing.expect(
        (try polyphase_oversampler.latencySamples()) > 0.0,
    );
    var multichannel_polyphase_oversampler =
        try plugin.dsp.MultichannelPolyphaseIirOversampler(
            f32,
            8,
            2,
            2,
        ).initWithOptions(
            2,
            .{},
            .{ .use_integer_latency = true },
        );
    var polyphase_left: [8]f32 = @splat(0.125);
    var polyphase_right: [8]f32 = @splat(-0.25);
    const multichannel_high_rate =
        try multichannel_polyphase_oversampler.upsample(
            &.{ &polyphase_left, &polyphase_right },
        );
    try std.testing.expectEqual(
        @as(usize, 16),
        multichannel_high_rate[0].len,
    );
    var polyphase_left_output: [8]f32 = undefined;
    var polyphase_right_output: [8]f32 = undefined;
    try multichannel_polyphase_oversampler.downsample(
        &.{ &polyphase_left_output, &polyphase_right_output },
    );
    try std.testing.expect(
        try multichannel_polyphase_oversampler.latencySamples() > 0.0,
    );
    try std.testing.expectEqual(
        @ceil(
            try multichannel_polyphase_oversampler.latencySamples(),
        ),
        try multichannel_polyphase_oversampler.latencySamples(),
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 2.0),
        solution[1],
        0.000_001,
    );

    const InstalledPolynomial = plugin.dsp.Polynomial(f32, 3);
    try std.testing.expectEqual(
        @as(usize, 3),
        InstalledPolynomial.coefficient_capacity,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        InstalledPolynomial.maximum_degree,
    );
    try std.testing.expectEqual(
        @as(f32, 1.0e-5),
        InstalledPolynomial.default_root_tolerance,
    );
    try std.testing.expectEqual(
        @as(usize, 256),
        InstalledPolynomial.default_root_maximum_iterations,
    );
    const polynomial = try InstalledPolynomial.init(
        &.{ 1.0, 2.0, 3.0 },
    );
    try std.testing.expectEqual(@as(f32, 17.0), polynomial.evaluate(2.0));
    const root_polynomial = try plugin.dsp.Polynomial(f32, 3)
        .init(&.{ -1.0, 0.0, 1.0 });
    const roots = try root_polynomial.findRoots(.{});
    try std.testing.expect(roots.converged);
    try std.testing.expectEqual(@as(usize, 2), roots.count);
    try std.testing.expectApproxEqAbs(
        @as(f32, -1.0),
        roots.values[0].re,
        0.000_1,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        roots.values[1].re,
        0.000_1,
    );
    const linear = try plugin.dsp.Polynomial(f32, 3)
        .init(&.{ -1.0, 1.0 });
    const division = try root_polynomial.divide(linear);
    try std.testing.expectEqual(
        @as(f32, 1.0),
        division.quotient.coefficients[1],
    );
    const integral = try linear.integral(3.0);
    try std.testing.expectEqual(
        @as(f32, 3.0),
        integral.coefficients[0],
    );
    const interpolated = try plugin.dsp.Polynomial(f32, 3).interpolate(
        &.{ 0.0, 1.0, 2.0 },
        &.{ 1.0, 4.0, 9.0 },
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 16.0),
        interpolated.evaluate(3.0),
        0.000_1,
    );
    const fitted_polynomial =
        try plugin.dsp.Polynomial(f32, 3).fitLeastSquares(
            3,
            1,
            .{ 1.0, 2.0, 3.0 },
            .{ 1.0, 2.0, 2.0 },
        );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        fitted_polynomial.coefficients[1],
        0.000_1,
    );
    const minimum_norm_polynomial =
        try plugin.dsp.Polynomial(f32, 3)
            .fitLeastSquaresMinimumNorm(
            3,
            2,
            .{ 0.0, 0.0, 1.0 },
            .{ 1.0, 1.0, 3.0 },
        );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        minimum_norm_polynomial.coefficients[2],
        0.000_1,
    );
    const legendre =
        try plugin.dsp.Polynomial(f32, 6).legendre(4);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        legendre.evaluate(1.0),
        0.000_1,
    );
    const chebyshev_polynomial =
        try plugin.dsp.Polynomial(f32, 6).chebyshevFirstKind(5);
    try std.testing.expectEqual(
        @as(f32, 16.0),
        chebyshev_polynomial.coefficients[5],
    );
    const chebyshev_second =
        try plugin.dsp.Polynomial(f32, 6).chebyshevSecondKind(4);
    try std.testing.expectEqual(
        @as(f32, -12.0),
        chebyshev_second.coefficients[2],
    );

    const Ladder = plugin.dsp.LadderFilter(f32);
    try std.testing.expectError(
        error.InvalidLadderConfig,
        Ladder.init(.{
            .mode = .low_pass_24,
            .sample_rate = 0.0,
            .frequency_hz = 1_000.0,
        }),
    );
    var ladder = try Ladder.init(.{
        .mode = .low_pass_24,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    try std.testing.expect(std.math.isFinite(ladder.processSample(0.25)));

    var phase = try plugin.dsp.Phase(f32).init(0.0);
    try std.testing.expectEqual(@as(f32, 0.0), try phase.advance(0.25));
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.266_065_877_752_008_2),
        plugin.dsp.besselI0(@as(f64, 1.0)),
        0.000_000_000_000_01,
    );
    const elliptic = try plugin.dsp.ellipticIntegralK(@as(f64, 0.5));
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.685_750_354_812_596),
        elliptic.k,
        0.000_000_000_000_01,
    );
    const incomplete =
        try plugin.dsp.ellipticIntegralF(@as(f64, 1.0), 0.5);
    const jacobi = try plugin.dsp.jacobiElliptic(incomplete, 0.5);
    try std.testing.expectApproxEqAbs(
        incomplete,
        try plugin.dsp.inverseJacobiSn(jacobi.sn, 0.5),
        1.0e-12,
    );
    const near_one = std.math.nextAfter(f64, 1.0, 0.0);
    const near_one_quarter =
        try plugin.dsp.inverseJacobiSn(@as(f64, 1.0), near_one);
    try std.testing.expect(std.math.isFinite(near_one_quarter));
    const near_one_endpoint =
        try plugin.dsp.jacobiElliptic(near_one_quarter, near_one);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        near_one_endpoint.sn,
        2.0e-14,
    );
    const extreme_jacobi = try plugin.dsp.jacobiElliptic(
        std.math.floatMax(f64),
        0.5,
    );
    try std.testing.expect(std.math.isFinite(extreme_jacobi.sn));
    try std.testing.expect(std.math.isFinite(
        extreme_jacobi.principal_amplitude,
    ));

    var flanger = try plugin.dsp.Flanger(f32, 512).init(.{
        .sample_rate = 48_000.0,
    });
    try flanger.syncTempo(120.0, .whole, 0.01);
    try std.testing.expect(std.math.isFinite(flanger.processSample(0.25)));
    var vibrato = try plugin.dsp.Vibrato(f32, 512).init(.{
        .sample_rate = 48_000.0,
    });
    try std.testing.expect(std.math.isFinite(vibrato.processSample(0.25)));

    const FastMath = plugin.dsp.FastMathApproximations(f32);
    var approximated = [_]f32{ -0.5, 0.0, 0.5 };
    try FastMath.applyNative(.sine, &approximated);
    try std.testing.expectApproxEqAbs(
        @sin(@as(f32, 0.5)),
        approximated[2],
        0.000_001,
    );
    const Simd = plugin.dsp.SimdRegister(f32, 4);
    const simd_left = try Simd.load(&.{ 1.0, 2.0, 3.0, 4.0 });
    const simd_right = try Simd.splat(2.0);
    try std.testing.expectEqual(
        @as(f32, 20.0),
        try simd_left.dot(simd_right),
    );
    const simd_selected = try Simd.select(
        simd_left.greaterThan(simd_right),
        simd_left,
        simd_right,
    );
    try std.testing.expectEqual(@as(f32, 4.0), try simd_selected.getLane(3));

    const Shared = plugin.dsp.SharedProcessorDuplicator(
        f32,
        InstalledSharedState,
        InstalledSharedProcessor,
        2,
    );
    var shared_state = InstalledSharedState{ .gain = 0.5 };
    var shared = try Shared.init(&shared_state, .{}, 2);
    try std.testing.expectEqual(
        @as(f32, 1.0),
        try shared.processSample(0, 2.0),
    );
    try std.testing.expect(shared.valid());

    const StereoFlanger = plugin.dsp.StereoModulation(
        f32,
        plugin.dsp.Flanger(f32, 512),
    );
    var stereo_flanger = try StereoFlanger.init(
        try plugin.dsp.Flanger(f32, 512).init(.{
            .sample_rate = 48_000.0,
        }),
        try plugin.dsp.Flanger(f32, 512).init(.{
            .sample_rate = 48_000.0,
        }),
        0.25,
    );
    var stereo_left: [8]f32 = @splat(0.25);
    var stereo_right: [8]f32 = @splat(-0.25);
    var stereo_left_output: [8]f32 = undefined;
    var stereo_right_output: [8]f32 = undefined;
    try stereo_flanger.process(
        &stereo_left,
        &stereo_right,
        &stereo_left_output,
        &stereo_right_output,
    );
    try std.testing.expect(stereo_flanger.valid());

    var butterworth: [2]plugin.dsp.BiquadCoefficients = undefined;
    try plugin.dsp.ButterworthDesigner(f32).lowPass(
        &butterworth,
        48_000.0,
        1_000.0,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0 / @sqrt(2.0)),
        plugin.dsp.ButterworthDesigner(f32).magnitude(
            &butterworth,
            48_000.0,
            1_000.0,
        ),
        0.000_001,
    );
    const specified_butterworth =
        try plugin.dsp.ButterworthDesigner(f32).lowPassForSpecification(.{
            .sample_rate = 48_000.0,
            .passband_hz = 1_000.0,
            .stopband_hz = 2_000.0,
            .maximum_passband_loss_db = 1.0,
            .minimum_stopband_attenuation_db = 40.0,
        });
    try std.testing.expect(specified_butterworth.cascade.valid());
    try std.testing.expectEqual(
        @as(f64, 0.5),
        try plugin.dsp.modulationRateHz(120.0, .whole),
    );
    try std.testing.expectEqual(
        @as(f64, 120.0),
        try plugin.dsp.modulationTempoFromTransport(null, 120.0),
    );
    try std.testing.expectEqual(
        @as(?f64, 0.75),
        plugin.dsp.modulationPhaseFromTransport(.{
            .project_time_samples = 0,
            .project_quarter_notes = 3.5,
        }, .half),
    );
    try std.testing.expect(
        plugin.dsp.modulationPhaseFromTransport(.{
            .project_time_samples = 0,
            .project_quarter_notes = std.math.floatMax(f64),
        }, .thirty_second) == null,
    );

    var multichannel = try plugin.dsp.MultichannelOversampler(
        f32,
        4,
        2,
        2,
    ).init(2);
    var oversampling_left: [4]f32 = @splat(0.25);
    var oversampling_right: [4]f32 = @splat(-0.25);
    var oversampling_output_left: [4]f32 = undefined;
    var oversampling_output_right: [4]f32 = undefined;
    _ = try multichannel.upsample(
        &.{ oversampling_left[0..], oversampling_right[0..] },
    );
    try multichannel.downsample(
        &.{
            oversampling_output_left[0..],
            oversampling_output_right[0..],
        },
    );

    var lookahead = try plugin.dsp.LookaheadLimiter(f32, 256).init(.{
        .sample_rate = 48_000.0,
        .lookahead_ms = 1.0,
    });
    var lookahead_samples = [_]f32{ 0.25, 1.25 } ++ [_]f32{0.0} ** 48;
    lookahead.process(&lookahead_samples);
    try std.testing.expectEqual(@as(usize, 48), lookahead.latencySamples());
    try std.testing.expect(lookahead.valid());
    var lookahead_compressor =
        try plugin.dsp.LookaheadCompressor(f32, 256).init(.{
            .compressor = .{
                .sample_rate = 48_000.0,
                .threshold_db = -12.0,
                .ratio = 4.0,
            },
            .lookahead_ms = 2.0,
        });
    var lookahead_compressor_samples = [_]f32{ 0.1, 1.0, 0.1 };
    lookahead_compressor.process(&lookahead_compressor_samples);
    try std.testing.expectEqual(
        @as(usize, 96),
        lookahead_compressor.latencySamples(),
    );
    try std.testing.expect(lookahead_compressor.valid());
    try std.testing.expectError(
        error.InvalidCompressorConfig,
        plugin.dsp.Compressor(f64).init(.{
            .sample_rate = std.math.floatMax(f64),
        }),
    );

    var inter_sample = try plugin.dsp.InterSampleLimiter(
        f32,
        8,
        2,
    ).init(.{ .sample_rate = 48_000.0 });
    var inter_sample_block = [_]f32{ 0.0, 0.75, -0.75, 0.0 };
    try inter_sample.process(&inter_sample_block);
    try std.testing.expect(inter_sample.valid());

    const multiband_config = plugin.dsp.TwoBandCompressorConfig{
        .sample_rate = 48_000.0,
        .crossover_hz = 1_000.0,
        .low = .{
            .sample_rate = 48_000.0,
            .threshold_db = -12.0,
            .ratio = 4.0,
        },
        .high = .{
            .sample_rate = 48_000.0,
            .threshold_db = -6.0,
            .ratio = 2.0,
        },
    };
    var multiband = try plugin.dsp.TwoBandCompressor(f32).init(
        multiband_config,
    );
    var multiband_samples = [_]f32{ 0.1, -0.2, 0.3, -0.4 };
    multiband.process(&multiband_samples);
    try std.testing.expect(multiband.valid());
    const Multiband = plugin.dsp.MultibandCompressor(f32, 3);
    const multiband_three_config =
        plugin.dsp.MultibandCompressorConfig(3){
            .sample_rate = 48_000.0,
            .crossover_hz = .{ 300.0, 3_000.0 },
            .bands = @splat(.{
                .sample_rate = 48_000.0,
                .threshold_db = -12.0,
                .ratio = 2.0,
            }),
        };
    var multiband_three = try Multiband.init(multiband_three_config);
    var multiband_three_samples = [_]f32{ 0.1, -0.2, 0.3, -0.4 };
    multiband_three.process(&multiband_three_samples);
    try std.testing.expect(multiband_three.valid());
    try std.testing.expect(std.math.isFinite(
        try multiband_three.gainReductionDb(1),
    ));
    const LinkedMultiband =
        plugin.dsp.LinkedMultibandCompressor(f32, 3, 2);
    var linked_multiband = try LinkedMultiband.init(
        multiband_three_config,
    );
    var linked_samples = [_]f32{
        0.5,  0.1,
        -0.5, -0.1,
    };
    try linked_multiband.processInterleaved(&linked_samples);
    try std.testing.expect(linked_multiband.valid());

    var wav_bytes: [48]u8 = undefined;
    const wav = try plugin.dsp.writeInterleavedWav(
        f32,
        &wav_bytes,
        &.{ -0.5, 0.5 },
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
    );
    try std.testing.expectEqualStrings("RIFF", wav[0..4]);
    var incremental_bytes: [48]u8 = undefined;
    var wav_writer = try plugin.dsp.WavWriter.init(
        &incremental_bytes,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
    );
    try wav_writer.append(f32, &.{-0.5});
    try wav_writer.append(f32, &.{0.5});
    try std.testing.expectEqualSlices(u8, wav, wav_writer.bytes());

    var aiff_bytes: [58]u8 = undefined;
    const aiff = try plugin.dsp.writeInterleavedAiff(
        f32,
        &aiff_bytes,
        &.{0.5},
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
    );
    try std.testing.expectEqualStrings("FORM", aiff[0..4]);
    try std.testing.expectEqualStrings("AIFF", aiff[8..12]);
    var incremental_aiff_bytes: [60]u8 = undefined;
    var aiff_writer = try plugin.dsp.AiffWriter.init(
        &incremental_aiff_bytes,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
    );
    try aiff_writer.append(f32, &.{0.25});
    try aiff_writer.append(f32, &.{-0.25});
    try std.testing.expectEqual(@as(usize, 60), aiff_writer.bytes().len);

    const flac_source = [_]i32{
        0,    0,     100,  -100,  200,  -200,  300,  -300,
        400,  -400,  500,  -500,  600,  -600,  700,  -700,
        800,  -800,  900,  -900,  1000, -1000, 1100, -1100,
        1200, -1200, 1300, -1300, 1400, -1400, 1500, -1500,
    };
    var flac_storage: [1024]u8 = undefined;
    const flac = try plugin.dsp.encodeInterleavedFlacWithComments(
        &flac_storage,
        &flac_source,
        .{
            .sample_rate = 48_000,
            .channel_count = 2,
            .encoding = .pcm_i24,
            .block_size = 16,
        },
        .{ .fields = &.{
            .{ .name = "TITLE", .value = "Installed FLAC" },
        } },
    );
    var flac_comments =
        (try plugin.dsp.FlacCommentIterator.init(flac)).?;
    const flac_title = (try flac_comments.next()).?;
    try std.testing.expectEqualStrings("TITLE", flac_title.name);
    try std.testing.expectEqualStrings("Installed FLAC", flac_title.value);
    var flac_decoded: [flac_source.len]i32 = undefined;
    const flac_result = try plugin.dsp.decodeInterleavedFlac(
        flac,
        &flac_decoded,
    );
    try std.testing.expectEqual(
        flac_source.len / 2,
        flac_result.frames_decoded,
    );
    try std.testing.expectEqualSlices(
        i32,
        &flac_source,
        &flac_decoded,
    );
    var flac_range: [8]i32 = undefined;
    var flac_frame_scratch: [32]i32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        try plugin.dsp.decodeInterleavedFlacRange(
            flac,
            3,
            &flac_range,
            &flac_frame_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        i32,
        flac_source[6..14],
        &flac_range,
    );

    var flac_temporary = std.testing.tmpDir(.{});
    defer flac_temporary.cleanup();
    var flac_file = try flac_temporary.dir.createFile(
        std.testing.io,
        "incremental.flac",
        .{ .read = true },
    );
    defer flac_file.close(std.testing.io);
    const flac_spec = plugin.dsp.FlacSpec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i24,
        .block_size = 16,
    };
    var flac_pending: [32]i32 = undefined;
    var flac_frame_storage: [113]u8 = undefined;
    var flac_metadata_storage: [128]u8 = undefined;
    const incremental_comments = plugin.dsp.FlacComments{
        .fields = &.{
            .{ .name = "TITLE", .value = "Installed stream" },
        },
    };
    const incremental_metadata = plugin.dsp.FlacFileWriterMetadata{
        .comments = incremental_comments,
        .seek_interval = 1,
        .seek_point_capacity = 2,
    };
    try std.testing.expectEqual(
        flac_pending.len,
        try plugin.dsp.requiredFlacPendingSamples(flac_spec),
    );
    try std.testing.expectEqual(
        flac_frame_storage.len,
        try plugin.dsp.requiredFlacFrameStorageBytes(flac_spec),
    );
    try std.testing.expect(
        try plugin.dsp.requiredFlacFileWriterMetadataBytes(
            incremental_metadata,
        ) <= flac_metadata_storage.len,
    );
    var flac_writer = try plugin.dsp.FlacFileWriter.initWithMetadata(
        std.testing.io,
        flac_file,
        flac_spec,
        &flac_pending,
        &flac_frame_storage,
        &flac_metadata_storage,
        incremental_metadata,
    );
    try flac_writer.append(flac_source[0..10]);
    try flac_writer.append(flac_source[10..]);
    try flac_writer.finalize();
    var streaming_metadata: [128]u8 = undefined;
    const streaming_metadata_bytes =
        try plugin.dsp.requiredFlacFileReaderMetadataBytes(
            std.testing.io,
            flac_file,
        );
    try std.testing.expectEqual(
        streaming_metadata_bytes,
        try plugin.dsp.FlacFileReader.requiredMetadataBytes(
            std.testing.io,
            flac_file,
        ),
    );
    const streaming_reader = try plugin.dsp.FlacFileReader.init(
        std.testing.io,
        flac_file,
        streaming_metadata[0..streaming_metadata_bytes],
    );
    var streaming_frame: [128]u8 = undefined;
    var streaming_decoded: [flac_source.len]i32 = undefined;
    const streaming_result = try streaming_reader.decode(
        &streaming_decoded,
        &streaming_frame,
        &.{},
    );
    try std.testing.expectEqual(
        flac_source.len / 2,
        streaming_result.frames_decoded,
    );
    try std.testing.expectEqualSlices(
        i32,
        &flac_source,
        &streaming_decoded,
    );
    var streaming_comments =
        (try streaming_reader.commentIterator()).?;
    try std.testing.expectEqualStrings(
        "Installed stream",
        (try streaming_comments.next()).?.value,
    );
    try std.testing.expect(
        streaming_reader.seekTableIterator() != null,
    );
    var incremental_file_bytes: [1024]u8 = undefined;
    var incremental_decoded: [flac_source.len]i32 = undefined;
    const incremental_result = try plugin.dsp.readInterleavedFlacFile(
        std.testing.io,
        flac_file,
        &incremental_file_bytes,
        &incremental_decoded,
    );
    try std.testing.expectEqual(
        flac_source.len / 2,
        incremental_result.frames_decoded,
    );
    try std.testing.expectEqualSlices(
        i32,
        &flac_source,
        &incremental_decoded,
    );
    var incremental_comment_iterator =
        (try plugin.dsp.FlacCommentIterator.init(
            incremental_file_bytes[0..@intCast(flac_writer.byte_count)],
        )).?;
    const incremental_title =
        (try incremental_comment_iterator.next()).?;
    try std.testing.expectEqualStrings(
        "Installed stream",
        incremental_title.value,
    );

    var ogg_storage: [128]u8 = undefined;
    var ogg_writer = plugin.dsp.OggStreamWriter.init(
        &ogg_storage,
        0x10203040,
    );
    try ogg_writer.appendPacket(
        "installed packet",
        1,
        true,
        true,
    );
    var ogg_packet_storage: [32]u8 = undefined;
    var ogg_packets = plugin.dsp.OggPacketIterator.init(
        ogg_writer.bytes(),
        &ogg_packet_storage,
    );
    const ogg_packet = (try ogg_packets.next()).?;
    try std.testing.expect(ogg_packet.beginning);
    try std.testing.expect(ogg_packet.end);
    try std.testing.expectEqualStrings(
        "installed packet",
        ogg_packet.bytes,
    );
    var indexed_ogg_storage: [512]u8 = undefined;
    var indexed_ogg_writer = plugin.dsp.OggStreamWriter.init(
        &indexed_ogg_storage,
        0x50607080,
    );
    try indexed_ogg_writer.appendPacket("header 1", 0, true, false);
    try indexed_ogg_writer.appendPacket("header 2", 0, false, false);
    try indexed_ogg_writer.appendPacket("header 3", 0, false, false);
    try indexed_ogg_writer.appendPacket("audio 1", 0, false, false);
    try indexed_ogg_writer.appendPacket("audio 2", 32, false, true);
    try std.testing.expectEqual(
        @as(usize, 2),
        try plugin.dsp.requiredVorbisSeekPoints(
            indexed_ogg_writer.bytes(),
        ),
    );
    var installed_seek_points: [2]plugin.dsp.VorbisSeekPoint =
        undefined;
    const installed_seek_index = try plugin.dsp.buildVorbisSeekIndex(
        indexed_ogg_writer.bytes(),
        &installed_seek_points,
    );
    const installed_seek_point = try plugin.dsp.findVorbisSeekPoint(
        installed_seek_index,
        0,
        16,
    );
    try std.testing.expectEqual(
        @as(u64, 3),
        installed_seek_point.packet.logical_packet_index,
    );
    var vorbis_codebooks: [1]plugin.dsp.VorbisCodebook = undefined;
    var vorbis_entries: [1]plugin.dsp.VorbisCodebookEntry = undefined;
    var vorbis_nodes: [1]plugin.dsp.VorbisHuffmanNode = undefined;
    var vorbis_multiplicands: [1]u32 = undefined;
    var vorbis_floors: [1]plugin.dsp.VorbisFloor = undefined;
    var vorbis_residues: [1]plugin.dsp.VorbisResidue = undefined;
    var vorbis_mappings: [1]plugin.dsp.VorbisMapping = undefined;
    var vorbis_modes: [1]plugin.dsp.VorbisMode = undefined;
    try std.testing.expectError(
        error.InvalidVorbisSetupHeader,
        plugin.dsp.parseVorbisSetup(
            "not a setup packet",
            2,
            .{
                .codebooks = &vorbis_codebooks,
                .codebook_entries = &vorbis_entries,
                .huffman_nodes = &vorbis_nodes,
                .codebook_multiplicands = &vorbis_multiplicands,
                .floors = &vorbis_floors,
                .residues = &vorbis_residues,
                .mappings = &vorbis_mappings,
                .modes = &vorbis_modes,
            },
        ),
    );
    const residue = plugin.dsp.VorbisResidue{
        .kind = plugin.dsp.VorbisResidueKind.two,
        .begin = 0,
        .end = 16,
        .partition_size = 4,
        .classification_count = 1,
        .classbook = 0,
        .cascades = [_]u8{0} ** 64,
        .books = [_][8]i16{[_]i16{-1} ** 8} ** 64,
    };
    try std.testing.expectEqual(
        @as(usize, 4),
        try plugin.dsp.requiredVorbisResidueClassifications(
            residue,
            8,
            2,
        ),
    );
    const residue_packet = plugin.dsp.VorbisResiduePacket{};
    try std.testing.expect(!residue_packet.truncated);
    const mapping = plugin.dsp.VorbisMapping{
        .submap_count = 1,
        .coupling_step_count = 0,
        .coupling_steps = [_]plugin.dsp.VorbisCouplingStep{.{
            .magnitude = 0,
            .angle = 0,
        }} ** 256,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]plugin.dsp.VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    };
    var uncoupled = [_]f32{ 1, 2 };
    const uncoupled_channels = [_][]f32{&uncoupled};
    var coupling_scratch: [2]f32 = undefined;
    try plugin.dsp.forwardCoupleVorbisChannels(
        f32,
        mapping,
        &uncoupled_channels,
        &coupling_scratch,
    );
    try plugin.dsp.inverseCoupleVorbisChannels(
        f32,
        mapping,
        &uncoupled_channels,
        &coupling_scratch,
    );
    try std.testing.expectEqualSlices(f32, &.{ 1, 2 }, &uncoupled);
    var vorbis_window: [64]f32 = undefined;
    try plugin.dsp.synthesizeVorbisWindow(
        f32,
        .{
            .channel_count = 1,
            .sample_rate = 48_000,
            .bitrate_maximum = 0,
            .bitrate_nominal = 0,
            .bitrate_minimum = 0,
            .small_block_size = 64,
            .large_block_size = 64,
        },
        .{
            .mode_number = 0,
            .large_block = false,
            .previous_window_flag = null,
            .next_window_flag = null,
            .block_size = 64,
            .payload_bit_offset = 1,
        },
        &vorbis_window,
    );
    try std.testing.expect(vorbis_window[0] > 0);
    const window_plan = plugin.dsp.VorbisWindowPlan(f32, 64, 64).init();
    const installed_window = try window_plan.get(.{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 1,
    });
    try std.testing.expectEqual(@as(usize, 64), installed_window.len);

    var inverse_mdct = plugin.dsp.VorbisInverseMdct(f32, 64).init();
    var spectrum = [_]f32{0} ** 32;
    try plugin.dsp.applyVorbisFloor(
        f32,
        &spectrum,
        &([_]f32{1} ** 32),
    );
    var time_domain: [64]f32 = undefined;
    try inverse_mdct.processWindowed(
        &spectrum,
        installed_window,
        &time_domain,
    );
    try std.testing.expectEqual(@as(f32, 0), time_domain[0]);
    var forward_mdct = plugin.dsp.VorbisForwardMdct(f32, 64).init();
    var source_spectrum = [_]f32{0} ** 32;
    source_spectrum[3] = 1;
    var synthesized_block: [64]f32 = undefined;
    try inverse_mdct.process(&source_spectrum, &synthesized_block);
    var restored_spectrum: [32]f32 = undefined;
    try forward_mdct.process(&synthesized_block, &restored_spectrum);
    for (restored_spectrum, source_spectrum) |actual, expected| {
        try std.testing.expectApproxEqAbs(expected, actual, 0.000_01);
    }
    const installed_block_config =
        plugin.dsp.VorbisPcmBlockAnalysisConfig{};
    const installed_block_analysis: plugin.dsp.VorbisPcmBlockAnalysis =
        try plugin.dsp.analyzeVorbisPcmBlock(
            f32,
            &.{&synthesized_block},
            64,
            64,
            installed_block_config,
        );
    try std.testing.expect(
        !installed_block_analysis.recommended_large_block,
    );
    var installed_block_classifier =
        plugin.dsp.VorbisPcmBlockClassifier{};
    const installed_classification: plugin.dsp.VorbisPcmBlockClassification =
        try installed_block_classifier.classify(
            f32,
            &.{&synthesized_block},
            64,
            64,
            plugin.dsp.VorbisPcmBlockClassifierConfig{},
        );
    try std.testing.expect(
        !installed_classification.recommended_large_block,
    );
    var installed_psychoacoustic_floor: [32]f32 = undefined;
    var installed_noise_threshold: [32]f32 = undefined;
    const installed_psychoacoustics: plugin.dsp.VorbisPsychoacousticAnalysis =
        try plugin.dsp.analyzeVorbisPsychoacoustics(
            f32,
            &restored_spectrum,
            48_000,
            plugin.dsp.VorbisPsychoacousticConfig{},
            &installed_psychoacoustic_floor,
            &installed_noise_threshold,
        );
    try std.testing.expect(!installed_psychoacoustics.silent);
    const installed_audio_psychoacoustic_requirements: plugin.dsp.VorbisAudioPsychoacousticStorageRequirements =
        try plugin.dsp.requiredVorbisAudioPsychoacousticStorage(1, 32);
    try std.testing.expectEqual(
        @as(usize, 32),
        installed_audio_psychoacoustic_requirements.floor_values,
    );
    var installed_audio_psychoacoustic_scratch_floor: [32]f32 =
        undefined;
    var installed_audio_psychoacoustic_scratch_thresholds: [32]f32 =
        undefined;
    var installed_audio_psychoacoustic_analyses: [1]plugin.dsp.VorbisPsychoacousticAnalysis = undefined;
    var installed_audio_psychoacoustic_floor: [32]f32 = undefined;
    var installed_audio_psychoacoustic_thresholds: [32]f32 =
        undefined;
    const installed_psychoacoustic_spectra =
        [_][]const f32{&restored_spectrum};
    const installed_audio_psychoacoustics: plugin.dsp.VorbisAudioPsychoacousticPlan(f32) =
        try plugin.dsp.analyzeVorbisAudioPsychoacoustics(
            f32,
            &installed_psychoacoustic_spectra,
            48_000,
            plugin.dsp.VorbisPsychoacousticConfig{},
            plugin.dsp.VorbisAudioPsychoacousticScratch(f32){
                .floor_targets = &installed_audio_psychoacoustic_scratch_floor,
                .noise_thresholds = &installed_audio_psychoacoustic_scratch_thresholds,
            },
            plugin.dsp.VorbisAudioPsychoacousticStorage(f32){
                .analyses = &installed_audio_psychoacoustic_analyses,
                .floor_targets = &installed_audio_psychoacoustic_floor,
                .noise_thresholds = &installed_audio_psychoacoustic_thresholds,
            },
        );
    try std.testing.expectEqual(
        @as(usize, 32),
        installed_audio_psychoacoustics.coefficient_count,
    );
    try std.testing.expect(
        !installed_audio_psychoacoustics.analyses[0].silent,
    );
    const installed_distortion: plugin.dsp.VorbisRateDistortion =
        try plugin.dsp.evaluateVorbisRateDistortion(
            f32,
            &restored_spectrum,
            &restored_spectrum,
            &installed_noise_threshold,
        );
    try std.testing.expect(installed_distortion.within_mask);
    var overlap = plugin.dsp.VorbisOverlapAdd(f32, 64){};
    try std.testing.expectEqual(
        @as(usize, 0),
        try overlap.push(&time_domain, &.{}),
    );
    var finished: [32]f32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 32),
        try overlap.push(&time_domain, &finished),
    );
    try std.testing.expectEqual(@as(f32, 0), finished[0]);
    var channel_overlap =
        plugin.dsp.VorbisChannelOverlapAdd(f32, 1, 64){};
    const windowed_channels = [_][]const f32{&time_domain};
    var empty_overlap_output: [0]f32 = .{};
    const empty_overlap_channels = [_][]f32{&empty_overlap_output};
    _ = try channel_overlap.push(
        &windowed_channels,
        &empty_overlap_channels,
    );
    const finished_channels = [_][]f32{&finished};
    try std.testing.expectEqual(
        @as(usize, 32),
        try channel_overlap.push(
            &windowed_channels,
            &finished_channels,
        ),
    );

    const installed_entry = plugin.dsp.VorbisCodebookEntry{
        .codeword = 0,
        .length = 1,
    };
    const installed_codebook = plugin.dsp.VorbisCodebook{
        .dimensions = 1,
        .entries = 1,
        .entry_offset = 0,
        .active_entry_count = 1,
        .lookup_type = 0,
    };
    var installed_x = [_]u16{0} ** 65;
    installed_x[1] = 32;
    const installed_floor = plugin.dsp.VorbisFloor{
        .one = .{
            .partition_count = 0,
            .partition_classes = [_]u4{0} ** 31,
            .class_count = 0,
            .classes = [_]plugin.dsp.VorbisFloorOneClass{.{
                .dimensions = 0,
                .subclass_bits = 0,
                .masterbook = -1,
                .subclass_books = [_]i16{-1} ** 8,
            }} ** 16,
            .multiplier = 1,
            .range_bits = 5,
            .point_count = 2,
            .x_list = installed_x,
        },
    };
    const installed_identification = plugin.dsp.VorbisIdentification{
        .channel_count = 1,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    const installed_mode = plugin.dsp.VorbisMode{
        .large_block = false,
        .mapping = 0,
    };
    const installed_setup = plugin.dsp.VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 1,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 1,
            .maximum_codebook_entries = 1,
        },
        .codebooks = &.{installed_codebook},
        .codebook_entries = &.{installed_entry},
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{},
        .floors = &.{installed_floor},
        .residues = &.{residue},
        .mappings = &.{mapping},
        .modes = &.{installed_mode},
    };
    try std.testing.expectEqual(
        @as(u8, 0),
        try plugin.dsp.selectVorbisEncodingMode(
            installed_setup,
            0,
            false,
        ),
    );
    const installed_block_header =
        try plugin.dsp.planVorbisEncodingBlock(
            installed_identification,
            installed_setup,
            0,
            false,
            false,
            false,
        );
    var installed_lookahead =
        plugin.dsp.VorbisPcmBlockLookahead.init(false);
    try installed_lookahead.prime(installed_block_analysis);
    const installed_scheduled_frame =
        try installed_lookahead.finish(
            installed_identification,
            installed_setup,
            0,
        );
    try std.testing.expect(
        !installed_scheduled_frame.header.large_block,
    );
    var installed_frame_planner =
        plugin.dsp.VorbisPcmFramePlanner.init(false);
    const installed_frame: plugin.dsp.VorbisPcmFramePlan =
        try installed_frame_planner.plan(
            installed_identification,
            installed_setup,
            0,
            false,
            false,
        );
    try std.testing.expectEqual(
        @as(i64, -32),
        installed_frame.source_start,
    );
    var installed_sequence =
        try plugin.dsp.VorbisPcmPacketSequence.init(
            plugin.dsp.VorbisPcmPacketSequenceConfig{
                .rate_control = .{
                    .target_bitrate = 48_000,
                    .reservoir_capacity_bits = 1_024,
                },
            },
            false,
        );
    _ = try installed_sequence.prime(
        f32,
        &.{&synthesized_block},
        installed_identification,
    );
    const installed_first_packet_plan: plugin.dsp.VorbisPcmPacketPlan =
        try installed_sequence.planNext(
            f32,
            &.{&synthesized_block},
            installed_identification,
            installed_setup,
        );
    var installed_ogg_bytes: [96]u8 = undefined;
    var installed_ogg_writer =
        plugin.dsp.OggStreamWriter.init(
            &installed_ogg_bytes,
            0x696e7374,
        );
    try installed_ogg_writer.appendPacket(
        &.{1},
        0,
        true,
        false,
    );
    const installed_first_packet_commit: plugin.dsp.VorbisPcmPacketCommit =
        try installed_sequence.appendMemory(
            &installed_ogg_writer,
            installed_first_packet_plan,
            &.{0},
            1,
        );
    try std.testing.expect(!installed_first_packet_commit.end);
    try std.testing.expectEqual(
        @as(u64, 0),
        installed_first_packet_commit.granule_position,
    );
    const installed_final_packet_plan: plugin.dsp.VorbisPcmPacketPlan =
        try installed_sequence.planFinish(
            installed_identification,
            installed_setup,
            32,
        );
    const installed_final_packet_commit: plugin.dsp.VorbisPcmPacketCommit =
        try installed_sequence.appendMemory(
            &installed_ogg_writer,
            installed_final_packet_plan,
            &.{0},
            1,
        );
    try std.testing.expect(installed_final_packet_commit.end);
    try std.testing.expectEqual(
        @as(u64, 32),
        installed_final_packet_commit.granule_position,
    );
    var installed_reservoir =
        try plugin.dsp.VorbisBitReservoir.init(
            plugin.dsp.VorbisRateControlConfig{
                .target_bitrate = 48_000,
                .reservoir_capacity_bits = 1_024,
            },
        );
    const installed_budget: plugin.dsp.VorbisPacketBitBudget =
        try installed_reservoir.plan(
            installed_identification.sample_rate,
            installed_frame.pcm_advance,
        );
    var installed_residue_bit_budgets: [1]u32 = undefined;
    const installed_bit_allocation: plugin.dsp.VorbisResidueBitAllocation =
        try plugin.dsp.allocateVorbisResidueBitBudgets(
            installed_budget,
            4,
            &.{installed_psychoacoustics.rms},
            &installed_residue_bit_budgets,
        );
    try std.testing.expectEqual(
        installed_budget.target_bits - 4,
        installed_bit_allocation.residue_bits,
    );
    const installed_rate_commit: plugin.dsp.VorbisRateCommit =
        try installed_reservoir.commit(
            installed_budget.target_bits,
        );
    try std.testing.expectEqual(
        @as(i64, 0),
        installed_rate_commit.reservoir_balance_after,
    );
    var installed_extracted_block: [64]f32 = undefined;
    try plugin.dsp.extractVorbisPcmBlock(
        f32,
        &.{&synthesized_block},
        installed_frame.source_start,
        installed_frame.header.block_size,
        &.{&installed_extracted_block},
    );
    try std.testing.expectEqual(
        @as(f32, 0),
        installed_extracted_block[0],
    );
    var installed_block_transform =
        plugin.dsp.VorbisPcmBlockTransform(f32, 1, 64, 64).init();
    var installed_block_coefficients: [32]f32 = undefined;
    var installed_block_scratch: [32]f32 = undefined;
    try installed_block_transform.process(
        installed_block_header,
        &.{&synthesized_block},
        &.{&installed_block_coefficients},
        &installed_block_scratch,
    );
    for (installed_block_coefficients) |coefficient| {
        try std.testing.expect(std.math.isFinite(coefficient));
    }
    const InstalledFrameAnalyzer =
        plugin.dsp.VorbisPcmFrameAnalyzer(f32, 1, 64, 64);
    try std.testing.expect(
        @hasDecl(plugin.dsp, "encodeVorbisPcmPacket"),
    );
    try std.testing.expect(
        @hasDecl(
            plugin.dsp,
            "VorbisPcmPacketOrchestrationScratch",
        ),
    );
    try std.testing.expectEqual(
        plugin.dsp.VorbisPcmFrameAnalysisStorageRequirements{
            .pcm_values = 64,
            .transform_values = 32,
            .spectrum_values = 32,
            .analyses = 1,
            .floor_values = 32,
            .threshold_values = 32,
        },
        try InstalledFrameAnalyzer.requiredStorage(
            installed_frame.header,
        ),
    );
    var installed_frame_analyzer = InstalledFrameAnalyzer.init();
    var installed_frame_pcm_scratch: [64]f32 = undefined;
    var installed_frame_transform_scratch: [32]f32 = undefined;
    var installed_frame_spectrum_scratch: [32]f32 = undefined;
    var installed_frame_floor_scratch: [32]f32 = undefined;
    var installed_frame_threshold_scratch: [32]f32 = undefined;
    var installed_frame_spectra: [32]f32 = undefined;
    var installed_frame_analyses: [1]plugin.dsp.VorbisPsychoacousticAnalysis = undefined;
    var installed_frame_floor: [32]f32 = undefined;
    var installed_frame_thresholds: [32]f32 = undefined;
    const installed_frame_analysis: plugin.dsp.VorbisPcmFrameAnalysisPlan(f32) =
        try installed_frame_analyzer.analyze(
            &.{&synthesized_block},
            installed_frame,
            plugin.dsp.VorbisPsychoacousticConfig{},
            48_000,
            plugin.dsp.VorbisPcmFrameAnalysisScratch(f32){
                .pcm = &installed_frame_pcm_scratch,
                .transform = &installed_frame_transform_scratch,
                .spectra = &installed_frame_spectrum_scratch,
                .floor_targets = &installed_frame_floor_scratch,
                .noise_thresholds = &installed_frame_threshold_scratch,
            },
            plugin.dsp.VorbisPcmFrameAnalysisStorage(f32){
                .spectra = &installed_frame_spectra,
                .analyses = &installed_frame_analyses,
                .floor_targets = &installed_frame_floor,
                .noise_thresholds = &installed_frame_thresholds,
            },
        );
    try std.testing.expectEqual(
        @as(usize, 32),
        installed_frame_analysis.coefficient_count,
    );
    try std.testing.expect(
        !installed_frame_analysis.analyses[0].silent,
    );
    try std.testing.expectEqual(
        plugin.dsp.VorbisAudioFloorOneStorageRequirements{
            .encodings = 1,
            .y_values = 2,
            .curve_values = 32,
        },
        try plugin.dsp.requiredVorbisAudioFloorOneStorage(
            installed_identification,
            installed_setup,
            installed_block_header,
        ),
    );
    var installed_floor_trial_y: [2]u32 = undefined;
    var installed_floor_trial_curves: [32]f32 = undefined;
    var installed_floor_encodings: [1]plugin.dsp.VorbisFloorPacketEncoding = undefined;
    var installed_floor_retained_y: [2]u32 = undefined;
    var installed_floor_retained_curves: [32]f32 = undefined;
    const installed_floor_plan: plugin.dsp.VorbisAudioFloorOnePlan(f32) =
        try plugin.dsp.fitVorbisAudioFloorOne(
            f32,
            installed_identification,
            installed_setup,
            installed_block_header,
            &.{&installed_psychoacoustic_floor},
            plugin.dsp.VorbisAudioFloorOneScratch(f32){
                .y_values = &installed_floor_trial_y,
                .curves = &installed_floor_trial_curves,
            },
            plugin.dsp.VorbisAudioFloorOneStorage(f32){
                .encodings = &installed_floor_encodings,
                .y_values = &installed_floor_retained_y,
                .curves = &installed_floor_retained_curves,
            },
        );
    try std.testing.expectEqual(
        plugin.dsp.VorbisAudioResiduePreparationStorageRequirements{
            .floor_encodings = 1,
            .floor_y_values = 2,
            .floor_curve_values = 32,
            .residue_values = 32,
            .threshold_values = 32,
            .coupling_values = 32,
            .do_not_encode = 1,
        },
        try plugin.dsp.requiredVorbisAudioResiduePreparationStorage(
            installed_identification,
            installed_setup,
            installed_block_header,
        ),
    );
    var installed_preparation_fit_y: [2]u32 = undefined;
    var installed_preparation_fit_curves: [32]f32 = undefined;
    var installed_preparation_trial_encodings: [1]plugin.dsp.VorbisFloorPacketEncoding = undefined;
    var installed_preparation_trial_y: [2]u32 = undefined;
    var installed_preparation_trial_curves: [32]f32 = undefined;
    var installed_preparation_trial_residue: [32]f32 = undefined;
    var installed_preparation_trial_thresholds: [32]f32 = undefined;
    var installed_preparation_coupling_values: [32]f32 = undefined;
    var installed_preparation_coupling_thresholds: [32]f32 =
        undefined;
    var installed_preparation_trial_skips: [1]bool = undefined;
    var installed_preparation_encodings: [1]plugin.dsp.VorbisFloorPacketEncoding = undefined;
    var installed_preparation_y: [2]u32 = undefined;
    var installed_preparation_curves: [32]f32 = undefined;
    var installed_preparation_residue: [32]f32 = undefined;
    var installed_preparation_thresholds: [32]f32 = undefined;
    var installed_preparation_skips: [1]bool = undefined;
    const installed_preparation: plugin.dsp.VorbisAudioResiduePreparationPlan(f32) =
        try plugin.dsp.prepareVorbisAudioResidue(
            f32,
            installed_identification,
            installed_setup,
            installed_block_header,
            &.{&restored_spectrum},
            &.{&installed_psychoacoustic_floor},
            &.{&installed_noise_threshold},
            plugin.dsp.VorbisAudioResiduePreparationScratch(f32){
                .floor_fit_y_values = &installed_preparation_fit_y,
                .floor_fit_curves = &installed_preparation_fit_curves,
                .floor_encodings = &installed_preparation_trial_encodings,
                .floor_y_values = &installed_preparation_trial_y,
                .floor_curves = &installed_preparation_trial_curves,
                .residue_values = &installed_preparation_trial_residue,
                .noise_thresholds = &installed_preparation_trial_thresholds,
                .coupling_values = &installed_preparation_coupling_values,
                .coupling_thresholds = &installed_preparation_coupling_thresholds,
                .do_not_encode = &installed_preparation_trial_skips,
            },
            plugin.dsp.VorbisAudioResiduePreparationStorage(f32){
                .floor_encodings = &installed_preparation_encodings,
                .floor_y_values = &installed_preparation_y,
                .floor_curves = &installed_preparation_curves,
                .residue_values = &installed_preparation_residue,
                .noise_thresholds = &installed_preparation_thresholds,
                .do_not_encode = &installed_preparation_skips,
            },
        );
    try std.testing.expect(
        installed_preparation.floor_encodings[0].one.used,
    );
    try std.testing.expect(!installed_preparation.do_not_encode[0]);
    try std.testing.expectEqual(
        plugin.dsp.VorbisAudioResidueQuantizationStorageRequirements{
            .encodings = 1,
            .submap_results = 1,
            .do_not_encode = 1,
            .classifications = 4,
            .entries = 0,
            .partition_values = 4,
            .vector_values = 0,
            .classification_scratch = 4,
        },
        try plugin.dsp.requiredVorbisAudioResidueQuantizationStorage(
            installed_identification,
            installed_setup,
            installed_block_header,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        try plugin.dsp.requiredVorbisResidueQuantizationEntries(
            installed_setup,
            0,
            32,
            1,
        ),
    );
    var installed_quantization_partition: [4]f32 = undefined;
    var installed_quantization_vector: [0]f32 = .{};
    var installed_quantization_classification_scratch: [4]u8 =
        undefined;
    var installed_quantization_best: [4]u8 = undefined;
    var installed_quantization_trial_classifications: [4]u8 =
        undefined;
    var installed_quantization_trial_entries: [0]u32 = .{};
    var installed_quantization_trial_skips: [1]bool = undefined;
    var installed_quantization_encodings: [1]plugin.dsp.VorbisResidueEncoding = undefined;
    var installed_quantization_results: [1]plugin.dsp.VorbisAudioResidueSubmapResult = undefined;
    var installed_quantization_skips: [1]bool = undefined;
    var installed_quantization_classifications: [4]u8 = undefined;
    var installed_quantization_entries: [0]u32 = .{};
    const installed_quantization: plugin.dsp.VorbisAudioResidueQuantizationPlan =
        try plugin.dsp.quantizeVorbisAudioResiduesAdaptive(
            f32,
            installed_identification,
            installed_setup,
            installed_block_header,
            installed_preparation.residue_values,
            installed_preparation.noise_thresholds,
            installed_preparation.do_not_encode,
            plugin.dsp.VorbisPacketBitBudget{
                .packet_index = 0,
                .nominal_bits = installed_preparation.fixed_packet_bits + 4,
                .target_bits = installed_preparation.fixed_packet_bits + 4,
                .reservoir_balance_before = 0,
            },
            installed_preparation.fixed_packet_bits,
            &.{1},
            plugin.dsp.VorbisAudioResidueQuantizationConfig{},
            plugin.dsp.VorbisAudioResidueQuantizationScratch(f32){
                .partition = &installed_quantization_partition,
                .vector = &installed_quantization_vector,
                .classifications = &installed_quantization_classification_scratch,
                .best_classifications = &installed_quantization_best,
                .output_classifications = &installed_quantization_trial_classifications,
                .entries = &installed_quantization_trial_entries,
                .do_not_encode = &installed_quantization_trial_skips,
            },
            plugin.dsp.VorbisAudioResidueQuantizationStorage{
                .encodings = &installed_quantization_encodings,
                .submap_results = &installed_quantization_results,
                .do_not_encode = &installed_quantization_skips,
                .classifications = &installed_quantization_classifications,
                .entries = &installed_quantization_entries,
            },
        );
    try std.testing.expectEqual(
        @as(u32, 4),
        installed_quantization.submap_results[0].encoded_bits,
    );
    var installed_trial_sequence =
        try plugin.dsp.VorbisPcmPacketSequence.init(
            plugin.dsp.VorbisPcmPacketSequenceConfig{
                .rate_control = .{
                    .target_bitrate = 48_000,
                    .reservoir_capacity_bits = 1_024,
                },
            },
            false,
        );
    _ = try installed_trial_sequence.prime(
        f32,
        &.{&synthesized_block},
        installed_identification,
    );
    const installed_encoding_plan =
        try installed_trial_sequence.planFinish(
            installed_identification,
            installed_setup,
            0,
        );
    try std.testing.expectEqualDeep(
        installed_frame_analysis.frame,
        installed_encoding_plan.frame,
    );
    try std.testing.expectEqual(
        plugin.dsp.VorbisPcmPacketEncodingStorageRequirements{
            .preparation = .{
                .floor_encodings = 1,
                .floor_y_values = 2,
                .floor_curve_values = 32,
                .residue_values = 32,
                .threshold_values = 32,
                .coupling_values = 32,
                .do_not_encode = 1,
            },
            .quantization = .{
                .encodings = 1,
                .submap_results = 1,
                .do_not_encode = 1,
                .classifications = 4,
                .entries = 0,
                .partition_values = 4,
                .vector_values = 0,
                .classification_scratch = 4,
            },
        },
        try plugin.dsp.requiredVorbisPcmPacketEncodingStorage(
            installed_identification,
            installed_setup,
            installed_encoding_plan.frame,
        ),
    );
    var installed_trial_retained_floor_encodings: [1]plugin.dsp.VorbisFloorPacketEncoding = undefined;
    var installed_trial_retained_floor_y: [2]u32 = undefined;
    var installed_trial_retained_floor_curves: [32]f32 = undefined;
    var installed_trial_retained_residue: [32]f32 = undefined;
    var installed_trial_retained_thresholds: [32]f32 = undefined;
    var installed_trial_retained_preparation_skips: [1]bool =
        undefined;
    var installed_trial_retained_residue_encodings: [1]plugin.dsp.VorbisResidueEncoding = undefined;
    var installed_trial_retained_results: [1]plugin.dsp.VorbisAudioResidueSubmapResult = undefined;
    var installed_trial_retained_quantization_skips: [1]bool =
        undefined;
    var installed_trial_retained_classifications: [4]u8 = undefined;
    var installed_trial_retained_entries: [0]u32 = .{};
    var installed_trial_packet: [32]u8 = undefined;
    const installed_trial_sequence_before = installed_trial_sequence;
    const installed_encoding_trial: plugin.dsp.VorbisPcmPacketEncodingTrial(f32) =
        try plugin.dsp.encodeVorbisPcmPacketTrial(
            f32,
            &installed_trial_sequence,
            installed_identification,
            installed_setup,
            installed_encoding_plan,
            installed_frame_analysis,
            &.{1},
            plugin.dsp.VorbisAudioResidueQuantizationConfig{},
            &installed_trial_packet,
            plugin.dsp.VorbisPcmPacketEncodingScratch(f32){
                .preparation = .{
                    .floor_fit_y_values = &installed_preparation_fit_y,
                    .floor_fit_curves = &installed_preparation_fit_curves,
                    .floor_encodings = &installed_preparation_trial_encodings,
                    .floor_y_values = &installed_preparation_trial_y,
                    .floor_curves = &installed_preparation_trial_curves,
                    .residue_values = &installed_preparation_trial_residue,
                    .noise_thresholds = &installed_preparation_trial_thresholds,
                    .coupling_values = &installed_preparation_coupling_values,
                    .coupling_thresholds = &installed_preparation_coupling_thresholds,
                    .do_not_encode = &installed_preparation_trial_skips,
                },
                .preparation_storage = .{
                    .floor_encodings = &installed_preparation_encodings,
                    .floor_y_values = &installed_preparation_y,
                    .floor_curves = &installed_preparation_curves,
                    .residue_values = &installed_preparation_residue,
                    .noise_thresholds = &installed_preparation_thresholds,
                    .do_not_encode = &installed_preparation_skips,
                },
                .quantization = .{
                    .partition = &installed_quantization_partition,
                    .vector = &installed_quantization_vector,
                    .classifications = &installed_quantization_classification_scratch,
                    .best_classifications = &installed_quantization_best,
                    .output_classifications = &installed_quantization_trial_classifications,
                    .entries = &installed_quantization_trial_entries,
                    .do_not_encode = &installed_quantization_trial_skips,
                },
                .quantization_storage = .{
                    .encodings = &installed_quantization_encodings,
                    .submap_results = &installed_quantization_results,
                    .do_not_encode = &installed_quantization_skips,
                    .classifications = &installed_quantization_classifications,
                    .entries = &installed_quantization_entries,
                },
            },
            plugin.dsp.VorbisPcmPacketEncodingStorage(f32){
                .preparation = .{
                    .floor_encodings = &installed_trial_retained_floor_encodings,
                    .floor_y_values = &installed_trial_retained_floor_y,
                    .floor_curves = &installed_trial_retained_floor_curves,
                    .residue_values = &installed_trial_retained_residue,
                    .noise_thresholds = &installed_trial_retained_thresholds,
                    .do_not_encode = &installed_trial_retained_preparation_skips,
                },
                .quantization = .{
                    .encodings = &installed_trial_retained_residue_encodings,
                    .submap_results = &installed_trial_retained_results,
                    .do_not_encode = &installed_trial_retained_quantization_skips,
                    .classifications = &installed_trial_retained_classifications,
                    .entries = &installed_trial_retained_entries,
                },
            },
        );
    try std.testing.expectEqualDeep(
        installed_trial_sequence_before,
        installed_trial_sequence,
    );
    try std.testing.expectEqual(
        installed_encoding_trial.packet.bit_count,
        installed_encoding_trial.commit.rate.actual_bits,
    );
    try std.testing.expectEqual(
        @intFromPtr(installed_trial_retained_floor_encodings[0..].ptr),
        @intFromPtr(
            installed_encoding_trial.preparation.floor_encodings.ptr,
        ),
    );
    try std.testing.expect(installed_floor_plan.encodings[0].one.used);
    try std.testing.expectEqual(
        @as(usize, 32),
        installed_floor_plan.coefficient_count,
    );
    var installed_floor_y: [2]u32 = undefined;
    const installed_floor_fit: plugin.dsp.VorbisFloorOneFit =
        try plugin.dsp.fitVorbisFloorOne(
            f32,
            installed_setup,
            0,
            &([_]f32{0.25} ** 32),
            &installed_floor_y,
        );
    try std.testing.expect(installed_floor_fit.encoding.used);
    var installed_floor_curve: [32]f32 = undefined;
    try plugin.dsp.synthesizeVorbisFloorOne(
        f32,
        installed_floor.one,
        .{
            .used = true,
            .value_count = 2,
        },
        installed_floor_fit.encoding.y_values,
        &installed_floor_curve,
    );
    var installed_normalized: [32]f32 = undefined;
    var installed_spectrum: [32]f32 = undefined;
    for (&installed_spectrum, installed_floor_curve) |
        *value,
        floor_value,
    | {
        value.* = 2 * floor_value;
    }
    try plugin.dsp.normalizeVorbisResidue(
        f32,
        &installed_spectrum,
        &installed_floor_curve,
        &installed_normalized,
    );
    for (installed_normalized) |value| {
        try std.testing.expectApproxEqAbs(
            @as(f32, 2),
            value,
            0.000_01,
        );
    }
    const installed_thresholds = [_]f32{0.1} ** 32;
    var installed_normalized_thresholds: [32]f32 = undefined;
    try plugin.dsp.normalizeVorbisNoiseThresholds(
        f32,
        &installed_thresholds,
        &installed_floor_curve,
        &installed_normalized_thresholds,
    );
    var threshold_mapping = mapping;
    threshold_mapping.coupling_step_count = 1;
    threshold_mapping.coupling_steps[0] = .{
        .magnitude = 0,
        .angle = 1,
    };
    const threshold_source_first = [_]f32{ 1, 2 };
    const threshold_source_second = [_]f32{ 0.5, 1 };
    const threshold_sources = [_][]const f32{
        &threshold_source_first,
        &threshold_source_second,
    };
    var threshold_first = [_]f32{ 0.2, 0.2 };
    var threshold_second = [_]f32{ 0.4, 0.4 };
    const threshold_channels = [_][]f32{
        &threshold_first,
        &threshold_second,
    };
    var threshold_value_scratch: [4]f32 = undefined;
    var threshold_bound_scratch: [4]f32 = undefined;
    try plugin.dsp.forwardCoupleVorbisNoiseThresholds(
        f32,
        threshold_mapping,
        &threshold_sources,
        &threshold_channels,
        &threshold_value_scratch,
        &threshold_bound_scratch,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.1),
        threshold_first[0],
        0.000_001,
    );
    const installed_residue_requirements =
        try plugin.dsp.requiredVorbisResidueQuantizationScratch(
            installed_setup,
            0,
            32,
            1,
        );
    try std.testing.expectEqual(
        plugin.dsp.VorbisResidueQuantizationScratchRequirements{
            .partition_values = 4,
            .vector_values = 0,
            .classifications = 4,
        },
        installed_residue_requirements,
    );
    var installed_residue_partition: [4]f32 = undefined;
    var installed_residue_vector: [0]f32 = .{};
    var installed_residue_classification_scratch: [4]u8 = undefined;
    var installed_residue_classifications: [4]u8 = undefined;
    var installed_residue_entries: [0]u32 = .{};
    const installed_residue_scratch =
        plugin.dsp.VorbisResidueQuantizationScratch(f32){
            .partition = &installed_residue_partition,
            .vector = &installed_residue_vector,
            .classifications = &installed_residue_classification_scratch,
        };
    const installed_residue_input = [_]f32{0} ** 32;
    const installed_residue_quantization =
        try plugin.dsp.quantizeVorbisResidue(
            f32,
            installed_setup,
            0,
            &.{false},
            &.{&installed_residue_input},
            installed_residue_scratch,
            &installed_residue_classifications,
            &installed_residue_entries,
        );
    try std.testing.expectEqual(
        @as(usize, 4),
        installed_residue_quantization.encoding.classifications.len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        installed_residue_quantization.encoding.entries.len,
    );
    try std.testing.expectEqual(
        @as(f64, 0),
        installed_residue_quantization.squared_error,
    );
    var installed_adaptive_best: [4]u8 = undefined;
    const installed_residue_threshold = [_]f32{0.1} ** 32;
    const installed_adaptive_quantization: plugin.dsp.VorbisAdaptiveResidueQuantization =
        try plugin.dsp.quantizeVorbisResidueAdaptive(
            f32,
            installed_setup,
            0,
            &.{false},
            &.{&installed_residue_input},
            &.{&installed_residue_threshold},
            plugin.dsp.VorbisAdaptiveResidueConfig{
                .target_bits = installed_residue_bit_budgets[0],
            },
            plugin.dsp.VorbisAdaptiveResidueScratch(f32){
                .partition = &installed_residue_partition,
                .vector = &installed_residue_vector,
                .classifications = &installed_residue_classification_scratch,
                .best_classifications = &installed_adaptive_best,
            },
            &installed_residue_classifications,
            &installed_residue_entries,
        );
    try std.testing.expect(installed_adaptive_quantization.budget_met);
    try std.testing.expectEqual(
        @as(f64, 0),
        installed_adaptive_quantization.weighted_squared_error,
    );
    const quantizer_entries = [_]plugin.dsp.VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const quantizer_codebook = plugin.dsp.VorbisCodebook{
        .dimensions = 1,
        .entries = 2,
        .entry_offset = 0,
        .active_entry_count = 2,
        .tree_node_count = 1,
        .lookup_type = 2,
        .delta_value = 1,
        .multiplicand_count = 2,
    };
    const quantizer_node = plugin.dsp.VorbisHuffmanNode{
        .branches = .{ 0x8000_0000, 0x8000_0001 },
    };
    var quantizer_setup = installed_setup;
    quantizer_setup.codebooks = &.{quantizer_codebook};
    quantizer_setup.codebook_entries = &quantizer_entries;
    quantizer_setup.huffman_nodes = &.{quantizer_node};
    quantizer_setup.codebook_multiplicands = &.{ 0, 1 };
    const quantized = try plugin.dsp.quantizeVorbisVector(
        f64,
        quantizer_setup,
        0,
        &.{0.9},
    );
    try std.testing.expectEqual(@as(u32, 1), quantized.entry);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.01),
        quantized.squared_error,
        1e-12,
    );
    var quantized_entries: [2]u32 = undefined;
    const quantized_batch = try plugin.dsp.quantizeVorbisVectors(
        f32,
        quantizer_setup,
        0,
        &.{ 0.1, 0.9 },
        &quantized_entries,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0, 1 },
        quantized_batch.entries,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.02),
        quantized_batch.squared_error,
        1e-6,
    );
    var installed_setup_packet: [256]u8 = undefined;
    const installed_setup_bytes = try plugin.dsp.encodeVorbisSetupPacket(
        &installed_setup_packet,
        installed_setup,
        1,
    );
    try std.testing.expectEqual(
        installed_setup_bytes.len,
        try plugin.dsp.requiredVorbisSetupPacketBytes(
            installed_setup,
            1,
        ),
    );
    try std.testing.expectEqualDeep(
        installed_setup.summary,
        try plugin.dsp.validateVorbisSetup(
            installed_setup_bytes,
            1,
        ),
    );
    const installed_floor_encoding =
        [_]plugin.dsp.VorbisFloorPacketEncoding{
            .{ .one = .{
                .used = true,
                .y_values = &.{ 0, 0 },
            } },
        };
    const installed_residue_encoding =
        [_]plugin.dsp.VorbisResidueEncoding{
            .{
                .do_not_encode = &.{false},
                .classifications = &.{ 0, 0, 0, 0 },
                .entries = &.{},
            },
        };
    const installed_audio_encoding =
        plugin.dsp.VorbisAudioPacketEncoding{
            .mode_number = 0,
            .floors = &installed_floor_encoding,
            .residues = &installed_residue_encoding,
        };
    var installed_audio_skips: [1]bool = undefined;
    const installed_fixed_cost: plugin.dsp.VorbisAudioPacketFixedCost =
        try plugin.dsp.measureVorbisAudioPacketFixedCost(
            installed_identification,
            installed_setup,
            plugin.dsp.VorbisAudioPacketPrefixEncoding{
                .mode_number = 0,
                .floors = &installed_floor_encoding,
            },
            &installed_audio_skips,
        );
    try std.testing.expect(!installed_fixed_cost.do_not_encode[0]);
    var installed_audio_packet: [32]u8 = undefined;
    const installed_audio_bytes =
        try plugin.dsp.encodeVorbisAudioPacket(
            &installed_audio_packet,
            installed_identification,
            installed_setup,
            installed_audio_encoding,
        );
    try std.testing.expectEqual(
        installed_audio_bytes.bytes.len,
        try plugin.dsp.requiredVorbisAudioPacketBytes(
            installed_identification,
            installed_setup,
            installed_audio_encoding,
        ),
    );
    try std.testing.expectEqual(
        installed_audio_bytes.bit_count,
        installed_audio_bytes.header.payload_bit_offset + 21,
    );
    try std.testing.expect(
        installed_fixed_cost.bit_count <
            installed_audio_bytes.bit_count,
    );
    const installed_header = try plugin.dsp.parseVorbisAudioPacketHeader(
        &.{0},
        installed_identification,
        installed_setup,
    );
    const installed_requirements =
        try plugin.dsp.requiredVorbisAudioPacketScratch(
            installed_identification,
            installed_setup,
            installed_header,
        );
    try std.testing.expectEqual(
        @as(usize, 32),
        installed_requirements.spectrum_values,
    );
    var installed_spectra: [32]f32 = undefined;
    var installed_floors: [32]f32 = undefined;
    var installed_coupling: [32]f32 = undefined;
    var installed_time: [64]f32 = undefined;
    var installed_classifications: [4]u8 = undefined;
    var installed_output = [_]f32{99} ** 64;
    const installed_outputs = [_][]f32{&installed_output};
    var installed_decoder =
        plugin.dsp.VorbisAudioPacketDecoder(f32, 1, 64, 64).init();
    const installed_result = try installed_decoder.decode(
        &.{0},
        installed_identification,
        installed_setup,
        &installed_outputs,
        .{
            .spectra = &installed_spectra,
            .floor_curves = &installed_floors,
            .coupling = &installed_coupling,
            .time = &installed_time,
            .classifications = &installed_classifications,
        },
    );
    try std.testing.expect(!installed_result.truncated);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 64),
        &installed_output,
    );
    var granules = plugin.dsp.VorbisGranuleTracker{};
    const granule_range = try granules.trim(32, 28, true);
    try std.testing.expectEqual(@as(usize, 0), granule_range.source_start);
    try std.testing.expectEqual(@as(usize, 28), granule_range.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), granule_range.pcm_start);

    var installed_stream =
        plugin.dsp.VorbisPcmStreamDecoder(f32, 1, 64, 64).init();
    var installed_stream_windowed: [64]f32 = undefined;
    const installed_empty_outputs = [_][]f32{&empty_overlap_output};
    _ = try installed_stream.decode(
        .{
            .bytes = &.{0},
            .granule_position = std.math.maxInt(u64),
            .beginning = false,
            .end = false,
        },
        installed_identification,
        installed_setup,
        &installed_empty_outputs,
        .{
            .packet = .{
                .spectra = &installed_spectra,
                .floor_curves = &installed_floors,
                .coupling = &installed_coupling,
                .time = &installed_time,
                .classifications = &installed_classifications,
            },
            .windowed = &installed_stream_windowed,
        },
    );
    const installed_stream_outputs =
        [_][]f32{installed_output[0..32]};
    const installed_stream_result = try installed_stream.decode(
        .{
            .bytes = &.{0},
            .granule_position = 32,
            .beginning = false,
            .end = true,
        },
        installed_identification,
        installed_setup,
        &installed_stream_outputs,
        .{
            .packet = .{
                .spectra = &installed_spectra,
                .floor_curves = &installed_floors,
                .coupling = &installed_coupling,
                .time = &installed_time,
                .classifications = &installed_classifications,
            },
            .windowed = &installed_stream_windowed,
        },
    );
    try std.testing.expectEqual(
        @as(usize, 32),
        installed_stream_result.sample_count,
    );
    var installed_pcm_seek = plugin.dsp.VorbisPcmSeekCursor.init(12);
    const installed_pcm_range =
        try installed_pcm_seek.select(installed_stream_result);
    try std.testing.expectEqual(
        @as(usize, 12),
        installed_pcm_range.source_start,
    );
    try std.testing.expectEqual(
        @as(usize, 20),
        installed_pcm_range.sample_count,
    );
}

test "installed package exposes validated IR editor snapshots" {
    const snapshot = plugin.gui_ir_editor.Snapshot{
        .import = .{
            .status = .ready,
            .entry_point = .picker,
            .path_count = 1,
            .completed_units = 4,
            .total_units = 4,
            .generation = 1,
            .cancellation_pending = false,
        },
        .sample_rate = 48_000,
        .channels = 1,
        .sample_frames = 4,
        .decoded_frames = 4,
        .original_frames = 4,
        .original_peak = 0.5,
        .edited_peak = 0.5,
        .edited = false,
    };
    try snapshot.validate(4);
    try std.testing.expect(snapshot.valid(4));

    var malformed = snapshot;
    malformed.original_frames = 3;
    try std.testing.expect(!malformed.valid(4));
}

test "installed package exposes bounded audio handoff metadata" {
    const sample = plugin.gui_audio_sample_store.Metadata{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 2,
        .frames = 32,
    };
    try sample.validate(32);
    try std.testing.expect(sample.valid(32));

    const impulse = plugin.gui_ir_convolution.Metadata{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 64,
    };
    try impulse.validate(64);
    try std.testing.expect(impulse.valid(64));

    const Convolver = plugin.dsp.PartitionedConvolver(16, 8);
    var convolver = Convolver.initWithOptions(
        48_000,
        plugin.dsp.ConvolutionOptions{
            .latency = plugin.dsp.ConvolutionLatencyMode.zero,
            .routing = plugin.dsp.ConvolutionRouting.mono,
        },
    );
    try std.testing.expectEqual(@as(usize, 0), convolver.latencySamples());
    try convolver.begin(.{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 1,
    });
    try convolver.write(1, 0, &.{1.0});
    try convolver.commit(1);
    try std.testing.expect(convolver.adoptPending());
    try std.testing.expectEqual(
        @as([2]f32, .{ 0.5, 0.5 }),
        convolver.processFrame(1.0, 0.0),
    );

    const Queue = plugin.dsp.ConvolutionPreparationQueue(16, 2);
    var queue = Queue{};
    try queue.submit(
        .{
            .generation = 2,
            .sample_rate = 48_000,
            .channels = 1,
            .frames = 1,
        },
        &.{0.25},
    );
    try std.testing.expectEqual(
        @as(?u64, 2),
        try queue.prepareNext(8, &convolver),
    );
    try std.testing.expect(convolver.adoptPending());
}

test "installed package exposes allocation-free ID3 metadata versions" {
    var title_payload_storage: [64]u8 = undefined;
    const title_payload = try plugin.dsp.encodeId3Utf8TextPayload(
        &title_payload_storage,
        "Installed title",
    );
    const frames = [_]plugin.dsp.Id3Frame{
        .{
            .id = plugin.dsp.id3.title,
            .payload = title_payload,
            .unsynchronise = true,
        },
        .{
            .id = .{ 'X', 'B', 'I', 'N' },
            .payload = &.{ 0xff, 0xe1 },
            .unsynchronise = true,
            .grouping_identity = 7,
        },
    };
    var tag_storage: [160]u8 = undefined;
    const options = plugin.dsp.Id3EncodeOptions{
        .footer = true,
        .padding_bytes = 4,
    };
    const encoded = try plugin.dsp.encodeId3(
        &tag_storage,
        &frames,
        options,
    );
    try std.testing.expectEqual(
        encoded.len,
        try plugin.dsp.requiredId3Bytes(&frames, options),
    );

    const view = try plugin.dsp.Id3View.init(encoded);
    try std.testing.expect(view.header.unsynchronised);
    try std.testing.expect(view.header.footer);
    var iterator: plugin.dsp.Id3Iterator = view.iterator();
    var decoded_storage: [64]u8 = undefined;
    const decoded_title =
        try (try iterator.next()).?.decode(&decoded_storage);
    try std.testing.expectEqualStrings(
        "Installed title",
        (try decoded_title.text()).value,
    );
    const decoded_binary =
        try (try iterator.next()).?.decode(&decoded_storage);
    try std.testing.expectEqual(
        @as(?u8, 7),
        decoded_binary.grouping_identity,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xff, 0xe1 },
        decoded_binary.payload,
    );
    try std.testing.expect((try iterator.next()) == null);

    var v23_payload_storage: [32]u8 = undefined;
    const v23_payload = try plugin.dsp.encodeId3V23TextPayload(
        &v23_payload_storage,
        .latin1,
        "Installed v2.3",
    );
    const v23_frames = [_]plugin.dsp.Id3V23Frame{
        .{
            .id = plugin.dsp.id3.title,
            .payload = v23_payload,
        },
    };
    const v23_options = plugin.dsp.Id3V23EncodeOptions{
        .extended_header = true,
        .padding_bytes = 2,
    };
    const encoded_v23 = try plugin.dsp.encodeId3V23(
        &tag_storage,
        &v23_frames,
        v23_options,
    );
    try std.testing.expectEqual(
        encoded_v23.len,
        try plugin.dsp.requiredId3V23Bytes(
            &v23_frames,
            v23_options,
        ),
    );
    const v23_view = try plugin.dsp.Id3V23View.init(encoded_v23, &.{});
    var v23_iterator: plugin.dsp.Id3V23Iterator = v23_view.iterator();
    try std.testing.expectEqualStrings(
        "Installed v2.3",
        (try (try v23_iterator.next()).?.text()).value,
    );

    var v1_storage: [128]u8 = undefined;
    _ = try plugin.dsp.encodeId3V1(&v1_storage, plugin.dsp.Id3V1Tag{
        .title = "Installed v1.1",
        .track_number = 3,
    });
    const v1_view = try plugin.dsp.Id3V1View.init(&v1_storage);
    try std.testing.expectEqualStrings("Installed v1.1", v1_view.title);
    try std.testing.expectEqual(@as(?u8, 3), v1_view.track_number);
}

test "installed package exposes bounded MP3 framing and seeking" {
    var public_encoder = try plugin.dsp.Mp3FrameEncoder.init(
        plugin.dsp.Mp3EncoderConfig{
            .channel_mode = .mono,
            .crc_present = true,
        },
    );
    var generated: [2 * plugin.dsp.maximumMp3EncodedFrameBytes]u8 = undefined;
    var generated_length: usize = 0;
    for (0..2) |_| {
        const frame_bytes = try public_encoder.encodeSilentFrame(
            generated[generated_length..],
        );
        generated_length += frame_bytes.len;
    }
    const generated_summary = try plugin.dsp.Mp3Stream.summarize(
        generated[0..generated_length],
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        generated_summary.frame_count,
    );
    var generated_stream = try plugin.dsp.Mp3Stream.init(
        generated[0..generated_length],
    );
    var generated_decoder = plugin.dsp.Mp3FrameDecoder{};
    while (try generated_stream.next()) |frame| {
        try std.testing.expectEqual(
            @as(?bool, true),
            try frame.crcValid(),
        );
        const pcm = try generated_decoder.decode(frame);
        try std.testing.expectEqual(@as(u2, 1), pcm.channel_count);
        for (pcm.channels[0]) |sample|
            try std.testing.expectEqual(@as(f32, 0), sample);
    }

    var quantized_encoder = try plugin.dsp.Mp3FrameEncoder.init(
        .{ .channel_mode = .mono },
    );
    var quantized_frame = plugin.dsp.Mp3QuantizedEncoderFrame{};
    quantized_frame.granules[0][0].description = .{
        .big_values = 1,
        .global_gain = 210,
        .table_select = @splat(1),
        .region0_count = 7,
        .region1_count = 5,
    };
    quantized_frame.granules[0][0].spectrum[0] = 1;
    quantized_frame.granules[0][0].spectrum[1] = -1;
    var quantized_storage: [plugin.dsp.maximumMp3EncodedFrameBytes]u8 = undefined;
    const quantized_bytes = try quantized_encoder.encodeQuantizedFrame(
        &quantized_frame,
        &quantized_storage,
    );
    var quantized_decoder = plugin.dsp.Mp3FrameDecoder{};
    const quantized_pcm = try quantized_decoder.decode(
        try plugin.dsp.Mp3Frame.parse(quantized_bytes, 0),
    );
    var quantized_nonzero = false;
    for (quantized_pcm.channels[0]) |sample|
        quantized_nonzero = quantized_nonzero or sample != 0;
    try std.testing.expect(quantized_nonzero);

    var encoded: [834]u8 = undefined;
    @memset(&encoded, 0);
    const header = [_]u8{ 0xff, 0xfb, 0x90, 0x00 };
    @memcpy(encoded[0..4], &header);
    @memcpy(encoded[417..421], &header);

    const parsed = try plugin.dsp.Mp3Header.parse(&header);
    try std.testing.expectEqual(
        plugin.dsp.Mp3Version.mpeg1,
        parsed.version,
    );
    try std.testing.expectEqual(@as(usize, 417), parsed.frameBytes());
    var public_spectrum: [576]i32 = @splat(0);
    public_spectrum[0] = 1;
    public_spectrum[1] = -1;
    var public_main_storage: [8]u8 = undefined;
    const public_huffman: plugin.dsp.Mp3EncodedHuffmanChannel =
        try plugin.dsp.encodeMp3HuffmanChannel(
            parsed,
            .{
                .big_values = 1,
                .table_select = @splat(1),
                .region0_count = 7,
                .region1_count = 5,
            },
            &public_spectrum,
            &public_main_storage,
        );
    var public_side = plugin.dsp.Mp3SideInformation{
        .channel_count = 2,
        .granule_count = 2,
        .main_data_begin = 0,
        .private_bits = 0,
        .main_data_bits = public_huffman.main_data.bit_count,
    };
    public_side.granules[0].channels[0] =
        public_huffman.description;
    var public_side_storage: [32]u8 = undefined;
    try std.testing.expectEqual(
        @as(usize, 32),
        (try plugin.dsp.encodeMp3SideInformation(
            parsed,
            public_side,
            &public_side_storage,
        )).len,
    );
    try std.testing.expectEqual(
        @as(?bool, null),
        try (try plugin.dsp.Mp3Frame.parse(&encoded, 0)).crcValid(),
    );

    var protected: [417]u8 = @splat(0);
    const protected_header = [_]u8{ 0xff, 0xfa, 0x90, 0x00 };
    @memcpy(protected[0..4], &protected_header);
    for (protected[6..38], 0..) |*byte, index|
        byte.* = @intCast(index);
    protected[4] = 0x65;
    protected[5] = 0xe8;
    try std.testing.expectEqual(
        @as(?bool, true),
        try (try plugin.dsp.Mp3Frame.parse(&protected, 0)).crcValid(),
    );
    const protected_side: plugin.dsp.Mp3SideInformation =
        try (try plugin.dsp.Mp3Frame.parse(
            &protected,
            0,
        )).sideInformation();
    try std.testing.expectEqual(@as(u2, 2), protected_side.channel_count);
    try std.testing.expectEqual(@as(u2, 2), protected_side.granule_count);

    const Reservoir = plugin.dsp.Mp3MainDataReservoir(511);
    var reservoir = Reservoir{};
    var main_data_storage: [1]u8 = undefined;
    const installed_frame = try plugin.dsp.Mp3Frame.parse(&encoded, 0);
    const installed_side = try installed_frame.sideInformation();
    const main_data: plugin.dsp.Mp3MainData = try reservoir.assemble(
        installed_frame,
        &main_data_storage,
    );
    try std.testing.expectEqual(@as(u16, 0), main_data.bit_count);
    try std.testing.expectEqual(@as(usize, 0), main_data.bytes.len);
    const scale_factors: plugin.dsp.Mp3ScaleFactors =
        try plugin.dsp.decodeMp3ScaleFactors(
            parsed,
            installed_side,
            main_data,
        );
    try std.testing.expectEqual(
        @as(u2, 2),
        scale_factors.granule_count,
    );
    const scale_channel: plugin.dsp.Mp3ScaleFactorChannel =
        scale_factors.granules[0].channels[0];
    try std.testing.expectEqual(@as(u12, 0), scale_channel.part2_bits);
    const bands: plugin.dsp.Mp3ScaleFactorBands =
        try plugin.dsp.mp3ScaleFactorBands(parsed);
    try std.testing.expectEqual(@as(u16, 576), bands.long_starts[22]);
    try std.testing.expectEqual(
        [2]u16{ 4, 8 },
        try plugin.dsp.mp3HuffmanRegionEnds(parsed, .{}),
    );
    const spectrum: plugin.dsp.Mp3QuantizedSpectrum =
        try plugin.dsp.decodeMp3HuffmanChannel(
            parsed,
            installed_side.granules[0].channels[0],
            scale_channel,
            main_data,
        );
    try std.testing.expectEqual(@as(u10, 0), spectrum.decoded_lines);

    const pair_spectrum = try plugin.dsp.decodeMp3HuffmanChannel(
        parsed,
        plugin.dsp.Mp3GranuleChannel{
            .part2_3_length = 5,
            .big_values = 1,
            .table_select = .{ 1, 0, 0 },
        },
        plugin.dsp.Mp3ScaleFactorChannel{
            .huffman_bit_count = 5,
        },
        plugin.dsp.Mp3MainData{
            .bytes = &.{0x08},
            .bit_count = 5,
        },
    );
    try std.testing.expectEqualSlices(
        i32,
        &.{ 1, -1 },
        pair_spectrum.lines[0..2],
    );
    try std.testing.expectEqual(
        @as(u12, 5),
        pair_spectrum.huffman_bits_consumed,
    );
    const requantized: plugin.dsp.Mp3RequantizedSpectrum =
        try plugin.dsp.requantizeMp3Channel(
            parsed,
            plugin.dsp.Mp3GranuleChannel{
                .global_gain = 210,
            },
            plugin.dsp.Mp3ScaleFactorChannel{
                .value_count = 22,
            },
            pair_spectrum,
        );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1, -1 },
        requantized.lines[0..2],
    );
    const joint_header =
        try plugin.dsp.Mp3Header.parse(&.{ 0xff, 0xfb, 0x90, 0x60 });
    var stereo_input: [2]plugin.dsp.Mp3RequantizedSpectrum =
        @splat(.{});
    stereo_input[0].lines[0] = 2;
    stereo_input[1].lines[0] = 1;
    const stereo: plugin.dsp.Mp3StereoSpectrum =
        try plugin.dsp.processMp3Stereo(
            joint_header,
            @splat(.{}),
            @splat(.{ .value_count = 22 }),
            stereo_input,
        );
    try std.testing.expectApproxEqAbs(
        @as(f32, 3.0 / @sqrt(2.0)),
        stereo.channels[0].lines[0],
        1e-6,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0 / @sqrt(2.0)),
        stereo.channels[1].lines[0],
        1e-6,
    );
    var alias_input = stereo.channels[0];
    alias_input.lines[17] = 1;
    alias_input.lines[18] = 2;
    const alias_reduced = try plugin.dsp.reduceMp3Aliases(
        joint_header,
        .{},
        alias_input,
    );
    try std.testing.expect(alias_reduced.lines[17] != 1);
    try std.testing.expect(alias_reduced.lines[18] != 2);
    const alias_prepared =
        try plugin.dsp.prepareMp3AliasesForEncoding(
            joint_header,
            .{},
            alias_reduced,
        );
    try std.testing.expectApproxEqAbs(
        alias_input.lines[17],
        alias_prepared.lines[17],
        2e-6,
    );
    try std.testing.expectApproxEqAbs(
        alias_input.lines[18],
        alias_prepared.lines[18],
        2e-6,
    );

    var pcm_analysis = try plugin.dsp.Mp3EncoderAnalysis.init(
        .{ .channel_mode = .stereo },
    );
    var analysis_pcm = plugin.dsp.Mp3PcmFrame{
        .channel_count = 2,
        .sample_count = 1152,
    };
    analysis_pcm.channels[0][0] = 1;
    analysis_pcm.channels[1][1] = -1;
    const analyzed_frame: plugin.dsp.Mp3AnalyzedEncoderFrame =
        try pcm_analysis.analyze(
            @splat(@splat(.{})),
            analysis_pcm,
        );
    const analyzed_channel: plugin.dsp.Mp3AnalyzedEncoderChannel =
        analyzed_frame.granules[0][0];
    try std.testing.expectEqual(@as(u2, 2), analyzed_frame.channel_count);
    try std.testing.expectEqual(@as(u2, 2), analyzed_frame.granule_count);
    try std.testing.expect(std.math.isFinite(
        analyzed_channel.spectrum.lines[0],
    ));
    try std.testing.expectEqual(@as(u64, 1), pcm_analysis.frames_analyzed);
    const psychoacoustic_config =
        plugin.dsp.Mp3EncoderPsychoacousticConfig{};
    const psychoacoustic_model =
        plugin.dsp.Mp3EncoderPsychoacousticModel{
            .config = psychoacoustic_config,
        };
    const psychoacoustic: plugin.dsp.Mp3EncoderPsychoacousticChannel =
        try psychoacoustic_model.analyze(
            joint_header,
            analyzed_channel,
        );
    try std.testing.expectEqual(
        @as(u6, 22),
        psychoacoustic.band_count,
    );
    const joint_analyzed: plugin.dsp.Mp3AnalyzedEncoderFrame =
        try plugin.dsp.prepareMp3EncoderStereo(
            joint_header,
            analyzed_frame,
        );
    try std.testing.expect(std.math.isFinite(
        joint_analyzed.granules[0][0].spectrum.lines[0],
    ));
    var classifier = plugin.dsp.Mp3EncoderBlockClassifier{};
    const classified = try classifier.classify(
        joint_header,
        analysis_pcm,
    );
    try std.testing.expectEqual(
        plugin.dsp.Mp3GranuleChannel{},
        classified[0][0],
    );
    const automatic_quantized: plugin.dsp.Mp3QuantizedEncoderFrame =
        try plugin.dsp.Mp3EncoderQuantizer.quantize(
            joint_header,
            joint_analyzed,
        );
    try std.testing.expect(
        automatic_quantized.granules[0][0]
            .description.big_values <= 288,
    );
    var encoder_factors = plugin.dsp.Mp3EncoderScaleFactors{
        .value_count = 22,
    };
    encoder_factors.values[0] = 1;
    var scale_storage: [64]u8 = undefined;
    const encoded_factors: plugin.dsp.Mp3EncodedScaleFactors =
        try plugin.dsp.encodeMp3ScaleFactors(
            joint_header,
            .{ .scalefac_compress = 5 },
            0,
            0,
            0,
            .{},
            encoder_factors,
            &scale_storage,
        );
    try std.testing.expectEqual(
        @as(u16, 21),
        encoded_factors.main_data.bit_count,
    );
    var automatic_encoder = try plugin.dsp.Mp3PcmEncoder.init(
        .{ .channel_mode = .stereo },
    );
    var automatic_storage: [2048]u8 = undefined;
    const automatic_frame = try automatic_encoder.encode(
        analysis_pcm,
        &automatic_storage,
    );
    try std.testing.expect(automatic_frame.len > 4);
    automatic_encoder.reset();
    pcm_analysis.reset();

    var polyphase_analysis = plugin.dsp.Mp3PolyphaseAnalysis{};
    var analysis_granule = plugin.dsp.Mp3PcmGranule{};
    analysis_granule.samples[0] = 1;
    const analyzed_subbands =
        try polyphase_analysis.process(analysis_granule);
    var hybrid_analysis = plugin.dsp.Mp3HybridAnalysis{};
    const analyzed_spectrum = try hybrid_analysis.process(
        joint_header,
        .{},
        analyzed_subbands,
    );
    try std.testing.expect(std.math.isFinite(
        analyzed_spectrum.lines[0],
    ));
    polyphase_analysis.reset();
    hybrid_analysis.reset();

    var hybrid = plugin.dsp.Mp3HybridSynthesis{};
    const hybrid_samples: plugin.dsp.Mp3HybridSamples =
        try hybrid.process(joint_header, .{}, alias_reduced);
    try std.testing.expect(
        std.math.isFinite(hybrid_samples.time_slots[0][0]),
    );
    try std.testing.expect(hybrid_samples.time_slots[0][0] != 0);
    hybrid.reset();
    var polyphase = plugin.dsp.Mp3PolyphaseSynthesis{};
    const pcm: plugin.dsp.Mp3PcmGranule =
        try polyphase.process(hybrid_samples);
    var pcm_nonzero = false;
    for (pcm.samples) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        pcm_nonzero = pcm_nonzero or sample != 0;
    }
    try std.testing.expect(pcm_nonzero);
    polyphase.reset();
    var frame_decoder = plugin.dsp.Mp3FrameDecoder{};
    const decoded_frame: plugin.dsp.Mp3PcmFrame =
        try frame_decoder.decode(installed_frame);
    try std.testing.expectEqual(
        @as(u2, 2),
        decoded_frame.channel_count,
    );
    try std.testing.expectEqual(
        @as(u16, 1152),
        decoded_frame.sample_count,
    );
    try std.testing.expectEqual(
        @as(?plugin.dsp.Mp3DecoderFormat, .{
            .version = .mpeg1,
            .sample_rate = 44_100,
            .channel_count = 2,
        }),
        frame_decoder.format,
    );
    frame_decoder.reset();

    const summary = try plugin.dsp.Mp3Stream.summarize(&encoded);
    try std.testing.expectEqual(@as(u64, 2), summary.frame_count);
    try std.testing.expectEqual(@as(u64, 2304), summary.sample_count);
    const gapless_plan: plugin.dsp.Mp3GaplessPlan =
        try plugin.dsp.Mp3GaplessPlan.fromSummary(summary);
    try std.testing.expectEqual(@as(u64, 2304), gapless_plan.audible_samples);
    var stream_decoder =
        try plugin.dsp.Mp3StreamDecoder.init(summary);
    var decode_stream = try plugin.dsp.Mp3Stream.init(&encoded);
    while (try decode_stream.next()) |decode_frame| {
        const trimmed: plugin.dsp.Mp3TrimmedPcmFrame =
            try stream_decoder.decode(decode_frame);
        try std.testing.expectEqual(
            plugin.dsp.Mp3PcmRange{
                .start = 0,
                .length = 1152,
            },
            trimmed.audible,
        );
    }
    try stream_decoder.finish();

    var points: [2]plugin.dsp.Mp3SeekPoint = undefined;
    const index = try plugin.dsp.buildMp3SeekIndex(
        &encoded,
        1,
        &points,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        try plugin.dsp.requiredMp3SeekPoints(&encoded, 1),
    );
    try std.testing.expectEqual(
        index[1],
        try plugin.dsp.findMp3SeekPoint(index, 1152),
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "installed.mp3",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &encoded, 0);
    var frame_storage: [500]u8 = undefined;
    const file_summary = try plugin.dsp.Mp3FileReader.summarize(
        std.testing.io,
        file,
        &frame_storage,
    );
    try std.testing.expectEqual(@as(u64, 2), file_summary.frame_count);

    var free_encoded: [2 * 500]u8 = @splat(0);
    const free_header = [_]u8{ 0xff, 0xfb, 0x00, 0x00 };
    @memcpy(free_encoded[0..4], &free_header);
    @memcpy(free_encoded[500..504], &free_header);
    const free_parsed =
        try plugin.dsp.Mp3Header.parse(&free_header);
    try std.testing.expect(free_parsed.free_format);
    try std.testing.expectEqual(@as(usize, 0), free_parsed.frameBytes());
    const free_summary =
        try plugin.dsp.Mp3Stream.summarize(&free_encoded);
    try std.testing.expectEqual(@as(u64, 2), free_summary.frame_count);
    try std.testing.expect(
        plugin.dsp.maximumMp3FreeFormatFrameBytes >= 500,
    );
}

test "installed package exposes coherent audio import snapshots" {
    const snapshot = plugin.gui_audio_file_importer.Snapshot{
        .import = .{
            .status = .ready,
            .entry_point = .picker,
            .path_count = 1,
            .completed_units = 16,
            .total_units = 16,
            .generation = 1,
            .cancellation_pending = false,
        },
        .failure = .none,
        .sample_rate = 48_000,
        .channels = 2,
        .sample_frames = 8,
        .preview_points = 8,
        .decoded_frames = 8,
    };
    try snapshot.validate();
    try std.testing.expect(snapshot.valid());

    var malformed = snapshot;
    malformed.failure = .truncated;
    try std.testing.expect(!malformed.valid());
    try std.testing.expect(snapshot.import.valid());
}

test "installed package exposes file-backed audio writers" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    var wav_file = try temporary.dir.createFile(
        std.testing.io,
        "installed.wav",
        .{ .read = true },
    );
    defer wav_file.close(std.testing.io);
    const metadata = [_]plugin.dsp.AudioMetadataEntry{
        .{
            .id = plugin.dsp.audio_metadata.title,
            .value = "Installed consumer",
        },
        .{
            .id = plugin.dsp.audio_metadata.software,
            .value = "zig-vst3",
        },
    };
    const ixml_tracks = [_]plugin.dsp.IxmlTrack{.{
        .channel_index = 1,
        .interleave_index = 1,
        .name = "Mono mix",
        .function = "MIX",
    }};
    const ixml_sync_points = [_]plugin.dsp.IxmlSyncPoint{.{
        .kind = .relative,
        .function = "SLATE_GENERIC",
        .comment = "Camera A",
        .low = 240_000,
        .high = 0,
        .event_duration = 0,
    }};
    var ixml_document_storage: [4096]u8 = undefined;
    const ixml_document = try plugin.dsp.encodeIxmlMetadata(
        &ixml_document_storage,
        .{
            .ixml_version = "1.52",
            .project = "Installed",
            .scene = "1A",
            .take = "2",
            .circled = true,
            .speed = .{
                .timecode_rate = .{
                    .numerator = 30_000,
                    .denominator = 1_001,
                },
                .timecode_flag = .df,
                .file_sample_rate = 48_000,
                .audio_bit_depth = 24,
            },
            .loudness = plugin.dsp.IxmlLoudness{
                .value = -23,
                .max_true_peak_level = -1,
            },
            .history = plugin.dsp.IxmlHistory{
                .original_filename = "installed.wav",
                .parent_uid = "installed-parent",
            },
            .bext = plugin.dsp.IxmlBext{
                .description = "Portable metadata",
                .time_reference_low = 240_000,
                .version = "2.0",
            },
            .location = plugin.dsp.IxmlLocation{
                .name = "Stage A",
                .gps = plugin.dsp.IxmlLocationGps{
                    .latitude = 40.7128,
                    .longitude = -74.006,
                },
                .kind = "INTERIOR",
            },
            .user = plugin.dsp.IxmlUser{
                .sound_mixer_name = "Installed Mixer",
                .audio_recorder_model = "Fixture Recorder",
            },
            .file_set = .{
                .total_files = 1,
                .family_uid = "installed-family",
                .index = "A",
            },
            .sync_points = &ixml_sync_points,
            .tracks = &ixml_tracks,
        },
    );
    const adm_entries = [_]plugin.dsp.AdmChannelAllocationEntry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AT_00010001_01",
        .pack_ref = "AP_00010001",
    }};
    const riff_metadata = plugin.dsp.RiffMetadata{
        .broadcast = .{
            .description = "Installed consumer",
            .originator = "zig-vst3",
            .version = .version_2,
            .loudness = .{ .integrated = -2300 },
        },
        .ixml = ixml_document,
        .axml =
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <profileList>
        \\    <profile profileName="Production Profile"
        \\      profileVersion="1.0.0" profileLevel="1">ITU-R <![CDATA[BS.&<draft>]]></profile>
        \\  </profileList>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001"
        \\      rtime="00:00:00.00000" duration="48000S48000">
        \\      <gain>0.5</gain>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
        ,
        .channel_allocation = .{
            .num_tracks = 1,
            .entries = &adm_entries,
        },
        .info = &metadata,
    };
    const installed_adm_document = try riff_metadata.validateAdm();
    try std.testing.expectEqual(
        @as(usize, 2),
        installed_adm_document.declaration_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        installed_adm_document.profile_count,
    );
    var installed_profiles = installed_adm_document.profiles();
    const installed_profile = (try installed_profiles.next()).?;
    try std.testing.expectEqualStrings(
        "Production Profile",
        installed_profile.name,
    );
    try std.testing.expectEqualStrings(
        "ITU-R BS.&<draft>",
        installed_profile.reference,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        installed_adm_document.block_count,
    );
    var installed_blocks = installed_adm_document.blocks();
    const installed_block = (try installed_blocks.next()).?;
    try std.testing.expectEqual(
        plugin.dsp.AdmTimeFormat.fractional_samples,
        installed_block.duration.?.format,
    );
    try std.testing.expectEqual(
        @as(f64, 0.5),
        installed_block.gain.value,
    );
    try std.testing.expectEqual(
        plugin.dsp.AdmXmlCoordinate.azimuth,
        installed_block.positionSlice()[0].coordinate,
    );
    const advanced_adm = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioObject audioObjectID="AO_1001"/>
        \\  <tagList>
        \\    <tagGroup>
        \\      <tag class="delivery">immersive</tag>
        \\      <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\    </tagGroup>
        \\  </tagList>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <speakerLabel>M+000</speakerLabel>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041002">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041002_00000001">
        \\      <order>1</order>
        \\      <degree>-1</degree>
        \\      <normalization>N3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021003">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021003_00000001">
        \\      <matrix>
        \\        <coefficient gainVar="mix">AC_00010001</coefficient>
        \\      </matrix>
        \\    </audioBlockFormatMatrix>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051004" audioChannelFormatName="RightEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051004_00000001"/>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    try std.testing.expectEqual(@as(usize, 1), advanced_adm.tag_count);
    var advanced_tags: plugin.dsp.AdmXmlTagIterator =
        advanced_adm.tags();
    const advanced_tag: plugin.dsp.AdmXmlTag =
        (try advanced_tags.next()).?.tag;
    try std.testing.expectEqualStrings("immersive", advanced_tag.value);
    var advanced_blocks = advanced_adm.blocks();
    _ = (try advanced_blocks.next()).?;
    _ = (try advanced_blocks.next()).?;
    const matrix_block = (try advanced_blocks.next()).?;
    const coefficient: plugin.dsp.AdmXmlMatrixCoefficient =
        matrix_block.matrixCoefficientSlice()[0];
    try std.testing.expectEqualStrings(
        "mix",
        coefficient.gain_variable.?.value(),
    );
    const matrix_inputs = [_]plugin.dsp.AdmIdentifier{
        try plugin.dsp.AdmIdentifier.parse("AC_00010001"),
    };
    try std.testing.expectError(
        error.UnsupportedDynamicAdmMatrixCoefficient,
        plugin.dsp.AdmStaticMatrixMixer(f32).init(
            &matrix_block,
            &matrix_inputs,
        ),
    );
    var direct_blocks = advanced_adm.blocks();
    const direct_block = (try direct_blocks.next()).?;
    const speaker_labels = [_][]const u8{"M+000"};
    const speaker_router = try plugin.dsp.AdmDirectSpeakerRouter(f32).init(
        &direct_block,
        &speaker_labels,
    );
    const speaker_input = [_]f32{ 0.25, -0.5 };
    var speaker_output = [_]f32{ 0.0, 0.0 };
    const speaker_outputs = [_][]f32{&speaker_output};
    try speaker_router.mix(&speaker_input, &speaker_outputs);
    try std.testing.expectEqualDeep(
        speaker_input,
        speaker_output,
    );
    const speaker_layout = [_]plugin.dsp.AdmOutputSpeaker{.{
        .label = "M+000",
        .nominal_polar = plugin.dsp.AdmPolarPosition{
            .azimuth_degrees = 0.0,
            .elevation_degrees = 0.0,
        },
        .allocentric = plugin.dsp.AdmCartesianPosition{
            .x = 0.0,
            .y = 1.0,
        },
    }};
    const position_router =
        try plugin.dsp.AdmDirectSpeakerPositionRouter(f32).init(
            &direct_block,
            &speaker_layout,
            plugin.dsp.AdmDirectSpeakerRoutingContext{
                .screen_edges = plugin.dsp.AdmScreenEdges{
                    .left_azimuth_degrees = 30.0,
                    .right_azimuth_degrees = -30.0,
                    .bottom_elevation_degrees = -15.0,
                    .top_elevation_degrees = 15.0,
                },
            },
        );
    try std.testing.expectEqual(
        @as(u8, 0),
        position_router.route.output,
    );
    try std.testing.expectEqual(
        @as(f32, 0.25),
        try position_router.processSample(0.25),
    );
    const cartesian_panner =
        try plugin.dsp.AdmCartesianPointSourcePanner(f32).init(
            &speaker_layout,
        );
    var cartesian_gains: [speaker_layout.len]f32 = undefined;
    try cartesian_panner.calculateGains(
        plugin.dsp.AdmCartesianPosition{ .x = 0.0, .y = 0.0 },
        &cartesian_gains,
    );
    try std.testing.expectEqual(@as(f32, 1.0), cartesian_gains[0]);
    const polar_layout = [_]plugin.dsp.AdmOutputSpeaker{
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -1, .y = 1 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 1, .y = 1 },
        },
        .{
            .label = "M+000",
            .nominal_polar = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
            },
            .reproduction_polar = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 0, .y = 1 },
        },
        .{
            .label = "M+110",
            .nominal_polar = .{
                .azimuth_degrees = 110,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -1, .y = -1 },
        },
        .{
            .label = "M-110",
            .nominal_polar = .{
                .azimuth_degrees = -110,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 1, .y = -1 },
        },
    };
    const polar_panner =
        try plugin.dsp.AdmPolarPointSourcePanner(f32).init(
            &polar_layout,
        );
    var polar_gains: [polar_layout.len]f32 = undefined;
    try polar_panner.calculateGains(
        plugin.dsp.AdmPolarPosition{
            .azimuth_degrees = 0,
            .elevation_degrees = 0,
        },
        &polar_gains,
    );
    try std.testing.expectEqual(@as(f32, 1.0), polar_gains[2]);
    const polar_cartesian_panner =
        try plugin.dsp.AdmCartesianPointSourcePanner(f32).init(
            &polar_layout,
        );
    const object_context = plugin.dsp.AdmObjectRenderingContext{};
    const object_plan = try plugin.dsp.AdmObjectPointGainPlan(f32).init(
        &installed_block,
        &polar_layout,
        &polar_panner,
        &polar_cartesian_panner,
        object_context,
    );
    try std.testing.expectEqual(
        @as(f32, 0.5),
        object_plan.directGainSlice()[2],
    );
    try std.testing.expectEqual(
        @as(f32, 0.0),
        object_plan.diffuseGainSlice()[2],
    );
    var timed_blocks = [_]plugin.dsp.AdmXmlBlockFormat{
        installed_block,
        installed_block,
    };
    timed_blocks[1].identifier =
        try plugin.dsp.AdmIdentifier.parse("AB_00031001_00000002");
    timed_blocks[1].rtime =
        try plugin.dsp.AdmTimeValue.parse("48000S48000");
    timed_blocks[1].gain.value = 1.0;
    const object_timeline =
        try plugin.dsp.AdmObjectGainTimeline(f32, 2).init(
            &timed_blocks,
            &polar_layout,
            &polar_panner,
            &polar_cartesian_panner,
            object_context,
            48_000,
        );
    const timed_input = [_]f32{ 1.0, 1.0 };
    var timed_direct_storage: [polar_layout.len][timed_input.len]f32 =
        @splat(@splat(0.0));
    var timed_diffuse_storage: [polar_layout.len][timed_input.len]f32 =
        @splat(@splat(0.0));
    var timed_direct: [polar_layout.len][]f32 = undefined;
    var timed_diffuse: [polar_layout.len][]f32 = undefined;
    for (
        &timed_direct_storage,
        &timed_direct,
        &timed_diffuse_storage,
        &timed_diffuse,
    ) |*direct_samples, *direct_output, *diffuse_samples, *diffuse_output| {
        direct_output.* = direct_samples;
        diffuse_output.* = diffuse_samples;
    }
    try object_timeline.mix(
        48_000,
        &timed_input,
        &timed_direct,
        &timed_diffuse,
    );
    try std.testing.expectEqual(
        @as(f32, 0.5),
        timed_direct_storage[2][0],
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5 + 0.5 / 48_000.0),
        timed_direct_storage[2][1],
        0.000_001,
    );
    var diffuse_processor =
        try plugin.dsp.AdmObjectDiffuseProcessor(
            f32,
            polar_layout.len,
        ).init(&polar_layout);
    var timed_direct_inputs: [polar_layout.len][]const f32 = undefined;
    var timed_diffuse_inputs: [polar_layout.len][]const f32 = undefined;
    var rendered_storage: [polar_layout.len][timed_input.len]f32 =
        @splat(@splat(0.0));
    var rendered_outputs: [polar_layout.len][]f32 = undefined;
    for (
        &timed_direct_storage,
        &timed_direct_inputs,
        &timed_diffuse_storage,
        &timed_diffuse_inputs,
        &rendered_storage,
        &rendered_outputs,
    ) |
        *direct_samples,
        *direct_input,
        *diffuse_samples,
        *diffuse_input,
        *rendered_samples,
        *rendered_output,
    | {
        direct_input.* = direct_samples;
        diffuse_input.* = diffuse_samples;
        rendered_output.* = rendered_samples;
    }
    try diffuse_processor.process(
        &timed_direct_inputs,
        &timed_diffuse_inputs,
        &rendered_outputs,
    );
    try std.testing.expectEqual(
        plugin.dsp.adm_object_direct_delay_samples,
        diffuse_processor.latencySamples(),
    );
    try std.testing.expectEqual(
        @as(usize, 512),
        plugin.dsp.adm_object_diffuse_filter_length,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.0 },
        &rendered_storage[2],
    );
    var extent_gain_storage: [
        plugin.dsp.adm_polar_extent_spreading_direction_count *
            polar_layout.len
    ]f32 = undefined;
    const extent_panner = try plugin.dsp.AdmPolarExtentPanner(f32).init(
        &polar_panner,
        &extent_gain_storage,
    );
    var installed_extent_block = installed_block;
    installed_extent_block.width = 20.0;
    installed_extent_block.height = 10.0;
    installed_extent_block.depth = 0.25;
    const extent_plan =
        try plugin.dsp.AdmObjectPolarExtentGainPlan(f32).initPolarExtent(
            &installed_extent_block,
            &polar_layout,
            &extent_panner,
            object_context,
        );
    var extent_power: f32 = 0.0;
    for (extent_plan.directGainSlice()) |gain| {
        extent_power += gain * gain;
    }
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        extent_power,
        0.000_001,
    );
    const cartesian_extent_panner =
        try plugin.dsp.AdmCartesianExtentPanner(f32).init(
            &polar_cartesian_panner,
        );
    var cartesian_extent_gains: [polar_layout.len]f32 = undefined;
    try cartesian_extent_panner.calculateGains(
        .{ .x = 0.25, .y = 0.0, .z = 0.0 },
        0.4,
        0.2,
        0.1,
        &cartesian_extent_gains,
    );
    var cartesian_extent_power: f32 = 0.0;
    for (cartesian_extent_gains) |gain| {
        cartesian_extent_power += gain * gain;
    }
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        cartesian_extent_power,
        0.000_001,
    );
    const cartesian_extent_adm = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031002">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031002_00000001">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X">0.25</position>
        \\      <position coordinate="Y">0</position>
        \\      <position coordinate="Z">0</position>
        \\      <width>0.4</width>
        \\      <height>0.2</height>
        \\      <depth>0.1</depth>
        \\      <gain>0.5</gain>
        \\      <zoneExclusion>
        \\        <zone minAzimuth="0" maxAzimuth="0" minElevation="0" maxElevation="0"/>
        \\      </zoneExclusion>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var cartesian_extent_blocks = cartesian_extent_adm.blocks();
    const cartesian_extent_block =
        (try cartesian_extent_blocks.next()).?;
    const cartesian_extent_plan =
        try plugin.dsp.AdmObjectCartesianExtentGainPlan(
            f32,
        ).initCartesianExtent(
            &cartesian_extent_block,
            &polar_layout,
            &cartesian_extent_panner,
            object_context,
        );
    var cartesian_plan_power: f32 = 0.0;
    for (cartesian_extent_plan.directGainSlice()) |gain| {
        cartesian_plan_power += gain * gain;
    }
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        cartesian_plan_power,
        0.000_001,
    );
    try std.testing.expectEqual(
        @as(f32, 0.0),
        cartesian_extent_plan.directGainSlice()[2],
    );
    try std.testing.expectEqual(
        @as(usize, 32),
        plugin.dsp.maximum_adm_exclusion_zones,
    );
    const installed_zone = plugin.dsp.AdmXmlExclusionZone{
        .polar = plugin.dsp.AdmXmlPolarExclusionZone{
            .min_azimuth = -30.0,
            .max_azimuth = 30.0,
            .min_elevation = -10.0,
            .max_elevation = 10.0,
        },
    };
    try std.testing.expectEqual(
        @as(f64, 30.0),
        installed_zone.polar.max_azimuth,
    );
    const polar_router =
        try plugin.dsp.AdmDirectSpeakerPositionRouter(f32).init(
            &direct_block,
            &polar_layout,
            .{},
        );
    var polar_storage: [polar_layout.len][speaker_input.len]f32 =
        @splat(@splat(0.0));
    var polar_outputs: [polar_layout.len][]f32 = undefined;
    for (&polar_storage, &polar_outputs) |*channel, *output| {
        output.* = channel;
    }
    try polar_router.mixWithPointSourceFallback(
        &polar_panner,
        &polar_cartesian_panner,
        &speaker_input,
        &polar_outputs,
    );
    try std.testing.expectEqualDeep(
        speaker_input,
        polar_storage[2],
    );
    const frequency = plugin.dsp.AdmXmlFrequency{
        .low_pass_hz = 120.0,
    };
    try std.testing.expect(frequency.isLfe());
    try std.testing.expectEqual(
        @as(u8, 0),
        (try plugin.dsp.resolveAdmDirectSpeakerRoute(
            &direct_block,
            &speaker_layout,
            .{},
        )).output,
    );
    const emission_adm = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended version="ITU-R_BS.2076-3">
        \\  <audioProgramme audioProgrammeID="APR_1001" audioProgrammeName="Multilingual" audioProgrammeLanguage="und">
        \\    <audioProgrammeLabel language="eng">Main programme</audioProgrammeLabel>
        \\    <audioProgrammeLabel language="fra">Programme principal</audioProgrammeLabel>
        \\    <audioContentIDRef>ACO_1001</audioContentIDRef>
        \\    <audioContentIDRef>ACO_1002</audioContentIDRef>
        \\    <loudnessMetadata>
        \\      <integratedLoudness>-23.0</integratedLoudness>
        \\      <dialogueLoudness>-24.0</dialogueLoudness>
        \\    </loudnessMetadata>
        \\  </audioProgramme>
        \\  <audioContent audioContentID="ACO_1001" audioContentName="Main" audioContentLanguage="eng">
        \\    <audioContentLabel language="eng">Main</audioContentLabel>
        \\    <audioContentLabel language="fra">Principal</audioContentLabel>
        \\    <audioObjectIDRef>AO_1001</audioObjectIDRef>
        \\    <loudnessMetadata>
        \\      <dialogueLoudness>-24.0</dialogueLoudness>
        \\    </loudnessMetadata>
        \\    <dialogue dialogueContentKind="5">1</dialogue>
        \\  </audioContent>
        \\  <audioContent audioContentID="ACO_1002" audioContentName="Alternative" audioContentLanguage="fra">
        \\    <audioContentLabel language="eng">Alternative</audioContentLabel>
        \\    <audioContentLabel language="fra">Alternative</audioContentLabel>
        \\    <audioObjectIDRef>AO_1002</audioObjectIDRef>
        \\    <loudnessMetadata>
        \\      <dialogueLoudness>-24.0</dialogueLoudness>
        \\    </loudnessMetadata>
        \\    <dialogue dialogueContentKind="5">1</dialogue>
        \\  </audioContent>
        \\  <audioObject audioObjectID="AO_1001" audioObjectName="Main" interact="0">
        \\    <audioComplementaryObjectGroupLabel language="eng">Language</audioComplementaryObjectGroupLabel>
        \\    <audioComplementaryObjectGroupLabel language="fra">Langue</audioComplementaryObjectGroupLabel>
        \\    <audioComplementaryObjectIDRef>AO_1002</audioComplementaryObjectIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000001</audioTrackUIDRef>
        \\    <alternativeValueSet alternativeValueSetID="AVS_1001_0001"/>
        \\    <alternativeValueSet alternativeValueSetID="AVS_1001_0002"/>
        \\  </audioObject>
        \\  <audioObject audioObjectID="AO_1002" audioObjectName="Alternative" interact="0">
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\    <audioTrackUIDRef>ATU_00000002</audioTrackUIDRef>
        \\  </audioObject>
        \\  <audioPackFormat audioPackFormatID="AP_00021001" audioPackFormatName="Stereo Downmix" typeLabel="0002" typeDefinition="Matrix">
        \\    <audioChannelFormatIDRef>AC_00021001</audioChannelFormatIDRef>
        \\    <inputPackFormatIDRef>AP_00010001</inputPackFormatIDRef>
        \\    <outputPackFormatIDRef>AP_00010002</outputPackFormatIDRef>
        \\  </audioPackFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001" audioChannelFormatName="Left Downmix" typeLabel="0002" typeDefinition="Matrix">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <outputChannelFormatIDRef>AC_00010001</outputChannelFormatIDRef>
        \\      <matrix>
        \\        <coefficient gain="0.5">AC_00010003</coefficient>
        \\      </matrix>
        \\    </audioBlockFormatMatrix>
        \\  </audioChannelFormat>
        \\  <audioTrackUID UID="ATU_00000001" sampleRate="48000" bitDepth="24">
        \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <audioTrackUID UID="ATU_00000002" sampleRate="48000" bitDepth="24">
        \\    <audioChannelFormatIDRef>AC_00010003</audioChannelFormatIDRef>
        \\    <audioPackFormatIDRef>AP_00010001</audioPackFormatIDRef>
        \\  </audioTrackUID>
        \\  <profileList>
        \\    <profile profileName="Advanced sound system: ADM and S-ADM profile for emission"
        \\      profileVersion="1" profileLevel="1">ITU-R BS.2168</profile>
        \\  </profileList>
        \\</audioFormatExtended>
    );
    try std.testing.expectEqual(
        plugin.dsp.AdmXmlEmissionProfileLevel.level_1,
        try emission_adm.validateEmissionProfileElementLimits(),
    );
    try emission_adm.validateEmissionProfileSubelementLimits();
    try emission_adm.validateEmissionProfileIdentifiers();
    try emission_adm.validateEmissionProfileObjectTopology();
    try emission_adm.validateEmissionProfileObjectSources();
    try emission_adm.validateEmissionProfileMatrices();
    try emission_adm.validateEmissionProfileComplementaryObjects();
    try emission_adm.validateEmissionProfileObjectParameters();
    try emission_adm.validateEmissionProfileComplementaryParameters();
    try emission_adm.validateEmissionProfileProgrammeContentMetadata();
    try emission_adm.validateEmissionProfileFormatMetadata();
    try emission_adm.validateEmissionProfileObjectBlocks();
    try emission_adm.validateEmissionProfileComplementaryLabels();
    try emission_adm.validateEmissionProfileConsistentLabelLanguages();
    try emission_adm.validateEmissionProfileRecommendedProgrammeLanguages();
    try emission_adm.validateEmissionProfileRecommendedDialogueLoudness();
    try emission_adm.validateEmissionProfilePcmEssence(.{
        .sample_rate = 48_000,
        .bit_depth = 24,
        .channel_count = 2,
        .frame_count = 48_000,
    });
    const namespaced_adm = try plugin.dsp.AdmXmlDocument.init(
        \\<a:audioFormatExtended xmlns:a="urn:adm" xmlns:v="urn:vendor" v:session="fixture">
        \\  <a:audioObject audioObjectID="AO_1001" a:revision="next">
        \\    <a:audioPackFormatIDRef><![CDATA[AP_00010002]]></a:audioPackFormatIDRef>
        \\    <a:futureMetadata mode="fixture"><![CDATA[literal < & >]]></a:futureMetadata>
        \\  </a:audioObject>
        \\  <v:audioObject audioObjectID="AO_1002"><![CDATA[literal < & >]]></v:audioObject>
        \\</a:audioFormatExtended>
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        namespaced_adm.declaration_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        namespaced_adm.extension_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        namespaced_adm.untyped_element_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        namespaced_adm.untyped_attribute_count,
    );
    try std.testing.expectError(
        error.UnsupportedAdmMetadataVocabulary,
        namespaced_adm.validateTypedVocabulary(),
    );
    var installed_untyped_elements: plugin.dsp.AdmXmlUntypedElementIterator =
        namespaced_adm.untypedElements();
    const installed_untyped_element: plugin.dsp.AdmXmlUntypedElement =
        (try installed_untyped_elements.next()).?;
    try std.testing.expectEqualStrings(
        "futureMetadata",
        installed_untyped_element.localName(),
    );
    try std.testing.expectEqualStrings(
        "AO_1001",
        installed_untyped_element.declaration_owner.?.raw,
    );
    try std.testing.expect((try installed_untyped_elements.next()) == null);
    var installed_untyped_attributes: plugin.dsp.AdmXmlUntypedAttributeIterator =
        namespaced_adm.untypedAttributes();
    const installed_untyped_attribute: plugin.dsp.AdmXmlUntypedAttribute =
        (try installed_untyped_attributes.next()).?;
    try std.testing.expectEqualStrings(
        "a:revision",
        installed_untyped_attribute.qualified_name,
    );
    try std.testing.expectEqualStrings(
        "AO_1001",
        installed_untyped_attribute.declaration_owner.?.raw,
    );
    try std.testing.expect(
        (try installed_untyped_attributes.next()) == null,
    );
    var installed_extensions: plugin.dsp.AdmXmlExtensionIterator = namespaced_adm.extensions();
    const installed_extension: plugin.dsp.AdmXmlExtension = (try installed_extensions.next()).?;
    try std.testing.expectEqualStrings(
        "v:audioObject",
        installed_extension.qualified_name,
    );
    try std.testing.expectEqualStrings(
        "urn:vendor",
        installed_extension.namespace_uri.?,
    );
    try std.testing.expectEqualStrings(
        "audioFormatExtended",
        installed_extension.parent_element_name,
    );
    try std.testing.expectEqualStrings(
        "<v:audioObject audioObjectID=\"AO_1002\"><![CDATA[literal < & >]]></v:audioObject>",
        installed_extension.source,
    );
    try std.testing.expect((try installed_extensions.next()) == null);
    try std.testing.expectEqual(
        @as(usize, 1),
        namespaced_adm.extension_attribute_count,
    );
    var installed_extension_attributes: plugin.dsp.AdmXmlExtensionAttributeIterator =
        namespaced_adm.extensionAttributes();
    const installed_extension_attribute: plugin.dsp.AdmXmlExtensionAttribute =
        (try installed_extension_attributes.next()).?;
    try std.testing.expectEqualStrings(
        "v:session",
        installed_extension_attribute.qualified_name,
    );
    try std.testing.expectEqualStrings(
        "fixture",
        installed_extension_attribute.encoded_value,
    );
    try std.testing.expect(
        (try installed_extension_attributes.next()) == null,
    );
    var serial_flow_state =
        plugin.dsp.AdmXmlEmissionSerialFlowState{};
    try std.testing.expect(!serial_flow_state.initialized);
    serial_flow_state.reset();
    var wav = try plugin.dsp.WavFileWriter.initWithRiffMetadata(
        std.testing.io,
        wav_file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
        riff_metadata,
    );
    try wav.append(f32, &.{ -0.5, 0.5 });
    try wav.finalize();
    try std.testing.expect(wav.valid());
    const wav_reader = try plugin.dsp.AudioFileReader.init(
        std.testing.io,
        wav_file,
    );
    try std.testing.expectEqual(
        plugin.dsp.AudioFileContainer.wav,
        wav_reader.getInfo().container,
    );
    var wav_samples: [2]f32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 2),
        try wav_reader.readInterleaved(f32, 0, &wav_samples),
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, -0.5),
        wav_samples[0],
        1.0 / 32768.0,
    );
    var metadata_storage: [4096]u8 = undefined;
    const required_broadcast =
        (try wav_reader.requiredMetadataChunkBytes(.broadcast)).?;
    const broadcast_chunk = try wav_reader.readMetadataChunk(
        .broadcast,
        metadata_storage[0..required_broadcast],
    );
    try std.testing.expectEqual(
        required_broadcast,
        broadcast_chunk.?.len,
    );
    const broadcast_view = try plugin.dsp.BroadcastMetadataView.init(
        broadcast_chunk.?,
    );
    try std.testing.expectEqualStrings(
        "Installed consumer",
        broadcast_view.description,
    );
    const ixml_chunk = try wav_reader.readMetadataChunk(
        .ixml,
        &metadata_storage,
    );
    const ixml_view = try plugin.dsp.RiffXmlView.init(ixml_chunk.?);
    try std.testing.expectEqual(
        plugin.dsp.RiffXmlKind.ixml,
        ixml_view.kind,
    );
    const ixml_requirements =
        try plugin.dsp.requiredIxmlParseStorage(ixml_view.document);
    var parsed_ixml_tracks: [1]plugin.dsp.IxmlTrack = undefined;
    var parsed_ixml_sync_points: [1]plugin.dsp.IxmlSyncPoint =
        undefined;
    var parsed_ixml_text: [512]u8 = undefined;
    const parsed_ixml = try plugin.dsp.parseIxmlMetadata(
        ixml_view.document,
        .{
            .tracks = &parsed_ixml_tracks,
            .sync_points = &parsed_ixml_sync_points,
            .text = &parsed_ixml_text,
        },
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        ixml_requirements.track_count,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        ixml_requirements.sync_point_count,
    );
    try std.testing.expectEqualStrings(
        "Installed",
        parsed_ixml.project.?,
    );
    try std.testing.expectEqualStrings(
        "Mono mix",
        parsed_ixml.tracks[0].name.?,
    );
    try std.testing.expectEqual(
        plugin.dsp.IxmlRatio{
            .numerator = 30_000,
            .denominator = 1_001,
        },
        parsed_ixml.speed.?.timecode_rate.?,
    );
    try std.testing.expectEqual(
        plugin.dsp.IxmlTimecodeFlag.df,
        parsed_ixml.speed.?.timecode_flag.?,
    );
    try std.testing.expectEqualStrings(
        "installed-family",
        parsed_ixml.file_set.?.family_uid.?,
    );
    try std.testing.expectEqual(
        plugin.dsp.IxmlSyncPointType.relative,
        parsed_ixml.sync_points[0].kind.?,
    );
    try std.testing.expectEqualStrings(
        "Camera A",
        parsed_ixml.sync_points[0].comment.?,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -23),
        parsed_ixml.loudness.?.value.?,
        1.0e-12,
    );
    try std.testing.expectEqualStrings(
        "installed.wav",
        parsed_ixml.history.?.original_filename.?,
    );
    try std.testing.expectEqualStrings(
        "Portable metadata",
        parsed_ixml.bext.?.description.?,
    );
    const channel_chunk = try wav_reader.readMetadataChunk(
        .channel_allocation,
        &metadata_storage,
    );
    const channel_view =
        try plugin.dsp.AdmChannelAllocationView.init(channel_chunk.?);
    try std.testing.expectEqual(@as(u16, 1), channel_view.num_tracks);
    try std.testing.expectEqualStrings(
        "ATU_00000001",
        (try channel_view.entry(0)).uid,
    );
    try std.testing.expectEqualStrings(
        "Stage A",
        parsed_ixml.location.?.name.?,
    );
    try std.testing.expectEqualStrings(
        "Fixture Recorder",
        parsed_ixml.user.?.audio_recorder_model.?,
    );

    var aiff_file = try temporary.dir.createFile(
        std.testing.io,
        "installed.aiff",
        .{ .read = true },
    );
    defer aiff_file.close(std.testing.io);
    var aiff = try plugin.dsp.AiffFileWriter.initWithMetadata(
        std.testing.io,
        aiff_file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
        &.{
            plugin.dsp.AudioMetadataEntry{
                .id = plugin.dsp.audio_metadata.aiff_name,
                .value = "Installed consumer",
            },
        },
    );
    try aiff.append(f32, &.{ -0.5, 0.5 });
    try aiff.finalize();
    try std.testing.expect(aiff.valid());
    const aiff_reader = try plugin.dsp.AudioFileReader.init(
        std.testing.io,
        aiff_file,
    );
    try std.testing.expectEqual(
        plugin.dsp.AudioFileEncoding.pcm_i24,
        aiff_reader.getInfo().encoding,
    );

    var rf64_file = try temporary.dir.createFile(
        std.testing.io,
        "installed.rf64.wav",
        .{ .read = true },
    );
    defer rf64_file.close(std.testing.io);
    var rf64 = try plugin.dsp.Rf64FileWriter.initWithRiffMetadata(
        std.testing.io,
        rf64_file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
        .{ .axml = "<audioFormatExtended/>" },
    );
    try rf64.append(f32, &.{ -0.5, 0.5 });
    try rf64.finalize();
    try std.testing.expect(rf64.valid());
    const rf64_reader = try plugin.dsp.AudioFileReader.init(
        std.testing.io,
        rf64_file,
    );
    try std.testing.expectEqual(
        plugin.dsp.AudioFileContainer.rf64,
        rf64_reader.getInfo().container,
    );
    const axml_chunk = try rf64_reader.readMetadataChunk(
        .axml,
        &metadata_storage,
    );
    const axml_view = try plugin.dsp.RiffXmlView.init(axml_chunk.?);
    try std.testing.expectEqual(
        plugin.dsp.RiffXmlKind.axml,
        axml_view.kind,
    );
    try std.testing.expectEqualStrings(
        "<audioFormatExtended/>",
        axml_view.document,
    );

    var bw64_file = try temporary.dir.createFile(
        std.testing.io,
        "installed.bw64.wav",
        .{ .read = true },
    );
    defer bw64_file.close(std.testing.io);
    var bw64 = try plugin.dsp.Bw64FileWriter.initBw64WithRiffMetadata(
        std.testing.io,
        bw64_file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
        .{
            .axml = "<audioFormatExtended/>",
            .channel_allocation = .{
                .num_tracks = 1,
                .entries = &adm_entries,
            },
        },
    );
    try bw64.append(f32, &.{ -0.5, 0.5 });
    try bw64.finalize();
    const bw64_reader = try plugin.dsp.AudioFileReader.init(
        std.testing.io,
        bw64_file,
    );
    try std.testing.expectEqual(
        plugin.dsp.AudioFileContainer.bw64,
        bw64_reader.getInfo().container,
    );
    const bw64_channel_chunk = try bw64_reader.readMetadataChunk(
        .channel_allocation,
        &metadata_storage,
    );
    _ = try plugin.dsp.AdmChannelAllocationView.init(
        bw64_channel_chunk.?,
    );
    var bw64_xml_storage: [256]u8 = undefined;
    var bw64_channel_storage: [256]u8 = undefined;
    const bw64_adm_requirements: plugin.dsp.AudioFileAdmMetadataRequirements =
        (try bw64_reader.requiredAdmMetadataBytes()).?;
    const bw64_adm = try bw64_reader.readAdmMetadata(
        bw64_xml_storage[0..bw64_adm_requirements.xml_bytes],
        bw64_channel_storage[0..bw64_adm_requirements.channel_allocation_bytes],
    );
    try std.testing.expectEqual(
        @as(u16, 1),
        bw64_adm.?.channel_allocation.num_tracks,
    );

    var wave64_file = try temporary.dir.createFile(
        std.testing.io,
        "installed.w64",
        .{ .read = true },
    );
    defer wave64_file.close(std.testing.io);
    var wave64 = try plugin.dsp.Wave64FileWriter.initWithMetadata(
        std.testing.io,
        wave64_file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
        plugin.dsp.Wave64Metadata{
            .broadcast = .{ .description = "Installed Wave64" },
            .info = &.{
                plugin.dsp.AudioMetadataEntry{
                    .id = plugin.dsp.audio_metadata.title,
                    .value = "Installed consumer",
                },
            },
        },
    );
    try wave64.append(f32, &.{ -0.5, 0.5 });
    try wave64.finalize();
    try std.testing.expect(wave64.valid());
    const wave64_reader = try plugin.dsp.AudioFileReader.init(
        std.testing.io,
        wave64_file,
    );
    try std.testing.expectEqual(
        plugin.dsp.AudioFileContainer.wave64,
        wave64_reader.getInfo().container,
    );
    const wave64_broadcast_bytes =
        (try wave64_reader.requiredMetadataChunkBytes(.broadcast)).?;
    const wave64_broadcast = try wave64_reader.readMetadataChunk(
        .broadcast,
        metadata_storage[0..wave64_broadcast_bytes],
    );
    const wave64_broadcast_view =
        try plugin.dsp.BroadcastMetadataView.init(wave64_broadcast.?);
    try std.testing.expectEqualStrings(
        "Installed Wave64",
        wave64_broadcast_view.description,
    );
    const wave64_info = try wave64_reader.readMetadataChunk(
        .info,
        &metadata_storage,
    );
    _ = try plugin.dsp.RiffInfoMetadataView.init(wave64_info.?);
}

test "installed package exposes advanced filter SIMD publication and transport APIs" {
    const inverse_chebyshev =
        try plugin.dsp.ChebyshevTypeIIDesigner(f64).lowPass(.{
            .order = 6,
            .sample_rate = 48_000.0,
            .stopband_hz = 4_000.0,
            .attenuation_db = 60.0,
        });
    try std.testing.expect(inverse_chebyshev.valid());
    try std.testing.expect(
        inverse_chebyshev.magnitude(48_000.0, 4_000.0) <= 0.001_001,
    );

    const elliptic = try plugin.dsp.EllipticDesigner(f64).lowPass(.{
        .order = 5,
        .sample_rate = 48_000.0,
        .frequency_hz = 2_000.0,
        .ripple_db = 1.0,
        .attenuation_db = 60.0,
    });
    try std.testing.expect(elliptic.valid());

    const Native = plugin.dsp.NativeSimdRegister(f32);
    var native_source: [Native.lanes]f32 align(Native.alignment) =
        @splat(0.25);
    const native_value = try Native.loadAligned(&native_source);
    try native_value.storeAligned(&native_source);
    try std.testing.expectEqual(
        plugin.dsp.nativeSimdLaneCount(f32),
        Native.lanes,
    );

    const Complex = plugin.dsp.NativeComplexSimdRegister(f32);
    var real: [Native.lanes]f32 = @splat(1.0);
    var imaginary: [Native.lanes]f32 = @splat(2.0);
    const complex = try Complex.load(&real, &imaginary);
    const magnitude = try complex.magnitudeSquared();
    try magnitude.store(&real);
    for (real) |value|
        try std.testing.expectEqual(@as(f32, 5.0), value);

    const State = struct {
        gain: f32,
        mode: u8,
    };
    var snapshots = plugin.dsp.RealtimeSnapshotPublisher(State).init(.{
        .gain = 1.0,
        .mode = 0,
    });
    const snapshot_generation = try snapshots.publish(.{
        .gain = 0.5,
        .mode = 1,
    });
    const snapshot = snapshots.tryRead().?;
    try std.testing.expectEqual(snapshot_generation, snapshot.generation);
    try std.testing.expectEqual(@as(f32, 0.5), snapshot.value.gain);

    var references =
        plugin.dsp.RealtimeReferencePublisher(State, 4).init(.{
            .gain = 1.0,
            .mode = 0,
        });
    const reference_generation = try references.publish(.{
        .gain = 0.25,
        .mode = 2,
    });
    var handle = references.tryAcquire().?;
    defer handle.release();
    var retained_handle = handle.retain().?;
    defer retained_handle.release();
    try std.testing.expectEqual(reference_generation, handle.generation().?);
    try std.testing.expectEqual(
        handle.generation().?,
        retained_handle.generation().?,
    );
    try std.testing.expectEqual(@as(f32, 0.25), handle.value().?.gain);
    try std.testing.expectEqual(
        handle.value().?.gain,
        retained_handle.value().?.gain,
    );
    var update = try references.beginUpdate();
    defer update.cancel();
    update.value().?.mode = 3;
    const update_generation = try update.commit();
    var updated_handle = references.tryAcquire().?;
    defer updated_handle.release();
    try std.testing.expectEqual(
        update_generation,
        updated_handle.generation().?,
    );
    try std.testing.expectEqual(
        @as(f32, 0.25),
        updated_handle.value().?.gain,
    );
    try std.testing.expectEqual(
        @as(u8, 3),
        updated_handle.value().?.mode,
    );
    try std.testing.expectEqual(@as(u8, 2), handle.value().?.mode);

    var chorus = try plugin.dsp.Chorus(f32, 512).init(.{
        .sample_rate = 48_000.0,
    });
    try chorus.syncTransport(.{
        .project_time_samples = 0,
        .state_valid = true,
        .playing = true,
        .tempo_bpm = 90.0,
        .project_quarter_notes = 3.0,
    }, 120.0, .half, 0.01);
    try std.testing.expect(chorus.valid());
}

test "installed package exposes ADM common layout speaker mapping" {
    const document = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <speakerLabel>M+000</speakerLabel>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <gain>0.5</gain>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const layout = [_]plugin.dsp.AdmOutputSpeaker{
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30.0,
                .elevation_degrees = 0.0,
            },
            .allocentric = .{ .x = -1.0, .y = 1.0 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30.0,
                .elevation_degrees = 0.0,
            },
            .allocentric = .{ .x = 1.0, .y = 1.0 },
        },
    };
    const context = plugin.dsp.AdmDirectSpeakerRoutingContext{
        .common_pack_mapping = plugin.dsp.AdmDirectSpeakerCommonPackMapping{
            .input_pack = try plugin.dsp.AdmIdentifier.parse("AP_00010005"),
            .output_layout_name = "0+2+0",
        },
    };
    const router =
        try plugin.dsp.AdmDirectSpeakerPositionRouter(f32).init(
            &block,
            &layout,
            context,
        );
    const input = [_]f32{ 2.0, -4.0 };
    var left: [input.len]f32 = @splat(0.0);
    var right: [input.len]f32 = @splat(0.0);
    const outputs = [_][]f32{ &left, &right };
    try router.mix(&input, &outputs);
    const gain: f32 = @sqrt(0.5) * 0.5;
    try std.testing.expectApproxEqAbs(gain * 2.0, left[0], 0.000_001);
    try std.testing.expectApproxEqAbs(gain * -4.0, left[1], 0.000_001);
    try std.testing.expectEqualDeep(left, right);
}

test "installed package exposes ADM Matrix coefficient delays" {
    const document = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient gain="0.5" delay="1.5">AC_00010001</coefficient>
        \\      </matrix>
        \\    </audioBlockFormatMatrix>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const channels = [_]plugin.dsp.AdmIdentifier{
        try plugin.dsp.AdmIdentifier.parse("AC_00010001"),
    };
    var mixer =
        try plugin.dsp.AdmMatrixCoefficientMixer(f32, 1).init(
            &block,
            &channels,
            1000.0,
        );
    const input = [_]f32{ 2.0, 4.0, 6.0 };
    const inputs = [_][]const f32{&input};
    var output: [input.len]f32 = undefined;
    try mixer.process(&inputs, &output);
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 1.0, 2.0 },
        output,
    );
}

test "installed package exposes bounded ADM HOA matrix decoding" {
    const document = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>0</order>
        \\      <degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041002">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041002_00000001">
        \\      <order>1</order>
        \\      <degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    const blocks = [_]plugin.dsp.AdmXmlBlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const Decoder = plugin.dsp.AdmHoaMatrixDecoder(f32, 2, 1);
    const decoder = try Decoder.init(&blocks, 1, &.{ 0.5, -1.0 });
    const first = [_]f32{ 2.0, 4.0 };
    const second = [_]f32{ 1.0, -3.0 };
    const inputs = [_][]const f32{ &first, &second };
    var output: [first.len]f32 = undefined;
    const outputs = [_][]f32{&output};
    try decoder.process(&inputs, &outputs);
    try std.testing.expectEqualDeep([_]f32{ 0.0, 5.0 }, output);
    try std.testing.expectEqual(
        @as(u32, 50),
        plugin.dsp.maximum_supported_adm_hoa_order,
    );
}

test "installed package exposes ADM binaural stereo mixing" {
    const document = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="RightEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001"/>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051002" audioChannelFormatName="LeftEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051002_00000001">
        \\      <gain>0.5</gain>
        \\    </audioBlockFormatBinaural>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    const blocks = [_]plugin.dsp.AdmXmlBlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const mixer = try plugin.dsp.AdmBinauralStereoMixer(f32).init(
        &blocks,
    );
    const right = [_]f32{ 3.0, -1.0 };
    const left = [_]f32{ 2.0, 4.0 };
    const inputs = [_][]const f32{ &right, &left };
    var left_output: [left.len]f32 = undefined;
    var right_output: [right.len]f32 = undefined;
    const outputs = [_][]f32{ &left_output, &right_output };
    try mixer.process(&inputs, &outputs);
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 2.0 },
        left_output,
    );
    try std.testing.expectEqualDeep(right, right_output);
}

test "installed package exposes timed ADM binaural gain" {
    const document = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051001" audioChannelFormatName="RightEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000001"
        \\      rtime="0.00000" duration="1.00000">
        \\      <gain>1</gain>
        \\    </audioBlockFormatBinaural>
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051001_00000002"
        \\      rtime="1.00000" duration="1.00000">
        \\      <gain>0.5</gain>
        \\      <jumpPosition>1</jumpPosition>
        \\    </audioBlockFormatBinaural>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00051002" audioChannelFormatName="LeftEar">
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051002_00000001"
        \\      rtime="0.00000" duration="1.00000">
        \\      <gain>0.25</gain>
        \\    </audioBlockFormatBinaural>
        \\    <audioBlockFormatBinaural audioBlockFormatID="AB_00051002_00000002"
        \\      rtime="1.00000" duration="1.00000">
        \\      <gain>1</gain>
        \\    </audioBlockFormatBinaural>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    const right_blocks = [_]plugin.dsp.AdmXmlBlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const left_blocks = [_]plugin.dsp.AdmXmlBlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const sequences = [_][]const plugin.dsp.AdmXmlBlockFormat{
        &right_blocks,
        &left_blocks,
    };
    const timeline =
        try plugin.dsp.AdmBinauralStereoGainTimeline(f32, 2).init(
            &sequences,
            4,
        );
    const input: [8]f32 = @splat(1.0);
    const inputs = [_][]const f32{ &input, &input };
    var left: [input.len]f32 = undefined;
    var right: [input.len]f32 = undefined;
    const outputs = [_][]f32{ &left, &right };
    try timeline.process(0, &inputs, &outputs);
    try std.testing.expectEqualDeep(
        [_]f32{ 0.25, 0.25, 0.25, 0.25, 0.25, 0.4375, 0.625, 0.8125 },
        left,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 1.0, 1.0, 1.0, 0.5, 0.5, 0.5, 0.5 },
        right,
    );
}
