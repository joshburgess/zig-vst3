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

fn installedConstantOne(_: f32) f32 {
    return 1.0;
}

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

test "installed package contains hostile logarithmic ramp arithmetic" {
    var ramp = try plugin.dsp.LogRampedValue(f64).init(
        std.math.floatMax(f64),
    );
    ramp.ratio = 2.0;
    ramp.remaining = 2;
    try std.testing.expectEqual(
        std.math.floatMax(f64),
        ramp.next(),
    );
    try std.testing.expect(ramp.valid());
    try std.testing.expect(!ramp.smoothing());

    var gain = try plugin.dsp.Gain(f64).init(1.0);
    gain.target_gain = 0.5;
    gain.step = 64.0;
    gain.remaining = 2;
    try std.testing.expectEqual(
        @as(f64, 0.5),
        gain.processSample(1.0),
    );
    try std.testing.expect(gain.valid());

    var rate = try plugin.dsp.ModulationRateSmoother.init(
        48_000.0,
        20.0,
    );
    rate.target_hz = 10.0;
    rate.step_hz = 20.0;
    rate.remaining_samples = 2;
    try std.testing.expectEqual(@as(f64, 20.0), rate.next());
    try std.testing.expectEqual(@as(f64, 10.0), rate.current_hz);
    try std.testing.expect(rate.valid());

    var envelope = try plugin.dsp.BallisticsFilter(f32).init(.{
        .sample_rate = 48_000.0,
        .mode = .rms,
    });
    try std.testing.expectError(
        error.InvalidBallisticsResetValue,
        envelope.reset(std.math.floatMax(f32)),
    );
    try std.testing.expect(envelope.valid());
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

    var malformed = dither;
    malformed.config.channel_count = 0;
    try std.testing.expect(!malformed.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed.channelCount());
    try std.testing.expectEqual(@as(u6, 0), malformed.bitsPerSample());
    var unchanged: [46]u8 = @splat(0xa5);
    try std.testing.expectError(
        error.InvalidDitherChannelCount,
        plugin.dsp.writeInterleavedWavDithered(
            f64,
            &unchanged,
            &.{0.0},
            .{
                .sample_rate = 48_000,
                .channel_count = 1,
                .encoding = .pcm_i16,
            },
            &malformed,
        ),
    );
    try std.testing.expectEqual(
        [_]u8{0xa5} ** unchanged.len,
        unchanged,
    );

    var saturating = try plugin.dsp.PcmDither.init(.{
        .channel_count = 1,
        .bits_per_sample = 32,
        .mode = .none,
    });
    try std.testing.expectEqual(
        std.math.maxInt(i32),
        try saturating.quantize(std.math.floatMax(f64), 0),
    );
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

    const ogg_limits = plugin.dsp.OggLimits{
        .max_stream_bytes = (try file.stat(std.testing.io)).size,
        .max_pages = 1,
        .max_packets = 1,
        .max_logical_streams = 1,
    };
    var page_reader = try plugin.dsp.OggFilePageReader.initWithLimits(
        std.testing.io,
        file,
        ogg_limits,
    );
    var transactional_page_storage: [64]u8 = undefined;
    var transactional_page_scratch: [64]u8 = undefined;
    const page = (try page_reader.nextTransactional(
        &transactional_page_storage,
        &transactional_page_scratch,
    )).?;
    try std.testing.expectEqualStrings("installed", page.body);
    try std.testing.expectEqual(
        @intFromPtr(transactional_page_storage[28..].ptr),
        @intFromPtr(page.body.ptr),
    );

    var transactional_packet_reader =
        try plugin.dsp.OggFilePacketReader.initWithLimits(
            std.testing.io,
            file,
            ogg_limits,
        );
    var transactional_packet_destination: [9]u8 = undefined;
    var transactional_packet_scratch: [9]u8 = undefined;
    const transactional_packet =
        (try transactional_packet_reader.nextTransactional(
            &transactional_packet_destination,
            &transactional_page_scratch,
            &transactional_packet_scratch,
        )).?;
    try std.testing.expectEqualStrings(
        "installed",
        transactional_packet.bytes,
    );
    try std.testing.expectEqual(
        @intFromPtr(transactional_packet_destination[0..].ptr),
        @intFromPtr(transactional_packet.bytes.ptr),
    );

    var reader = try plugin.dsp.OggFilePacketReader.init(
        std.testing.io,
        file,
    );
    var reader_page_storage: [plugin.dsp.ogg.maximum_page_bytes]u8 = undefined;
    var packet_storage: [9]u8 = undefined;
    try std.testing.expect(reader.valid(
        &reader_page_storage,
        &packet_storage,
    ));
    const packet = (try reader.next(
        &reader_page_storage,
        &packet_storage,
    )).?;
    try std.testing.expect(packet.beginning);
    try std.testing.expect(packet.end);
    try std.testing.expectEqualStrings("installed", packet.bytes);
    try std.testing.expect(reader.valid(
        &reader_page_storage,
        &packet_storage,
    ));
    var detached_reader = reader;
    var detached_lacing = [_]u8{
        detached_reader.page.?.lacing_values[0],
    };
    detached_reader.page.?.lacing_values = &detached_lacing;
    try std.testing.expect(!detached_reader.valid(
        &reader_page_storage,
        &packet_storage,
    ));
    const detached_reader_before = detached_reader;
    try std.testing.expectError(
        error.InvalidOggFilePacketReaderState,
        detached_reader.next(&reader_page_storage, &packet_storage),
    );
    try std.testing.expectEqualDeep(
        detached_reader_before,
        detached_reader,
    );
    reader.pages.expected_sequence = null;
    try std.testing.expect(!reader.valid(
        &reader_page_storage,
        &packet_storage,
    ));
    const malformed_offset = reader.pages.offset;
    try std.testing.expectError(
        error.InvalidOggFilePacketReaderState,
        reader.next(&reader_page_storage, &packet_storage),
    );
    try std.testing.expectEqual(malformed_offset, reader.pages.offset);
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
    multichannel.channel_count = std.math.maxInt(usize);
    try std.testing.expect(!multichannel.valid());
    try std.testing.expectError(
        error.InvalidOversamplerState,
        multichannel.channel(0),
    );
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
    try std.testing.expectError(
        error.FirOversamplingCapacityExceeded,
        mixed.reconfigure(
            &.{.{ .fir_equiripple = .{
                .up = .{ .normalized_transition_width = 1.0e-300 },
            } }},
            .{},
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        try mixed.oversamplingFactor(),
    );

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
    multichannel.channel_count = std.math.maxInt(usize);
    try std.testing.expect(!multichannel.valid());
    try std.testing.expectError(
        error.InvalidOversamplerState,
        multichannel.channel(0),
    );
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
    exchange.slots[exchange.active_slot].generation.store(0, .release);
    try std.testing.expectEqual(
        @as(?RuntimeExchange.MutableView, null),
        exchange.activeMutable(),
    );
    try std.testing.expect(exchange.retireActiveAtBlockBoundary());
}

test "installed package exposes bounded resource presentation" {
    var recovery = InstalledRecovery.init();
    defer recovery.deinit();
    const retained = recovery.snapshot();
    try retained.validate();
    try std.testing.expect(retained.valid());
    var presentation = recovery.presentationSnapshot();
    try std.testing.expectEqual(plugin.resource.RecoveryStatus.empty, presentation.status);
    try std.testing.expectEqual(plugin.gui_progress.State.idle, presentation.progress.state);
    try std.testing.expectEqualStrings("empty", presentation.statusText());
    try std.testing.expectEqualStrings("", presentation.metadata());
    try presentation.progress.validate();
    try std.testing.expectError(
        error.InvalidProgressGeneration,
        (plugin.gui_progress.Snapshot{ .state = .running }).validate(),
    );
    try std.testing.expectError(
        error.InvalidIdleProgress,
        (plugin.gui_progress.Snapshot{ .value = 0.5 }).validate(),
    );
    try std.testing.expect(!(plugin.gui_progress.Snapshot{
        .state = .running,
    }).valid());
    try std.testing.expectError(
        error.InvalidImportGeneration,
        (plugin.gui_file_importer.Snapshot{
            .status = .empty,
            .entry_point = .picker,
            .path_count = 0,
            .completed_units = 0,
            .total_units = 0,
            .generation = 0,
            .cancellation_pending = false,
        }).validate(),
    );
    const malformed_import = plugin.gui_file_importer.Snapshot{
        .status = .importing,
        .entry_point = .picker,
        .path_count = 0,
        .completed_units = 0,
        .total_units = 1,
        .generation = 1,
        .cancellation_pending = false,
    };
    try std.testing.expect(!malformed_import.canCancel());
    try std.testing.expectEqual(@as(f64, 0.0), malformed_import.progress());

    presentation.progress.generation = 1;
    try std.testing.expect(!presentation.valid());
    try std.testing.expectEqualStrings("", presentation.statusText());
    try std.testing.expectEqualStrings("", presentation.metadata());

    recovery.next_publication_generation = std.math.maxInt(u64);
    recovery.running_publication_generation.store(1, .release);
    try std.testing.expect(recovery.importPath("generation.fixture"));
    try std.testing.expectEqual(@as(u64, 2), recovery.snapshot().generation);
    recovery.waitAndPoll();
}

test "installed package exposes validated DSP and telemetry state" {
    const Lookup = plugin.dsp.LookupTable(f32, 8);
    try std.testing.expectError(
        error.InvalidLookupTableRange,
        Lookup.init(
            -std.math.floatMax(f32),
            std.math.floatMax(f32),
            installedConstantOne,
        ),
    );
    var malformed_lookup = try Lookup.init(-1.0, 1.0, installedConstantOne);
    malformed_lookup.scale = 0.0;
    try std.testing.expectEqual(
        @as(f32, 0.5),
        malformed_lookup.processSample(0.5),
    );

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
    const FirResampler =
        plugin.dsp.FiniteImpulseResponseResampler(f64, 4, 8);
    const fir_resampler = try FirResampler.init(24_000, 48_000);
    var converted_response: [8]f64 = undefined;
    try fir_resampler.resample(
        &.{ 1.0, 0.0, 0.0, 0.0 },
        &converted_response,
    );
    var converted_sum: f64 = 0.0;
    for (converted_response) |sample| converted_sum += sample;
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        converted_sum,
        1.0e-12,
    );
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
    for (capture_fifo.storage) |channel|
        try std.testing.expectEqual(@as([9]f64, @splat(0.0)), channel);
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
    capture_fifo.reset();
    for (capture_fifo.storage) |channel|
        try std.testing.expectEqual(@as([9]f64, @splat(0.0)), channel);
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
        .lifecycle = .{
            .startup_buffer_frames = 4,
            .recovery_buffer_frames = 4,
            .control_interval_frames = 2,
            .underflow_policy = .rebuffer,
            .overflow_policy = .drop_newest_and_rebuffer,
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
    try std.testing.expectEqual(
        plugin.plugin.CaptureRateOperatingState.running,
        bridge_report.state_after,
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
            .lifecycle = .{
                .startup_buffer_frames = 4,
                .recovery_buffer_frames = 4,
                .control_interval_frames = 2,
                .underflow_policy = .rebuffer,
                .overflow_policy = .drop_newest_and_rebuffer,
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
    try std.testing.expectEqual(
        plugin.plugin.CaptureRateOperatingState.running,
        capture_adapter.bridge.operating_state,
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
    for (pipeline.pending_model) |sample|
        try std.testing.expectEqual(@as(f64, 0.0), sample);
    pipeline.pending_model[0] = 0.25;
    pipeline.pending_model_count = 1;
    pipeline.reset();
    for (pipeline.pending_model) |sample|
        try std.testing.expectEqual(@as(f64, 0.0), sample);
    pipeline.latency_samples +%= 1;
    try std.testing.expect(!pipeline.validState());

    const DryWet = plugin.dsp.DryWetMixer(f32, 4, 2);
    var dry_wet = try DryWet.init(.{});
    for (dry_wet.pending_dry) |sample|
        try std.testing.expectEqual(@as(f32, 0.0), sample);
    try dry_wet.pushDry(&.{ 1.0, 0.5 });
    var wet = [_]f32{ 0.0, 0.0 };
    try dry_wet.mixWet(&wet);
    for (dry_wet.pending_dry) |sample|
        try std.testing.expectEqual(@as(f32, 0.0), sample);

    var snapshot = plugin.gui_telemetry.ScalarSnapshot(f64).init(std.math.nan(f64));
    try std.testing.expect(snapshot.valid());
    try std.testing.expectEqual(@as(f64, 0.0), snapshot.load());
    snapshot.store(0.75);
    snapshot.store(std.math.inf(f64));
    try std.testing.expectEqual(@as(f64, 0.75), snapshot.load());
    snapshot.bits.store(@bitCast(std.math.nan(f64)), .release);
    try std.testing.expect(!snapshot.valid());
    try std.testing.expectEqual(@as(f64, 0.0), snapshot.load());
    snapshot.store(0.75);
    try std.testing.expect(snapshot.valid());

    var meter_bank = plugin.gui_telemetry.MeterBank(f64, 2).init(0.0);
    try std.testing.expect(meter_bank.valid());
    meter_bank.snapshots[1].bits.store(
        @bitCast(std.math.inf(f64)),
        .release,
    );
    try std.testing.expect(!meter_bank.valid());
    try std.testing.expectEqual(@as(?f64, 0.0), meter_bank.load(1));
    meter_bank.snapshots[1].store(0.25);
    try std.testing.expect(meter_bank.valid());

    var graph_snapshot = plugin.gui_graph.SnapshotSeries(2).init();
    try std.testing.expect(graph_snapshot.valid());
    graph_snapshot.editorOpened();
    try std.testing.expect(graph_snapshot.publish(&.{.{
        .x = 0.25,
        .y = 0.75,
    }}));
    try std.testing.expect(graph_snapshot.valid());
    graph_snapshot.points[0].x.bits.store(
        @bitCast(std.math.nan(f64)),
        .release,
    );
    try std.testing.expect(!graph_snapshot.valid());
    var graph_output: [2]plugin.gui_graph.Point = undefined;
    try std.testing.expect(graph_snapshot.read(&graph_output) == null);
    graph_snapshot.points[0].x.store(0.25);
    try std.testing.expect(graph_snapshot.valid());

    const InstalledSpectrum = plugin.gui_graph.SpectrumAnalyzer(8);
    var installed_spectrum = InstalledSpectrum.init();
    try std.testing.expect(installed_spectrum.valid());
    installed_spectrum.write_index = 8;
    try std.testing.expect(!installed_spectrum.valid());
    installed_spectrum.write_index = 0;
    installed_spectrum.window[0] = std.math.inf(f64);
    try std.testing.expect(!installed_spectrum.valid());
    installed_spectrum.window[0] = 0.0;
    try std.testing.expect(installed_spectrum.valid());

    const TelemetryQueue = plugin.gui_telemetry.SpscQueue(u32, 2);
    var telemetry_queue = TelemetryQueue{};
    try std.testing.expect(telemetry_queue.valid());
    try std.testing.expectEqual(@as([2]u32, @splat(0)), telemetry_queue.items);
    try std.testing.expect(telemetry_queue.push(10));
    try std.testing.expect(telemetry_queue.valid());
    telemetry_queue.read_index.store(1, .release);
    telemetry_queue.write_index.store(8, .release);
    try std.testing.expect(!telemetry_queue.valid());
    try std.testing.expectEqual(
        @as(?u32, null),
        telemetry_queue.pop(),
    );
    try std.testing.expect(telemetry_queue.valid());
    telemetry_queue.reset();
    try std.testing.expectEqual(@as([2]u32, @splat(0)), telemetry_queue.items);
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

    var malformed_block = block;
    malformed_block.channel_count = std.math.maxInt(usize);
    try std.testing.expect(!malformed_block.valid());
    try std.testing.expectError(
        error.InvalidAudioBlockState,
        malformed_block.channel(0),
    );
    try std.testing.expectError(
        error.InvalidAudioBlockState,
        malformed_block.fill(1.0),
    );
    try std.testing.expect(!malformed_block.asConst().valid());

    var malformed_const = added;
    malformed_const.channel_count = std.math.maxInt(usize);
    try std.testing.expect(!malformed_const.valid());
    try std.testing.expectError(
        error.InvalidAudioBlockState,
        malformed_const.peakMagnitude(),
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

    var hostile_frequency = try plugin.dsp.MultiplicativeSmoothedValue.init(
        48_000.0,
        std.math.floatMax(f64),
        1.0,
        std.math.floatMax(f64),
    );
    hostile_frequency.multiplier = 2.0;
    hostile_frequency.remaining_samples = 3;
    try std.testing.expectEqual(
        std.math.floatMax(f64),
        hostile_frequency.skip(1),
    );
    try std.testing.expect(hostile_frequency.valid());

    var hostile_linear = try plugin.dsp.LinearSmoothedValue.init(
        48_000.0,
        std.math.floatMax(f64),
        -std.math.floatMax(f64),
        std.math.floatMax(f64),
    );
    hostile_linear.step = std.math.floatMax(f64);
    hostile_linear.remaining_samples = 2;
    try std.testing.expectEqual(
        std.math.floatMax(f64),
        hostile_linear.next(),
    );
    try std.testing.expect(hostile_linear.valid());

    const M = plugin.dsp.Matrix(f32, 2, 2);
    const matrix = try M.init(.{
        .{ 1.0, 2.0 },
        .{ 3.0, 4.0 },
    });
    const product = try matrix.multiply(2, M.identity());
    try std.testing.expectEqualDeep(matrix.values, product.values);
    try std.testing.expectEqualDeep(
        [2][2]f32{
            .{ 0.0, 2.0 },
            .{ 3.0, 3.0 },
        },
        (try matrix.subtract(M.identity())).values,
    );
    const solution = try matrix.solve(.{ 5.0, 11.0 });
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        solution[0],
        0.000_001,
    );
    var decomposition = try matrix.decompose();
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
    decomposition.odd_swaps = !decomposition.odd_swaps;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        decomposition.determinant(),
    );
    decomposition.odd_swaps = !decomposition.odd_swaps;
    try std.testing.expect(decomposition.valid());
    const retained_lu_matrix_scale = decomposition.matrix_scale;
    decomposition.matrix_scale *= 2.0;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        decomposition.determinant(),
    );
    decomposition.matrix_scale = retained_lu_matrix_scale;
    try std.testing.expect(decomposition.valid());
    const tiny_matrix = try plugin.dsp.Matrix(f32, 2, 2).init(.{
        .{ 1.0e-20, 0.0 },
        .{ 0.0, 2.0e-20 },
    });
    const tiny_solution = try (try tiny_matrix.decompose()).solve(.{
        3.0e-20,
        -8.0e-20,
    });
    try std.testing.expectApproxEqAbs(
        @as(f32, 3.0),
        tiny_solution[0],
        0.000_01,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, -4.0),
        tiny_solution[1],
        0.000_01,
    );
    const rectangular = try plugin.dsp.Matrix(f32, 3, 2).init(.{
        .{ 1.0, 1.0 },
        .{ 1.0, 2.0 },
        .{ 1.0, 3.0 },
    });
    var qr: plugin.dsp.QrDecomposition(f32, 3, 2) =
        try rectangular.decomposeQr();
    const fitted = try qr.solveLeastSquares(.{ 1.0, 2.0, 2.0 });
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        fitted[1],
        0.000_001,
    );
    const retained_qr_tau = qr.tau[0];
    qr.tau[0] *= 0.5;
    try std.testing.expect(!qr.valid());
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        qr.solveLeastSquares(.{ 1.0, 2.0, 2.0 }),
    );
    qr.tau[0] = retained_qr_tau;
    try std.testing.expect(qr.valid());
    const retained_fixed_qr_matrix_scale = qr.matrix_scale;
    qr.matrix_scale *= 2.0;
    try std.testing.expect(!qr.valid());
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        qr.solveLeastSquares(.{ 1.0, 2.0, 2.0 }),
    );
    qr.matrix_scale = retained_fixed_qr_matrix_scale;
    try std.testing.expect(qr.valid());
    const deficient_matrix =
        try plugin.dsp.Matrix(f32, 3, 2).init(.{
            .{ 1.0, 2.0 },
            .{ 2.0, 4.0 },
            .{ 3.0, 6.0 },
        });
    var svd: plugin.dsp.SvdDecomposition(f32, 3, 2) =
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
    const retained_fixed_svd_maximum_sweeps = svd.maximum_sweeps;
    svd.maximum_sweeps = 0;
    try std.testing.expect(!svd.valid());
    try std.testing.expectError(
        error.InvalidSvdDecomposition,
        svd.conditionNumber(),
    );
    svd.maximum_sweeps = retained_fixed_svd_maximum_sweeps;
    try std.testing.expect(svd.valid());
    const retained_svd_right_column = [_]f32{
        svd.right[0][0],
        svd.right[1][0],
    };
    for (0..2) |row| svd.right[row][0] *= 0.5;
    try std.testing.expect(!svd.valid());
    try std.testing.expectError(
        error.InvalidSvdDecomposition,
        svd.solveLeastSquares(.{ 1.0, 2.0, 3.0 }),
    );
    for (0..2) |row|
        svd.right[row][0] = retained_svd_right_column[row];
    try std.testing.expect(svd.valid());
    const retained_svd_second_right_column = [_]f32{
        svd.right[0][1],
        svd.right[1][1],
    };
    for (0..2) |row|
        svd.right[row][1] = svd.right[row][0];
    try std.testing.expect(!svd.valid());
    try std.testing.expectError(
        error.InvalidSvdDecomposition,
        svd.pseudoinverse(),
    );
    for (0..2) |row|
        svd.right[row][1] = retained_svd_second_right_column[row];
    try std.testing.expect(svd.valid());
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
    var malformed_butterworth = odd_butterworth;
    malformed_butterworth.section_count = std.math.maxInt(usize);
    try std.testing.expect(!malformed_butterworth.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_butterworth.active().len,
    );
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
    var malformed_allpass = allpass_design;
    malformed_allpass.section_count = std.math.maxInt(usize);
    try std.testing.expect(!malformed_allpass.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_allpass.directSectionCount(),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_allpass.delayedSectionCount(),
    );
    try std.testing.expect(malformed_allpass.directAlpha(0) == null);
    try std.testing.expect(malformed_allpass.delayedAlpha(0) == null);
    try std.testing.expect(allpass_design.directAlpha(
        std.math.maxInt(usize),
    ) == null);
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
    multichannel_polyphase_oversampler.channel_count =
        std.math.maxInt(usize);
    try std.testing.expect(!multichannel_polyphase_oversampler.valid());
    try std.testing.expectError(
        error.InvalidOversamplerState,
        multichannel_polyphase_oversampler.channel(0),
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
    var malformed_roots = roots;
    malformed_roots.count = std.math.maxInt(usize);
    try std.testing.expect(!malformed_roots.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_roots.slice().len,
    );
    const no_roots = try (try InstalledPolynomial.init(&.{1.0})).findRoots(.{});
    for (no_roots.values) |root| {
        try std.testing.expectEqual(@as(f32, 0.0), root.re);
        try std.testing.expectEqual(@as(f32, 0.0), root.im);
    }
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
    const hermite =
        try plugin.dsp.Polynomial(f32, 6).hermitePhysicists(4);
    try std.testing.expectEqual(
        @as(f32, 16.0),
        hermite.coefficients[4],
    );
    const laguerre =
        try plugin.dsp.Polynomial(f32, 6)
            .generalizedLaguerre(3, 2.0);
    try std.testing.expectApproxEqAbs(
        @as(f32, 10.0),
        laguerre.evaluate(0.0),
        0.000_1,
    );
    const jacobi_polynomial =
        try plugin.dsp.Polynomial(f32, 6).jacobi(2, 1.0, 0.0);
    try std.testing.expectApproxEqAbs(
        @as(f32, 3.0),
        jacobi_polynomial.evaluate(1.0),
        0.000_1,
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
    const alternate_sn = try plugin.dsp.inverseJacobiSnBranch(
        jacobi.sn,
        0.5,
        plugin.dsp.JacobiInverseBranch{ .reflected = true },
    );
    try std.testing.expectApproxEqAbs(
        jacobi.sn,
        (try plugin.dsp.jacobiElliptic(alternate_sn, 0.5)).sn,
        1.0e-12,
    );
    const alternate_cn = try plugin.dsp.inverseJacobiCnBranch(
        jacobi.cn,
        0.5,
        .{ .period_index = 1, .reflected = true },
    );
    try std.testing.expectApproxEqAbs(
        jacobi.cn,
        (try plugin.dsp.jacobiElliptic(alternate_cn, 0.5)).cn,
        1.0e-12,
    );
    const alternate_dn = try plugin.dsp.inverseJacobiDnBranch(
        jacobi.dn,
        0.5,
        .{ .period_index = -1 },
    );
    try std.testing.expectApproxEqAbs(
        jacobi.dn,
        (try plugin.dsp.jacobiElliptic(alternate_dn, 0.5)).dn,
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
    const Complex64 = std.math.complex.Complex(f64);
    const complex_parameter_values =
        try plugin.dsp.complexParameterJacobiElliptic(
            Complex64.init(0.7, -0.35),
            Complex64.init(0.25, 0.2),
        );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.665_339_136_284_985_9),
        complex_parameter_values.sn.re,
        2.0e-12,
    );
    const complex_parameter_cd =
        try plugin.dsp.complexParameterJacobiEllipticFunction(
            Complex64.init(0.7, -0.35),
            Complex64.init(0.25, 0.2),
            .cd,
        );
    try std.testing.expectApproxEqAbs(
        complex_parameter_values.cn.div(complex_parameter_values.dn).re,
        complex_parameter_cd.re,
        2.0e-12,
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
    multichannel.channel_count = std.math.maxInt(usize);
    try std.testing.expect(!multichannel.valid());
    try std.testing.expectError(
        error.InvalidOversamplerState,
        multichannel.channel(0),
    );

    var lookahead = try plugin.dsp.LookaheadLimiter(f32, 256).init(.{
        .sample_rate = 48_000.0,
        .lookahead_ms = 1.0,
    });
    var lookahead_samples = [_]f32{ 0.25, 1.25 } ++ [_]f32{0.0} ** 48;
    lookahead.process(&lookahead_samples);
    try std.testing.expectEqual(@as(usize, 48), lookahead.latencySamples());
    try std.testing.expect(lookahead.valid());
    const lookahead_read =
        (lookahead.write_index + 1) % (lookahead.lookahead_samples + 1);
    lookahead.delay[lookahead_read] = std.math.nan(f32);
    try std.testing.expect(!lookahead.valid());
    try std.testing.expectEqual(
        @as(f32, 0.25),
        lookahead.processSample(0.25),
    );
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
    lookahead_compressor.write_index = 0;
    try std.testing.expect(!lookahead_compressor.valid());
    try std.testing.expectEqual(
        @as(f32, 0.25),
        lookahead_compressor.processSample(0.25),
    );
    try std.testing.expect(lookahead_compressor.valid());
    try std.testing.expectError(
        error.InvalidCompressorConfig,
        plugin.dsp.Compressor(f64).init(.{
            .sample_rate = std.math.floatMax(f64),
        }),
    );
    var hostile_compressor = try plugin.dsp.Compressor(f32).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = 24.0,
        .ratio = 1.0,
        .attack_ms = 0.01,
        .release_ms = 0.01,
        .makeup_db = 60.0,
    });
    try std.testing.expectEqual(
        @as(f32, 0.0),
        hostile_compressor.processSample(std.math.floatMax(f32)),
    );
    var hostile_linked = [2]f32{
        std.math.floatMax(f32),
        std.math.floatMax(f32) / 2.0,
    };
    try hostile_compressor.processLinkedFrame(&hostile_linked);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.0 },
        &hostile_linked,
    );
    try std.testing.expect(hostile_compressor.valid());

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
    var malformed_wav_writer = wav_writer;
    malformed_wav_writer.byte_count = std.math.maxInt(usize);
    try std.testing.expect(!malformed_wav_writer.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_wav_writer.bytes().len,
    );

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
    var malformed_aiff_writer = aiff_writer;
    malformed_aiff_writer.data_bytes = std.math.maxInt(usize);
    try std.testing.expect(!malformed_aiff_writer.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_aiff_writer.bytes().len,
    );

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
    try std.testing.expect(flac_comments.valid());
    const flac_title = (try flac_comments.next()).?;
    try std.testing.expectEqualStrings("TITLE", flac_title.name);
    try std.testing.expectEqualStrings("Installed FLAC", flac_title.value);
    var nonincreasing_seek_table = [_]u8{0} ** 82;
    @memcpy(nonincreasing_seek_table[0..4], "fLaC");
    nonincreasing_seek_table[7] = 34;
    nonincreasing_seek_table[42] = 0x83;
    nonincreasing_seek_table[45] = 36;
    std.mem.writeInt(
        u64,
        nonincreasing_seek_table[46..54],
        16,
        .big,
    );
    std.mem.writeInt(
        u64,
        nonincreasing_seek_table[54..62],
        100,
        .big,
    );
    std.mem.writeInt(
        u16,
        nonincreasing_seek_table[62..64],
        16,
        .big,
    );
    std.mem.writeInt(
        u64,
        nonincreasing_seek_table[64..72],
        32,
        .big,
    );
    std.mem.writeInt(
        u64,
        nonincreasing_seek_table[72..80],
        100,
        .big,
    );
    std.mem.writeInt(
        u16,
        nonincreasing_seek_table[80..82],
        16,
        .big,
    );
    try std.testing.expectError(
        error.InvalidFlacSeekTable,
        plugin.dsp.FlacSeekTableIterator.init(&nonincreasing_seek_table),
    );
    var hostile_seek_iterator = plugin.dsp.FlacSeekTableIterator{
        .payload = nonincreasing_seek_table[46..82],
    };
    try std.testing.expect(!hostile_seek_iterator.valid());
    try std.testing.expect(hostile_seek_iterator.next() == null);
    try std.testing.expectEqual(@as(usize, 0), hostile_seek_iterator.offset);
    const seek_source = [_]i32{17} ** 96;
    var seek_storage: [2048]u8 = undefined;
    const seek_flac = try plugin.dsp.encodeInterleavedFlacWithMetadata(
        &seek_storage,
        &seek_source,
        .{
            .sample_rate = 48_000,
            .channel_count = 2,
            .encoding = .pcm_i16,
            .block_size = 16,
        },
        .{ .encoded_frames_per_seek_point = 2 },
    );
    const seek_iterator =
        (try plugin.dsp.FlacSeekTableIterator.init(seek_flac)).?;
    const seek_payload_offset =
        @intFromPtr(seek_iterator.payload.ptr) -
        @intFromPtr(seek_flac.ptr);
    @memset(seek_storage[12..18], 0);
    std.mem.writeInt(
        u64,
        seek_storage[seek_payload_offset + 18 ..][0..8],
        16,
        .big,
    );
    var seek_output = [_]i32{-765_432} ** seek_source.len;
    try std.testing.expectError(
        error.InvalidFlacSeekTable,
        plugin.dsp.decodeInterleavedFlac(
            seek_storage[0..seek_flac.len],
            &seek_output,
        ),
    );
    try std.testing.expectEqual(
        [_]i32{-765_432} ** seek_source.len,
        seek_output,
    );
    var hostile_flac_comments = flac_comments;
    hostile_flac_comments.offset = std.math.maxInt(usize);
    try std.testing.expect(!hostile_flac_comments.valid());
    try std.testing.expectError(
        error.InvalidFlacVorbisComments,
        hostile_flac_comments.next(),
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        hostile_flac_comments.offset,
    );
    var stale_flac_vendor = flac_comments;
    stale_flac_vendor.vendor = "stale";
    try std.testing.expect(!stale_flac_vendor.valid());
    const stale_flac_vendor_before = stale_flac_vendor;
    try std.testing.expectError(
        error.InvalidFlacVorbisComments,
        stale_flac_vendor.next(),
    );
    try std.testing.expectEqualDeep(
        stale_flac_vendor_before,
        stale_flac_vendor,
    );
    var flac_decoded: [flac_source.len]i32 = undefined;
    const installed_flac_limits: plugin.dsp.FlacLimits =
        plugin.dsp.default_flac_limits;
    const flac_result = try plugin.dsp.decodeInterleavedFlacWithLimits(
        flac,
        &flac_decoded,
        &.{},
        installed_flac_limits,
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
    var impossible_flac_extent = flac_storage;
    @memset(impossible_flac_extent[12..15], 0);
    impossible_flac_extent[15] = 0;
    impossible_flac_extent[16] = 0;
    impossible_flac_extent[17] = 1;
    flac_decoded = @splat(-765_432);
    try std.testing.expectError(
        error.InvalidFlacFrameSize,
        plugin.dsp.decodeInterleavedFlac(
            impossible_flac_extent[0..flac.len],
            &flac_decoded,
        ),
    );
    try std.testing.expectEqual(
        @as([flac_source.len]i32, @splat(-765_432)),
        flac_decoded,
    );
    var flac_transactional: [flac_source.len]i32 = undefined;
    var flac_decode_scratch: [flac_source.len]i32 = undefined;
    const flac_transactional_result =
        try plugin.dsp.decodeInterleavedFlacTransactional(
            flac,
            &flac_transactional,
            &flac_decode_scratch,
        );
    try std.testing.expectEqual(
        flac_source.len / 2,
        flac_transactional_result.frames_decoded,
    );
    try std.testing.expectEqualSlices(
        i32,
        &flac_source,
        &flac_transactional,
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
    var flac_transactional_range: [8]i32 = undefined;
    var flac_range_output_scratch: [8]i32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        try plugin.dsp.decodeInterleavedFlacRangeTransactional(
            flac,
            3,
            &flac_transactional_range,
            &flac_range_output_scratch,
            &flac_frame_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        i32,
        flac_source[6..14],
        &flac_transactional_range,
    );

    const flac_sentinel = [_]i32{-987_654} ** flac_source.len;
    flac_transactional = flac_sentinel;
    var corrupt_flac_storage = flac_storage;
    corrupt_flac_storage[flac.len - 1] ^= 1;
    try std.testing.expectError(
        error.FlacFrameCrcMismatch,
        plugin.dsp.decodeInterleavedFlacTransactional(
            corrupt_flac_storage[0..flac.len],
            &flac_transactional,
            &flac_decode_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        i32,
        &flac_sentinel,
        &flac_transactional,
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
    var invalid_flac_writer = flac_writer;
    invalid_flac_writer.frames_written = 1;
    const invalid_flac_writer_before = invalid_flac_writer;
    try std.testing.expect(!invalid_flac_writer.recoverable());
    try std.testing.expect(!invalid_flac_writer.valid());
    try std.testing.expectError(
        error.InvalidFlacFileWriterState,
        invalid_flac_writer.append(&.{ 1, -1 }),
    );
    try std.testing.expectEqualDeep(
        invalid_flac_writer_before,
        invalid_flac_writer,
    );
    var finalizing_flac_writer = flac_writer;
    finalizing_flac_writer.finalizing = true;
    const finalizing_flac_writer_before = finalizing_flac_writer;
    try std.testing.expect(finalizing_flac_writer.recoverable());
    try std.testing.expect(!finalizing_flac_writer.valid());
    try std.testing.expectError(
        error.InvalidFlacFileWriterState,
        finalizing_flac_writer.append(&.{ 1, -1 }),
    );
    try std.testing.expectEqualDeep(
        finalizing_flac_writer_before,
        finalizing_flac_writer,
    );
    try flac_writer.append(flac_source[0..10]);
    try flac_writer.append(flac_source[10..]);
    try flac_writer.finalize();
    var streaming_metadata: [128]u8 = undefined;
    const streaming_metadata_bytes =
        try plugin.dsp.requiredFlacFileReaderMetadataBytesWithLimits(
            std.testing.io,
            flac_file,
            installed_flac_limits,
        );
    try std.testing.expectEqual(
        streaming_metadata_bytes,
        try plugin.dsp.FlacFileReader.requiredMetadataBytes(
            std.testing.io,
            flac_file,
        ),
    );
    var streaming_metadata_scratch: [128]u8 = undefined;
    const streaming_reader = try plugin.dsp.FlacFileReader.initTransactionalWithLimits(
        std.testing.io,
        flac_file,
        streaming_metadata[0..streaming_metadata_bytes],
        streaming_metadata_scratch[0..streaming_metadata_bytes],
        installed_flac_limits,
    );
    try std.testing.expect(streaming_reader.valid());
    const published_streaming_metadata = streaming_metadata;
    try std.testing.expectError(
        error.FlacMetadataBufferTooSmall,
        plugin.dsp.FlacFileReader.initTransactional(
            std.testing.io,
            flac_file,
            streaming_metadata[0 .. streaming_metadata_bytes - 1],
            streaming_metadata_scratch[0..streaming_metadata_bytes],
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &published_streaming_metadata,
        &streaming_metadata,
    );
    try std.testing.expectError(
        error.OverlappingFlacBuffers,
        plugin.dsp.FlacFileReader.initTransactional(
            std.testing.io,
            flac_file,
            streaming_metadata[0..streaming_metadata_bytes],
            streaming_metadata[0..streaming_metadata_bytes],
        ),
    );
    var malformed_streaming_reader = streaming_reader;
    malformed_streaming_reader.info.channel_count = 0;
    try std.testing.expect(!malformed_streaming_reader.valid());
    try std.testing.expect(
        malformed_streaming_reader.seekTableIterator() == null,
    );
    var impossible_streaming_extent = streaming_reader;
    impossible_streaming_extent.file_size =
        impossible_streaming_extent.audio_offset + 1;
    try std.testing.expect(!impossible_streaming_extent.valid());
    const streaming_seek_offset =
        @intFromPtr(streaming_reader.seek_table_payload.ptr) -
        @intFromPtr(streaming_metadata[0..].ptr);
    var impossible_seek_metadata = streaming_metadata;
    var impossible_streaming_seek = streaming_reader;
    impossible_streaming_seek.seek_table_payload =
        impossible_seek_metadata[streaming_seek_offset..][0..streaming_reader.seek_table_payload.len];
    std.mem.writeInt(
        u64,
        impossible_seek_metadata[streaming_seek_offset..][0..8],
        1,
        .big,
    );
    try std.testing.expect(!impossible_streaming_seek.valid());
    var impossible_seek_length_metadata = streaming_metadata;
    var impossible_streaming_seek_length = streaming_reader;
    impossible_streaming_seek_length.seek_table_payload =
        impossible_seek_length_metadata[streaming_seek_offset..][0..streaming_reader.seek_table_payload.len];
    std.mem.writeInt(
        u16,
        impossible_seek_length_metadata[streaming_seek_offset + 16 ..][0..2],
        1,
        .big,
    );
    try std.testing.expect(!impossible_streaming_seek_length.valid());
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
    var streaming_transactional: [flac_source.len]i32 = undefined;
    var streaming_output_scratch: [flac_source.len]i32 = undefined;
    const streaming_transactional_result =
        try streaming_reader.decodeTransactional(
            &streaming_transactional,
            &streaming_output_scratch,
            &streaming_frame,
            &.{},
        );
    try std.testing.expectEqual(
        flac_source.len / 2,
        streaming_transactional_result.frames_decoded,
    );
    try std.testing.expectEqualSlices(
        i32,
        &flac_source,
        &streaming_transactional,
    );
    var streaming_transactional_range: [8]i32 = undefined;
    var streaming_range_output_scratch: [8]i32 = undefined;
    var streaming_decoded_frame_scratch: [32]i32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        try streaming_reader.decodeRangeTransactional(
            3,
            &streaming_transactional_range,
            &streaming_range_output_scratch,
            &streaming_frame,
            &streaming_decoded_frame_scratch,
            &.{},
        ),
    );
    try std.testing.expectEqualSlices(
        i32,
        flac_source[6..14],
        &streaming_transactional_range,
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
    var incremental_transactional: [flac_source.len]i32 = undefined;
    var incremental_output_scratch: [flac_source.len]i32 = undefined;
    const incremental_transactional_result =
        try plugin.dsp.readInterleavedFlacFileTransactional(
            std.testing.io,
            flac_file,
            &incremental_file_bytes,
            &incremental_transactional,
            &incremental_output_scratch,
        );
    try std.testing.expectEqual(
        flac_source.len / 2,
        incremental_transactional_result.frames_decoded,
    );
    try std.testing.expectEqualSlices(
        i32,
        &flac_source,
        &incremental_transactional,
    );
    var incremental_range: [8]i32 = undefined;
    var incremental_range_output_scratch: [8]i32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        try plugin.dsp.readInterleavedFlacFileRangeTransactional(
            std.testing.io,
            flac_file,
            &incremental_file_bytes,
            3,
            &incremental_range,
            &incremental_range_output_scratch,
            &streaming_decoded_frame_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        i32,
        flac_source[6..14],
        &incremental_range,
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
    var impossible_ogg_writer = ogg_writer;
    impossible_ogg_writer.sequence_number = 1;
    const impossible_ogg_writer_before = impossible_ogg_writer;
    try std.testing.expect(!impossible_ogg_writer.valid());
    try std.testing.expectError(
        error.InvalidOggStreamWriterState,
        impossible_ogg_writer.appendPacket(
            "installed packet",
            1,
            true,
            true,
        ),
    );
    try std.testing.expectEqualDeep(
        impossible_ogg_writer_before,
        impossible_ogg_writer,
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
    try std.testing.expect(ogg_packets.valid());
    const ogg_packet = (try ogg_packets.next()).?;
    try std.testing.expect(ogg_packet.beginning);
    try std.testing.expect(ogg_packet.end);
    try std.testing.expectEqualStrings(
        "installed packet",
        ogg_packet.bytes,
    );
    var detached_ogg_page = ogg_packets;
    var detached_ogg_lacing = [_]u8{
        detached_ogg_page.page.?.lacing_values[0],
    };
    detached_ogg_page.page.?.lacing_values = &detached_ogg_lacing;
    try std.testing.expect(!detached_ogg_page.valid());
    const detached_ogg_page_before = detached_ogg_page;
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        detached_ogg_page.next(),
    );
    try std.testing.expectEqualDeep(
        detached_ogg_page_before,
        detached_ogg_page,
    );

    var transactional_ogg_destination: [32]u8 = @splat(0xa5);
    const transactional_ogg_untouched = transactional_ogg_destination;
    var transactional_ogg_packets = plugin.dsp.OggPacketIterator.init(
        ogg_writer.bytes(),
        &transactional_ogg_destination,
    );
    var short_ogg_scratch: [8]u8 = undefined;
    const transactional_ogg_before = transactional_ogg_packets;
    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        transactional_ogg_packets.nextTransactional(&short_ogg_scratch),
    );
    try std.testing.expectEqualDeep(
        transactional_ogg_before,
        transactional_ogg_packets,
    );
    try std.testing.expectEqualSlices(
        u8,
        &transactional_ogg_untouched,
        &transactional_ogg_destination,
    );
    var transactional_ogg_scratch: [32]u8 = undefined;
    const transactional_ogg_packet =
        (try transactional_ogg_packets.nextTransactional(
            &transactional_ogg_scratch,
        )).?;
    try std.testing.expectEqualStrings(
        "installed packet",
        transactional_ogg_packet.bytes,
    );
    try std.testing.expectEqual(
        @intFromPtr(transactional_ogg_destination[0..].ptr),
        @intFromPtr(transactional_ogg_packet.bytes.ptr),
    );
    var hostile_ogg_packets = ogg_packets;
    hostile_ogg_packets.pages.expected_sequence = null;
    try std.testing.expect(!hostile_ogg_packets.valid());
    try std.testing.expectError(
        error.InvalidOggReaderState,
        hostile_ogg_packets.next(),
    );
    ogg_writer.byte_count = std.math.maxInt(usize);
    try std.testing.expect(!ogg_writer.valid());
    try std.testing.expectEqual(@as(usize, 0), ogg_writer.bytes().len);
    try std.testing.expectError(
        error.InvalidOggStreamWriterState,
        ogg_writer.appendPacket("more", 2, false, true),
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        ogg_writer.byte_count,
    );

    var vorbis_packet_storage: [1]u8 = .{0};
    var vorbis_writer = plugin.dsp.VorbisPacketWriter.init(
        &vorbis_packet_storage,
    );
    vorbis_writer.bit_offset = std.math.maxInt(usize);
    try std.testing.expect(!vorbis_writer.valid());
    try std.testing.expectEqual(@as(usize, 0), vorbis_writer.bytes().len);
    try std.testing.expectError(
        error.InvalidVorbisPacketWriterState,
        vorbis_writer.writeBits(1, 1),
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        vorbis_writer.bit_offset,
    );
    const quality_reference = [_]f32{ 1, -1, 0.5, -0.5 };
    const quality_candidate = [_]f32{ 0.5, -0.5, 0.25, -0.25 };
    var quality_meter = plugin.dsp.VorbisPcmQualityMeter{};
    try quality_meter.update(
        f32,
        &.{&quality_reference},
        &.{&quality_candidate},
    );
    const quality: plugin.dsp.VorbisPcmQualityMeasurement =
        try quality_meter.measurement();
    try std.testing.expectEqual(@as(u64, 4), quality.sample_count);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        quality.normalized_rms_error,
        1.0e-12,
    );
    const retained_quality_meter = quality_meter;
    quality_meter.peak_absolute_error = 0;
    try std.testing.expect(!quality_meter.valid());
    const invalid_peak_quality_meter = quality_meter;
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        quality_meter.measurement(),
    );
    try std.testing.expectEqualDeep(
        invalid_peak_quality_meter,
        quality_meter,
    );
    const quality_silence = [_]f32{ 0, 0 };
    const quality_signal = [_]f32{ 0.25, -0.5 };
    var silent_reference_quality_meter =
        plugin.dsp.VorbisPcmQualityMeter{};
    try silent_reference_quality_meter.update(
        f32,
        &.{&quality_silence},
        &.{&quality_signal},
    );
    silent_reference_quality_meter.cross_energy = 1;
    const invalid_silent_reference_meter = silent_reference_quality_meter;
    try std.testing.expect(!silent_reference_quality_meter.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        silent_reference_quality_meter.measurement(),
    );
    try std.testing.expectEqualDeep(
        invalid_silent_reference_meter,
        silent_reference_quality_meter,
    );
    var exact_quality_meter = plugin.dsp.VorbisPcmQualityMeter{};
    try exact_quality_meter.update(
        f32,
        &.{&quality_signal},
        &.{&quality_signal},
    );
    exact_quality_meter.cross_energy += 1;
    const invalid_exact_quality_meter = exact_quality_meter;
    try std.testing.expect(!exact_quality_meter.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        exact_quality_meter.measurement(),
    );
    try std.testing.expectEqualDeep(
        invalid_exact_quality_meter,
        exact_quality_meter,
    );
    var silent_candidate_quality_meter =
        plugin.dsp.VorbisPcmQualityMeter{};
    try silent_candidate_quality_meter.update(
        f32,
        &.{&quality_signal},
        &.{&quality_silence},
    );
    silent_candidate_quality_meter.error_energy += 1;
    try std.testing.expect(!silent_candidate_quality_meter.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        silent_candidate_quality_meter.measurement(),
    );
    quality_meter = retained_quality_meter;
    quality_meter.error_energy = std.math.nan(f128);
    try std.testing.expect(!quality_meter.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmQualityMeter,
        quality_meter.measurement(),
    );
    quality_meter = retained_quality_meter;
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
    const indexed_ogg_bytes = indexed_ogg_writer.bytes();
    var clean_pages = plugin.dsp.OggPageIterator.init(
        indexed_ogg_bytes,
    );
    const first_clean_page = (try clean_pages.next()).?;
    var impossible_pages = plugin.dsp.OggPageIterator.init(
        indexed_ogg_bytes,
    );
    impossible_pages.packet_continues = true;
    try std.testing.expect(!impossible_pages.valid());
    const impossible_pages_before = impossible_pages;
    try std.testing.expectError(
        error.InvalidOggReaderState,
        impossible_pages.next(),
    );
    try std.testing.expectEqual(
        impossible_pages_before,
        impossible_pages,
    );
    const inserted_junk = [_]u8{ 0x49, 0x44, 0x33 };
    const insertion_offset: usize =
        @intCast(first_clean_page.byte_length);
    var damaged_ogg_storage: [
        indexed_ogg_storage.len +
            inserted_junk.len
    ]u8 = undefined;
    @memcpy(
        damaged_ogg_storage[0..insertion_offset],
        indexed_ogg_bytes[0..insertion_offset],
    );
    @memcpy(
        damaged_ogg_storage[insertion_offset..][0..inserted_junk.len],
        &inserted_junk,
    );
    @memcpy(
        damaged_ogg_storage[insertion_offset + inserted_junk.len ..][0 .. indexed_ogg_bytes.len - insertion_offset],
        indexed_ogg_bytes[insertion_offset..],
    );
    var damaged_pages = plugin.dsp.OggPageIterator.init(
        damaged_ogg_storage[0 .. indexed_ogg_bytes.len + inserted_junk.len],
    );
    _ = try damaged_pages.next();
    try std.testing.expectEqual(
        inserted_junk.len,
        try damaged_pages.resynchronize(inserted_junk.len),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        (try damaged_pages.next()).?.sequence_number,
    );
    var damaged_packet_storage: [8]u8 = undefined;
    var damaged_packets = plugin.dsp.OggPacketIterator.init(
        damaged_ogg_storage[0 .. indexed_ogg_bytes.len + inserted_junk.len],
        &damaged_packet_storage,
    );
    var impossible_packet_counts = damaged_packets;
    impossible_packet_counts.logical_stream_packet_index = 1;
    try std.testing.expect(!impossible_packet_counts.valid());
    const impossible_packet_counts_before =
        impossible_packet_counts;
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        impossible_packet_counts.next(),
    );
    try std.testing.expectEqualDeep(
        impossible_packet_counts_before,
        impossible_packet_counts,
    );
    try std.testing.expectEqualStrings(
        "header 1",
        (try damaged_packets.next()).?.bytes,
    );
    try std.testing.expectEqual(
        inserted_junk.len,
        try damaged_packets.resynchronize(inserted_junk.len),
    );
    try std.testing.expectEqualStrings(
        "header 2",
        (try damaged_packets.next()).?.bytes,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        try plugin.dsp.requiredVorbisSeekPoints(
            indexed_ogg_bytes,
        ),
    );
    var installed_seek_points: [2]plugin.dsp.VorbisSeekPoint =
        undefined;
    const installed_seek_index = try plugin.dsp.buildVorbisSeekIndex(
        indexed_ogg_bytes,
        &installed_seek_points,
    );
    var indexed_ogg_temporary = std.testing.tmpDir(.{});
    defer indexed_ogg_temporary.cleanup();
    var indexed_ogg_file = try indexed_ogg_temporary.dir.createFile(
        std.testing.io,
        "indexed.ogg",
        .{ .read = true },
    );
    defer indexed_ogg_file.close(std.testing.io);
    try indexed_ogg_file.writePositionalAll(
        std.testing.io,
        indexed_ogg_bytes,
        0,
    );
    try indexed_ogg_file.setLength(
        std.testing.io,
        indexed_ogg_bytes.len,
    );
    var installed_file_page_storage: [plugin.dsp.maximum_ogg_page_bytes]u8 = undefined;
    var installed_file_seek_points: [2]plugin.dsp.VorbisSeekPoint =
        undefined;
    var installed_file_seek_scratch: [2]plugin.dsp.VorbisSeekPoint =
        undefined;
    const installed_file_seek_index =
        try plugin.dsp.buildVorbisFileSeekIndexTransactional(
            std.testing.io,
            indexed_ogg_file,
            &installed_file_page_storage,
            &installed_file_seek_points,
            &installed_file_seek_scratch,
        );
    try std.testing.expectEqualSlices(
        plugin.dsp.VorbisSeekPoint,
        installed_seek_index,
        installed_file_seek_index,
    );
    var installed_aliased_page_storage: [plugin.dsp.maximum_ogg_page_bytes]u8 align(@alignOf(plugin.dsp.VorbisSeekPoint)) = undefined;
    const installed_page_aliased_seek_scratch = std.mem.bytesAsSlice(
        plugin.dsp.VorbisSeekPoint,
        installed_aliased_page_storage[0 .. 2 * @sizeOf(plugin.dsp.VorbisSeekPoint)],
    );
    const installed_file_seek_before = installed_file_seek_points;
    try std.testing.expectError(
        error.OverlappingVorbisSeekStorage,
        plugin.dsp.buildVorbisFileSeekIndexTransactional(
            std.testing.io,
            indexed_ogg_file,
            &installed_aliased_page_storage,
            &installed_file_seek_points,
            installed_page_aliased_seek_scratch,
        ),
    );
    try std.testing.expectEqual(
        installed_file_seek_before,
        installed_file_seek_points,
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
        try std.testing.expectApproxEqAbs(expected * 2, actual, 0.000_01);
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
    try std.testing.expect(installed_block_classifier.valid());
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
    try std.testing.expect(installed_block_classifier.valid());
    try std.testing.expect(
        installed_block_classifier.short_blocks_remaining != 0,
    );
    var installed_invalid_hold = installed_block_classifier;
    installed_invalid_hold.large_block = true;
    const installed_invalid_hold_before = installed_invalid_hold;
    try std.testing.expect(!installed_invalid_hold.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockClassifierState,
        installed_invalid_hold.classify(
            f32,
            &.{&synthesized_block},
            64,
            64,
            plugin.dsp.VorbisPcmBlockClassifierConfig{},
        ),
    );
    try std.testing.expectEqualDeep(
        installed_invalid_hold_before,
        installed_invalid_hold,
    );
    var installed_invalid_classifier = installed_block_classifier;
    installed_invalid_classifier.smoothed_mean_square = -1;
    try std.testing.expect(!installed_invalid_classifier.valid());
    const installed_invalid_classifier_before = installed_invalid_classifier;
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockClassifierState,
        installed_invalid_classifier.classify(
            f32,
            &.{&synthesized_block},
            64,
            64,
            plugin.dsp.VorbisPcmBlockClassifierConfig{},
        ),
    );
    try std.testing.expectEqualDeep(
        installed_invalid_classifier_before,
        installed_invalid_classifier,
    );
    var installed_psychoacoustic_floor: [32]f32 = undefined;
    var installed_noise_threshold: [32]f32 = undefined;
    const installed_quality_preset =
        plugin.dsp.VorbisQualityPreset.q4.applyTo(.{});
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.4),
        installed_quality_preset.quality,
        1.0e-15,
    );
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
    overlap.previous_size = 3;
    try std.testing.expect(!overlap.valid());
    try std.testing.expect(!overlap.primed());
    try std.testing.expectEqual(
        @as(usize, 0),
        overlap.previousBlockSize(),
    );
    try std.testing.expectError(
        error.InvalidVorbisOverlapState,
        overlap.push(&time_domain, &finished),
    );
    overlap.reset();
    try std.testing.expectEqual(
        [_]f32{0} ** 64,
        overlap.previous,
    );
    try std.testing.expectEqual(
        [_]f32{0} ** 32,
        overlap.pending,
    );
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
    channel_overlap.channels[0].previous_size = 3;
    try std.testing.expect(!channel_overlap.valid());
    try std.testing.expectError(
        error.InvalidVorbisChannelOverlapState,
        channel_overlap.previousBlockSize(),
    );
    channel_overlap.reset();
    try std.testing.expectEqual(
        [_]f32{0} ** 64,
        channel_overlap.channels[0].previous,
    );
    try std.testing.expectEqual(
        [_]f32{0} ** 32,
        channel_overlap.channels[0].pending,
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
    var installed_packet_reader = try plugin.dsp.VorbisPacketReader.init(
        &.{0},
        0,
    );
    try std.testing.expect(installed_packet_reader.valid());
    installed_packet_reader.bit_offset = std.math.maxInt(usize);
    try std.testing.expect(!installed_packet_reader.valid());
    try std.testing.expectError(
        error.InvalidVorbisPacketBitOffset,
        installed_packet_reader.decodeScalar(installed_setup, 0),
    );
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        installed_packet_reader.bit_offset,
    );

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
    try std.testing.expect(installed_lookahead.valid());
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
    try std.testing.expect(installed_lookahead.valid());
    var installed_invalid_lookahead = installed_lookahead;
    installed_invalid_lookahead.frames.center = -1;
    try std.testing.expect(!installed_invalid_lookahead.valid());
    const installed_invalid_lookahead_before = installed_invalid_lookahead;
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockLookaheadState,
        installed_invalid_lookahead.prime(installed_block_analysis),
    );
    try std.testing.expectEqualDeep(
        installed_invalid_lookahead_before,
        installed_invalid_lookahead,
    );
    var installed_frame_planner =
        plugin.dsp.VorbisPcmFramePlanner.init(false);
    try std.testing.expect(installed_frame_planner.valid());
    var installed_invalid_frame_planner = installed_frame_planner;
    installed_invalid_frame_planner.packet_index = std.math.maxInt(u64);
    const installed_invalid_frame_planner_before =
        installed_invalid_frame_planner;
    try std.testing.expect(!installed_invalid_frame_planner.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmFramePlannerState,
        installed_invalid_frame_planner.plan(
            installed_identification,
            installed_setup,
            0,
            false,
            false,
        ),
    );
    try std.testing.expectEqualDeep(
        installed_invalid_frame_planner_before,
        installed_invalid_frame_planner,
    );
    var installed_misaligned_frame_planner =
        plugin.dsp.VorbisPcmFramePlanner.init(false);
    installed_misaligned_frame_planner.packet_index = 1;
    installed_misaligned_frame_planner.center = 33;
    const installed_misaligned_frame_planner_before =
        installed_misaligned_frame_planner;
    try std.testing.expect(!installed_misaligned_frame_planner.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmFramePlannerState,
        installed_misaligned_frame_planner.plan(
            installed_identification,
            installed_setup,
            0,
            false,
            false,
        ),
    );
    try std.testing.expectEqualDeep(
        installed_misaligned_frame_planner_before,
        installed_misaligned_frame_planner,
    );
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
    try std.testing.expect(installed_frame_planner.valid());
    var installed_sequence =
        try plugin.dsp.VorbisPcmPacketSequence.init(
            plugin.dsp.VorbisPcmPacketSequenceConfig{
                .rate_control = .{
                    .target_bitrate = 48_000,
                    .reservoir_capacity_bits = 1_024,
                },
                .adaptive_rate = .{},
            },
            false,
        );
    try std.testing.expect(installed_sequence.valid());
    _ = try installed_sequence.prime(
        f32,
        &.{&synthesized_block},
        installed_identification,
    );
    try std.testing.expect(installed_sequence.valid());
    var installed_invalid_classifier_schedule = installed_sequence;
    installed_invalid_classifier_schedule
        .classifier.short_blocks_remaining = 0;
    installed_invalid_classifier_schedule.classifier.large_block =
        !installed_invalid_classifier_schedule
            .lookahead.pending_large_block.?;
    try std.testing.expect(
        installed_invalid_classifier_schedule.classifier.valid(),
    );
    const installed_invalid_classifier_schedule_before =
        installed_invalid_classifier_schedule;
    try std.testing.expect(!installed_invalid_classifier_schedule.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketSequenceState,
        installed_invalid_classifier_schedule.planNext(
            f32,
            &.{&synthesized_block},
            installed_identification,
            installed_setup,
        ),
    );
    try std.testing.expectEqualDeep(
        installed_invalid_classifier_schedule_before,
        installed_invalid_classifier_schedule,
    );
    var installed_invalid_sequence = installed_sequence;
    installed_invalid_sequence.revision += 1;
    try std.testing.expect(!installed_invalid_sequence.valid());
    const installed_invalid_sequence_before = installed_invalid_sequence;
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketSequenceState,
        installed_invalid_sequence.planNext(
            f32,
            &.{&synthesized_block},
            installed_identification,
            installed_setup,
        ),
    );
    try std.testing.expectEqualDeep(
        installed_invalid_sequence_before,
        installed_invalid_sequence,
    );
    const installed_first_packet_plan: plugin.dsp.VorbisPcmPacketPlan =
        try installed_sequence.planNext(
            f32,
            &.{&synthesized_block},
            installed_identification,
            installed_setup,
        );
    var installed_forged_plan = installed_first_packet_plan;
    installed_forged_plan.frame.source_start += 1;
    const installed_sequence_before_forgery = installed_sequence;
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketPlan,
        installed_sequence.commit(installed_forged_plan, 1),
    );
    try std.testing.expectEqualDeep(
        installed_sequence_before_forgery,
        installed_sequence,
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
    try std.testing.expect(
        installed_sequence.classifier.short_blocks_remaining != 0,
    );
    var installed_invalid_hold_sequence = installed_sequence;
    installed_invalid_hold_sequence.classifier.large_block = true;
    const installed_invalid_hold_sequence_before =
        installed_invalid_hold_sequence;
    try std.testing.expect(!installed_invalid_hold_sequence.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketSequenceState,
        installed_invalid_hold_sequence.planFinish(
            installed_identification,
            installed_setup,
            32,
        ),
    );
    try std.testing.expectEqualDeep(
        installed_invalid_hold_sequence_before,
        installed_invalid_hold_sequence,
    );
    var installed_impossible_granule = installed_sequence;
    installed_impossible_granule.granule_position = @intCast(
        installed_impossible_granule.lookahead.frames.center,
    );
    const installed_impossible_granule_before =
        installed_impossible_granule;
    try std.testing.expect(!installed_impossible_granule.valid());
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketSequenceState,
        installed_impossible_granule.planFinish(
            installed_identification,
            installed_setup,
            32,
        ),
    );
    try std.testing.expectEqualDeep(
        installed_impossible_granule_before,
        installed_impossible_granule,
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
    try std.testing.expect(installed_sequence.valid());
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
    try std.testing.expect(installed_reservoir.valid());
    var installed_corrupt_reservoir = installed_reservoir;
    var installed_corrupt_budget = installed_budget;
    installed_corrupt_budget.packet_index += 1;
    installed_corrupt_reservoir.pending = installed_corrupt_budget;
    try std.testing.expect(!installed_corrupt_reservoir.valid());
    const installed_corrupt_before = installed_corrupt_reservoir;
    try std.testing.expectError(
        error.InvalidVorbisBitReservoirState,
        installed_corrupt_reservoir.cancel(),
    );
    try std.testing.expectEqualDeep(
        installed_corrupt_before,
        installed_corrupt_reservoir,
    );
    const installed_adaptive_policy =
        plugin.dsp.VorbisAdaptiveRatePolicyConfig{};
    const installed_adaptive_decision: plugin.dsp.VorbisAdaptiveRateDecision =
        try plugin.dsp.adaptVorbisPacketBitBudget(
            installed_budget,
            installed_classification,
            installed_reservoir.config,
            installed_adaptive_policy,
        );
    try std.testing.expect(
        installed_adaptive_decision.budget.target_bits >= 1,
    );
    var installed_quality_controller =
        try plugin.dsp.VorbisQualityRateController.init(
            plugin.dsp.VorbisQualityRateControllerConfig{
                .minimum_quality = 0.4,
                .maximum_quality = 0.9,
                .initial_quality = 0.7,
                .adjustment_per_packet = 0.05,
                .headroom_ratio = 0.1,
            },
        );
    const installed_psychoacoustic_config =
        try installed_quality_controller.applyTo(.{});
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.7),
        installed_psychoacoustic_config.quality,
        1.0e-15,
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
    const installed_quality_decision: plugin.dsp.VorbisQualitySignalDecision =
        try installed_quality_controller.observeSignal(
            installed_budget,
            installed_rate_commit,
            &.{plugin.dsp.VorbisAudioResidueSubmapResult{
                .target_bits = installed_bit_allocation.residue_bits,
                .encoded_bits = installed_bit_allocation.residue_bits,
                .budget_met = true,
                .squared_error = 0,
                .weighted_squared_error = 0,
                .audible_excess_power = 0,
                .lambda = 0,
                .iterations = 0,
            }},
        );
    try std.testing.expectEqual(
        plugin.dsp.VorbisQualityRateAction.hold,
        installed_quality_decision.rate.action,
    );
    try std.testing.expect(installed_quality_decision.within_mask);
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
    const installed_trial_quality_decision: plugin.dsp.VorbisQualitySignalDecision =
        try installed_quality_controller.observePcmPacketTrial(
            f32,
            installed_encoding_plan,
            installed_encoding_trial,
        );
    try std.testing.expect(
        std.math.isFinite(
            installed_trial_quality_decision.audible_excess_power,
        ),
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
    var node_overlap_setup = quantizer_setup;
    node_overlap_setup.summary.codebook_count = 1;
    node_overlap_setup.summary.codebook_entry_count = 2;
    node_overlap_setup.summary.huffman_node_count = 1;
    node_overlap_setup.summary.codebook_multiplicand_count = 2;
    node_overlap_setup.summary.maximum_codebook_dimensions = 1;
    node_overlap_setup.summary.maximum_codebook_entries = 2;
    var installed_node_overlap: [256]u8 align(@alignOf(plugin.dsp.VorbisHuffmanNode)) = @splat(0x5a);
    const installed_overlapping_nodes = std.mem.bytesAsSlice(
        plugin.dsp.VorbisHuffmanNode,
        installed_node_overlap[0 .. node_overlap_setup.huffman_nodes.len *
            @sizeOf(plugin.dsp.VorbisHuffmanNode)],
    );
    @memcpy(
        installed_overlapping_nodes,
        node_overlap_setup.huffman_nodes,
    );
    var installed_overlapping_setup = node_overlap_setup;
    installed_overlapping_setup.huffman_nodes =
        installed_overlapping_nodes;
    const installed_node_before = installed_node_overlap;
    try std.testing.expectError(
        error.OverlappingVorbisSetupStorage,
        plugin.dsp.encodeVorbisSetupPacket(
            &installed_node_overlap,
            installed_overlapping_setup,
            1,
        ),
    );
    try std.testing.expectEqual(
        installed_node_before,
        installed_node_overlap,
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
    try std.testing.expect(!installed_result.floor_truncated);
    try std.testing.expect(!installed_result.residue_truncated);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 64),
        &installed_output,
    );
    var granules = plugin.dsp.VorbisGranuleTracker{};
    try std.testing.expect(granules.valid());
    const granule_range = try granules.trim(32, 28, true);
    try std.testing.expectEqual(@as(usize, 0), granule_range.source_start);
    try std.testing.expectEqual(@as(usize, 28), granule_range.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), granule_range.pcm_start);
    try std.testing.expect(granules.valid());
    var installed_invalid_granules = granules;
    installed_invalid_granules.decoded_samples = std.math.maxInt(u64);
    try std.testing.expect(!installed_invalid_granules.valid());
    const installed_invalid_granules_before = installed_invalid_granules;
    try std.testing.expectError(
        error.InvalidVorbisGranuleTrackerState,
        installed_invalid_granules.trim(32, 60, true),
    );
    try std.testing.expectEqualDeep(
        installed_invalid_granules_before,
        installed_invalid_granules,
    );
    const installed_overflowing_granules = plugin.dsp.VorbisGranuleTracker{
        .decoded_samples = 1,
        .position_offset = std.math.maxInt(i64),
    };
    try std.testing.expect(!installed_overflowing_granules.valid());

    var installed_stream =
        plugin.dsp.VorbisPcmStreamDecoder(f32, 1, 64, 64).init();
    try std.testing.expect(installed_stream.valid());
    var installed_invalid_stream = installed_stream;
    installed_invalid_stream.concealed_packet_count = 1;
    try std.testing.expect(!installed_invalid_stream.valid());
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
    var installed_impossible_packet_timeline = installed_stream;
    installed_impossible_packet_timeline.audio_packet_count = 2;
    try std.testing.expect(!installed_impossible_packet_timeline.valid());
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

    var installed_concealing_stream =
        plugin.dsp.VorbisPcmStreamDecoder(f32, 1, 64, 64).init();
    _ = try installed_concealing_stream.concealMissingPacket(
        false,
        std.math.maxInt(u64),
        false,
        installed_identification,
        &installed_empty_outputs,
        &installed_stream_windowed,
    );
    const installed_concealment: plugin.dsp.VorbisPcmConcealmentResult =
        try installed_concealing_stream
            .concealMissingPacketUsingPreviousBlockSize(
            32,
            true,
            installed_identification,
            &installed_stream_outputs,
            &installed_stream_windowed,
        );
    try std.testing.expectEqual(
        @as(u64, 2),
        installed_concealment.concealed_packet_count,
    );
    const InstalledVorbisDecoder =
        plugin.dsp.VorbisPcmStreamDecoder(f32, 1, 64, 64);
    var installed_signal_stream = InstalledVorbisDecoder.init();
    const installed_retained_window = [_]f32{1} ** 64;
    _ = try installed_signal_stream.overlap.push(
        &[_][]const f32{&installed_retained_window},
        &installed_empty_outputs,
    );
    installed_signal_stream.audio_packet_count = 1;
    const installed_signal_config: plugin.dsp.VorbisPcmSignalConcealmentConfig = .{};
    const installed_signal_concealment =
        try installed_signal_stream
            .concealMissingPacketUsingPreviousBlockSignal(
            installed_signal_config,
            32,
            false,
            installed_identification,
            &installed_stream_outputs,
            &installed_stream_windowed,
        );
    try std.testing.expectEqual(
        @as(usize, 32),
        installed_signal_concealment.sample_count,
    );
    try std.testing.expect(installed_output[0] > 1);
    try std.testing.expect(@hasDecl(
        plugin.dsp.VorbisChainedPcmStreamDecoder(f32, 1, 64, 64),
        "concealMissingPacketUsingPreviousBlockSignal",
    ));
    const installed_following_header = plugin.dsp.VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 1,
    };
    try std.testing.expect(
        !try plugin.dsp.inferVorbisMissingPacketLargeBlock(
            installed_identification,
            installed_following_header,
        ),
    );
    var installed_mixed_identification = installed_identification;
    installed_mixed_identification.large_block_size = 256;
    try std.testing.expect(
        !try plugin.dsp
            .inferVorbisMissingPacketLargeBlockFromFollowingGranule(
            installed_mixed_identification,
            64,
            installed_following_header,
            .{
                .decoded_samples = 32,
                .position_offset = 0,
            },
            96,
            false,
        ),
    );

    var installed_chained =
        plugin.dsp.VorbisChainedPcmStreamDecoder(
            f32,
            1,
            64,
            64,
        ).init();
    try std.testing.expect(installed_chained.valid());
    var installed_invalid_chained = installed_chained;
    installed_invalid_chained.sample_rate = 48_000;
    try std.testing.expect(!installed_invalid_chained.valid());
    const installed_invalid_chained_before = installed_invalid_chained;
    try std.testing.expectError(
        error.InvalidVorbisChainedPcmStreamState,
        installed_invalid_chained.beginLogicalStream(
            installed_identification,
        ),
    );
    try std.testing.expectEqualDeep(
        installed_invalid_chained_before,
        installed_invalid_chained,
    );
    try installed_chained.beginLogicalStream(installed_identification);
    try std.testing.expect(installed_chained.valid());
    _ = try installed_chained.decode(
        .{
            .bytes = &.{0},
            .granule_position = std.math.maxInt(u64),
            .beginning = true,
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
    var installed_impossible_chained_output = installed_chained;
    installed_impossible_chained_output.current_stream_pcm = 1;
    try std.testing.expect(!installed_impossible_chained_output.valid());
    const installed_chain_end = try installed_chained.decode(
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
        @as(u64, 0),
        installed_chain_end.global_pcm_start,
    );
    try std.testing.expectEqual(
        @as(u64, 32),
        installed_chain_end.global_pcm_end,
    );
    var installed_chained_concealment =
        plugin.dsp.VorbisChainedPcmStreamDecoder(
            f32,
            1,
            64,
            64,
        ).init();
    try installed_chained_concealment.beginLogicalStream(
        installed_identification,
    );
    _ = try installed_chained_concealment.concealMissingPacket(
        false,
        std.math.maxInt(u64),
        false,
        installed_identification,
        &installed_empty_outputs,
        &installed_stream_windowed,
    );
    const installed_chained_loss: plugin.dsp.VorbisChainedPcmConcealmentResult =
        try installed_chained_concealment
            .concealMissingPacketUsingPreviousBlockSize(
            32,
            true,
            installed_identification,
            &installed_stream_outputs,
            &installed_stream_windowed,
        );
    try std.testing.expectEqual(
        @as(u64, 32),
        installed_chained_loss.global_pcm_end,
    );
    try installed_chained.beginLogicalStream(installed_identification);
    try std.testing.expectEqual(
        @as(u64, 32),
        installed_chained.completed_pcm,
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

    var editor = plugin.gui_ir_editor.Editor(2){};
    editor.sample_rate = 48_000;
    editor.channels = 1;
    editor.original_frames = 2;
    editor.edited_frames = 2;
    editor.generation = 1;
    editor.original_peak = 0.5;
    editor.edited_peak = 0.5;
    editor.original[0] = 0.25;
    editor.original[1] = 0.5;
    editor.edited[0] = 0.25;
    editor.edited[1] = std.math.nan(f32);
    var output: [2]f32 = @splat(9.0);
    try std.testing.expectEqual(
        @as(usize, 0),
        editor.copyDecoded(0, &output),
    );
    try std.testing.expectEqual(@as(f32, 9.0), output[0]);
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

    const SampleStore = plugin.gui_audio_sample_store.Store(2);
    var sample_store: SampleStore = .{};
    try sample_store.begin(.{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 1,
    });
    try sample_store.write(1, 0, &.{0.25});
    try sample_store.commit(1);
    try std.testing.expect(sample_store.adoptPending());
    try sample_store.begin(.{
        .generation = 2,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 1,
    });
    try sample_store.write(2, 0, &.{0.5});
    try sample_store.commit(2);
    const malformed_slot = sample_store.pending_slot.load(.acquire);
    sample_store.slots[malformed_slot].metadata.channels = 0;
    try std.testing.expect(!sample_store.adoptPending());
    try std.testing.expectEqual(
        @as(u64, 1),
        sample_store.activeMetadata().?.generation,
    );

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
    try std.testing.expect(convolver.valid());
    try std.testing.expectEqual(@as(usize, 0), convolver.latencySamples());
    try convolver.begin(.{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 1,
    });
    try convolver.write(1, 0, &.{1.0});
    try convolver.commit(1);
    try std.testing.expect(convolver.valid());
    try std.testing.expect(convolver.adoptPending());
    try std.testing.expect(convolver.valid());
    try std.testing.expectEqual(
        @as([2]f32, .{ 0.5, 0.5 }),
        convolver.processFrame(1.0, 0.0),
    );
    try std.testing.expect(convolver.valid());
    convolver.output_index = Convolver.latency_samples;
    try std.testing.expect(!convolver.valid());
    try std.testing.expectEqual(
        @as([2]f32, .{ 0.0, 0.0 }),
        convolver.processFrame(1.0, 0.0),
    );
    convolver.resetProcessing();
    try std.testing.expect(convolver.valid());

    const Queue = plugin.dsp.ConvolutionPreparationQueue(16, 2);
    var queue = Queue{};
    try std.testing.expect(queue.valid());
    try queue.submit(
        .{
            .generation = 2,
            .sample_rate = 48_000,
            .channels = 1,
            .frames = 1,
        },
        &.{0.25},
    );
    try std.testing.expect(queue.valid());
    queue.slots[queue.consumer_cursor].metadata.generation = 0;
    try std.testing.expect(!queue.valid());
    try std.testing.expectError(
        error.InvalidGeneration,
        queue.pendingCount(),
    );
    try std.testing.expectError(
        error.InvalidGeneration,
        queue.prepareNext(8, &convolver),
    );
    queue.slots[queue.consumer_cursor].metadata.generation = 2;
    try std.testing.expect(queue.valid());
    try std.testing.expectEqual(
        @as(?u64, 2),
        try queue.prepareNext(8, &convolver),
    );
    try std.testing.expect(queue.valid());
    try std.testing.expect(convolver.adoptPending());

    try convolver.begin(.{
        .generation = 3,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 1,
    });
    try convolver.write(3, 0, &.{0.125});
    try convolver.commit(3);
    const malformed_convolution = convolver.pending_slot.load(.acquire);
    convolver.slots[malformed_convolution].prepared_partitions =
        std.math.maxInt(usize);
    try std.testing.expect(!convolver.adoptPending());
    try std.testing.expectEqual(
        @as(u64, 2),
        convolver.activeMetadata().?.generation,
    );
    convolver.output_block[0][convolver.output_index] =
        std.math.nan(f32);
    convolver.output_block[1][convolver.output_index] =
        std.math.inf(f32);
    try std.testing.expectEqual(
        @as([2]f32, .{ 0.0, 0.0 }),
        convolver.processFrame(0.0, 0.0),
    );
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

    const installed_id3_limits: plugin.dsp.Id3Limits =
        plugin.dsp.default_id3_limits;
    const view = try plugin.dsp.Id3View.initWithLimits(
        encoded,
        installed_id3_limits,
    );
    try std.testing.expect(view.header.unsynchronised);
    try std.testing.expect(view.header.footer);
    var middle_iterator: plugin.dsp.Id3Iterator = view.iterator();
    middle_iterator.offset = 1;
    try std.testing.expect(!middle_iterator.valid());
    try std.testing.expectError(
        error.InvalidId3IteratorState,
        middle_iterator.next(),
    );
    try std.testing.expectEqual(@as(usize, 1), middle_iterator.offset);
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

    var aliased_v24_text: [16]u8 = @splat(0xa5);
    aliased_v24_text[0] = 'x';
    const aliased_v24_text_before = aliased_v24_text;
    try std.testing.expectError(
        error.Id3SourceAliasesOutput,
        plugin.dsp.encodeId3Utf8TextPayload(
            &aliased_v24_text,
            aliased_v24_text[0..1],
        ),
    );
    try std.testing.expectEqual(
        aliased_v24_text_before,
        aliased_v24_text,
    );

    var aliased_v24_frames_storage: [96]u8 align(@alignOf(plugin.dsp.Id3Frame)) = @splat(0x5a);
    const aliased_v24_frames = std.mem.bytesAsSlice(
        plugin.dsp.Id3Frame,
        aliased_v24_frames_storage[0..@sizeOf(plugin.dsp.Id3Frame)],
    );
    aliased_v24_frames[0] = .{
        .id = plugin.dsp.id3.title,
        .payload = &.{ 3, 'x' },
    };
    const aliased_v24_frames_before = aliased_v24_frames_storage;
    try std.testing.expectError(
        error.Id3SourceAliasesOutput,
        plugin.dsp.encodeId3(
            &aliased_v24_frames_storage,
            aliased_v24_frames,
            .{},
        ),
    );
    try std.testing.expectEqual(
        aliased_v24_frames_before,
        aliased_v24_frames_storage,
    );

    var invalid_iterator = plugin.dsp.Id3Iterator{
        .bytes = &.{},
        .offset = 1,
        .tag_unsynchronised = false,
    };
    try std.testing.expect(!invalid_iterator.valid());
    try std.testing.expectError(
        error.InvalidId3IteratorState,
        invalid_iterator.next(),
    );
    try std.testing.expectEqual(@as(usize, 1), invalid_iterator.offset);

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
    _ = try plugin.dsp.Id3V23View.requiredDecodedBytesWithLimits(
        encoded_v23,
        installed_id3_limits,
    );
    const v23_view = try plugin.dsp.Id3V23View.initWithLimits(
        encoded_v23,
        &.{},
        installed_id3_limits,
    );
    var middle_v23_iterator: plugin.dsp.Id3V23Iterator =
        v23_view.iterator();
    middle_v23_iterator.offset = 1;
    try std.testing.expect(!middle_v23_iterator.valid());
    try std.testing.expectError(
        error.InvalidId3IteratorState,
        middle_v23_iterator.next(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        middle_v23_iterator.offset,
    );
    var v23_iterator: plugin.dsp.Id3V23Iterator = v23_view.iterator();
    try std.testing.expectEqualStrings(
        "Installed v2.3",
        (try (try v23_iterator.next()).?.text()).value,
    );

    var aliased_v23_text: [16]u8 = @splat(0xa5);
    aliased_v23_text[0] = 'x';
    const aliased_v23_text_before = aliased_v23_text;
    try std.testing.expectError(
        error.Id3SourceAliasesOutput,
        plugin.dsp.encodeId3V23TextPayload(
            &aliased_v23_text,
            .latin1,
            aliased_v23_text[0..1],
        ),
    );
    try std.testing.expectEqual(
        aliased_v23_text_before,
        aliased_v23_text,
    );

    var aliased_v23_frames_storage: [96]u8 align(@alignOf(plugin.dsp.Id3V23Frame)) = @splat(0x5a);
    const aliased_v23_frames = std.mem.bytesAsSlice(
        plugin.dsp.Id3V23Frame,
        aliased_v23_frames_storage[0..@sizeOf(plugin.dsp.Id3V23Frame)],
    );
    aliased_v23_frames[0] = .{
        .id = plugin.dsp.id3.title,
        .payload = &.{ 0, 'x' },
    };
    const aliased_v23_frames_before = aliased_v23_frames_storage;
    try std.testing.expectError(
        error.Id3SourceAliasesOutput,
        plugin.dsp.encodeId3V23(
            &aliased_v23_frames_storage,
            aliased_v23_frames,
            .{},
        ),
    );
    try std.testing.expectEqual(
        aliased_v23_frames_before,
        aliased_v23_frames_storage,
    );

    var invalid_v23_iterator = plugin.dsp.Id3V23Iterator{
        .bytes = &.{},
        .offset = 1,
    };
    try std.testing.expect(!invalid_v23_iterator.valid());
    try std.testing.expectError(
        error.InvalidId3IteratorState,
        invalid_v23_iterator.next(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        invalid_v23_iterator.offset,
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
    try std.testing.expect(public_encoder.valid());
    var hostile_public_encoder = public_encoder;
    hostile_public_encoder.padding_accumulator =
        hostile_public_encoder.config.sample_rate;
    try std.testing.expect(!hostile_public_encoder.valid());
    const hostile_public_before = hostile_public_encoder;
    try std.testing.expectError(
        error.InvalidMp3EncoderState,
        hostile_public_encoder.nextFrameBytes(),
    );
    try std.testing.expectEqual(
        hostile_public_before,
        hostile_public_encoder,
    );
    var generated: [2 * plugin.dsp.maximumMp3EncodedFrameBytes]u8 = undefined;
    var generated_length: usize = 0;
    for (0..2) |_| {
        const frame_bytes = try public_encoder.encodeSilentFrame(
            generated[generated_length..],
        );
        generated_length += frame_bytes.len;
    }
    const generated_limits = plugin.dsp.Mp3Limits{
        .max_stream_bytes = generated_length,
        .max_frames = 2,
    };
    const generated_summary = try plugin.dsp.Mp3Stream.summarizeWithLimits(
        generated[0..generated_length],
        generated_limits,
    );
    try std.testing.expectEqual(
        @as(u64, 2),
        generated_summary.frame_count,
    );
    var generated_stream = try plugin.dsp.Mp3Stream.initWithLimits(
        generated[0..generated_length],
        generated_limits,
    );
    try std.testing.expect(generated_stream.valid());
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
    try std.testing.expect(generated_stream.valid());
    var impossible_generated_progress = generated_stream;
    impossible_generated_progress.cursor =
        impossible_generated_progress.audio_start;
    const impossible_generated_progress_before =
        impossible_generated_progress;
    try std.testing.expect(!impossible_generated_progress.valid());
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        impossible_generated_progress.next(),
    );
    try std.testing.expectEqualDeep(
        impossible_generated_progress_before,
        impossible_generated_progress,
    );
    generated_stream.sample_offset += 1;
    try std.testing.expect(!generated_stream.valid());
    const malformed_stream_cursor = generated_stream.cursor;
    try std.testing.expectError(
        error.InvalidMp3StreamState,
        generated_stream.next(),
    );
    try std.testing.expectEqual(
        malformed_stream_cursor,
        generated_stream.cursor,
    );

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
    try std.testing.expect(reservoir.valid());
    var main_data_storage: [1]u8 = undefined;
    const installed_frame = try plugin.dsp.Mp3Frame.parse(&encoded, 0);
    const installed_side = try installed_frame.sideInformation();
    const main_data: plugin.dsp.Mp3MainData = try reservoir.assemble(
        installed_frame,
        &main_data_storage,
    );
    try std.testing.expect(reservoir.valid());
    try std.testing.expectEqual(@as(u16, 0), main_data.bit_count);
    try std.testing.expectEqual(@as(usize, 0), main_data.bytes.len);
    var hostile_reservoir = reservoir;
    hostile_reservoir.length = hostile_reservoir.storage.len + 1;
    try std.testing.expect(!hostile_reservoir.valid());
    const hostile_reservoir_before = hostile_reservoir;
    try std.testing.expectError(
        error.InvalidMp3ReservoirState,
        hostile_reservoir.assemble(
            installed_frame,
            &main_data_storage,
        ),
    );
    try std.testing.expectEqual(
        hostile_reservoir_before,
        hostile_reservoir,
    );
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
    try std.testing.expect(pcm_analysis.valid());
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
    try std.testing.expect(pcm_analysis.valid());
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
    try std.testing.expect(classifier.valid());
    const classified = try classifier.classify(
        joint_header,
        analysis_pcm,
    );
    try std.testing.expectEqual(
        plugin.dsp.Mp3GranuleChannel{},
        classified[0][0],
    );
    classifier.attack_ratio = std.math.nan(f32);
    try std.testing.expect(!classifier.valid());
    classifier.reset();
    classifier.attack_ratio = 8;
    try std.testing.expect(classifier.valid());
    const automatic_quantized: plugin.dsp.Mp3QuantizedEncoderFrame =
        try plugin.dsp.Mp3EncoderQuantizer.quantize(
            joint_header,
            joint_analyzed,
        );
    try std.testing.expect(
        automatic_quantized.granules[0][0]
            .description.big_values <= 288,
    );
    const reservoir_quantizer_budget: plugin.dsp.Mp3ReservoirQuantizerBudget =
        try plugin.dsp.mp3ReservoirQuantizerBudget(
            joint_header,
            511,
        );
    try std.testing.expectEqual(
        @as(usize, 511 * 8),
        reservoir_quantizer_budget.history_bits,
    );
    try std.testing.expect(
        reservoir_quantizer_budget.logical_bits >
            reservoir_quantizer_budget.physical_bits,
    );
    var reservoir_masking_timeline =
        plugin.dsp.Mp3EncoderPsychoacousticTimeline{};
    const reservoir_masking =
        try reservoir_masking_timeline.analyzeFrame(
            joint_header,
            joint_analyzed,
        );
    var hostile_masking_timeline = reservoir_masking_timeline;
    hostile_masking_timeline.previous[1] =
        hostile_masking_timeline.previous[0];
    hostile_masking_timeline.history_present = .{ false, true };
    const hostile_masking_timeline_before = hostile_masking_timeline;
    try std.testing.expect(!hostile_masking_timeline.valid());
    try std.testing.expectError(
        error.InvalidMp3PsychoacousticHistory,
        hostile_masking_timeline.analyzeFrame(
            joint_header,
            joint_analyzed,
        ),
    );
    try std.testing.expectEqualDeep(
        hostile_masking_timeline_before,
        hostile_masking_timeline,
    );
    const reservoir_quantized =
        try (plugin.dsp.Mp3EncoderQuantizer{})
            .processWithReservoirMasking(
            joint_header,
            joint_analyzed,
            reservoir_masking,
            511,
        );
    try std.testing.expect(
        reservoir_quantized.granules[0][0]
            .description.big_values <= 288,
    );
    var parts_encoder = try plugin.dsp.Mp3FrameEncoder.init(.{
        .channel_mode = .mono,
    });
    var parts_frame_storage: [plugin.dsp.maximumMp3EncodedFrameBytes]u8 = undefined;
    var parts_main_data_storage: [plugin.dsp.maximumMp3EncodedMainDataBytes]u8 = undefined;
    const silent_parts: plugin.dsp.Mp3QuantizedFrameParts =
        try parts_encoder.encodeQuantizedFrameParts(
            &plugin.dsp.Mp3QuantizedEncoderFrame{},
            &parts_frame_storage,
            &parts_main_data_storage,
        );
    try std.testing.expectEqual(@as(u16, 0), silent_parts.main_data_bits);
    var packed_parts_scratch: [plugin.dsp.maximumMp3EncodedFrameBytes]u8 = undefined;
    const packed_parts: plugin.dsp.Mp3ReservoirRepackResult =
        try plugin.dsp.packMp3MainDataReservoir(
            silent_parts.frame,
            silent_parts.main_data,
            511,
            &packed_parts_scratch,
        );
    try std.testing.expectEqual(@as(u64, 1), packed_parts.frame_count);
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
    var automatic_encoder =
        try plugin.dsp.Mp3PcmEncoder.initWithPsychoacoustics(
            .{ .channel_mode = .stereo },
            plugin.dsp.Mp3EncoderPsychoacousticConfig.production,
        );
    try std.testing.expect(automatic_encoder.valid());
    var automatic_storage: [2048]u8 = undefined;
    const automatic_frame = try automatic_encoder.encode(
        analysis_pcm,
        &automatic_storage,
    );
    try std.testing.expect(automatic_encoder.valid());
    try std.testing.expect(automatic_frame.len > 4);

    var repack_encoder = try plugin.dsp.Mp3PcmEncoder.init(.{
        .channel_mode = .mono,
        .crc_present = true,
    });
    var repack_pcm_frames: [5]plugin.dsp.Mp3PcmFrame = @splat(.{
        .channel_count = 1,
        .sample_count = 1152,
    });
    for (0..1152) |sample| {
        const position: f32 = @floatFromInt(sample);
        repack_pcm_frames[3].channels[0][sample] =
            0.5 * @sin(position * 0.19);
        repack_pcm_frames[4].channels[0][sample] =
            0.4 * @cos(position * 0.13);
    }
    var repack_stream_storage: [plugin.dsp.maximumMp3EncodedFrameBytes * repack_pcm_frames.len]u8 =
        undefined;
    var repack_stream_length: usize = 0;
    for (repack_pcm_frames) |frame_pcm| {
        const frame = try repack_encoder.encode(
            frame_pcm,
            repack_stream_storage[repack_stream_length..],
        );
        repack_stream_length += frame.len;
    }
    const repack_requirements: plugin.dsp.Mp3ReservoirRepackRequirements =
        try plugin.dsp.mp3ReservoirRepackRequirements(
            repack_stream_storage[0..repack_stream_length],
        );
    var repack_encoded_scratch: [plugin.dsp.maximumMp3EncodedFrameBytes * repack_pcm_frames.len]u8 =
        undefined;
    var repack_payload_scratch: [plugin.dsp.maximumMp3EncodedFrameBytes * repack_pcm_frames.len]u8 =
        undefined;
    const repack_result: plugin.dsp.Mp3ReservoirRepackResult =
        try plugin.dsp.repackMp3MainDataReservoir(
            repack_stream_storage[0..repack_stream_length],
            511,
            &repack_encoded_scratch,
            &repack_payload_scratch,
        );
    try std.testing.expectEqual(
        @as(u64, repack_pcm_frames.len),
        repack_requirements.frame_count,
    );
    try std.testing.expectEqual(
        repack_requirements.frame_count,
        repack_result.frame_count,
    );
    try std.testing.expect(repack_result.borrowed_bytes > 0);
    try std.testing.expect(repack_result.maximum_backpointer > 0);
    var packed_stream = try plugin.dsp.Mp3Stream.init(
        repack_stream_storage[0..repack_stream_length],
    );
    while (try packed_stream.next()) |packed_frame| {
        try std.testing.expectEqual(
            @as(?bool, true),
            try packed_frame.crcValid(),
        );
    }
    const adaptive_batch_config = plugin.dsp.Mp3EncoderConfig{
        .bitrate_kbps = 32,
        .channel_mode = .mono,
        .crc_present = true,
    };
    const adaptive_batch_bytes =
        try plugin.dsp.requiredMp3PcmReservoirBatchFrameBytes(
            adaptive_batch_config,
            repack_pcm_frames.len,
        );
    var adaptive_batch_destination: [plugin.dsp.maximumMp3EncodedFrameBytes * repack_pcm_frames.len]u8 =
        undefined;
    var adaptive_batch_frames: [plugin.dsp.maximumMp3EncodedFrameBytes * repack_pcm_frames.len]u8 =
        undefined;
    var adaptive_batch_pack: [plugin.dsp.maximumMp3EncodedFrameBytes * repack_pcm_frames.len]u8 =
        undefined;
    var adaptive_batch_main: [plugin.dsp.maximumMp3EncodedMainDataBytes * repack_pcm_frames.len]u8 =
        undefined;
    const adaptive_batch: plugin.dsp.Mp3PcmReservoirBatchResult =
        try plugin.dsp.encodeMp3PcmReservoirBatch(
            adaptive_batch_config,
            &repack_pcm_frames,
            511,
            &adaptive_batch_destination,
            &adaptive_batch_frames,
            &adaptive_batch_pack,
            &adaptive_batch_main,
        );
    try std.testing.expectEqual(
        adaptive_batch_bytes,
        adaptive_batch.stream.len,
    );
    try std.testing.expectEqual(
        @as(u64, repack_pcm_frames.len),
        adaptive_batch.frame_count,
    );
    try std.testing.expect(adaptive_batch.borrowed_bytes > 0);
    const adaptive_vbr_batch: plugin.dsp.Mp3VbrPcmReservoirBatchResult =
        try plugin.dsp.encodeMp3VbrPcmReservoirBatch(
            .{
                .template = .{
                    .channel_mode = .mono,
                    .crc_present = true,
                },
                .minimum_bitrate_index = 1,
                .maximum_bitrate_index = 5,
            },
            &repack_pcm_frames,
            511,
            &adaptive_batch_destination,
            &adaptive_batch_frames,
            &adaptive_batch_pack,
            &adaptive_batch_main,
        );
    try std.testing.expectEqual(
        @as(u64, repack_pcm_frames.len),
        adaptive_vbr_batch.frame_count,
    );
    try std.testing.expect(adaptive_vbr_batch.borrowed_bytes > 0);
    const gapless_frame_capacity = repack_pcm_frames.len + 3;
    var gapless_destination: [plugin.dsp.maximumMp3EncodedFrameBytes * gapless_frame_capacity]u8 =
        undefined;
    var gapless_frames: [plugin.dsp.maximumMp3EncodedFrameBytes * gapless_frame_capacity]u8 =
        undefined;
    var gapless_pack: [plugin.dsp.maximumMp3EncodedFrameBytes * gapless_frame_capacity]u8 =
        undefined;
    var gapless_main: [plugin.dsp.maximumMp3EncodedMainDataBytes * gapless_frame_capacity]u8 =
        undefined;
    var gapless_metadata: [plugin.dsp.maximumMp3EncodedFrameBytes]u8 =
        undefined;
    const gapless_identifier: [9]u8 = "Consumer1".*;
    const gapless_batch: plugin.dsp.Mp3PcmReservoirGaplessBatchResult =
        try plugin.dsp.encodeMp3PcmReservoirGaplessBatch(
            adaptive_batch_config,
            &repack_pcm_frames,
            511,
            gapless_identifier,
            &gapless_destination,
            &gapless_frames,
            &gapless_pack,
            &gapless_main,
            &gapless_metadata,
        );
    const gapless_summary = try plugin.dsp.Mp3Stream.summarize(
        gapless_batch.stream,
    );
    try std.testing.expectEqual(
        gapless_batch.summary.input_samples,
        (try plugin.dsp.Mp3GaplessPlan.fromSummary(gapless_summary))
            .audible_samples,
    );
    const gapless_vbr_batch: plugin.dsp.Mp3VbrPcmReservoirGaplessBatchResult =
        try plugin.dsp.encodeMp3VbrPcmReservoirGaplessBatch(
            .{
                .template = .{
                    .channel_mode = .mono,
                    .crc_present = true,
                },
                .minimum_bitrate_index = 1,
                .maximum_bitrate_index = 5,
            },
            &repack_pcm_frames,
            511,
            73,
            gapless_identifier,
            &gapless_destination,
            &gapless_frames,
            &gapless_pack,
            &gapless_main,
            &gapless_metadata,
        );
    const gapless_vbr_summary = try plugin.dsp.Mp3Stream.summarize(
        gapless_vbr_batch.stream,
    );
    try std.testing.expectEqual(
        gapless_vbr_batch.summary.input_samples,
        (try plugin.dsp.Mp3GaplessPlan.fromSummary(gapless_vbr_summary))
            .audible_samples,
    );
    const adaptive_stream_pending_bytes =
        try plugin.dsp.requiredMp3PcmAdaptiveReservoirStorage(
            adaptive_batch_config,
            511,
        );
    var adaptive_stream_pending: [plugin.dsp.maximumMp3EncodedFrameBytes * 12]u8 =
        undefined;
    var adaptive_stream_staging: [plugin.dsp.maximumMp3EncodedFrameBytes * 12]u8 =
        undefined;
    var adaptive_stream_frame: [plugin.dsp.maximumMp3EncodedFrameBytes]u8 =
        undefined;
    var adaptive_stream_main: [plugin.dsp.maximumMp3EncodedMainDataBytes]u8 =
        undefined;
    var adaptive_stream_output: [plugin.dsp.maximumMp3EncodedFrameBytes * repack_pcm_frames.len]u8 =
        undefined;
    var adaptive_stream =
        try plugin.dsp.Mp3PcmAdaptiveReservoirStreamEncoder.init(
            adaptive_batch_config,
            511,
            adaptive_stream_pending[0..adaptive_stream_pending_bytes],
        );
    var adaptive_stream_bytes: usize = 0;
    for (repack_pcm_frames) |frame_pcm| {
        const appended: plugin.dsp.Mp3PcmAdaptiveReservoirAppend =
            try adaptive_stream.append(
                frame_pcm,
                adaptive_stream_output[adaptive_stream_bytes..],
                adaptive_stream_staging[0..adaptive_stream_pending_bytes],
                &adaptive_stream_frame,
                &adaptive_stream_main,
            );
        adaptive_stream_bytes += appended.frames.len;
    }
    const adaptive_stream_finish: plugin.dsp.Mp3PcmAdaptiveReservoirFinish =
        try adaptive_stream.finish(
            adaptive_stream_output[adaptive_stream_bytes..],
        );
    adaptive_stream_bytes += adaptive_stream_finish.frames.len;
    try std.testing.expect(adaptive_stream.valid());
    adaptive_stream.byte_count += 1;
    try std.testing.expect(!adaptive_stream.valid());
    try std.testing.expectError(
        error.InvalidMp3AdaptiveReservoirState,
        adaptive_stream.finish(
            adaptive_stream_output[adaptive_stream_bytes..],
        ),
    );
    adaptive_stream.byte_count -= 1;
    try std.testing.expect(adaptive_stream.valid());
    try std.testing.expectEqual(
        adaptive_batch_bytes,
        adaptive_stream_bytes,
    );
    var adaptive_encoded_stream = try plugin.dsp.Mp3Stream.init(
        adaptive_stream_output[0..adaptive_stream_bytes],
    );
    var adaptive_encoded_frames: usize = 0;
    while (try adaptive_encoded_stream.next()) |_| {
        adaptive_encoded_frames += 1;
    }
    try std.testing.expectEqual(
        repack_pcm_frames.len,
        adaptive_encoded_frames,
    );
    var adaptive_gapless_stream =
        try plugin.dsp.Mp3PcmAdaptiveReservoirGaplessStreamEncoder.init(
            adaptive_batch_config,
            511,
            adaptive_stream_pending[0..adaptive_stream_pending_bytes],
        );
    var adaptive_gapless_bytes: usize = 0;
    const adaptive_gapless_placeholder =
        try adaptive_gapless_stream.startMetadataWithEncoder(
            gapless_identifier,
            gapless_destination[adaptive_gapless_bytes..],
            &adaptive_stream_frame,
            &adaptive_stream_main,
        );
    adaptive_gapless_bytes += adaptive_gapless_placeholder.len;
    for (repack_pcm_frames) |frame_pcm| {
        const appended = try adaptive_gapless_stream.append(
            frame_pcm,
            gapless_destination[adaptive_gapless_bytes..],
            adaptive_stream_staging[0..adaptive_stream_pending_bytes],
            &adaptive_stream_frame,
            &adaptive_stream_main,
        );
        adaptive_gapless_bytes += appended.frames.len;
    }
    const adaptive_gapless_finish: plugin.dsp.Mp3PcmAdaptiveReservoirGaplessFinish =
        try adaptive_gapless_stream.finish(
            gapless_destination[adaptive_gapless_bytes..],
            adaptive_stream_staging[0..adaptive_stream_pending_bytes],
            gapless_pack[0..adaptive_stream_pending_bytes],
            &adaptive_stream_frame,
            &adaptive_stream_main,
            &gapless_frames,
        );
    adaptive_gapless_bytes += adaptive_gapless_finish.frames.len;
    _ = try adaptive_gapless_stream.metadataFrame(
        gapless_destination[0..adaptive_gapless_placeholder.len],
    );
    const adaptive_gapless_summary = try plugin.dsp.Mp3Stream.summarize(
        gapless_destination[0..adaptive_gapless_bytes],
    );
    try std.testing.expectEqual(
        adaptive_gapless_finish.summary.input_samples,
        (try plugin.dsp.Mp3GaplessPlan.fromSummary(
            adaptive_gapless_summary,
        )).audible_samples,
    );
    const adaptive_vbr_stream_pending_bytes =
        try plugin.dsp.requiredMp3VbrPcmAdaptiveReservoirStorage(
            .{
                .template = .{
                    .channel_mode = .mono,
                    .crc_present = true,
                },
                .minimum_bitrate_index = 1,
                .maximum_bitrate_index = 5,
            },
            511,
        );
    var adaptive_vbr_stream_pending: [plugin.dsp.maximumMp3EncodedFrameBytes * 12]u8 =
        undefined;
    var adaptive_vbr_stream_staging: [plugin.dsp.maximumMp3EncodedFrameBytes * 12]u8 =
        undefined;
    var adaptive_vbr_stream_output: [plugin.dsp.maximumMp3EncodedFrameBytes * repack_pcm_frames.len]u8 =
        undefined;
    var adaptive_vbr_stream =
        try plugin.dsp.Mp3VbrPcmAdaptiveReservoirStreamEncoder.init(
            .{
                .template = .{
                    .channel_mode = .mono,
                    .crc_present = true,
                },
                .minimum_bitrate_index = 1,
                .maximum_bitrate_index = 5,
            },
            511,
            adaptive_vbr_stream_pending[0..adaptive_vbr_stream_pending_bytes],
        );
    var adaptive_vbr_stream_bytes: usize = 0;
    for (repack_pcm_frames) |frame_pcm| {
        const appended: plugin.dsp.Mp3VbrPcmAdaptiveReservoirAppend =
            try adaptive_vbr_stream.append(
                frame_pcm,
                adaptive_vbr_stream_output[adaptive_vbr_stream_bytes..],
                adaptive_vbr_stream_staging[0..adaptive_vbr_stream_pending_bytes],
                &adaptive_stream_frame,
                &adaptive_stream_main,
            );
        try std.testing.expect(appended.selection.bitrate_index >= 1);
        try std.testing.expect(appended.selection.bitrate_index <= 5);
        adaptive_vbr_stream_bytes += appended.frames.len;
    }
    const adaptive_vbr_stream_finish: plugin.dsp.Mp3VbrPcmAdaptiveReservoirFinish =
        try adaptive_vbr_stream.finish(
            adaptive_vbr_stream_output[adaptive_vbr_stream_bytes..],
        );
    adaptive_vbr_stream_bytes += adaptive_vbr_stream_finish.frames.len;
    try std.testing.expect(adaptive_vbr_stream.valid());
    try std.testing.expectEqual(
        adaptive_vbr_batch.stream.len,
        adaptive_vbr_stream_bytes,
    );
    try std.testing.expectEqual(
        @as(u64, repack_pcm_frames.len),
        adaptive_vbr_stream_finish.frame_count,
    );
    var adaptive_vbr_encoded_stream = try plugin.dsp.Mp3Stream.init(
        adaptive_vbr_stream_output[0..adaptive_vbr_stream_bytes],
    );
    var adaptive_vbr_encoded_frames: usize = 0;
    while (try adaptive_vbr_encoded_stream.next()) |_| {
        adaptive_vbr_encoded_frames += 1;
    }
    try std.testing.expectEqual(
        repack_pcm_frames.len,
        adaptive_vbr_encoded_frames,
    );
    var adaptive_vbr_gapless =
        try plugin.dsp.Mp3VbrPcmAdaptiveReservoirGaplessStreamEncoder.init(
            .{
                .template = .{
                    .channel_mode = .mono,
                    .crc_present = true,
                },
                .minimum_bitrate_index = 1,
                .maximum_bitrate_index = 5,
            },
            511,
            adaptive_vbr_stream_pending[0..adaptive_vbr_stream_pending_bytes],
        );
    var adaptive_vbr_gapless_bytes: usize = 0;
    const adaptive_vbr_placeholder =
        try adaptive_vbr_gapless.startMetadataWithEncoder(
            gapless_identifier,
            gapless_destination[adaptive_vbr_gapless_bytes..],
            &adaptive_stream_frame,
        );
    adaptive_vbr_gapless_bytes += adaptive_vbr_placeholder.len;
    for (repack_pcm_frames) |frame_pcm| {
        const appended = try adaptive_vbr_gapless.append(
            frame_pcm,
            gapless_destination[adaptive_vbr_gapless_bytes..],
            adaptive_vbr_stream_staging[0..adaptive_vbr_stream_pending_bytes],
            &adaptive_stream_frame,
            &adaptive_stream_main,
        );
        adaptive_vbr_gapless_bytes += appended.frames.len;
    }
    const adaptive_vbr_gapless_finish: plugin.dsp.Mp3VbrPcmAdaptiveReservoirGaplessFinish =
        try adaptive_vbr_gapless.finish(
            gapless_destination[adaptive_vbr_gapless_bytes..],
            adaptive_vbr_stream_staging[0..adaptive_vbr_stream_pending_bytes],
            gapless_pack[0..adaptive_vbr_stream_pending_bytes],
            &adaptive_stream_frame,
            &adaptive_stream_main,
            &gapless_frames,
        );
    adaptive_vbr_gapless_bytes += adaptive_vbr_gapless_finish.frames.len;
    _ = try adaptive_vbr_gapless.metadataFrame(
        73,
        gapless_destination[0..adaptive_vbr_gapless_bytes],
        gapless_destination[0..adaptive_vbr_placeholder.len],
    );
    const adaptive_vbr_gapless_summary = try plugin.dsp.Mp3Stream.summarize(
        gapless_destination[0..adaptive_vbr_gapless_bytes],
    );
    try std.testing.expectEqual(
        adaptive_vbr_gapless_finish.summary.input_samples,
        (try plugin.dsp.Mp3GaplessPlan.fromSummary(
            adaptive_vbr_gapless_summary,
        )).audible_samples,
    );
    var resync_storage: [4096]u8 = undefined;
    @memcpy(
        resync_storage[0..automatic_frame.len],
        automatic_frame,
    );
    const resync_junk = [_]u8{ 0, 1, 2 };
    @memcpy(
        resync_storage[automatic_frame.len..][0..resync_junk.len],
        &resync_junk,
    );
    const recovered_frame_offset =
        automatic_frame.len + resync_junk.len;
    @memcpy(
        resync_storage[recovered_frame_offset..][0..automatic_frame.len],
        automatic_frame,
    );
    var resync_stream = try plugin.dsp.Mp3Stream.init(
        resync_storage[0 .. recovered_frame_offset + automatic_frame.len],
    );
    _ = try resync_stream.next();
    try std.testing.expectError(
        error.InvalidMp3Sync,
        resync_stream.next(),
    );
    try std.testing.expectEqual(
        resync_junk.len,
        try resync_stream.resynchronize(resync_junk.len),
    );
    _ = try resync_stream.next();
    try std.testing.expect((try resync_stream.next()) == null);
    try std.testing.expect(automatic_encoder.masking.history_present[0]);
    try std.testing.expect(automatic_encoder.masking.history_present[1]);
    try std.testing.expect(automatic_encoder.masking.valid());
    var hostile_automatic_encoder = automatic_encoder;
    hostile_automatic_encoder.analysis.frames_analyzed += 1;
    try std.testing.expect(!hostile_automatic_encoder.valid());
    const hostile_automatic_before = hostile_automatic_encoder;
    try std.testing.expectError(
        error.InvalidMp3PcmEncoderState,
        hostile_automatic_encoder.encode(
            analysis_pcm,
            &automatic_storage,
        ),
    );
    try std.testing.expectEqual(
        hostile_automatic_before,
        hostile_automatic_encoder,
    );
    automatic_encoder.reset();
    try std.testing.expectEqual(
        [_]bool{ false, false },
        automatic_encoder.masking.history_present,
    );
    try std.testing.expect(automatic_encoder.masking.valid());
    try std.testing.expect(automatic_encoder.valid());
    var intensity_encoder = try plugin.dsp.Mp3PcmEncoder.init(.{
        .bitrate_kbps = 192,
        .channel_mode = .joint_stereo,
        .mode_extension = 1,
    });
    const intensity_frame = try intensity_encoder.encode(
        analysis_pcm,
        &automatic_storage,
    );
    try std.testing.expect(intensity_frame.len > 4);
    try std.testing.expectEqual(
        @as(u2, 1),
        (try plugin.dsp.Mp3Frame.parse(
            intensity_frame,
            0,
        )).header.mode_extension,
    );
    var reservoir_encoder =
        try plugin.dsp.Mp3PcmReservoirEncoder.init(
            .{ .channel_mode = .stereo },
        );
    try std.testing.expect(reservoir_encoder.valid());
    var hostile_reservoir_encoder = reservoir_encoder;
    hostile_reservoir_encoder.borrowed_bytes = 1;
    try std.testing.expect(!hostile_reservoir_encoder.valid());
    const reservoir_prime: plugin.dsp.Mp3PcmReservoirAppend =
        try reservoir_encoder.append(
            analysis_pcm,
            automatic_storage[0..0],
        );
    try std.testing.expect(reservoir_prime.frame == null);
    try std.testing.expect(reservoir_encoder.valid());
    const reservoir_emitted: plugin.dsp.Mp3PcmReservoirAppend =
        try reservoir_encoder.append(
            analysis_pcm,
            &automatic_storage,
        );
    try std.testing.expect(reservoir_emitted.frame != null);
    try std.testing.expect(reservoir_emitted.borrowed_bytes > 0);
    var mismatched_reservoir_borrow = reservoir_encoder;
    mismatched_reservoir_borrow.borrowed_bytes -=
        reservoir_emitted.borrowed_bytes;
    try std.testing.expect(!mismatched_reservoir_borrow.valid());
    try std.testing.expect(
        (try reservoir_encoder.finish(&automatic_storage)) != null,
    );
    try std.testing.expect(reservoir_encoder.valid());
    var stream_encoder = try plugin.dsp.Mp3PcmStreamEncoder.init(
        .{ .channel_mode = .stereo },
    );
    var stream_storage: [4096]u8 = undefined;
    try std.testing.expect(stream_encoder.valid());
    var hostile_stream_encoder = stream_encoder;
    hostile_stream_encoder.frame_count = 1;
    try std.testing.expect(!hostile_stream_encoder.valid());
    const hostile_stream_before = hostile_stream_encoder;
    try std.testing.expectError(
        error.InvalidMp3EncoderStreamState,
        hostile_stream_encoder.append(
            analysis_pcm,
            &stream_storage,
        ),
    );
    try std.testing.expectEqual(
        hostile_stream_before,
        hostile_stream_encoder,
    );
    const stream_frame = try stream_encoder.append(
        analysis_pcm,
        &stream_storage,
    );
    try std.testing.expect(stream_encoder.valid());
    const stream_finish: plugin.dsp.Mp3PcmStreamFinish =
        try stream_encoder.finish(
            stream_storage[stream_frame.len..],
        );
    try std.testing.expect(stream_encoder.valid());
    const stream_summary: plugin.dsp.Mp3EncoderStreamSummary =
        stream_finish.summary;
    try std.testing.expectEqual(
        @as(u16, 1057),
        stream_summary.encoder_delay,
    );
    try std.testing.expectEqual(
        @as(u16, 95),
        stream_summary.end_padding,
    );
    var reservoir_stream =
        try plugin.dsp.Mp3PcmReservoirStreamEncoder.init(
            .{ .channel_mode = .stereo },
        );
    try std.testing.expect(reservoir_stream.valid());
    var hostile_reservoir_stream = reservoir_stream;
    hostile_reservoir_stream.encoder.pending_length =
        std.math.maxInt(u16);
    try std.testing.expect(!hostile_reservoir_stream.valid());
    const reservoir_stream_prime =
        try reservoir_stream.append(
            analysis_pcm,
            stream_storage[0..0],
        );
    try std.testing.expect(
        reservoir_stream_prime.frame == null,
    );
    try std.testing.expect(reservoir_stream.valid());
    const reservoir_stream_frame =
        try reservoir_stream.append(
            analysis_pcm,
            &stream_storage,
        );
    const reservoir_stream_frame_bytes =
        reservoir_stream_frame.frame.?.len;
    const reservoir_stream_finish: plugin.dsp.Mp3PcmReservoirStreamFinish =
        try reservoir_stream.finish(
            stream_storage[reservoir_stream_frame_bytes..],
        );
    try std.testing.expect(reservoir_stream.valid());
    try std.testing.expect(
        reservoir_stream_finish.borrowed_bytes > 0,
    );
    try std.testing.expectEqual(
        @as(u16, 95),
        reservoir_stream_finish.summary.end_padding,
    );

    var mp3_temporary = std.testing.tmpDir(.{});
    defer mp3_temporary.cleanup();
    var adaptive_batch_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "adaptive-batch.mp3",
        .{ .read = true },
    );
    defer adaptive_batch_file.close(std.testing.io);
    const adaptive_batch_file_result: plugin.dsp.Mp3PcmReservoirBatchFileResult =
        try plugin.dsp.writeMp3PcmReservoirBatchFile(
            std.testing.io,
            adaptive_batch_file,
            adaptive_batch_config,
            &repack_pcm_frames,
            511,
            0,
            &adaptive_batch_destination,
            &adaptive_batch_frames,
            &adaptive_batch_pack,
            &adaptive_batch_main,
        );
    try std.testing.expectEqual(
        adaptive_batch_file_result.file_end,
        try adaptive_batch_file.length(std.testing.io),
    );
    var adaptive_vbr_batch_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "adaptive-vbr-batch.mp3",
        .{ .read = true },
    );
    defer adaptive_vbr_batch_file.close(std.testing.io);
    const adaptive_vbr_batch_file_result: plugin.dsp.Mp3VbrPcmReservoirBatchFileResult =
        try plugin.dsp.writeMp3VbrPcmReservoirBatchFile(
            std.testing.io,
            adaptive_vbr_batch_file,
            .{
                .template = .{
                    .channel_mode = .mono,
                    .crc_present = true,
                },
                .minimum_bitrate_index = 1,
                .maximum_bitrate_index = 5,
            },
            &repack_pcm_frames,
            511,
            0,
            &adaptive_batch_destination,
            &adaptive_batch_frames,
            &adaptive_batch_pack,
            &adaptive_batch_main,
        );
    try std.testing.expectEqual(
        adaptive_vbr_batch_file_result.file_end,
        try adaptive_vbr_batch_file.length(std.testing.io),
    );
    var gapless_batch_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "adaptive-gapless-batch.mp3",
        .{ .read = true },
    );
    defer gapless_batch_file.close(std.testing.io);
    const gapless_batch_file_result: plugin.dsp.Mp3PcmReservoirGaplessBatchFileResult =
        try plugin.dsp.writeMp3PcmReservoirGaplessBatchFile(
            std.testing.io,
            gapless_batch_file,
            adaptive_batch_config,
            &repack_pcm_frames,
            511,
            0,
            gapless_identifier,
            &gapless_destination,
            &gapless_frames,
            &gapless_pack,
            &gapless_main,
            &gapless_metadata,
        );
    try std.testing.expectEqual(
        gapless_batch_file_result.file_end,
        try gapless_batch_file.length(std.testing.io),
    );
    var gapless_vbr_batch_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "adaptive-gapless-vbr-batch.mp3",
        .{ .read = true },
    );
    defer gapless_vbr_batch_file.close(std.testing.io);
    const gapless_vbr_batch_file_result: plugin.dsp.Mp3VbrPcmReservoirGaplessBatchFileResult =
        try plugin.dsp.writeMp3VbrPcmReservoirGaplessBatchFile(
            std.testing.io,
            gapless_vbr_batch_file,
            .{
                .template = .{
                    .channel_mode = .mono,
                    .crc_present = true,
                },
                .minimum_bitrate_index = 1,
                .maximum_bitrate_index = 5,
            },
            &repack_pcm_frames,
            511,
            0,
            73,
            gapless_identifier,
            &gapless_destination,
            &gapless_frames,
            &gapless_pack,
            &gapless_main,
            &gapless_metadata,
        );
    try std.testing.expectEqual(
        gapless_vbr_batch_file_result.file_end,
        try gapless_vbr_batch_file.length(std.testing.io),
    );
    var adaptive_file_rollback: [plugin.dsp.maximumMp3EncodedFrameBytes * 12]u8 =
        undefined;
    var adaptive_file_output: [plugin.dsp.maximumMp3EncodedFrameBytes * 12]u8 =
        undefined;
    var adaptive_incremental_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "adaptive-incremental.mp3",
        .{ .read = true },
    );
    defer adaptive_incremental_file.close(std.testing.io);
    var adaptive_file_encoder =
        try plugin.dsp.Mp3PcmAdaptiveReservoirFileEncoder.init(
            std.testing.io,
            adaptive_incremental_file,
            adaptive_batch_config,
            511,
            adaptive_stream_pending[0..adaptive_stream_pending_bytes],
            adaptive_stream_staging[0..adaptive_stream_pending_bytes],
            adaptive_file_rollback[0..adaptive_stream_pending_bytes],
            &adaptive_stream_frame,
            &adaptive_stream_main,
            adaptive_file_output[0..adaptive_stream_pending_bytes],
        );
    for (repack_pcm_frames) |frame_pcm|
        _ = try adaptive_file_encoder.append(frame_pcm);
    const adaptive_file_summary: plugin.dsp.Mp3PcmAdaptiveReservoirFileSummary =
        try adaptive_file_encoder.finalize();
    try std.testing.expect(adaptive_file_encoder.valid());
    try std.testing.expectEqual(
        adaptive_file_summary.file_end,
        try adaptive_incremental_file.length(std.testing.io),
    );

    var adaptive_vbr_incremental_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "adaptive-vbr-incremental.mp3",
        .{ .read = true },
    );
    defer adaptive_vbr_incremental_file.close(std.testing.io);
    var adaptive_vbr_file_encoder =
        try plugin.dsp.Mp3VbrPcmAdaptiveReservoirFileEncoder.init(
            std.testing.io,
            adaptive_vbr_incremental_file,
            .{
                .template = .{
                    .channel_mode = .mono,
                    .crc_present = true,
                },
                .minimum_bitrate_index = 1,
                .maximum_bitrate_index = 5,
            },
            511,
            adaptive_vbr_stream_pending[0..adaptive_vbr_stream_pending_bytes],
            adaptive_vbr_stream_staging[0..adaptive_vbr_stream_pending_bytes],
            adaptive_file_rollback[0..adaptive_vbr_stream_pending_bytes],
            &adaptive_stream_frame,
            &adaptive_stream_main,
            adaptive_file_output[0..adaptive_vbr_stream_pending_bytes],
        );
    for (repack_pcm_frames) |frame_pcm|
        _ = try adaptive_vbr_file_encoder.append(frame_pcm);
    const adaptive_vbr_file_summary: plugin.dsp.Mp3VbrPcmAdaptiveReservoirFileSummary =
        try adaptive_vbr_file_encoder.finalize();
    try std.testing.expect(adaptive_vbr_file_encoder.valid());
    try std.testing.expectEqual(
        adaptive_vbr_file_summary.file_end,
        try adaptive_vbr_incremental_file.length(std.testing.io),
    );
    var adaptive_gapless_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "adaptive-gapless-cbr.mp3",
        .{ .read = true },
    );
    defer adaptive_gapless_file.close(std.testing.io);
    try std.testing.expect(
        adaptive_file_output.len >=
            try plugin.dsp.requiredMp3PcmAdaptiveReservoirGaplessFileFinishStorage(
                adaptive_batch_config,
                511,
            ),
    );
    var adaptive_gapless_file_encoder =
        try plugin.dsp.Mp3PcmAdaptiveReservoirGaplessFileEncoder.init(
            std.testing.io,
            adaptive_gapless_file,
            adaptive_batch_config,
            511,
            adaptive_stream_pending[0..adaptive_stream_pending_bytes],
            adaptive_stream_staging[0..adaptive_stream_pending_bytes],
            adaptive_file_rollback[0..adaptive_stream_pending_bytes],
            &adaptive_stream_frame,
            &adaptive_stream_main,
            &adaptive_file_output,
            &gapless_frames,
        );
    _ = try adaptive_gapless_file_encoder.startMetadataWithEncoder(
        gapless_identifier,
    );
    for (repack_pcm_frames) |frame_pcm|
        _ = try adaptive_gapless_file_encoder.append(frame_pcm);
    const adaptive_gapless_file_summary: plugin.dsp.Mp3PcmAdaptiveReservoirGaplessFileSummary =
        try adaptive_gapless_file_encoder.finalize();
    try std.testing.expect(adaptive_gapless_file_encoder.valid());
    try std.testing.expectEqual(
        adaptive_gapless_file_summary.file_end,
        try adaptive_gapless_file.length(std.testing.io),
    );

    var adaptive_gapless_vbr_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "adaptive-gapless-vbr.mp3",
        .{ .read = true },
    );
    defer adaptive_gapless_vbr_file.close(std.testing.io);
    const adaptive_gapless_vbr_config = plugin.dsp.Mp3VbrEncoderConfig{
        .template = .{
            .channel_mode = .mono,
            .crc_present = true,
        },
        .minimum_bitrate_index = 1,
        .maximum_bitrate_index = 5,
    };
    try std.testing.expect(
        adaptive_file_output.len >=
            try plugin.dsp.requiredMp3VbrPcmAdaptiveReservoirGaplessFileFinishStorage(
                adaptive_gapless_vbr_config,
                511,
            ),
    );
    const adaptive_gapless_required_offsets =
        try plugin.dsp.requiredMp3VbrPcmAdaptiveReservoirGaplessFrameOffsets(
            adaptive_gapless_vbr_config,
            repack_pcm_frames.len,
        );
    var adaptive_gapless_frame_offsets: [repack_pcm_frames.len + 3]u64 = undefined;
    var adaptive_gapless_initial_offsets: [1]u64 = undefined;
    var adaptive_gapless_vbr_file_encoder =
        try plugin.dsp.Mp3VbrPcmAdaptiveReservoirGaplessFileEncoder.init(
            std.testing.io,
            adaptive_gapless_vbr_file,
            adaptive_gapless_vbr_config,
            511,
            adaptive_vbr_stream_pending[0..adaptive_vbr_stream_pending_bytes],
            adaptive_vbr_stream_staging[0..adaptive_vbr_stream_pending_bytes],
            adaptive_file_rollback[0..adaptive_vbr_stream_pending_bytes],
            &adaptive_stream_frame,
            &adaptive_stream_main,
            &adaptive_file_output,
            &gapless_frames,
            &adaptive_gapless_initial_offsets,
        );
    _ = try adaptive_gapless_vbr_file_encoder.startMetadataWithEncoder(
        gapless_identifier,
    );
    var adaptive_gapless_retry: ?usize = null;
    for (repack_pcm_frames, 0..) |frame_pcm, index| {
        _ = adaptive_gapless_vbr_file_encoder.append(frame_pcm) catch |failure| {
            try std.testing.expectEqual(
                error.Mp3VbrFrameIndexStorageTooSmall,
                failure,
            );
            adaptive_gapless_retry = index;
            break;
        };
    }
    const adaptive_gapless_retry_index = adaptive_gapless_retry orelse
        return error.InstalledAdaptiveGaplessVbrCapacityFailureMissing;
    try adaptive_gapless_vbr_file_encoder.replaceFrameOffsetStorage(
        adaptive_gapless_frame_offsets[0..adaptive_gapless_required_offsets],
    );
    for (repack_pcm_frames[adaptive_gapless_retry_index..]) |frame_pcm|
        _ = try adaptive_gapless_vbr_file_encoder.append(frame_pcm);
    const adaptive_gapless_vbr_file_summary: plugin.dsp.Mp3VbrPcmAdaptiveReservoirGaplessFileSummary =
        try adaptive_gapless_vbr_file_encoder.finalize(73);
    try std.testing.expect(adaptive_gapless_vbr_file_encoder.valid());
    try std.testing.expectEqual(
        adaptive_gapless_vbr_file_summary.file_end,
        try adaptive_gapless_vbr_file.length(std.testing.io),
    );
    const adaptive_gapless_vbr_file_parsed =
        try plugin.dsp.Mp3FileReader.summarize(
            std.testing.io,
            adaptive_gapless_vbr_file,
            &adaptive_stream_frame,
        );
    try std.testing.expectEqual(
        @as(?u32, 73),
        adaptive_gapless_vbr_file_parsed.first_xing.?.quality,
    );
    var adaptive_metadata_storage: [plugin.dsp.maximumMp3EncodedFrameBytes]u8 =
        undefined;
    var adaptive_info_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "adaptive-info-batch.mp3",
        .{ .read = true },
    );
    defer adaptive_info_file.close(std.testing.io);
    const adaptive_info_result: plugin.dsp.Mp3PcmReservoirBatchFileResult =
        try plugin.dsp.writeMp3PcmReservoirBatchFileWithInfo(
            std.testing.io,
            adaptive_info_file,
            adaptive_batch_config,
            &repack_pcm_frames,
            511,
            0,
            "Consumer1".*,
            &adaptive_batch_destination,
            &adaptive_batch_frames,
            &adaptive_batch_pack,
            &adaptive_batch_main,
            &adaptive_metadata_storage,
        );
    try std.testing.expect(adaptive_info_result.metadata_bytes > 0);
    var adaptive_xing_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "adaptive-xing-batch.mp3",
        .{ .read = true },
    );
    defer adaptive_xing_file.close(std.testing.io);
    const adaptive_xing_result: plugin.dsp.Mp3VbrPcmReservoirBatchFileResult =
        try plugin.dsp.writeMp3VbrPcmReservoirBatchFileWithXing(
            std.testing.io,
            adaptive_xing_file,
            .{
                .template = .{
                    .channel_mode = .mono,
                    .crc_present = true,
                },
                .minimum_bitrate_index = 1,
                .maximum_bitrate_index = 5,
            },
            &repack_pcm_frames,
            511,
            0,
            50,
            "Consumer1".*,
            &adaptive_batch_destination,
            &adaptive_batch_frames,
            &adaptive_batch_pack,
            &adaptive_batch_main,
            &adaptive_metadata_storage,
        );
    try std.testing.expect(adaptive_xing_result.metadata_bytes > 0);
    var mp3_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "public-encoder.mp3",
        .{ .read = true },
    );
    defer mp3_file.close(std.testing.io);
    var file_encoder_storage: [8192]u8 = undefined;
    var file_encoder = try plugin.dsp.Mp3PcmFileEncoder.init(
        std.testing.io,
        mp3_file,
        .{ .channel_mode = .stereo },
        &file_encoder_storage,
    );
    try std.testing.expect(file_encoder.valid());
    try file_encoder.startGaplessMetadata();
    try std.testing.expect(file_encoder.valid());
    try file_encoder.append(analysis_pcm);
    const file_encoder_summary = try file_encoder.finalize();
    try std.testing.expect(file_encoder.valid());
    try std.testing.expectEqual(
        file_encoder_summary.byte_count,
        try mp3_file.length(std.testing.io),
    );
    var metadata_frame_storage: [2048]u8 = undefined;
    var installed_file_reader = try plugin.dsp.Mp3FileReader.init(
        std.testing.io,
        mp3_file,
    );
    try std.testing.expect(installed_file_reader.valid());
    var transactional_file_reader = installed_file_reader;
    var transactional_frame_storage: [2048]u8 = @splat(0xa5);
    var transactional_frame_scratch: [2048]u8 = undefined;
    const transactional_frame =
        (try transactional_file_reader.nextTransactional(
            &transactional_frame_storage,
            &transactional_frame_scratch,
        )).?;
    try std.testing.expect(transactional_frame.bytes.len > 4);
    try std.testing.expectEqual(
        @intFromPtr(transactional_frame_storage[0..].ptr),
        @intFromPtr(transactional_frame.bytes.ptr),
    );
    try std.testing.expect(transactional_file_reader.valid());
    var impossible_file_reader_progress = installed_file_reader;
    impossible_file_reader_progress.frame_index = 1;
    impossible_file_reader_progress.sample_offset =
        impossible_file_reader_progress.first_header.samplesPerFrame();
    try std.testing.expect(!impossible_file_reader_progress.valid());
    installed_file_reader.sample_offset = 1;
    try std.testing.expect(!installed_file_reader.valid());
    const malformed_file_offset = installed_file_reader.offset;
    try std.testing.expectError(
        error.InvalidMp3FileReaderState,
        installed_file_reader.next(&metadata_frame_storage),
    );
    try std.testing.expectEqual(
        malformed_file_offset,
        installed_file_reader.offset,
    );
    const metadata_summary = try plugin.dsp.Mp3FileReader.summarize(
        std.testing.io,
        mp3_file,
        &metadata_frame_storage,
    );
    try std.testing.expectEqual(
        @as(?u32, @intCast(file_encoder_summary.frame_count)),
        metadata_summary.first_xing.?.frame_count,
    );
    try std.testing.expectEqual(
        @as(?u12, 528),
        metadata_summary.first_xing.?.encoder_delay,
    );
    var tagged_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "public-tagged-encoder.mp3",
        .{ .read = true },
    );
    defer tagged_file.close(std.testing.io);
    const id3v2_prefix = [_]u8{
        'I', 'D', '3', 4, 0, 0, 0, 0, 0, 0,
    };
    const tagged_audio_offset =
        try plugin.dsp.writeMp3Id3v2FilePrefix(
            std.testing.io,
            tagged_file,
            &id3v2_prefix,
        );
    var tagged_encoder = try plugin.dsp.Mp3PcmFileEncoder.initAt(
        std.testing.io,
        tagged_file,
        .{ .channel_mode = .stereo },
        &file_encoder_storage,
        tagged_audio_offset,
    );
    try tagged_encoder.append(analysis_pcm);
    const tagged_summary = try tagged_encoder.finalize();
    var id3v1_tail: [128]u8 = @splat(0);
    @memcpy(id3v1_tail[0..3], "TAG");
    const tagged_file_bytes =
        try plugin.dsp.appendMp3Id3v1FileTail(
            std.testing.io,
            tagged_file,
            tagged_audio_offset,
            tagged_summary.byte_count,
            &id3v1_tail,
        );
    try std.testing.expectEqual(
        tagged_file_bytes,
        try tagged_file.length(std.testing.io),
    );
    const tagged_file_summary =
        try plugin.dsp.Mp3FileReader.summarize(
            std.testing.io,
            tagged_file,
            &metadata_frame_storage,
        );
    try std.testing.expectEqual(
        tagged_audio_offset,
        tagged_file_summary.audio_offset,
    );
    try std.testing.expectEqual(
        tagged_summary.frame_count,
        tagged_file_summary.frame_count,
    );
    var reservoir_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "public-reservoir-encoder.mp3",
        .{ .read = true },
    );
    defer reservoir_file.close(std.testing.io);
    var reservoir_file_storage: [4600]u8 = undefined;
    var reservoir_file_encoder =
        try plugin.dsp.Mp3PcmReservoirFileEncoder.init(
            std.testing.io,
            reservoir_file,
            .{ .channel_mode = .stereo },
            &reservoir_file_storage,
        );
    try std.testing.expect(reservoir_file_encoder.valid());
    try reservoir_file_encoder.startGaplessMetadata();
    _ = try reservoir_file_encoder.append(analysis_pcm);
    try std.testing.expect(
        try reservoir_file_encoder.append(analysis_pcm) > 0,
    );
    const reservoir_file_summary: plugin.dsp.Mp3PcmReservoirFileSummary =
        try reservoir_file_encoder.finalize();
    try std.testing.expect(reservoir_file_encoder.valid());
    try std.testing.expect(
        reservoir_file_summary.borrowed_bytes > 0,
    );
    try std.testing.expectEqual(
        reservoir_file_summary.stream.byte_count,
        try reservoir_file.length(std.testing.io),
    );
    const vbr_config = plugin.dsp.Mp3VbrEncoderConfig{
        .template = .{ .channel_mode = .stereo },
        .minimum_bitrate_index = 9,
        .maximum_bitrate_index = 9,
    };
    var vbr_encoder = try plugin.dsp.Mp3VbrPcmEncoder.init(
        vbr_config,
    );
    try std.testing.expect(vbr_encoder.valid());
    const vbr_frame: plugin.dsp.Mp3VbrPcmFrame =
        try vbr_encoder.encode(
            analysis_pcm,
            &automatic_storage,
        );
    try std.testing.expect(vbr_encoder.valid());
    try std.testing.expectEqual(
        @as(u4, 9),
        vbr_frame.bitrate_index,
    );
    var hostile_vbr_encoder = vbr_encoder;
    hostile_vbr_encoder.bitrate_histogram[0] = 1;
    try std.testing.expect(!hostile_vbr_encoder.valid());
    const hostile_vbr_before = hostile_vbr_encoder;
    try std.testing.expectError(
        error.InvalidMp3VbrEncoderState,
        hostile_vbr_encoder.encode(
            analysis_pcm,
            &automatic_storage,
        ),
    );
    try std.testing.expectEqual(
        hostile_vbr_before,
        hostile_vbr_encoder,
    );
    var vbr_reservoir =
        try plugin.dsp.Mp3VbrPcmReservoirEncoder.init(
            vbr_config,
        );
    try std.testing.expect(vbr_reservoir.valid());
    var hostile_vbr_reservoir = vbr_reservoir;
    hostile_vbr_reservoir.borrowed_bytes = 1;
    try std.testing.expect(!hostile_vbr_reservoir.valid());
    const vbr_reservoir_prime: plugin.dsp.Mp3VbrPcmReservoirAppend =
        try vbr_reservoir.appendAtBitrateIndex(
            analysis_pcm,
            automatic_storage[0..0],
            9,
        );
    try std.testing.expect(vbr_reservoir_prime.frame == null);
    try std.testing.expect(vbr_reservoir.valid());
    const vbr_reservoir_emitted: plugin.dsp.Mp3VbrPcmReservoirAppend =
        try vbr_reservoir.appendAtBitrateIndex(
            analysis_pcm,
            &automatic_storage,
            9,
        );
    try std.testing.expect(vbr_reservoir_emitted.frame != null);
    try std.testing.expectEqual(
        @as(u4, 9),
        vbr_reservoir_emitted.selection.bitrate_index,
    );
    try std.testing.expect(vbr_reservoir_emitted.borrowed_bytes > 0);
    var mismatched_vbr_reservoir_borrow = vbr_reservoir;
    mismatched_vbr_reservoir_borrow.borrowed_bytes -=
        vbr_reservoir_emitted.borrowed_bytes;
    try std.testing.expect(!mismatched_vbr_reservoir_borrow.valid());
    try std.testing.expect(vbr_reservoir.valid());
    const vbr_reservoir_final =
        try vbr_reservoir.finish(&automatic_storage);
    try std.testing.expect(vbr_reservoir_final != null);
    try std.testing.expect(vbr_reservoir.valid());
    const public_xing: plugin.dsp.Mp3XingEncoderMetadata = .{
        .kind = .variable,
        .frame_count = 1,
        .stream_bytes = @intCast(vbr_frame.frame.len),
        .encoder_delay = 0,
        .encoder_padding = 0,
        .encoder = plugin.dsp.defaultMp3XingEncoderIdentifier,
    };
    const public_xing_frame = try plugin.dsp.encodeMp3XingFrame(
        vbr_frame.header,
        public_xing,
        &automatic_storage,
    );
    try std.testing.expectEqual(
        plugin.dsp.defaultMp3XingEncoderIdentifier,
        (try plugin.dsp.Mp3Frame.parse(public_xing_frame, 0))
            .xing.?.encoder.?,
    );
    const custom_encoder: [9]u8 = "Fixture 1".*;
    try std.testing.expect(@hasDecl(
        plugin.dsp.Mp3PcmStreamEncoder,
        "startGaplessMetadataWithEncoder",
    ));
    try std.testing.expect(@hasDecl(
        plugin.dsp.Mp3PcmReservoirStreamEncoder,
        "startGaplessMetadataWithEncoder",
    ));
    try std.testing.expect(@hasDecl(
        plugin.dsp.Mp3VbrPcmStreamEncoder,
        "startXingMetadataWithEncoder",
    ));
    try std.testing.expect(@hasDecl(
        plugin.dsp.Mp3VbrPcmReservoirStreamEncoder,
        "startXingMetadataWithEncoder",
    ));
    try std.testing.expect(@hasDecl(
        plugin.dsp.Mp3PcmFileEncoder,
        "startGaplessMetadataWithEncoder",
    ));
    try std.testing.expect(@hasDecl(
        plugin.dsp.Mp3PcmReservoirFileEncoder,
        "startGaplessMetadataWithEncoder",
    ));
    try std.testing.expect(@hasDecl(
        plugin.dsp.Mp3VbrPcmFileEncoder,
        "startXingMetadataWithEncoder",
    ));
    try std.testing.expect(@hasDecl(
        plugin.dsp.Mp3VbrPcmReservoirFileEncoder,
        "startXingMetadataWithEncoder",
    ));
    const public_info_frame =
        try plugin.dsp.encodeMp3InfoFrameWithEncoder(
            .{
                .bitrate_kbps = 320,
                .channel_mode = .stereo,
            },
            .{
                .frame_count = 2,
                .input_samples = 1,
                .encoded_samples = 2304,
                .byte_count = 2088,
                .encoder_delay = 1688,
                .end_padding = 0,
            },
            custom_encoder,
            &automatic_storage,
        );
    try std.testing.expectEqual(
        custom_encoder,
        (try plugin.dsp.Mp3Frame.parse(public_info_frame, 0))
            .xing.?.encoder.?,
    );
    const public_vbri_offsets = [_]u64{
        0,
        vbr_frame.frame.len,
    };
    var public_vbri_toc_storage: [4]u8 = undefined;
    try std.testing.expectEqual(
        public_vbri_toc_storage.len,
        try plugin.dsp.requiredMp3VbriTocBytes(2, 1, 2),
    );
    const public_vbri_toc = try plugin.dsp.buildMp3VbriToc(
        &public_vbri_offsets,
        2,
        @intCast(vbr_frame.frame.len * 2),
        1,
        1,
        2,
        &public_vbri_toc_storage,
    );
    const public_vbri: plugin.dsp.Mp3VbriEncoderMetadata = .{
        .quality = 17,
        .stream_bytes = @intCast(vbr_frame.frame.len * 2),
        .frame_count = 2,
        .toc_scale = 1,
        .entry_bytes = 2,
        .frames_per_entry = 1,
        .toc = public_vbri_toc,
    };
    const public_vbri_frame = try plugin.dsp.encodeMp3VbriFrame(
        vbr_frame.header,
        public_vbri,
        &automatic_storage,
    );
    const parsed_public_vbri = (try plugin.dsp.Mp3Frame.parse(
        public_vbri_frame,
        0,
    )).vbri.?;
    try std.testing.expectEqual(
        @as(u32, 2),
        parsed_public_vbri.frame_count,
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        try parsed_public_vbri.approximateByteOffsetForFrame(0),
    );
    try std.testing.expectEqual(
        @as(u32, @intCast(vbr_frame.frame.len)),
        try parsed_public_vbri.approximateByteOffsetForFrame(1),
    );
    var vbri_stream_encoder = try plugin.dsp.Mp3PcmStreamEncoder.init(.{
        .bitrate_kbps = 320,
        .sample_rate = 44_100,
        .channel_mode = .joint_stereo,
        .mode_extension = 3,
    });
    var vbri_stream_bytes: [plugin.dsp.maximumMp3EncodedFrameBytes * 4]u8 =
        undefined;
    var vbri_stream_length: usize = 0;
    const vbri_placeholder = try vbri_stream_encoder.startGaplessMetadata(
        vbri_stream_bytes[vbri_stream_length..],
    );
    vbri_stream_length += vbri_placeholder.len;
    const vbri_audio = try vbri_stream_encoder.append(
        analysis_pcm,
        vbri_stream_bytes[vbri_stream_length..],
    );
    vbri_stream_length += vbri_audio.len;
    const vbri_finished = try vbri_stream_encoder.finish(
        vbri_stream_bytes[vbri_stream_length..],
    );
    vbri_stream_length += vbri_finished.frames.len;
    var vbri_final_offsets: [4]u64 = undefined;
    var vbri_final_toc: [16]u8 = undefined;
    const vbri_final: plugin.dsp.Mp3VbriStreamMetadataResult =
        try plugin.dsp.finalizeMp3VbriStreamMetadata(
            vbri_stream_bytes[0..vbri_stream_length],
            71,
            1,
            1,
            4,
            &vbri_final_offsets,
            &vbri_final_toc,
        );
    const vbri_final_summary = try plugin.dsp.Mp3Stream.summarize(
        vbri_stream_bytes[0..vbri_stream_length],
    );
    try std.testing.expectEqual(
        vbri_final.frame_count,
        vbri_final_summary.first_vbri.?.frame_count,
    );

    var vbr_stream_offsets: [4]u64 = undefined;
    var vbr_stream =
        try plugin.dsp.Mp3VbrPcmStreamEncoder.init(
            vbr_config,
            &vbr_stream_offsets,
        );
    try std.testing.expect(vbr_stream.valid());
    var hostile_vbr_stream = vbr_stream;
    hostile_vbr_stream.quality_misses = 1;
    try std.testing.expect(!hostile_vbr_stream.valid());
    _ = try vbr_stream.startXingMetadata(&stream_storage);
    try std.testing.expect(vbr_stream.valid());
    _ = try vbr_stream.append(analysis_pcm, &stream_storage);
    try std.testing.expect(vbr_stream.valid());
    const vbr_stream_finish: plugin.dsp.Mp3VbrPcmStreamFinish =
        try vbr_stream.finish(&stream_storage);
    try std.testing.expect(vbr_stream.valid());
    try std.testing.expectEqual(
        @as(u16, 2209),
        vbr_stream_finish.summary.encoder_delay,
    );

    var vbr_reservoir_stream_offsets: [4]u64 = undefined;
    var vbr_reservoir_stream =
        try plugin.dsp.Mp3VbrPcmReservoirStreamEncoder.init(
            vbr_config,
            &vbr_reservoir_stream_offsets,
        );
    try std.testing.expect(vbr_reservoir_stream.valid());
    var hostile_vbr_reservoir_stream = vbr_reservoir_stream;
    hostile_vbr_reservoir_stream.pending_length =
        std.math.maxInt(u16);
    try std.testing.expect(!hostile_vbr_reservoir_stream.valid());
    hostile_vbr_reservoir_stream = vbr_reservoir_stream;
    hostile_vbr_reservoir_stream.borrowed_bytes = 1;
    try std.testing.expect(!hostile_vbr_reservoir_stream.valid());
    _ = try vbr_reservoir_stream.startXingMetadata(
        &stream_storage,
    );
    try std.testing.expect(vbr_reservoir_stream.valid());
    const vbr_reservoir_stream_prime: plugin.dsp.Mp3VbrPcmReservoirAppend =
        try vbr_reservoir_stream.append(
            analysis_pcm,
            &stream_storage,
        );
    try std.testing.expect(
        vbr_reservoir_stream_prime.frame == null,
    );
    try std.testing.expect(vbr_reservoir_stream.valid());
    const vbr_reservoir_stream_emitted: plugin.dsp.Mp3VbrPcmReservoirAppend =
        try vbr_reservoir_stream.append(
            analysis_pcm,
            &stream_storage,
        );
    try std.testing.expect(
        vbr_reservoir_stream_emitted.frame != null,
    );
    try std.testing.expect(
        vbr_reservoir_stream_emitted.borrowed_bytes > 0,
    );
    var mismatched_vbr_reservoir_stream =
        vbr_reservoir_stream;
    mismatched_vbr_reservoir_stream.borrowed_bytes -=
        vbr_reservoir_stream_emitted.borrowed_bytes;
    try std.testing.expect(
        !mismatched_vbr_reservoir_stream.valid(),
    );
    const vbr_reservoir_stream_finish: plugin.dsp.Mp3VbrPcmReservoirStreamFinish =
        try vbr_reservoir_stream.finish(&stream_storage);
    try std.testing.expect(vbr_reservoir_stream.valid());
    try std.testing.expectEqual(
        @as(u64, 4),
        vbr_reservoir_stream_finish.summary.frame_count,
    );

    var vbr_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "public-vbr-encoder.mp3",
        .{ .read = true },
    );
    defer vbr_file.close(std.testing.io);
    var vbr_file_offsets: [4]u64 = undefined;
    var vbr_file_encoder =
        try plugin.dsp.Mp3VbrPcmFileEncoder.init(
            std.testing.io,
            vbr_file,
            vbr_config,
            &file_encoder_storage,
            &vbr_file_offsets,
        );
    try std.testing.expect(vbr_file_encoder.valid());
    try vbr_file_encoder.startXingMetadata(42);
    _ = try vbr_file_encoder.append(analysis_pcm);
    const vbr_file_summary: plugin.dsp.Mp3VbrPcmFileSummary =
        try vbr_file_encoder.finalize();
    try std.testing.expect(vbr_file_encoder.valid());
    try std.testing.expectEqual(
        vbr_file_summary.stream.byte_count,
        try vbr_file.length(std.testing.io),
    );

    var vbr_reservoir_file = try mp3_temporary.dir.createFile(
        std.testing.io,
        "public-vbr-reservoir-encoder.mp3",
        .{ .read = true },
    );
    defer vbr_reservoir_file.close(std.testing.io);
    var vbr_reservoir_file_offsets: [4]u64 = undefined;
    var vbr_reservoir_file_encoder =
        try plugin.dsp.Mp3VbrPcmReservoirFileEncoder.init(
            std.testing.io,
            vbr_reservoir_file,
            vbr_config,
            &file_encoder_storage,
            &vbr_reservoir_file_offsets,
        );
    try std.testing.expect(vbr_reservoir_file_encoder.valid());
    try vbr_reservoir_file_encoder.startXingMetadata(17);
    _ = try vbr_reservoir_file_encoder.append(analysis_pcm);
    const vbr_reservoir_file_summary: plugin.dsp.Mp3VbrPcmReservoirFileSummary =
        try vbr_reservoir_file_encoder.finalize();
    try std.testing.expect(vbr_reservoir_file_encoder.valid());
    try std.testing.expectEqual(
        vbr_reservoir_file_summary.stream.byte_count,
        try vbr_reservoir_file.length(std.testing.io),
    );
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
    try std.testing.expect(hybrid.valid());
    const hybrid_samples: plugin.dsp.Mp3HybridSamples =
        try hybrid.process(joint_header, .{}, alias_reduced);
    try std.testing.expect(
        std.math.isFinite(hybrid_samples.time_slots[0][0]),
    );
    try std.testing.expect(hybrid_samples.time_slots[0][0] != 0);
    hybrid.reset();
    try std.testing.expect(hybrid.valid());
    var polyphase = plugin.dsp.Mp3PolyphaseSynthesis{};
    try std.testing.expect(polyphase.valid());
    const pcm: plugin.dsp.Mp3PcmGranule =
        try polyphase.process(hybrid_samples);
    var pcm_nonzero = false;
    for (pcm.samples) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        pcm_nonzero = pcm_nonzero or sample != 0;
    }
    try std.testing.expect(pcm_nonzero);
    polyphase.reset();
    try std.testing.expect(polyphase.valid());
    var frame_decoder = plugin.dsp.Mp3FrameDecoder{};
    try std.testing.expect(frame_decoder.valid());
    const decoded_frame: plugin.dsp.Mp3PcmFrame =
        try frame_decoder.decode(installed_frame);
    try std.testing.expect(frame_decoder.valid());
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
    var hostile_frame_decoder = frame_decoder;
    hostile_frame_decoder.polyphase[0].head_block = 16;
    try std.testing.expect(!hostile_frame_decoder.valid());
    const hostile_frame_decoder_before = hostile_frame_decoder;
    try std.testing.expectError(
        error.InvalidMp3DecoderState,
        hostile_frame_decoder.decode(installed_frame),
    );
    try std.testing.expectEqual(
        hostile_frame_decoder_before,
        hostile_frame_decoder,
    );
    frame_decoder.reset();
    try std.testing.expect(frame_decoder.valid());

    const summary = try plugin.dsp.Mp3Stream.summarize(&encoded);
    try std.testing.expectEqual(@as(u64, 2), summary.frame_count);
    try std.testing.expectEqual(@as(u64, 2304), summary.sample_count);
    const gapless_plan: plugin.dsp.Mp3GaplessPlan =
        try plugin.dsp.Mp3GaplessPlan.fromSummary(summary);
    try std.testing.expect(gapless_plan.valid());
    try std.testing.expectEqual(@as(u64, 2304), gapless_plan.audible_samples);
    var stream_decoder =
        try plugin.dsp.Mp3StreamDecoder.init(summary);
    try std.testing.expect(stream_decoder.valid());
    var decode_stream = try plugin.dsp.Mp3Stream.init(&encoded);
    while (try decode_stream.next()) |decode_frame| {
        const trimmed: plugin.dsp.Mp3TrimmedPcmFrame =
            try stream_decoder.decode(decode_frame);
        try std.testing.expect(stream_decoder.valid());
        try std.testing.expectEqual(
            plugin.dsp.Mp3PcmRange{
                .start = 0,
                .length = 1152,
            },
            trimmed.audible,
        );
    }
    try stream_decoder.finish();
    try std.testing.expect(stream_decoder.valid());
    var fractional_stream_decoder = stream_decoder;
    fractional_stream_decoder.sample_offset -= 1;
    try std.testing.expect(!fractional_stream_decoder.valid());
    const fractional_stream_decoder_before =
        fractional_stream_decoder;
    try std.testing.expectError(
        error.InvalidMp3StreamDecoderState,
        fractional_stream_decoder.finish(),
    );
    try std.testing.expectEqual(
        fractional_stream_decoder_before,
        fractional_stream_decoder,
    );
    var hostile_stream_decoder = stream_decoder;
    hostile_stream_decoder.decoder.hybrid[0].overlap[0][0] =
        std.math.inf(f32);
    try std.testing.expect(!hostile_stream_decoder.valid());

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
    var file_points: [2]plugin.dsp.Mp3SeekPoint = undefined;
    var file_point_scratch: [2]plugin.dsp.Mp3SeekPoint = undefined;
    const file_index = try plugin.dsp.buildMp3FileSeekIndexTransactional(
        std.testing.io,
        file,
        &frame_storage,
        1,
        &file_points,
        &file_point_scratch,
    );
    try std.testing.expectEqualSlices(
        plugin.dsp.Mp3SeekPoint,
        index,
        file_index,
    );
    var aliased_frame_storage: [500]u8 align(@alignOf(plugin.dsp.Mp3SeekPoint)) = undefined;
    const frame_aliased_point_scratch = std.mem.bytesAsSlice(
        plugin.dsp.Mp3SeekPoint,
        aliased_frame_storage[0 .. 2 * @sizeOf(plugin.dsp.Mp3SeekPoint)],
    );
    const file_points_before_alias = file_points;
    try std.testing.expectError(
        error.OverlappingMp3SeekStorage,
        plugin.dsp.buildMp3FileSeekIndexTransactional(
            std.testing.io,
            file,
            &aliased_frame_storage,
            1,
            &file_points,
            frame_aliased_point_scratch,
        ),
    );
    try std.testing.expectEqual(file_points_before_alias, file_points);

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

test "installed MP3 reservoir batches reject PCM scratch overlap" {
    const config = plugin.dsp.Mp3EncoderConfig{
        .channel_mode = .mono,
    };
    const header = try config.header(false);
    var pcm_storage: [@sizeOf(plugin.dsp.Mp3PcmFrame)]u8 align(@alignOf(plugin.dsp.Mp3PcmFrame)) = undefined;
    const pcm = std.mem.bytesAsSlice(
        plugin.dsp.Mp3PcmFrame,
        &pcm_storage,
    );
    pcm[0] = .{
        .channel_count = 1,
        .sample_count = header.samplesPerFrame(),
    };
    const before = pcm_storage;
    var destination: [plugin.dsp.maximumMp3EncodedFrameBytes]u8 = undefined;
    var pack_scratch: [plugin.dsp.maximumMp3EncodedFrameBytes]u8 = undefined;
    var main_data_scratch: [plugin.dsp.maximumMp3EncodedMainDataBytes]u8 =
        undefined;
    try std.testing.expectError(
        error.OverlappingMp3ReservoirStorage,
        plugin.dsp.encodeMp3PcmReservoirBatch(
            config,
            pcm,
            511,
            &destination,
            &pcm_storage,
            &pack_scratch,
            &main_data_scratch,
        ),
    );
    try std.testing.expectEqual(before, pcm_storage);
}

test "installed metadata encoders reject overlapping borrowed input" {
    var broadcast_storage: [640]u8 = @splat(0x69);
    @memcpy(broadcast_storage[0..5], "Title");
    const broadcast_before = broadcast_storage;
    try std.testing.expectError(
        error.BroadcastMetadataSourceAliasesOutput,
        plugin.dsp.encodeBroadcastMetadata(
            &broadcast_storage,
            .{ .description = broadcast_storage[0..5] },
        ),
    );
    try std.testing.expectEqual(broadcast_before, broadcast_storage);

    var xml_storage: [32]u8 = @splat(0xa5);
    @memcpy(xml_storage[0..4], "<x/>");
    const xml_before = xml_storage;
    try std.testing.expectError(
        error.MetadataSourceAliasesOutput,
        plugin.dsp.encodeRiffXmlMetadata(
            &xml_storage,
            .ixml,
            xml_storage[0..4],
        ),
    );
    try std.testing.expectEqual(xml_before, xml_storage);

    var info_storage: [32]u8 = @splat(0x5a);
    @memcpy(info_storage[0..5], "Title");
    const info_before = info_storage;
    const info_entries = [_]plugin.dsp.AudioMetadataEntry{.{
        .id = plugin.dsp.audio_metadata.title,
        .value = info_storage[0..5],
    }};
    try std.testing.expectError(
        error.MetadataSourceAliasesOutput,
        plugin.dsp.encodeRiffInfoMetadata(
            &info_storage,
            &info_entries,
        ),
    );
    try std.testing.expectEqual(info_before, info_storage);

    var text_storage: [64]u8 align(@alignOf(plugin.dsp.AudioMetadataEntry)) = @splat(0x3c);
    const text_entries = std.mem.bytesAsSlice(
        plugin.dsp.AudioMetadataEntry,
        text_storage[0..@sizeOf(plugin.dsp.AudioMetadataEntry)],
    );
    text_entries[0] = .{
        .id = plugin.dsp.audio_metadata.aiff_name,
        .value = "Title",
    };
    const text_before = text_storage;
    try std.testing.expectError(
        error.MetadataSourceAliasesOutput,
        plugin.dsp.encodeAiffTextMetadata(
            &text_storage,
            text_entries,
        ),
    );
    try std.testing.expectEqual(text_before, text_storage);

    var channel_storage: [52]u8 = @splat(0x69);
    @memcpy(channel_storage[0..12], "ATU_00000001");
    const channel_before = channel_storage;
    const channel_entries = [_]plugin.dsp.AdmChannelAllocationEntry{.{
        .track_index = 1,
        .uid = channel_storage[0..12],
        .track_ref = "AT_00010001_01",
        .pack_ref = "AP_00010001",
    }};
    try std.testing.expectError(
        error.AdmChannelAllocationSourceAliasesOutput,
        plugin.dsp.encodeAdmChannelAllocation(
            &channel_storage,
            .{
                .num_tracks = 1,
                .entries = &channel_entries,
            },
        ),
    );
    try std.testing.expectEqual(channel_before, channel_storage);
}

test "installed Vorbis comments contain aliases and hostile iterators" {
    var storage: [64]u8 align(@alignOf(plugin.dsp.VorbisComment)) =
        @splat(0x5a);
    const comments = std.mem.bytesAsSlice(
        plugin.dsp.VorbisComment,
        storage[0..@sizeOf(plugin.dsp.VorbisComment)],
    );
    comments[0] = .{ .name = "TITLE", .value = "value" };
    const before = storage;
    try std.testing.expectError(
        error.OverlappingVorbisCommentStorage,
        plugin.dsp.encodeVorbisCommentPacket(
            &storage,
            "",
            comments,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);

    var packet_storage: [64]u8 = undefined;
    const encoded = try plugin.dsp.encodeVorbisCommentPacket(
        &packet_storage,
        "vendor",
        &.{.{ .name = "TITLE", .value = "value" }},
    );
    var iterator = try plugin.dsp.VorbisCommentIterator.init(encoded);
    iterator.offset += 1;
    const hostile_offset = iterator.offset;
    try std.testing.expect(!iterator.valid());
    try std.testing.expectError(
        error.InvalidVorbisCommentIteratorState,
        iterator.next(),
    );
    try std.testing.expectEqual(hostile_offset, iterator.offset);

    var stale_vendor = try plugin.dsp.VorbisCommentIterator.init(encoded);
    stale_vendor.vendor = encoded[12..18];
    try std.testing.expect(!stale_vendor.valid());
    const stale_vendor_offset = stale_vendor.offset;
    try std.testing.expectError(
        error.InvalidVorbisCommentIteratorState,
        stale_vendor.next(),
    );
    try std.testing.expectEqual(stale_vendor_offset, stale_vendor.offset);
}

test "installed metadata iterators reject malformed retained cursors" {
    const entries = [_]plugin.dsp.AudioMetadataEntry{
        .{ .id = plugin.dsp.audio_metadata.title, .value = "Title" },
    };
    var riff_storage: [32]u8 = undefined;
    const riff_encoded = try plugin.dsp.encodeRiffInfoMetadata(
        &riff_storage,
        &entries,
    );
    const installed_metadata_limits: plugin.dsp.AudioMetadataLimits =
        plugin.dsp.default_audio_metadata_limits;
    const riff_view = try plugin.dsp.RiffInfoMetadataView.initWithLimits(
        riff_encoded,
        installed_metadata_limits,
    );
    var middle_riff_iterator = riff_view.iterator();
    middle_riff_iterator.offset = 13;
    try std.testing.expect(!middle_riff_iterator.valid());
    try std.testing.expectError(
        error.InvalidRiffInfoIteratorState,
        middle_riff_iterator.next(),
    );
    try std.testing.expectEqual(
        @as(usize, 13),
        middle_riff_iterator.offset,
    );

    var riff_iterator = plugin.dsp.audio_metadata.RiffInfoIterator{
        .bytes = &.{},
        .offset = 1,
    };
    try std.testing.expect(!riff_iterator.valid());
    try std.testing.expectError(
        error.InvalidRiffInfoIteratorState,
        riff_iterator.next(),
    );
    try std.testing.expectEqual(@as(usize, 1), riff_iterator.offset);

    var aiff_storage: [16]u8 = undefined;
    const aiff_encoded = try plugin.dsp.encodeAiffTextMetadata(
        &aiff_storage,
        &entries,
    );
    var middle_aiff_iterator = try plugin.dsp.AiffTextMetadataIterator.initWithLimits(
        aiff_encoded,
        installed_metadata_limits,
    );
    middle_aiff_iterator.offset = 1;
    try std.testing.expect(!middle_aiff_iterator.valid());
    try std.testing.expectError(
        error.InvalidAiffTextIteratorState,
        middle_aiff_iterator.next(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        middle_aiff_iterator.offset,
    );

    var aiff_iterator = plugin.dsp.AiffTextMetadataIterator{
        .bytes = &.{},
        .offset = 1,
    };
    try std.testing.expect(!aiff_iterator.valid());
    try std.testing.expectError(
        error.InvalidAiffTextIteratorState,
        aiff_iterator.next(),
    );
    try std.testing.expectEqual(@as(usize, 1), aiff_iterator.offset);
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

    var importer = plugin.gui_audio_file_importer.DecodedImporter(2).init();
    defer importer.deinit();
    for (importer.preview) |point|
        try std.testing.expectEqualDeep(
            plugin.gui_audio_file_importer.PreviewPoint{},
            point,
        );
    for (importer.decoded) |sample|
        try std.testing.expectEqual(@as(f32, 0.0), sample);
    importer.preview_points = 1;
    importer.preview[0] = .{ .x = 0.25, .y = std.math.nan(f64) };
    var preview_output = [1]plugin.gui_audio_file_importer.PreviewPoint{.{
        .x = 9.0,
        .y = 9.0,
    }};
    try std.testing.expectEqual(
        @as(usize, 0),
        importer.copyPreview(&preview_output),
    );
    try std.testing.expectEqual(@as(f64, 9.0), preview_output[0].y);

    importer.decoded_frames = 1;
    importer.channels = 1;
    importer.decoded[0] = std.math.inf(f32);
    var decoded_output = [1]f32{9.0};
    try std.testing.expectEqual(
        @as(usize, 0),
        importer.copyDecoded(0, &decoded_output),
    );
    try std.testing.expectEqual(@as(f32, 9.0), decoded_output[0]);
    try std.testing.expect(importer.reset());
    for (importer.preview) |point|
        try std.testing.expectEqualDeep(
            plugin.gui_audio_file_importer.PreviewPoint{},
            point,
        );
    for (importer.decoded) |sample|
        try std.testing.expectEqual(@as(f32, 0.0), sample);
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
    for (installed_block.positions[installed_block.position_count..]) |position| {
        try std.testing.expectEqual(
            plugin.dsp.AdmXmlCoordinate.azimuth,
            position.coordinate,
        );
        try std.testing.expectEqual(
            plugin.dsp.AdmXmlPositionBound.exact,
            position.bound,
        );
        try std.testing.expectEqual(@as(f64, 0.0), position.value);
    }
    for (installed_block.speaker_labels) |label| {
        try std.testing.expectEqual(@as(u8, 0), label.len);
        for (label.bytes) |byte|
            try std.testing.expectEqual(@as(u8, 0), byte);
    }
    for (installed_block.exclusion_zones) |zone| switch (zone) {
        .cartesian => |cartesian| {
            try std.testing.expectEqual(@as(f64, 0.0), cartesian.min_x);
            try std.testing.expectEqual(@as(f64, 0.0), cartesian.max_x);
        },
        .polar => return error.TestUnexpectedResult,
    };
    for (installed_block.matrix_coefficients) |coefficient| {
        try std.testing.expectEqual(
            @as(u8, 0),
            coefficient.channel_identifier_len,
        );
        for (coefficient.channel_identifier_bytes) |byte|
            try std.testing.expectEqual(@as(u8, 0), byte);
    }
    const minimal_adm_xml = "<audioFormatExtended/>";
    var installed_adm_limits: plugin.dsp.AdmXmlLimits =
        plugin.dsp.default_adm_xml_limits;
    installed_adm_limits.max_document_bytes = minimal_adm_xml.len;
    _ = try plugin.dsp.AdmXmlDocument.initWithLimits(
        minimal_adm_xml,
        installed_adm_limits,
    );
    installed_adm_limits.max_document_bytes -= 1;
    try std.testing.expectError(
        error.AdmXmlDocumentTooLarge,
        plugin.dsp.AdmXmlDocument.initWithLimits(
            minimal_adm_xml,
            installed_adm_limits,
        ),
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

    var malformed_block = matrix_block;
    malformed_block.position_count = std.math.maxInt(usize);
    malformed_block.speaker_label_count = std.math.maxInt(usize);
    malformed_block.exclusion_zone_count = std.math.maxInt(usize);
    malformed_block.matrix_coefficient_count = std.math.maxInt(usize);
    try std.testing.expect(!malformed_block.retainedCountsValid());
    try std.testing.expectEqual(@as(usize, 0), malformed_block.positionSlice().len);
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_block.speakerLabelSlice().len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_block.exclusionZoneSlice().len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_block.matrixCoefficientSlice().len,
    );

    const malformed_text = plugin.dsp.AdmXmlText{
        .len = std.math.maxInt(u8),
    };
    try std.testing.expect(!malformed_text.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed_text.value().len);

    const malformed_label = plugin.dsp.AdmXmlSpeakerLabel{
        .len = std.math.maxInt(u8),
    };
    try std.testing.expect(!malformed_label.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed_label.value().len);

    const malformed_coefficient = plugin.dsp.AdmXmlMatrixCoefficient{
        .channel_identifier_len = std.math.maxInt(u8),
    };
    try std.testing.expectError(
        error.InvalidAdmMatrixCoefficientState,
        malformed_coefficient.channelIdentifier(),
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
    var speaker_router = try plugin.dsp.AdmDirectSpeakerRouter(f32).init(
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
    speaker_router.output_count += 1;
    try std.testing.expectEqual(
        @as(f32, 0.0),
        speaker_router.processSample(0.25),
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
    var position_router =
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
    position_router.output_count += 1;
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        position_router.processSample(0.25),
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
    for (polar_panner.core.vertices[polar_panner.core.vertex_count..]) |vertex| {
        try std.testing.expectEqual(@as(f64, 0.0), vertex.position.x);
        try std.testing.expectEqual(@as(f64, 0.0), vertex.position.y);
        try std.testing.expectEqual(@as(f64, 0.0), vertex.position.z);
        for (vertex.output_gains) |gain|
            try std.testing.expectEqual(@as(f64, 0.0), gain);
    }
    for (
        polar_panner.core.nominal_positions[polar_panner.core.vertex_count..],
    ) |position| {
        try std.testing.expectEqual(@as(f64, 0.0), position.x);
        try std.testing.expectEqual(@as(f64, 0.0), position.y);
        try std.testing.expectEqual(@as(f64, 0.0), position.z);
    }
    for (polar_panner.core.regions[polar_panner.core.region_count..]) |region| {
        try std.testing.expectEqual(@as(u8, 0), region.count);
        try std.testing.expectEqual(@as([4]u8, @splat(0)), region.vertices);
    }
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
    for (polar_cartesian_panner.positions[polar_layout.len..]) |position|
        try std.testing.expectEqualDeep(plugin.dsp.AdmCartesianPosition{}, position);
    for (polar_cartesian_panner.enabled[polar_layout.len..]) |enabled|
        try std.testing.expect(!enabled);
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
    for (object_plan.direct_gains[polar_layout.len..]) |gain|
        try std.testing.expectEqual(@as(f32, 0.0), gain);
    for (object_plan.diffuse_gains[polar_layout.len..]) |gain|
        try std.testing.expectEqual(@as(f32, 0.0), gain);
    var malformed_object_plan = object_plan;
    malformed_object_plan.output_count += 1;
    try std.testing.expect(!malformed_object_plan.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_object_plan.directGainSlice().len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_object_plan.diffuseGainSlice().len,
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
    var object_timeline =
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
    object_timeline.segment_count = 1;
    try std.testing.expect(!object_timeline.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        object_timeline.blockCount(),
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
    for (cartesian_extent_panner.core.positions[polar_layout.len..]) |position| {
        try std.testing.expectEqual(@as(f64, 0.0), position.x);
        try std.testing.expectEqual(@as(f64, 0.0), position.y);
        try std.testing.expectEqual(@as(f64, 0.0), position.z);
    }
    for (cartesian_extent_panner.core.enabled[polar_layout.len..]) |enabled|
        try std.testing.expect(!enabled);
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
    const installed_audio_limits: plugin.dsp.AudioFileLimits =
        plugin.dsp.default_audio_file_limits;
    const wav_reader = try plugin.dsp.AudioFileReader.initWithLimits(
        std.testing.io,
        wav_file,
        installed_audio_limits,
    );
    try std.testing.expect(wav_reader.valid());
    try std.testing.expectEqual(
        plugin.dsp.AudioFileContainer.wav,
        wav_reader.getInfo().container,
    );
    var malformed_wav_reader = wav_reader;
    malformed_wav_reader.byte_order = .big;
    try std.testing.expect(!malformed_wav_reader.valid());
    try std.testing.expectError(
        error.InvalidAudioFileReaderState,
        malformed_wav_reader.requiredMetadataChunkBytes(.ixml),
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
    var transactional_wav_samples: [2]f32 = @splat(99.0);
    var transactional_wav_scratch: [2]f32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 2),
        try wav_reader.readInterleavedTransactional(
            f32,
            0,
            &transactional_wav_samples,
            &transactional_wav_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &wav_samples,
        &transactional_wav_samples,
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
    var transactional_metadata_storage: [4096]u8 = undefined;
    var transactional_metadata_scratch: [4096]u8 = undefined;
    const transactional_broadcast =
        try wav_reader.readMetadataChunkTransactional(
            .broadcast,
            &transactional_metadata_storage,
            &transactional_metadata_scratch,
        );
    try std.testing.expectEqualSlices(
        u8,
        broadcast_chunk.?,
        transactional_broadcast.?,
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
    const ixml_view = try plugin.dsp.RiffXmlView.initWithLimits(
        ixml_chunk.?,
        plugin.dsp.default_audio_metadata_limits,
    );
    try std.testing.expectEqual(
        plugin.dsp.RiffXmlKind.ixml,
        ixml_view.kind,
    );
    const ixml_limits = plugin.dsp.IxmlLimits{
        .max_document_bytes = 4 * 1024,
        .max_structural_work = 512 * 1024,
        .max_text_bytes = 512,
        .max_tracks = 1,
        .max_sync_points = 1,
    };
    const ixml_requirements =
        try plugin.dsp.requiredIxmlParseStorageWithLimits(
            ixml_view.document,
            ixml_limits,
        );
    var parsed_ixml_tracks: [1]plugin.dsp.IxmlTrack = undefined;
    var parsed_ixml_sync_points: [1]plugin.dsp.IxmlSyncPoint =
        undefined;
    var parsed_ixml_text: [512]u8 = undefined;
    const parsed_ixml = try plugin.dsp.parseIxmlMetadataWithLimits(
        ixml_view.document,
        .{
            .tracks = &parsed_ixml_tracks,
            .sync_points = &parsed_ixml_sync_points,
            .text = &parsed_ixml_text,
        },
        ixml_limits,
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
    var malformed_channel_view = channel_view;
    malformed_channel_view.num_uids = std.math.maxInt(u16);
    try std.testing.expect(!malformed_channel_view.valid());
    try std.testing.expectError(
        error.InvalidAdmChannelAllocation,
        malformed_channel_view.entry(0),
    );
    var malformed_channel_iterator = malformed_channel_view.iterator();
    try std.testing.expect(!malformed_channel_iterator.valid());
    try std.testing.expectError(
        error.InvalidAdmChannelAllocationIteratorState,
        malformed_channel_iterator.next(),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_channel_iterator.index,
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
    var transactional_bw64_xml: [256]u8 = undefined;
    var transactional_bw64_channels: [256]u8 = undefined;
    var transactional_bw64_xml_scratch: [256]u8 = undefined;
    var transactional_bw64_channel_scratch: [256]u8 = undefined;
    const transactional_bw64_adm =
        try bw64_reader.readAdmMetadataTransactional(
            &transactional_bw64_xml,
            &transactional_bw64_channels,
            &transactional_bw64_xml_scratch,
            &transactional_bw64_channel_scratch,
        );
    try std.testing.expectEqual(
        @as(u16, 1),
        transactional_bw64_adm.?.channel_allocation.num_tracks,
    );
    transactional_bw64_xml = @splat(0xa5);
    transactional_bw64_channels = @splat(0x5a);
    const rejected_bw64_xml = transactional_bw64_xml;
    const rejected_bw64_channels = transactional_bw64_channels;
    try std.testing.expectError(
        error.MissingAdmEmissionProfileDocumentVersion,
        bw64_reader.readEmissionProfileAdmMetadataTransactional(
            &transactional_bw64_xml,
            &transactional_bw64_channels,
            &transactional_bw64_xml_scratch,
            &transactional_bw64_channel_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &rejected_bw64_xml,
        &transactional_bw64_xml,
    );
    try std.testing.expectEqualSlices(
        u8,
        &rejected_bw64_channels,
        &transactional_bw64_channels,
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
    snapshots.next_generation = 0;
    try std.testing.expectEqual(
        @as(u64, 2),
        try snapshots.publish(.{ .gain = 0.75, .mode = 2 }),
    );

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

    var malformed_gains =
        plugin.dsp.adm_direct_speaker_mapping.GainVector{
            .output_count = 1,
        };
    malformed_gains.gains[0] = std.math.inf(f64);
    try std.testing.expect(!malformed_gains.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_gains.slice().len,
    );
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
    for (mixer.input_indices[mixer.term_count..]) |input_index|
        try std.testing.expectEqual(@as(u8, 0), input_index);
    for (mixer.gains[mixer.term_count..]) |gain|
        try std.testing.expectEqual(@as(f32, 0.0), gain);
    for (mixer.delays[mixer.term_count..]) |delay|
        try std.testing.expectEqual(@as(usize, 0), delay);
    const input = [_]f32{ 2.0, 4.0, 6.0 };
    const inputs = [_][]const f32{&input};
    var output: [input.len]f32 = undefined;
    try mixer.process(&inputs, &output);
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 1.0, 2.0 },
        output,
    );
    const retained_cursor = mixer.cursor;
    mixer.input_count += 1;
    mixer.reset();
    try std.testing.expectEqual(retained_cursor, mixer.cursor);
    const extra = [_]f32{ 0.0, 0.0, 0.0 };
    const expanded_inputs = [_][]const f32{ &input, &extra };
    output = @splat(7.0);
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        mixer.process(&expanded_inputs, &output),
    );
    try std.testing.expectEqualDeep([_]f32{ 7.0, 7.0, 7.0 }, output);
}

test "installed package exposes variable ADM Matrix coefficient rendering" {
    const document = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient gainVar="mix" phaseVar="angle">AC_00010001</coefficient>
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
    const gain_points = [_]plugin.dsp.AdmMatrixVariablePoint{
        .{ .sample = 0, .value = 0.5 },
    };
    const phase_points = [_]plugin.dsp.AdmMatrixVariablePoint{
        .{ .sample = 0, .value = 0.0 },
        .{ .sample = 2, .value = 90.0 },
    };
    const timelines = [_]plugin.dsp.AdmMatrixVariableTimeline{
        .{
            .name = "mix",
            .kind = .gain_linear,
            .interpolation = .hold,
            .points = &gain_points,
        },
        .{
            .name = "angle",
            .kind = .phase_degrees,
            .points = &phase_points,
        },
    };
    const Mixer = plugin.dsp.AdmVariableMatrixCoefficientMixer(
        f32,
        0,
        2,
        3,
        3,
    );
    var mixer = try Mixer.init(
        &block,
        &channels,
        48_000.0,
        &timelines,
        &.{ 0.5, 0.0, -0.5 },
    );
    try std.testing.expectEqual(@as(usize, 1), mixer.latencySamples());
    for (mixer.input_indices[mixer.term_count..]) |input_index|
        try std.testing.expectEqual(@as(u8, 0), input_index);
    for (mixer.fixed_gains[mixer.term_count..]) |gain|
        try std.testing.expectEqual(@as(f32, 0.0), gain);
    for (mixer.fixed_phases[mixer.term_count..]) |phase|
        try std.testing.expectEqual(@as(f64, 0.0), phase);
    for (mixer.fixed_delays[mixer.term_count..]) |delay|
        try std.testing.expectEqual(@as(f64, 0.0), delay);
    for (mixer.phase_taps[mixer.phase_tap_count..]) |tap|
        try std.testing.expectEqual(@as(f32, 0.0), tap);
    const input = [_]f32{ 1.0, 0.0, -1.0, 0.0 };
    const inputs = [_][]const f32{&input};
    var output: [input.len]f32 = undefined;
    try mixer.process(0, &inputs, &output);
    try std.testing.expectApproxEqAbs(
        @as(f32, -0.5),
        output[2],
        0.000_001,
    );
    const retained_cursor = mixer.cursor;
    const retained_next_sample = mixer.next_sample;
    mixer.term_count += 1;
    mixer.resetAt(0);
    try std.testing.expectEqual(retained_cursor, mixer.cursor);
    try std.testing.expectEqual(retained_next_sample, mixer.next_sample);
    output = @splat(7.0);
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        mixer.process(retained_next_sample, &inputs, &output),
    );
    try std.testing.expectEqualDeep([_]f32{ 7.0, 7.0, 7.0, 7.0 }, output);
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
    const CountBoundDecoder = plugin.dsp.AdmHoaMatrixDecoder(f32, 3, 2);
    const count_bound_decoder = try CountBoundDecoder.init(
        blocks[1..2],
        1,
        &.{1.0},
    );
    for (2..4) |forged_count| {
        var hostile = count_bound_decoder;
        hostile.input_count = forged_count;
        const hostile_before = hostile;
        var retained = [_]f32{ 31.0, 47.0 };
        try std.testing.expect(!hostile.valid());
        try std.testing.expectError(
            error.InvalidAdmHoaDecoderState,
            hostile.processSample(&.{ 1.0, 2.0 }, retained[0..1]),
        );
        try std.testing.expectEqualDeep(hostile_before, hostile);
        try std.testing.expectEqualDeep([_]f32{ 31.0, 47.0 }, retained);
    }
    var hostile_output_count = count_bound_decoder;
    hostile_output_count.output_count = 2;
    const hostile_output_count_before = hostile_output_count;
    var retained = [_]f32{ 53.0, 59.0 };
    try std.testing.expect(!hostile_output_count.valid());
    try std.testing.expectError(
        error.InvalidAdmHoaDecoderState,
        hostile_output_count.processSample(&.{1.0}, &retained),
    );
    try std.testing.expectEqualDeep(
        hostile_output_count_before,
        hostile_output_count,
    );
    try std.testing.expectEqualDeep([_]f32{ 53.0, 59.0 }, retained);
    try std.testing.expectEqual(
        @as(u32, 50),
        plugin.dsp.maximum_supported_adm_hoa_order,
    );
}

test "installed package generates ADM HOA loudspeaker matrices" {
    const document = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>0</order><degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\      <nfcRefDist>1</nfcRefDist>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041002">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041002_00000001">
        \\      <order>1</order><degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\      <nfcRefDist>1</nfcRefDist>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    const blocks = [_]plugin.dsp.AdmXmlBlockFormat{
        (try iterator.next()).?,
        (try iterator.next()).?,
    };
    const loudspeakers = [_]plugin.dsp.AdmHoaLoudspeaker{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 45.0 },
        .{ .azimuth_degrees = 180.0, .elevation_degrees = -45.0 },
    };
    const Matrix = plugin.dsp.AdmHoaLoudspeakerMatrix(f32, 3, 2);
    const generated = try Matrix.init(
        &blocks,
        &loudspeakers,
        plugin.dsp.AdmHoaMatrixGenerationOptions{
            .order_weighting = plugin.dsp.AdmHoaOrderWeighting.basic,
        },
    );
    try std.testing.expectEqual(@as(u8, 0), generated.orders[2]);
    try std.testing.expectEqual(@as(i8, 0), generated.degrees[2]);
    const decoder = try generated.decoder(&blocks);
    try std.testing.expectEqual(@as(u8, 0), decoder.orders[2]);
    try std.testing.expectEqual(@as(i8, 0), decoder.degrees[2]);
    var output: [2]f32 = undefined;
    try decoder.processSample(&.{ 1.0, 0.0 }, &output);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        output[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        output[1],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        try plugin.dsp.evaluateAdmHoaBasis(
            .sn3d,
            1,
            1,
            0.0,
            0.0,
        ),
        1.0e-14,
    );

    const DualBand = plugin.dsp.AdmHoaDualBandDecoder(
        f32,
        3,
        2,
    );
    const dual_band_config =
        plugin.dsp.AdmHoaDualBandConfig{
            .sample_rate = 48_000.0,
            .crossover_hz = 1_000.0,
        };
    var dual_band = try DualBand.init(
        &blocks,
        2,
        &.{
            1.0, 0.0,
            0.0, 1.0,
        },
        &.{
            0.5, 0.0,
            0.0, 0.5,
        },
        dual_band_config,
    );
    try std.testing.expect(dual_band.crossovers[2].valid());
    const first_band = [_]f32{ 1.0, 0.0, -1.0, 0.5 };
    const second_band = [_]f32{ 0.0, 1.0, 0.0, -0.5 };
    const band_inputs = [_][]const f32{
        &first_band,
        &second_band,
    };
    var first_output: [first_band.len]f32 = undefined;
    var second_output: [first_band.len]f32 = undefined;
    try dual_band.process(
        &band_inputs,
        &.{ first_output[0..], second_output[0..] },
    );
    for (first_output ++ second_output) |sample|
        try std.testing.expect(std.math.isFinite(sample));
    try dual_band.configure(.{
        .sample_rate = 48_000.0,
        .crossover_hz = 1_500.0,
    }, 32);
    try dual_band.reset();

    const Radial = plugin.dsp.AdmHoaRadialFilterBank(f32, 3, 4);
    var radial = try Radial.init(
        &blocks,
        plugin.dsp.AdmHoaRadialConfig{
            .sample_rate = 48_000.0,
            .loudspeaker_distance = 2.0,
            .normalization = .high_frequency_unity,
            .regularization = .{ .gain_limit = .{
                .maximum_gain_db = 12.0,
                .transition_hz = 100.0,
            } },
        },
    );
    try std.testing.expectEqual(@as(u8, 0), radial.orders[2]);
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        radial.magnitude(1, 0.0),
        1.0e-6,
    );
    var radial_first: [first_band.len]f32 = undefined;
    var radial_second: [second_band.len]f32 = undefined;
    try radial.process(
        &band_inputs,
        &.{ &radial_first, &radial_second },
    );
    for (radial_first ++ radial_second) |sample|
        try std.testing.expect(std.math.isFinite(sample));
    var hostile_radial_count = radial;
    hostile_radial_count.input_count = 3;
    const hostile_radial_count_before = hostile_radial_count;
    hostile_radial_count.reset();
    try std.testing.expectEqualDeep(
        hostile_radial_count_before,
        hostile_radial_count,
    );
    const third_band = [_]f32{ 0.25, -0.25, 0.5, -0.5 };
    var hostile_first: [first_band.len]f32 = @splat(61.0);
    var hostile_second: [first_band.len]f32 = @splat(67.0);
    var hostile_third: [first_band.len]f32 = @splat(71.0);
    try std.testing.expect(!hostile_radial_count.valid());
    try std.testing.expectError(
        error.InvalidAdmHoaRadialState,
        hostile_radial_count.process(
            &.{ &first_band, &second_band, &third_band },
            &.{ &hostile_first, &hostile_second, &hostile_third },
        ),
    );
    try std.testing.expectEqualDeep(
        hostile_radial_count_before,
        hostile_radial_count,
    );
    try std.testing.expectEqual(
        [_]f32{61.0} ** first_band.len,
        hostile_first,
    );
    try std.testing.expectEqual(
        [_]f32{67.0} ** first_band.len,
        hostile_second,
    );
    try std.testing.expectEqual(
        [_]f32{71.0} ** first_band.len,
        hostile_third,
    );

    var screen_blocks = blocks;
    for (&screen_blocks) |*block| block.screen_ref = true;
    const screen_matrix = try Matrix.init(
        &screen_blocks,
        &loudspeakers,
        .{
            .screen_reference_policy = plugin.dsp.AdmHoaScreenReferencePolicy.render_unchanged,
        },
    );
    try std.testing.expect(screen_matrix.screen_reference);
    const screen_decoder =
        try screen_matrix.decoder(&screen_blocks);
    try std.testing.expect(screen_decoder.screen_reference);
    var screen_radial = try Radial.init(
        &screen_blocks,
        .{
            .sample_rate = 48_000.0,
            .loudspeaker_distance = 2.0,
            .screen_reference_policy = .render_unchanged,
        },
    );
    try screen_radial.process(
        &band_inputs,
        &.{ &radial_first, &radial_second },
    );
    screen_radial.config.screen_reference_policy = .reject;
    const invalid_screen_radial_before = screen_radial;
    const radial_first_before = radial_first;
    const radial_second_before = radial_second;
    try std.testing.expect(!screen_radial.valid());
    try std.testing.expectError(
        error.InvalidAdmHoaRadialState,
        screen_radial.process(
            &band_inputs,
            &.{ &radial_first, &radial_second },
        ),
    );
    try std.testing.expectEqualDeep(
        invalid_screen_radial_before,
        screen_radial,
    );
    try std.testing.expectEqualSlices(
        f32,
        &radial_first_before,
        &radial_first,
    );
    try std.testing.expectEqualSlices(
        f32,
        &radial_second_before,
        &radial_second,
    );
}

test "installed package renders bounded HRTF responses" {
    const directions = [_]plugin.dsp.HrtfDirection{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
    };
    const Database = plugin.dsp.HrtfDatabase(1, 8);
    var database = try Database.init(
        48_000,
        &directions,
        &.{
            1.0, 0.5,
            0.0, 0.0,
            0.0, 0.0,
            0.0, 0.0,
            0.0, 0.0,
            0.0, 0.0,
            0.0, 0.0,
            0.0, 0.0,
        },
    );
    const database_before = database;
    const retained_response = @as(
        [*]f32,
        @ptrCast(&database.responses),
    )[0 .. database.frame_count * 2];
    try std.testing.expectError(
        error.OverlappingHrtfInterpolationStorage,
        database.interpolate(
            directions[0],
            plugin.dsp.HrtfInterpolation.nearest,
            retained_response,
        ),
    );
    try std.testing.expectEqualDeep(database_before, database);
    const Renderer = plugin.dsp.HrtfRenderer(16, 8);
    var renderer = try Renderer.init(
        48_000,
        plugin.dsp.ConvolutionLatencyMode.zero,
    );
    try std.testing.expect(renderer.valid());
    try renderer.prepare(
        &database,
        directions[0],
        plugin.dsp.HrtfInterpolation.nearest,
        1,
    );
    try std.testing.expect(renderer.valid());
    try std.testing.expect(renderer.adoptPending());
    try std.testing.expect(renderer.valid());
    const output = renderer.processSample(1.0);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        output[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        output[1],
        0.000_001,
    );
    try std.testing.expect(renderer.valid());
    renderer.convolver.input_fill = Renderer.latency_capacity;
    try std.testing.expect(!renderer.valid());
    try std.testing.expectEqual(
        @as([2]f32, .{ 0.0, 0.0 }),
        renderer.processSample(1.0),
    );
    renderer.reset();
    try std.testing.expect(renderer.valid());

    const RoomComposer = plugin.dsp.HrtfRoomResponseComposer(16, 2);
    var room_composer = RoomComposer{};
    try std.testing.expectEqual(
        @as(usize, 7),
        plugin.dsp.maximum_first_order_hrtf_room_paths,
    );
    try std.testing.expectEqual(
        @as(usize, 25),
        plugin.dsp.maximum_second_order_hrtf_room_paths,
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        plugin.dsp.maximum_supported_hrtf_room_reflection_order,
    );
    try std.testing.expectEqual(
        @as(usize, 63),
        plugin.dsp.hrtfRoomPathCapacityForOrder(3),
    );
    const planned_room = plugin.dsp.HrtfShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 0.02, .y = 0.02, .z = 0.02 },
        .absorption = plugin.dsp.HrtfRoomSurfaceAbsorption{
            .maximum_x = 0.75,
        },
    };
    const room_plan = try plugin.dsp.HrtfFirstOrderRoomPathPlan.init(
        planned_room,
        48_000,
        343.0,
        .{ .x = 0.014, .y = 0.01, .z = 0.01 },
        .{
            .position = .{ .x = 0.01, .y = 0.01, .z = 0.01 },
        },
    );
    const planned_paths = try room_plan.items();
    try std.testing.expectEqual(@as(usize, 2), planned_paths.len);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.125),
        planned_paths[1].gain,
        1.0e-12,
    );
    var shortened_room_plan = room_plan;
    shortened_room_plan.path_count -= 1;
    try std.testing.expect(!shortened_room_plan.valid());
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        shortened_room_plan.items(),
    );
    const RoomMoving = plugin.dsp.HrtfMotionRenderer(16, 1, 4);
    var room_moving = RoomMoving{};
    try room_moving.prepareRoom(
        &database,
        planned_room,
        343.0,
        &.{.{
            .sample_position = 0,
            .source_position = .{ .x = 0.014, .y = 0.01, .z = 0.01 },
            .head_pose = .{
                .position = .{ .x = 0.01, .y = 0.01, .z = 0.01 },
            },
        }},
        .nearest,
        4,
    );
    try std.testing.expect(room_moving.currentDirection() != null);
    const second_order_plan =
        try plugin.dsp.HrtfSecondOrderRoomPathPlan.init(
            planned_room,
            48_000,
            343.0,
            .{ .x = 0.014, .y = 0.01, .z = 0.01 },
            .{
                .position = .{ .x = 0.01, .y = 0.01, .z = 0.01 },
            },
        );
    try std.testing.expect(
        (try second_order_plan.items()).len >= planned_paths.len,
    );
    var shortened_second_order_plan = second_order_plan;
    shortened_second_order_plan.path_count -= 1;
    try std.testing.expect(!shortened_second_order_plan.valid());
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        shortened_second_order_plan.items(),
    );
    try room_moving.prepareSecondOrderRoom(
        &database,
        planned_room,
        343.0,
        &.{.{
            .sample_position = 0,
            .source_position = .{ .x = 0.014, .y = 0.01, .z = 0.01 },
            .head_pose = .{
                .position = .{ .x = 0.01, .y = 0.01, .z = 0.01 },
            },
        }},
        .nearest,
        4,
    );
    const ThirdOrder = plugin.dsp.HrtfImageSourceRoomPathPlan(3);
    const third_order_plan = try ThirdOrder.init(
        planned_room,
        48_000,
        343.0,
        .{ .x = 0.014, .y = 0.01, .z = 0.01 },
        .{
            .position = .{ .x = 0.01, .y = 0.01, .z = 0.01 },
        },
    );
    try std.testing.expect(
        (try third_order_plan.items()).len >= planned_paths.len,
    );
    var shortened_third_order_plan = third_order_plan;
    shortened_third_order_plan.path_count -= 1;
    try std.testing.expect(!shortened_third_order_plan.valid());
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        shortened_third_order_plan.imageIndices(),
    );
    try room_moving.prepareImageSourceRoom(
        3,
        &database,
        planned_room,
        343.0,
        &.{.{
            .sample_position = 0,
            .source_position = .{ .x = 0.014, .y = 0.01, .z = 0.01 },
            .head_pose = .{
                .position = .{ .x = 0.01, .y = 0.01, .z = 0.01 },
            },
        }},
        .nearest,
        4,
    );
    const SurfaceResponses =
        plugin.dsp.HrtfRoomSurfaceImpulseResponses(2);
    const delta = [_]f32{1.0};
    const surface_responses = try SurfaceResponses.init(48_000, .{
        .minimum_x = &delta,
        .maximum_x = &.{ 0.5, 0.5 },
        .minimum_y = &delta,
        .maximum_y = &delta,
        .minimum_z = &delta,
        .maximum_z = &delta,
    });
    const material_plan = try plugin.dsp.HrtfImageSourceRoomPathPlan(1).init(
        planned_room,
        48_000,
        343.0,
        .{ .x = 0.014, .y = 0.01, .z = 0.01 },
        .{
            .position = .{ .x = 0.01, .y = 0.01, .z = 0.01 },
        },
    );
    const MaterialComposer =
        plugin.dsp.HrtfFrequencyDependentRoomResponseComposer(16, 1, 2);
    var material_composer = MaterialComposer{};
    var material_response: [32]f32 = undefined;
    try std.testing.expect((try material_composer.compose(
        &database,
        &material_plan,
        &surface_responses,
        .nearest,
        &material_response,
    )) > database.frame_count);
    var shortened_surface_responses = surface_responses;
    shortened_surface_responses.frame_counts[1] -= 1;
    material_response = @splat(17.0);
    const retained_material_response = material_response;
    try std.testing.expect(!shortened_surface_responses.valid());
    try std.testing.expectError(
        error.InvalidHrtfRoomSurfaceResponseState,
        material_composer.compose(
            &database,
            &material_plan,
            &shortened_surface_responses,
            .nearest,
            &material_response,
        ),
    );
    try std.testing.expectEqualDeep(
        retained_material_response,
        material_response,
    );
    shortened_surface_responses = surface_responses;
    shortened_surface_responses.sample_rate = 96_000;
    try std.testing.expect(!shortened_surface_responses.valid());
    try room_moving.prepareFrequencyDependentImageSourceRoom(
        1,
        2,
        &database,
        planned_room,
        &surface_responses,
        343.0,
        &.{.{
            .sample_position = 0,
            .source_position = .{ .x = 0.014, .y = 0.01, .z = 0.01 },
            .head_pose = .{
                .position = .{ .x = 0.01, .y = 0.01, .z = 0.01 },
            },
        }},
        .nearest,
        4,
    );
    const room_path = plugin.dsp.HrtfRoomPath{
        .direction = directions[0],
        .gain = 0.5,
        .additional_delay_samples = 0.5,
    };
    try std.testing.expectError(
        error.OverlappingHrtfRoomResponseStorage,
        room_composer.compose(
            &database,
            &.{.{ .direction = directions[0] }},
            .nearest,
            retained_response,
        ),
    );
    try std.testing.expectEqualDeep(database_before, database);
    var room_response: [32]f32 = undefined;
    const room_frames = try room_composer.compose(
        &database,
        &.{room_path},
        .delay_aligned,
        &room_response,
    );
    try std.testing.expectEqual(@as(usize, 9), room_frames);
    try renderer.prepareInterleavedResponse(
        48_000,
        room_response[0 .. room_frames * 2],
        2,
    );
    try std.testing.expect(renderer.adoptPending());
    const room_output = renderer.processSample(1.0);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        room_output[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.125),
        room_output[1],
        0.000_001,
    );

    const MotionRenderer = plugin.dsp.HrtfMotionRenderer(8, 1, 4);
    var moving = MotionRenderer{};
    try std.testing.expect(moving.valid());
    const points = [_]plugin.dsp.HrtfMotionPoint{.{
        .sample_position = 0,
        .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
        .head_pose = .{
            .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        },
    }};
    try moving.prepare(
        &database,
        &points,
        plugin.dsp.HrtfInterpolation.delay_aligned,
        4,
    );
    try std.testing.expect(moving.valid());
    try std.testing.expectEqual(
        directions[0],
        moving.currentDirection().?,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 0.5 },
        moving.processSample(1.0),
    );
    try std.testing.expect(moving.valid());
    var hostile_moving = moving;
    hostile_moving.history_write = hostile_moving.frame_count;
    try std.testing.expect(!hostile_moving.valid());
    const hostile_moving_sample = hostile_moving.sample_position;
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0 },
        hostile_moving.processSample(1.0),
    );
    try std.testing.expectEqual(
        hostile_moving_sample,
        hostile_moving.sample_position,
    );

    const ScheduledRenderer = plugin.dsp.HrtfMotionRenderer(8, 2, 4);
    var scheduled = ScheduledRenderer{};
    var scheduled_points = [_]plugin.dsp.HrtfMotionPoint{
        points[0],
        points[0],
    };
    scheduled_points[1].sample_position = 4;
    try scheduled.prepare(
        &database,
        &scheduled_points,
        plugin.dsp.HrtfInterpolation.delay_aligned,
        4,
    );
    var truncated_schedule = scheduled;
    truncated_schedule.point_count = 1;
    try std.testing.expect(!truncated_schedule.valid());
    const truncated_history = truncated_schedule.history;
    const truncated_sample = truncated_schedule.sample_position;
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0 },
        truncated_schedule.processSample(1.0),
    );
    try std.testing.expectEqualDeep(
        truncated_history,
        truncated_schedule.history,
    );
    try std.testing.expectEqual(
        truncated_sample,
        truncated_schedule.sample_position,
    );
    var early_schedule = scheduled;
    early_schedule.current_point = 1;
    early_schedule.sample_position = 3;
    try std.testing.expect(!early_schedule.valid());
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0 },
        early_schedule.processSample(1.0),
    );
    var overdue_schedule = scheduled;
    overdue_schedule.sample_position = 8;
    try std.testing.expect(!overdue_schedule.valid());
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0 },
        overdue_schedule.processSample(1.0),
    );
    scheduled_points[1].sample_position = std.math.maxInt(u64) - 1;
    try std.testing.expectError(
        error.InvalidHrtfMotionSchedule,
        scheduled.prepare(
            &database,
            &scheduled_points,
            plugin.dsp.HrtfInterpolation.delay_aligned,
            4,
        ),
    );

    const MotionQueue = plugin.dsp.HrtfMotionPointQueue(2);
    var motion_queue = MotionQueue{};
    try std.testing.expect(motion_queue.valid());
    for (motion_queue.points) |point|
        try std.testing.expectEqualDeep(plugin.dsp.HrtfMotionPoint{}, point);
    const ClockCalibrator = plugin.dsp.HrtfMotionClockCalibrator(3);
    var clock_calibrator = ClockCalibrator{};
    try std.testing.expect(clock_calibrator.valid());
    var calibrated_clock: ?plugin.dsp.HrtfMotionClock = null;
    for ([_]plugin.dsp.HrtfMotionClockObservation{
        .{ .tracker_timestamp = 4_000_000_000, .sample_position = 0 },
        .{ .tracker_timestamp = 4_500_000_000, .sample_position = 24_000 },
        .{ .tracker_timestamp = 5_000_000_000, .sample_position = 48_000 },
    }) |observation| {
        calibrated_clock = try clock_calibrator.observeAndCalibrate(
            observation,
            48_000,
            100,
        );
        try std.testing.expect(clock_calibrator.valid());
    }
    var motion_clock = calibrated_clock orelse
        return error.MissingHrtfMotionClockCalibration;
    try std.testing.expect(motion_clock.valid());
    try std.testing.expect(try motion_queue.submitTracked(
        &motion_clock,
        5_000_000_000,
        points[0].source_position,
        points[0].head_pose,
    ));
    try std.testing.expect(motion_queue.valid());
    try std.testing.expect(motion_clock.valid());
    var tracked_point = points[0];
    tracked_point.sample_position = 48_000;
    const motion_read_before = motion_queue.read_index.load(.acquire);
    motion_queue.points[0].source_position =
        motion_queue.points[0].head_pose.position;
    try std.testing.expect(!motion_queue.valid());
    try std.testing.expectError(
        error.InvalidHrtfMotionQueueState,
        motion_queue.receive(),
    );
    try std.testing.expectEqual(
        motion_read_before,
        motion_queue.read_index.load(.acquire),
    );
    try std.testing.expectEqual(@as(usize, 1), try motion_queue.pending());
    motion_queue.points[0] = tracked_point;
    try std.testing.expect(motion_queue.valid());
    var later_tracked_point = tracked_point;
    later_tracked_point.sample_position += 1;
    try std.testing.expect(try motion_queue.submit(later_tracked_point));
    motion_queue.points[0].sample_position =
        later_tracked_point.sample_position;
    try std.testing.expect(!motion_queue.valid());
    try std.testing.expectError(
        error.InvalidHrtfMotionQueueState,
        motion_queue.receive(),
    );
    try std.testing.expectEqual(
        motion_read_before,
        motion_queue.read_index.load(.acquire),
    );
    try std.testing.expectEqual(@as(usize, 2), try motion_queue.pending());
    motion_queue.points[0] = tracked_point;
    try std.testing.expect(motion_queue.valid());
    try std.testing.expectEqual(
        tracked_point,
        (try motion_queue.receive()).?,
    );
    try std.testing.expectEqual(
        later_tracked_point,
        (try motion_queue.receive()).?,
    );
    try std.testing.expectEqual(@as(usize, 0), try motion_queue.pending());
    try std.testing.expect(motion_queue.valid());
    motion_queue.reset();
    for (motion_queue.points) |point|
        try std.testing.expectEqualDeep(plugin.dsp.HrtfMotionPoint{}, point);

    var hostile_motion_clock = motion_clock;
    hostile_motion_clock.has_mapped_timestamp = false;
    try std.testing.expect(!hostile_motion_clock.valid());
    const hostile_clock_before = hostile_motion_clock;
    try std.testing.expectError(
        error.InvalidHrtfMotionClockState,
        hostile_motion_clock.map(5_500_000_000),
    );
    try std.testing.expectEqual(hostile_clock_before, hostile_motion_clock);

    const StreamingMotion =
        plugin.dsp.HrtfStreamingMotionRenderer(8, 2, 4);
    var streaming_motion = try StreamingMotion.init(0, 2);
    try std.testing.expect(streaming_motion.valid());
    for (streaming_motion.slots) |slot|
        try std.testing.expectEqualDeep(@TypeOf(slot){}, slot);
    try std.testing.expect(try streaming_motion.prepare(
        &database,
        points[0],
        .delay_aligned,
    ));
    try std.testing.expect(streaming_motion.valid());
    streaming_motion.slots[0].frame_count -= 1;
    const truncated_streaming_history = streaming_motion.history;
    const truncated_streaming_sample = streaming_motion.sample_position;
    try std.testing.expect(!streaming_motion.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        streaming_motion.processSample(1.0),
    );
    try std.testing.expectEqualDeep(
        truncated_streaming_history,
        streaming_motion.history,
    );
    try std.testing.expectEqual(
        truncated_streaming_sample,
        streaming_motion.sample_position,
    );
    streaming_motion.slots[0].frame_count =
        streaming_motion.slots[0].declared_frame_count;
    try std.testing.expect(streaming_motion.valid());
    const streaming_output = try streaming_motion.processSample(1.0);
    try std.testing.expectEqualDeep(
        [_]f32{ 0.5, 0.25 },
        streaming_output,
    );
    try std.testing.expect(streaming_motion.valid());
    streaming_motion.history[0] = std.math.nan(f32);
    try std.testing.expect(!streaming_motion.valid());
    streaming_motion.reset(0);
    try std.testing.expect(streaming_motion.valid());
    for (streaming_motion.slots) |slot|
        try std.testing.expectEqualDeep(@TypeOf(slot){}, slot);
    var unfinishable_streaming_point = points[0];
    unfinishable_streaming_point.sample_position =
        std.math.maxInt(u64) - 1;
    try std.testing.expectError(
        error.InvalidHrtfMotionSchedule,
        streaming_motion.prepare(
            &database,
            unfinishable_streaming_point,
            .delay_aligned,
        ),
    );
    try std.testing.expect(streaming_motion.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        try streaming_motion.preparedCount(),
    );
    try std.testing.expect(try streaming_motion.prepare(
        &database,
        points[0],
        .delay_aligned,
    ));
    streaming_motion.sample_position = std.math.maxInt(u64) - 1;
    const late_streaming_history = streaming_motion.history;
    try std.testing.expect(!streaming_motion.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        streaming_motion.processSample(1.0),
    );
    try std.testing.expectEqualDeep(
        late_streaming_history,
        streaming_motion.history,
    );
    try std.testing.expectEqual(
        std.math.maxInt(u64) - 1,
        streaming_motion.sample_position,
    );
    streaming_motion.reset(0);
    try std.testing.expect(try streaming_motion.prepare(
        &database,
        points[0],
        .delay_aligned,
    ));
    var dense_streaming_point = points[0];
    dense_streaming_point.sample_position = 2;
    try std.testing.expect(try streaming_motion.prepare(
        &database,
        dense_streaming_point,
        .delay_aligned,
    ));
    streaming_motion.slots[1].point.sample_position = 1;
    streaming_motion.last_submitted_sample = 1;
    const dense_streaming_history = streaming_motion.history;
    try std.testing.expect(!streaming_motion.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        streaming_motion.processSample(1.0),
    );
    try std.testing.expectEqualDeep(
        dense_streaming_history,
        streaming_motion.history,
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        streaming_motion.sample_position,
    );

    const NearDatabase = plugin.dsp.HrtfDatabase(2, 1);
    const near_database = try NearDatabase.initWithDistances(
        48_000,
        &.{ .{}, .{} },
        &.{ 0.5, 1.5 },
        &.{ 0.25, 0.5, 0.75, 1.0 },
    );
    const measured = try plugin.dsp.hrtfMeasurementFromPositions(
        .{ .x = 1.5 },
        .{},
    );
    var near_response: [2]f32 = undefined;
    try near_database.interpolateAt(
        measured,
        plugin.dsp.HrtfInterpolation.nearest,
        &near_response,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 0.75, 1.0 },
        near_response,
    );
    var malformed_near_database = near_database;
    malformed_near_database.measurement_count = 1;
    near_response = @splat(7.0);
    try std.testing.expectError(
        error.InvalidHrtfDatabase,
        malformed_near_database.interpolateAt(
            measured,
            plugin.dsp.HrtfInterpolation.nearest,
            &near_response,
        ),
    );
    try std.testing.expectEqualDeep([_]f32{ 7.0, 7.0 }, near_response);

    const decoded = plugin.dsp.hrtf_sofa.DecodedDataset{
        .measurement_count = 1,
        .response_frame_count = 1,
        .sampling_rates = &.{48_000.0},
        .source_positions = &.{ 0.0, 0.0, 1.0 },
        .position_encoding = .cartesian_metres,
        .responses_measurement_ear_frame = &.{ 1.0, 0.5 },
    };
    const decoded_database =
        try plugin.dsp.hrtf_sofa.databaseFromDecoded(
            1,
            1,
            std.testing.allocator,
            decoded,
        );
    try std.testing.expect(decoded_database.valid());
    try std.testing.expectEqual(
        @as(f64, 1.0),
        decoded_database.distances_metres[0],
    );
    var decoded_into: plugin.dsp.HrtfDatabase(1, 1) = undefined;
    try plugin.dsp.hrtf_sofa.databaseFromDecodedInto(
        1,
        1,
        std.testing.allocator,
        decoded,
        &decoded_into,
    );
    try std.testing.expectEqualDeep(decoded_database, decoded_into);

    const SofaLoader = plugin.dsp.HrtfSofaLoader(1, 1);
    const sofa_limits: plugin.dsp.HrtfSofaLimits =
        plugin.dsp.default_hrtf_sofa_limits;
    try sofa_limits.validate();
    try std.testing.expect(@hasDecl(SofaLoader, "isOpen"));
    try std.testing.expect(@hasDecl(SofaLoader, "openRuntime"));
    try std.testing.expect(@hasDecl(SofaLoader, "loadFileWithLimits"));
    try std.testing.expect(@hasDecl(
        SofaLoader,
        "loadFileIntoWithLimits",
    ));
}

test "installed package owns and decomposes runtime-shaped matrices" {
    const Matrix = plugin.dsp.DynamicMatrix(f64);
    var first = try Matrix.fromSlice(
        std.testing.allocator,
        2,
        3,
        &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 },
    );
    defer first.deinit();
    var second = try Matrix.fromSlice(
        std.testing.allocator,
        3,
        1,
        &.{ 1.0, 0.0, -1.0 },
    );
    defer second.deinit();
    var product = try first.multiply(
        &second,
        std.testing.allocator,
    );
    defer product.deinit();
    try std.testing.expectEqualDeep(
        [_]f64{ -2.0, -2.0 },
        product.values[0..2].*,
    );
    const vector_product = try first.multiplyVector(
        &.{ 1.0, 0.0, -1.0 },
        std.testing.allocator,
    );
    defer std.testing.allocator.free(vector_product);
    try std.testing.expectEqualDeep(
        [_]f64{ -2.0, -2.0 },
        vector_product[0..2].*,
    );
    var vector_destination: [2]f64 = undefined;
    var vector_workspace: [2]f64 = undefined;
    try first.multiplyVectorInto(
        &.{ 1.0, 0.0, -1.0 },
        &vector_destination,
        &vector_workspace,
    );
    try std.testing.expectEqualDeep(
        [_]f64{ -2.0, -2.0 },
        vector_destination,
    );
    const retained_values = first.values[0..6].*;
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        first.multiplyVectorInto(
            &.{ 1.0, 0.0, -1.0 },
            first.values[0..2],
            &vector_workspace,
        ),
    );
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        first.multiplyVectorInto(
            &.{ 1.0, 0.0, -1.0 },
            &vector_destination,
            first.values[0..2],
        ),
    );
    try std.testing.expectEqualDeep(
        retained_values,
        first.values[0..6].*,
    );

    var arithmetic = try Matrix.init(std.testing.allocator, 2, 3);
    defer arithmetic.deinit();
    var arithmetic_workspace: [6]f64 = undefined;
    try first.addInto(&first, &arithmetic, &arithmetic_workspace);
    try first.subtractInto(
        &first,
        &arithmetic,
        &arithmetic_workspace,
    );
    try first.scaledInto(
        0.5,
        &arithmetic,
        &arithmetic_workspace,
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 0.5, 1.0, 1.5, 2.0, 2.5, 3.0 },
        arithmetic.values[0..6].*,
    );
    var transposed = try Matrix.init(std.testing.allocator, 3, 2);
    defer transposed.deinit();
    try first.transposeInto(&transposed, &arithmetic_workspace);
    try std.testing.expectEqualDeep(
        [_]f64{ 1.0, 4.0, 2.0, 5.0, 3.0, 6.0 },
        transposed.values[0..6].*,
    );
    var buffered_product = try Matrix.init(std.testing.allocator, 2, 1);
    defer buffered_product.deinit();
    try first.multiplyInto(
        &second,
        &buffered_product,
        &vector_workspace,
    );
    try std.testing.expectEqualDeep(
        [_]f64{ -2.0, -2.0 },
        buffered_product.values[0..2].*,
    );

    var square = try Matrix.fromSlice(
        std.testing.allocator,
        2,
        2,
        &.{ 3.0, 1.0, 1.0, 2.0 },
    );
    defer square.deinit();
    var lu: plugin.dsp.DynamicLuDecomposition(f64) =
        try square.decomposeLu(std.testing.allocator);
    defer lu.deinit();
    const solved = try lu.solve(
        std.testing.allocator,
        &.{ 7.0, 5.0 },
    );
    defer std.testing.allocator.free(solved);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.8),
        solved[0],
        0.000_000_000_001,
    );
    var lu_workspace: [2]f64 = undefined;
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        lu.solveInto(
            &.{ 7.0, 5.0 },
            lu.factors[0..2],
            &lu_workspace,
        ),
    );
    try std.testing.expect(lu.valid());
    lu.odd_swaps = !lu.odd_swaps;
    try std.testing.expect(!lu.valid());
    try std.testing.expectError(
        error.InvalidDynamicLuDecomposition,
        lu.determinant(),
    );
    lu.odd_swaps = !lu.odd_swaps;
    try std.testing.expect(lu.valid());
    const retained_lu_matrix_scale = lu.matrix_scale;
    lu.matrix_scale *= 2.0;
    try std.testing.expect(!lu.valid());
    try std.testing.expectError(
        error.InvalidDynamicLuDecomposition,
        lu.determinant(),
    );
    lu.matrix_scale = retained_lu_matrix_scale;
    try std.testing.expect(lu.valid());

    var tiny_square = try Matrix.fromSlice(
        std.testing.allocator,
        2,
        2,
        &.{ 1.0e-200, 0.0, 0.0, 2.0e-200 },
    );
    defer tiny_square.deinit();
    var tiny_lu = try tiny_square.decomposeLu(std.testing.allocator);
    defer tiny_lu.deinit();
    const tiny_lu_solution = try tiny_lu.solve(
        std.testing.allocator,
        &.{ 3.0e-200, -8.0e-200 },
    );
    defer std.testing.allocator.free(tiny_lu_solution);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        tiny_lu_solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -4.0),
        tiny_lu_solution[1],
        0.000_000_000_001,
    );

    var qr: plugin.dsp.DynamicQrDecomposition(f64) =
        try second.decomposeQr(std.testing.allocator);
    defer qr.deinit();
    const fitted = try qr.solveLeastSquares(
        std.testing.allocator,
        &.{ 1.0, 0.0, -1.0 },
    );
    defer std.testing.allocator.free(fitted);
    try std.testing.expectEqual(@as(usize, 1), fitted.len);
    var qr_workspace: [3]f64 = undefined;
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        qr.solveLeastSquaresInto(
            &.{ 1.0, 0.0, -1.0 },
            qr.tau,
            &qr_workspace,
        ),
    );
    try std.testing.expect(qr.valid());
    const retained_qr_tau = qr.tau[0];
    qr.tau[0] *= 0.5;
    var rejected_qr_destination = [_]f64{73.0};
    var rejected_qr_workspace = [_]f64{ 79.0, 83.0, 89.0 };
    const expected_qr_destination = rejected_qr_destination;
    const expected_qr_workspace = rejected_qr_workspace;
    try std.testing.expect(!qr.valid());
    try std.testing.expectError(
        error.InvalidDynamicQrDecomposition,
        qr.solveLeastSquaresInto(
            &.{ 1.0, 0.0, -1.0 },
            &rejected_qr_destination,
            &rejected_qr_workspace,
        ),
    );
    try std.testing.expectEqualDeep(
        expected_qr_destination,
        rejected_qr_destination,
    );
    try std.testing.expectEqualDeep(
        expected_qr_workspace,
        rejected_qr_workspace,
    );
    qr.tau[0] = retained_qr_tau;
    try std.testing.expect(qr.valid());
    const retained_qr_matrix_scale = qr.matrix_scale;
    qr.matrix_scale *= 2.0;
    try std.testing.expect(!qr.valid());
    try std.testing.expectError(
        error.InvalidDynamicQrDecomposition,
        qr.solveLeastSquaresInto(
            &.{ 1.0, 0.0, -1.0 },
            &rejected_qr_destination,
            &rejected_qr_workspace,
        ),
    );
    try std.testing.expectEqualDeep(
        expected_qr_destination,
        rejected_qr_destination,
    );
    try std.testing.expectEqualDeep(
        expected_qr_workspace,
        rejected_qr_workspace,
    );
    qr.matrix_scale = retained_qr_matrix_scale;
    try std.testing.expect(qr.valid());

    var tiny_tall = try Matrix.fromSlice(
        std.testing.allocator,
        3,
        2,
        &.{
            1.0e-200, 0.0,
            0.0,      2.0e-200,
            1.0e-200, 2.0e-200,
        },
    );
    defer tiny_tall.deinit();
    var tiny_qr = try tiny_tall.decomposeQr(std.testing.allocator);
    defer tiny_qr.deinit();
    const tiny_qr_solution = try tiny_qr.solveLeastSquares(
        std.testing.allocator,
        &.{ 3.0e-200, -8.0e-200, -5.0e-200 },
    );
    defer std.testing.allocator.free(tiny_qr_solution);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        tiny_qr_solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -4.0),
        tiny_qr_solution[1],
        0.000_000_000_001,
    );
    var tiny_svd = try tiny_tall.decomposeSvd(
        std.testing.allocator,
        .{},
    );
    defer tiny_svd.deinit();
    const tiny_svd_solution = try tiny_svd.solveLeastSquares(
        std.testing.allocator,
        &.{ 3.0e-200, -8.0e-200, -5.0e-200 },
    );
    defer std.testing.allocator.free(tiny_svd_solution);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        tiny_svd_solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -4.0),
        tiny_svd_solution[1],
        0.000_000_000_001,
    );

    var svd: plugin.dsp.DynamicSvdDecomposition(f64) =
        try first.decomposeSvd(std.testing.allocator, .{});
    defer svd.deinit();
    var pseudoinverse = try svd.pseudoinverse(
        std.testing.allocator,
    );
    defer pseudoinverse.deinit();
    try std.testing.expect(pseudoinverse.valid());
    var svd_destination: [3]f64 = undefined;
    var svd_solution_workspace: [3]f64 = undefined;
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        svd.solveLeastSquaresInto(
            &.{ 1.0, -1.0 },
            &svd_destination,
            svd.singular_values,
            &svd_solution_workspace,
        ),
    );
    try std.testing.expect(svd.valid());
    const retained_svd_maximum_sweeps = svd.maximum_sweeps;
    svd.maximum_sweeps = 0;
    try std.testing.expect(!svd.valid());
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        svd.conditionNumber(),
    );
    svd.maximum_sweeps = retained_svd_maximum_sweeps;
    try std.testing.expect(svd.valid());
    const retained_svd_left_column = [_]f64{
        svd.left[0],
        svd.left[2],
    };
    svd.left[0] *= 0.5;
    svd.left[2] *= 0.5;
    var rejected_svd_destination = [_]f64{ 97.0, 101.0, 103.0 };
    var rejected_svd_projection = [_]f64{ 107.0, 109.0 };
    var rejected_svd_solution = [_]f64{ 113.0, 127.0, 131.0 };
    const expected_svd_destination = rejected_svd_destination;
    const expected_svd_projection = rejected_svd_projection;
    const expected_svd_solution = rejected_svd_solution;
    try std.testing.expect(!svd.valid());
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        svd.solveLeastSquaresInto(
            &.{ 1.0, -1.0 },
            &rejected_svd_destination,
            &rejected_svd_projection,
            &rejected_svd_solution,
        ),
    );
    try std.testing.expectEqualDeep(
        expected_svd_destination,
        rejected_svd_destination,
    );
    try std.testing.expectEqualDeep(
        expected_svd_projection,
        rejected_svd_projection,
    );
    try std.testing.expectEqualDeep(
        expected_svd_solution,
        rejected_svd_solution,
    );
    svd.left[0] = retained_svd_left_column[0];
    svd.left[2] = retained_svd_left_column[1];
    try std.testing.expect(svd.valid());
    const retained_svd_second_left_column = [_]f64{
        svd.left[1],
        svd.left[3],
    };
    svd.left[1] = svd.left[0];
    svd.left[3] = svd.left[2];
    try std.testing.expect(!svd.valid());
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        svd.conditionNumber(),
    );
    svd.left[1] = retained_svd_second_left_column[0];
    svd.left[3] = retained_svd_second_left_column[1];
    try std.testing.expect(svd.valid());

    first.rows = std.math.maxInt(usize);
    try std.testing.expect(!first.valid());
    try std.testing.expectError(
        error.InvalidDynamicMatrix,
        first.clone(std.testing.allocator),
    );
    first.rows = 2;
    lu.dimensions = std.math.maxInt(usize);
    try std.testing.expect(!lu.valid());
    try std.testing.expectError(
        error.InvalidDynamicLuDecomposition,
        lu.determinant(),
    );
    lu.dimensions = 2;
    qr.rows = std.math.maxInt(usize);
    try std.testing.expect(!qr.valid());
    try std.testing.expectError(
        error.InvalidDynamicQrDecomposition,
        qr.upper(std.testing.allocator),
    );
    qr.rows = 3;
    svd.rows = std.math.maxInt(usize);
    try std.testing.expect(!svd.valid());
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        svd.conditionNumber(),
    );
    svd.rows = 2;

    first.deinit();
    first.deinit();
    lu.deinit();
    lu.deinit();
    qr.deinit();
    qr.deinit();
    svd.deinit();
    svd.deinit();
    try std.testing.expect(!first.valid());
    try std.testing.expect(!lu.valid());
    try std.testing.expect(!qr.valid());
    try std.testing.expect(!svd.valid());
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
    var timeline =
        try plugin.dsp.AdmBinauralStereoGainTimeline(f32, 3).init(
            &sequences,
            4,
        );
    for (timeline.segments) |ear_segments| {
        const spare = ear_segments[2];
        try std.testing.expectEqual(@as(u64, 0), spare.first_sample);
        try std.testing.expectEqual(
            @as(u128, 1),
            spare.start_position.denominator,
        );
        try std.testing.expectEqual(@as(f32, 0.0), spare.target_gain);
    }
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
    timeline.segment_counts[0] -= 1;
    left = @splat(7.0);
    right = @splat(7.0);
    try std.testing.expectError(
        error.InvalidAdmBinauralTimelineState,
        timeline.process(0, &inputs, &outputs),
    );
    try std.testing.expectEqualDeep(@as([input.len]f32, @splat(7.0)), left);
    try std.testing.expectEqualDeep(@as([input.len]f32, @splat(7.0)), right);
}
