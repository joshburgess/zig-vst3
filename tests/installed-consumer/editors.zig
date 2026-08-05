const builtin = @import("builtin");
const std = @import("std");
const vst3 = @import("zig-vst3");
const plugin = @import("zig-vst3-plugin");

const ui = vst3.vstgui;

test "installed consumer exposes the standalone Linux run loop" {
    try std.testing.expect(
        @hasDecl(vst3.vst_linux_run_loop, "StandaloneDriver"),
    );
    var driver =
        vst3.vst_linux_run_loop.initStandaloneDriver(
            2,
            2,
            std.testing.io,
        );
    defer driver.deinit();
    try std.testing.expectEqual(
        &driver.run_loop.iface,
        driver.asInterface(),
    );
    if (builtin.os.tag != .linux) {
        try std.testing.expectError(
            error.UnsupportedPlatform,
            driver.pump(0),
        );
    }
}

test "installed VST3 adapter exposes optional payload forwarding" {
    const Receiver = struct {
        value: u8 = 29,

        pub fn importPath(_: *@This(), _: []const u8) bool {
            return true;
        }

        pub fn relink(_: *@This(), _: []const u8) bool {
            return true;
        }

        pub fn requestCancel(_: *@This()) bool {
            return true;
        }

        pub fn retry(_: *@This()) bool {
            return true;
        }
    };
    const Definition = struct {
        receiver: Receiver = .{},

        pub const name = "Installed Payload Forwarding";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};

        pub fn resourcePathReceiver(
            self: *@This(),
        ) *Receiver {
            return &self.receiver;
        }

        pub fn guiTelemetryLoad(
            _: *@This(),
            source_id: u32,
        ) f64 {
            return @floatFromInt(source_id);
        }
    };
    const Adapter = plugin.Vst3Processor(Definition);
    try std.testing.expect(Adapter.hasResourcePathReceiver);
    try std.testing.expect(!Adapter.hasAudioImportReceiver);
    try std.testing.expect(Adapter.hasGuiTelemetryLoad);
    try std.testing.expect(!Adapter.hasGuiGraphLoad);
    var adapter =
        try Adapter.initWithAllocator(std.testing.allocator);
    defer adapter.deinit();
    try std.testing.expectEqual(
        @as(u8, 29),
        adapter.resourcePathReceiver().value,
    );
    try std.testing.expectEqual(
        @as(f64, 31),
        adapter.guiTelemetryLoad(31),
    );

    const Configuration = struct {
        pub const component_name = "InstalledPayloadComponent";
        pub const controller_cid = vst3.tuid.inlineUid(
            0xCF60F231,
            0x299B4F93,
            0xB711A2ED,
            0xCD82C439,
        );
        pub const resource_path_target_id: u32 = 3;
    };
    const Effect = plugin.Vst3Effect(
        Definition,
        Configuration,
    );
    var component_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        vst3.pluginterfaces.base.types.kResultOk,
        Effect.create(
            @ptrCast(
                &vst3.pluginterfaces.vst.ivstcomponent
                    .icomponent_iid,
            ),
            &component_out,
        ),
    );
    const component: *vst3.pluginterfaces.vst.ivstcomponent.IComponent =
        @ptrCast(@alignCast(
            component_out orelse return error.MissingComponent,
        ));
    defer _ = component.vtable.release(component);

    const Controller = plugin.Vst3Controller(
        Definition,
        "InstalledPayloadController",
    );
    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        vst3.pluginterfaces.base.types.kResultOk,
        Controller.create(
            @ptrCast(
                &vst3.pluginterfaces.vst.ivsteditcontroller
                    .iedit_controller_iid,
            ),
            &controller_out,
        ),
    );
    const controller: *vst3.pluginterfaces.vst.ivsteditcontroller
        .IEditController =
        @ptrCast(@alignCast(
            controller_out orelse return error.MissingController,
        ));
    defer _ = controller.vtable.release(controller);
}

fn installedSquare(value: f32) f32 {
    return value * value;
}

const EffectParameters = struct {
    gain: plugin.parameters.FloatParam = .{
        .id = 0,
        .name = "Gain",
        .units = "dB",
        .min = -24.0,
        .max = 12.0,
        .default = 0.0,
    },
    bypass: plugin.parameters.BoolParam = .{
        .id = 1,
        .name = "Bypass",
        .default = false,
    },
};

const InstrumentParameters = struct {
    gain: plugin.parameters.FloatParam = .{
        .id = 0,
        .name = "Gain",
        .units = "dB",
        .min = -48.0,
        .max = 6.0,
        .default = 0.0,
    },
    pan: plugin.parameters.FloatParam = .{
        .id = 1,
        .name = "Pan",
        .min = -1.0,
        .max = 1.0,
        .default = 0.0,
    },
};

const InstalledPropertyDelegate = struct {
    pub fn getData(
        _: *InstalledPropertyDelegate,
        request: plugin.process.MidiCiPropertyHostRequest,
    ) !plugin.process.MidiCiPropertyHostReply {
        if (!std.mem.eql(u8, request.header.resource, "LocalState"))
            return .{ .header = .{ .status = .not_found } };
        return .{
            .header = .{ .status = .ok },
            .data = "{\"active\":true}",
        };
    }

    pub fn setData(
        _: *InstalledPropertyDelegate,
        _: plugin.process.MidiCiPropertyHostRequest,
    ) !plugin.process.MidiCiPropertyHostReply {
        return .{ .header = .{ .status = .not_allowed } };
    }

    pub fn subscriptionChanged(
        _: *InstalledPropertyDelegate,
        _: plugin.process.MidiCiPropertyHostSubscriptionRequest,
    ) !plugin.process.MidiCiPropertyHostReply {
        return .{ .header = .{ .status = .not_allowed } };
    }
};

const InstalledProfileDelegate = struct {
    requests: usize = 0,

    pub fn profileEnablementRequested(
        self: *InstalledProfileDelegate,
        _: plugin.process.MidiCiProfileSet,
    ) !bool {
        self.requests += 1;
        return true;
    }

    pub fn profileDetails(
        _: *InstalledProfileDelegate,
        _: plugin.process.MidiCiProfileDetailsInquiry,
    ) ![]const u8 {
        return &.{1};
    }

    pub fn profileSpecificData(
        _: *InstalledProfileDelegate,
        _: plugin.process.MidiCiProfileHostSpecificDataRequest,
    ) !void {}
};

const MonoEffect = struct {
    pub const name = "Installed Mono Effect";
    pub const vendor = "Example Audio";
    pub const audio_input_layout: plugin.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plugin.plugin.AudioBusLayout = .mono;
    pub const Params = EffectParameters;
};

const effect_editor: ui.EditorDescription = .{
    .parameters = &.{
        .{ .id = 0, .title = "Gain", .units = "dB", .step_count = 0, .default_normalized = 2.0 / 3.0, .control_kind = .decibel_slider },
        .{ .id = 1, .title = "Bypass", .step_count = 1, .default_normalized = 0.0, .control_kind = .toggle },
    },
    .graphs = &.{.{
        .title = "Transfer",
        .kind = .transfer_function,
        .x_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Input" },
        .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Output" },
        .points = &.{ .{ .x = -1.0, .y = -1.0 }, .{ .x = 0.0, .y = 0.0 }, .{ .x = 1.0, .y = 1.0 } },
    }},
    .skin = .{ .layout = .parameter_workspace },
    .composition = .{
        .title = "Installed Effect",
        .groups = &.{.{ .title = "Output", .parameter_count = 2, .graph_count = 1 }},
    },
};

const instrument_editor: ui.EditorDescription = .{
    .parameters = &.{
        .{ .id = 0, .title = "Gain", .units = "dB", .step_count = 0, .default_normalized = 8.0 / 9.0, .control_kind = .decibel_slider },
        .{ .id = 1, .title = "Pan", .step_count = 0, .default_normalized = 0.5, .control_kind = .bipolar_slider },
    },
    .graphs = &.{.{
        .title = "Sample",
        .kind = .waveform,
        .style = .modulation,
        .x_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Time" },
        .y_axis = .{ .minimum = -1.0, .maximum = 1.0, .label = "Level" },
        .source_id = 100,
        .source = .controller,
        .dynamic = true,
        .maximum_refresh_hz = 30,
    }},
    .file_importers = &.{.{
        .id = 1,
        .title = "Sample",
        .prompt = "Drop a WAV or AIFF sample here",
        .picker_label = "Choose Sample",
        .picker_title = "Choose a Sample",
        .extensions = &.{ ".wav", ".aif", ".aiff" },
        .maximum_files = 1,
    }},
    .pianos = &.{.{ .title = "Audition", .first_note = 48, .note_count = 25 }},
    .skin = .{ .layout = .instrument_workspace },
    .composition = .{
        .title = "Installed Instrument",
        .groups = &.{.{ .title = "Playback", .parameter_count = 2, .graph_count = 1 }},
    },
};

test "installed package builds effect and instrument editor declarations" {
    try std.testing.expectError(
        error.InvalidParameterRange,
        plugin.parameters.FloatParam.initChecked(
            99,
            "Overflowing span",
            -std.math.floatMax(f64),
            std.math.floatMax(f64),
            0.0,
        ),
    );
    const effect_set = plugin.parameters.ParameterSet(EffectParameters).init(.{});
    const instrument_set = plugin.parameters.ParameterSet(InstrumentParameters).init(.{});
    try std.testing.expectEqual(@as(usize, 2), @TypeOf(effect_set).count);
    try std.testing.expectEqual(@as(usize, 2), @TypeOf(instrument_set).count);
    try std.testing.expectEqual(@as(usize, 2), effect_editor.parameters.len);
    try std.testing.expectEqual(@as(usize, 1), effect_editor.graphs.len);
    try std.testing.expectEqual(@as(usize, 2), instrument_editor.parameters.len);
    try std.testing.expectEqual(@as(usize, 1), instrument_editor.file_importers.len);
    try std.testing.expectEqual(@as(usize, 1), instrument_editor.pianos.len);

    const mono_spec = plugin.plugin.PluginSpec(MonoEffect);
    try std.testing.expectEqual(plugin.plugin.AudioBusLayout.mono, mono_spec.audio_input_layout);
    try std.testing.expectEqual(@as(u8, 1), mono_spec.audio_output_layout.channelCount());
    try std.testing.expectEqual(@as(u8, 4), plugin.plugin.AudioBusLayout.quadraphonic.channelCount());
    try std.testing.expectEqual(@as(u8, 6), plugin.plugin.AudioBusLayout.surround_5_1.channelCount());
    try std.testing.expectEqual(@as(u8, 8), plugin.plugin.AudioBusLayout.surround_7_1.channelCount());
    try std.testing.expectEqual(@as(u8, 4), plugin.plugin.AudioBusLayout.ambisonic_first_order.channelCount());
    try std.testing.expectEqual(@as(u8, 12), plugin.plugin.AudioBusLayout.surround_7_1_4.channelCount());
    try std.testing.expectEqual(@as(u8, 16), plugin.plugin.AudioBusLayout.ambisonic_third_order.channelCount());
}

test "installed package exposes reusable DSP primitives" {
    var oscillator = try plugin.dsp.Oscillator(f32).init(
        48_000.0,
        1_000.0,
        .sine,
    );
    var generated: [8]f32 = undefined;
    oscillator.process(&generated);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.0),
        generated[0],
        0.000_001,
    );

    var compressor = try plugin.dsp.Compressor(f32).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -12.0,
        .ratio = 4.0,
    });
    var samples = [_]f32{1.0} ** 1_024;
    compressor.process(&samples);
    try std.testing.expect(compressor.gainReductionDb() < 0.0);

    var gate = try plugin.dsp.NoiseGate(f32).init(.{
        .sample_rate = 48_000.0,
    });
    _ = gate.processSample(0.001);
    try std.testing.expect(gate.gainReductionDb() < 0.0);

    var limiter = try plugin.dsp.Limiter(f32).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -6.0,
    });
    try std.testing.expect(
        limiter.processSample(2.0) < 1.0,
    );

    const inverse_chebyshev =
        try plugin.dsp.ChebyshevTypeIIDesigner(f32).lowPass(.{
            .order = 5,
            .sample_rate = 48_000.0,
            .stopband_hz = 4_000.0,
            .attenuation_db = 60.0,
        });
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.001),
        inverse_chebyshev.magnitude(48_000.0, 4_000.0),
        0.000_001,
    );
    const jacobi = try plugin.dsp.jacobiElliptic(@as(f64, 1.0), 0.5);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.803_001_824_895_643_9),
        jacobi.sn,
        0.000_000_000_000_01,
    );
    const complex_jacobi = try plugin.dsp.complexJacobiElliptic(
        std.math.complex.Complex(f64).init(0.25, 0.5),
        0.2,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.285_638_124_095_013_88),
        complex_jacobi.sn.re,
        0.000_000_000_000_3,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.504_946_625_918_997_5),
        complex_jacobi.sn.im,
        0.000_000_000_000_3,
    );
    const complex_cd = try plugin.dsp.complexJacobiCd(
        std.math.complex.Complex(f64).init(0.25, 0.5),
        0.2,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.075_186_481_930_692_7),
        complex_cd.re,
        0.000_000_000_000_4,
    );
    const real_dc = try plugin.dsp.jacobiEllipticFunction(
        @as(f64, 1.0),
        0.5,
        .dc,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.381_196_923_306_613_3),
        real_dc,
        0.000_000_000_000_04,
    );
    const complex_ns = try plugin.dsp.complexJacobiEllipticFunction(
        std.math.complex.Complex(f64).init(0.25, 0.5),
        0.2,
        plugin.dsp.JacobiFunction.ns,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.848_698_378_830_729_5),
        complex_ns.re,
        0.000_000_000_000_5,
    );
    const inverse_complex_jacobi =
        try plugin.dsp.inverseComplexJacobiSn(complex_jacobi.sn, 0.2);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        inverse_complex_jacobi.re,
        0.000_000_000_000_5,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        inverse_complex_jacobi.im,
        0.000_000_000_000_5,
    );
    const elliptic =
        try plugin.dsp.EllipticDesigner(f32).lowPassForSpecification(.{
            .sample_rate = 48_000.0,
            .passband_hz = 1_000.0,
            .stopband_hz = 2_000.0,
            .maximum_passband_loss_db = 1.0,
            .minimum_stopband_attenuation_db = 60.0,
        });
    try std.testing.expect(
        elliptic.magnitude(48_000.0, 2_000.0) <= 0.001_001,
    );

    var delay = plugin.dsp.DelayLine(f32, 8){};
    _ = try delay.processSample(1.0, 2.0, .cubic);
    _ = try delay.processSample(0.0, 2.0, .cubic);
    try std.testing.expectEqual(
        @as(f32, 1.0),
        try delay.processSample(0.0, 2.0, .cubic),
    );

    const panner = try plugin.dsp.StereoPanner(f32).init(0.0);
    const panned = panner.processSample(1.0);
    try std.testing.expectApproxEqAbs(
        panned[0],
        panned[1],
        0.000_001,
    );
    var balanced_panner = try plugin.dsp.StereoPanner(f32).initWithRule(
        0.0,
        .balanced,
    );
    try std.testing.expectEqualDeep(
        [2]f32{ 1.0, 1.0 },
        balanced_panner.processSample(1.0),
    );
    balanced_panner.setRule(.linear);

    const InstalledConvolver = plugin.dsp.PartitionedConvolver(16, 8);
    var convolver = InstalledConvolver.init(48_000);
    try convolver.begin(.{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 1,
    });
    try convolver.write(1, 0, &.{1.0});
    try convolver.commit(1);
    try std.testing.expect(convolver.adoptPending());
    var convolved: [9]f32 = undefined;
    for (&convolved, 0..) |*sample, index| {
        sample.* = convolver.processFrame(
            if (index == 0) 1.0 else 0.0,
            0.0,
        )[0];
    }
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        convolved[8],
        0.000_1,
    );

    const InstalledFft = plugin.dsp.Fft(f32, 8);
    const fft = InstalledFft.init();
    const fft_input = [8]f32{ 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 };
    var fft_output: [8]InstalledFft.Value = undefined;
    try fft.forwardReal(&fft_input, &fft_output);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        fft_output[3].magnitude(),
        0.000_001,
    );

    var fir = try plugin.dsp.FirFilter(f32, 4).init(
        &.{ 0.5, 0.25 },
    );
    try std.testing.expectEqual(
        @as(f32, 0.5),
        fir.processSample(1.0),
    );
    try std.testing.expectEqual(
        @as(f32, 0.25),
        fir.processSample(0.0),
    );

    var window: [7]f32 = undefined;
    try plugin.dsp.fillWindow(
        f32,
        &window,
        .hann,
        false,
        .unit_peak,
    );
    try std.testing.expectEqual(@as(f32, 1.0), window[3]);
    try plugin.dsp.fillKaiserWindow(
        f32,
        &window,
        8.0,
        false,
        .unit_peak,
    );
    try std.testing.expectEqual(@as(f32, 1.0), window[3]);

    var coefficients: [15]f32 = undefined;
    try plugin.dsp.FirDesigner(f32).lowPass(
        &coefficients,
        0.125,
        .blackman,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        plugin.dsp.FirDesigner(f32).magnitude(&coefficients, 0.0),
        0.000_01,
    );

    const InstalledOversampler = plugin.dsp.Oversampler(f32, 8, 2);
    var oversampler = try InstalledOversampler.init();
    var oversampled_input: [8]f32 = @splat(0.25);
    const high_rate = try oversampler.upsample(&oversampled_input);
    for (high_rate) |*sample| sample.* *= 2.0;
    var downsampled: [8]f32 = undefined;
    try oversampler.downsample(&downsampled);
    try std.testing.expectEqual(@as(usize, 0), oversampler.pending_frames);

    const InstalledMixer = plugin.dsp.DryWetMixer(f32, 8, 4);
    var mixer = try InstalledMixer.init(.{
        .wet = 0.5,
        .rule = .linear,
    });
    try mixer.pushDry(&.{1.0});
    var mixed = [_]f32{0.0};
    try mixer.mixWet(&mixed);
    try std.testing.expectEqual(@as(f32, 0.5), mixed[0]);

    var shaper = try plugin.dsp.WaveShaper(f32).init(.{
        .kind = .hard_clip,
        .drive_db = 12.0,
    });
    try std.testing.expect(shaper.processSample(1.0) <= 1.0);

    var chorus = try plugin.dsp.Chorus(f32, 512).init(.{
        .sample_rate = 48_000.0,
    });
    try std.testing.expect(std.math.isFinite(
        chorus.processSample(0.25),
    ));

    var phaser = try plugin.dsp.Phaser(f32, 4).init(.{
        .sample_rate = 48_000.0,
    });
    try std.testing.expect(std.math.isFinite(
        phaser.processSample(0.25),
    ));

    var state_variable = try plugin.dsp.StateVariableFilter(f32).init(.{
        .kind = .low_pass,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    try std.testing.expect(std.math.isFinite(
        state_variable.processSample(0.25),
    ));

    var crossover = try plugin.dsp.LinkwitzRileyFilter(f32).init(.{
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    const split = crossover.processSample(0.25);
    try std.testing.expect(std.math.isFinite(split.low));
    try std.testing.expect(std.math.isFinite(split.high));

    var reverb = try plugin.dsp.Reverb(f32, 2_048).init(.{
        .sample_rate = 48_000.0,
    });
    const reverberated = reverb.processSample(0.25, -0.25);
    try std.testing.expect(std.math.isFinite(reverberated.left));
    try std.testing.expect(std.math.isFinite(reverberated.right));

    const lookup = try plugin.dsp.LookupTable(f32, 33).init(
        -1.0,
        1.0,
        installedSquare,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        lookup.processSample(0.5),
        0.001,
    );

    const InstalledChain = plugin.dsp.ProcessorChain(
        f32,
        struct {
            plugin.dsp.WaveShaper(f32),
            plugin.dsp.StateVariableFilter(f32),
        },
    );
    var chain = InstalledChain.init(.{
        try plugin.dsp.WaveShaper(f32).init(.{ .kind = .cubic }),
        try plugin.dsp.StateVariableFilter(f32).init(.{
            .kind = .low_pass,
            .sample_rate = 48_000.0,
            .frequency_hz = 2_000.0,
        }),
    });
    try std.testing.expect(std.math.isFinite(chain.processSample(0.25)));
    chain.setBypassed(0, true);
    try std.testing.expect(chain.isBypassed(0));
    try std.testing.expect(chain.valid());

    var first_order = try plugin.dsp.FirstOrderTptFilter(f32).init(.{
        .kind = .low_pass,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    try std.testing.expect(std.math.isFinite(
        first_order.processSample(0.25),
    ));

    var ballistics = try plugin.dsp.BallisticsFilter(f32).init(.{
        .sample_rate = 48_000.0,
        .mode = .rms,
    });
    try std.testing.expect(ballistics.processSample(0.25) >= 0.0);

    var ramp = try plugin.dsp.LogRampedValue(f32).init(1.0);
    try ramp.setTarget(4.0, 2);
    try std.testing.expectApproxEqAbs(
        @as(f32, 2.0),
        ramp.next(),
        0.000_001,
    );

    var gain = try plugin.dsp.Gain(f32).init(0.5);
    try std.testing.expectEqual(@as(f32, 0.5), gain.processSample(1.0));
    const bias = try plugin.dsp.Bias(f32).init(0.25);
    try std.testing.expectEqual(@as(f32, 0.75), bias.processSample(0.5));

    const InstalledDuplicator = plugin.dsp.ProcessorDuplicator(
        f32,
        plugin.dsp.Gain(f32),
        4,
    );
    var duplicator = try InstalledDuplicator.init(
        try plugin.dsp.Gain(f32).init(1.0),
        2,
    );
    try (try duplicator.get(1)).setLinear(0.5, 0);
    try std.testing.expectEqual(
        @as(f32, 0.5),
        try duplicator.processSample(1, 1.0),
    );
}

test "installed package exposes bounded resource commands" {
    try std.testing.expectEqual(@as(usize, 4096), vst3.resource_path_transport.maximum_path_bytes);
    try std.testing.expectEqual(
        vst3.pluginterfaces.base.types.kResultFalse,
        vst3.resource_path_transport.sendImport(null, 1, "model.nam"),
    );
    try std.testing.expectEqual(
        vst3.pluginterfaces.base.types.kResultFalse,
        vst3.resource_path_transport.sendCancel(null, 1),
    );
}

test "installed package exposes block boundary parameter latching" {
    var latch = plugin.process.BlockParameterLatch.init(12, 0.0);
    const changes = [_]plugin.process.ParameterChange{
        .{ .id = 12, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 12, .sample_offset = 3, .normalized = 0.75 },
    };
    const view = try plugin.process.ParameterChanges.init(&changes, 4);

    try std.testing.expect(view.valid(4));
    try std.testing.expect(latch.valid());
    try std.testing.expectEqual(@as(f64, 0.25), latch.beginBlock(view, 0.75));
    try std.testing.expectEqual(@as(f64, 0.25), latch.valueAt(view, 2));
    try std.testing.expectEqual(@as(f64, 0.75), latch.valueAt(view, 3));
    try std.testing.expectEqual(@as(f64, 0.75), latch.nextBlockValue());
    try std.testing.expectEqual(@as(f64, 0.75), latch.beginBlock(.{}, 0.75));

    const events = try plugin.process.Events.init(&.{
        plugin.process.Event.noteOn(0, 0, 60, 0.75),
        plugin.process.Event.noteOff(3, 0, 60, 0.0),
    }, 4);
    try std.testing.expect(events.valid(4));
}

test "installed package exposes host process modes" {
    const prepare = plugin.plugin.PrepareConfig{
        .sample_rate = 48_000.0,
        .max_block_size = 512,
        .process_mode = .prefetch,
    };
    try prepare.validate();
    try std.testing.expectEqual(plugin.process.ProcessMode.prefetch, prepare.process_mode);

    const context = try plugin.process.ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .process_mode = .offline,
        .input_channels = &.{},
        .output_channels = &.{},
        .transport = .{
            .project_time_samples = 96_000,
            .state_valid = true,
            .playing = true,
            .tempo_bpm = 128.0,
            .project_quarter_notes = 8.0,
        },
    });
    try std.testing.expectEqual(plugin.process.ProcessMode.offline, context.processMode());
    try std.testing.expect(context.isOffline());
    try std.testing.expect(!context.isRealtime());
    try std.testing.expect(!context.isPrefetch());
    try std.testing.expectEqual(@as(?f64, 128.0), context.hostTempoBpm());
    try std.testing.expect(context.transport().?.playing);

    var smoothed =
        try plugin.dsp.LinearSmoothedValue.init(1_000.0, 0.0, 0.0, 1.0);
    try smoothed.setTarget(1_000.0, 1.0, 0.004);
    try std.testing.expectEqual(@as(f64, 1.0), smoothed.skip(4));

    var snapshots =
        plugin.dsp.RealtimeSnapshotPublisher(struct { gain: f32 }).init(
            .{ .gain = 1.0 },
        );
    _ = try snapshots.publish(.{ .gain = 0.25 });
    try std.testing.expectEqual(
        @as(f32, 0.25),
        snapshots.tryRead().?.value.gain,
    );
    var references =
        plugin.dsp.RealtimeReferencePublisher(
            struct { gain: f32 },
            4,
        ).init(.{ .gain = 1.0 });
    var initial_reference = references.tryAcquire().?;
    _ = try references.publish(.{ .gain = 0.5 });
    var current_reference = references.tryAcquire().?;
    try std.testing.expectEqual(
        @as(f32, 1.0),
        initial_reference.value().?.gain,
    );
    try std.testing.expectEqual(
        @as(f32, 0.5),
        current_reference.value().?.gain,
    );
    initial_reference.release();
    current_reference.release();

    const dispatcher = plugin.dsp.KernelDispatcher.initDetected();
    var dispatched_samples = [_]f32{ 1.0, -2.0, 3.0, -4.0, 5.0 };
    try dispatcher.processGain(
        f32,
        &dispatched_samples,
        0.5,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, -1.0, 1.5, -2.0, 2.5 },
        &dispatched_samples,
    );
    try dispatcher.processAffine(
        f32,
        &dispatched_samples,
        2.0,
        0.25,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1.25, -1.75, 3.25, -3.75, 5.25 },
        &dispatched_samples,
    );
    var dispatched_fast_math = [_]f32{ -0.5, 0.0, 0.5 };
    try dispatcher.applyFastMath(
        f32,
        .sine,
        &dispatched_fast_math,
    );
    try std.testing.expectApproxEqAbs(
        @sin(@as(f32, 0.5)),
        dispatched_fast_math[2],
        0.000_001,
    );
    const dispatched_source = [_]f32{ 0.5, -1.0, 2.0 };
    var dispatched_binary: [3]f32 = undefined;
    try dispatcher.copyBuffer(
        f32,
        &dispatched_binary,
        &dispatched_source,
    );
    try dispatcher.addBuffer(
        f32,
        &dispatched_binary,
        &dispatched_source,
    );
    try dispatcher.multiplyBuffer(
        f32,
        &dispatched_binary,
        &dispatched_source,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, 2.0, 8.0 },
        &dispatched_binary,
    );
    var mixed: [3]f32 = undefined;
    try dispatcher.mixBuffers(
        f32,
        &mixed,
        &.{ 1.0, 2.0, 3.0 },
        &.{ 3.0, 2.0, 1.0 },
        0.25,
        0.75,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 2.5, 2.0, 1.5 },
        &mixed,
    );
    var interleaved: [6]f32 = undefined;
    try dispatcher.interleaveStereo(
        f32,
        &interleaved,
        &.{ 1.0, 2.0, 3.0 },
        &.{ -1.0, -2.0, -3.0 },
    );
    var left: [3]f32 = undefined;
    var right: [3]f32 = undefined;
    try dispatcher.deinterleaveStereo(
        f32,
        &left,
        &right,
        &interleaved,
    );
    try std.testing.expectEqualSlices(f32, &.{ 1.0, 2.0, 3.0 }, &left);
    try std.testing.expectEqualSlices(f32, &.{ -1.0, -2.0, -3.0 }, &right);
    try std.testing.expect(
        plugin.dsp.nativeSimdLaneCount(f32) >= 1,
    );
}

test "installed package exposes host-neutral processor runtimes" {
    const InstalledRuntimeGain = struct {
        pub const name = "Installed Runtime Gain";
        pub const vendor = "Example Audio";
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            context: *plugin.process.ProcessContext(f32),
        ) void {
            for (0..context.outputChannelCount()) |channel_index| {
                const input =
                    context.inputChannel(channel_index) orelse continue;
                const output =
                    context.outputChannel(channel_index) orelse continue;
                @memcpy(output, input);
            }
        }
    };

    const Runtime = plugin.plugin.ProcessorRuntime(
        InstalledRuntimeGain,
    );
    var runtime = try Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    try runtime.prepare(.{
        .sample_rate = 48_000.0,
        .max_block_size = 2,
        .process_mode = .offline,
    });
    try runtime.activate();
    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    var context =
        try plugin.process.ProcessContext(f32).initWithOptions(.{
            .sample_rate = 48_000.0,
            .process_mode = .offline,
            .input_channels = &inputs,
            .output_channels = &outputs,
        });
    try runtime.process(&context);
    try std.testing.expectEqualSlices(f32, &input, &output);
    try runtime.deactivate();
    try runtime.releaseResources();
    runtime.deinit();
    try std.testing.expectEqual(
        plugin.plugin.RuntimeState.deinitialized,
        runtime.runtimeState(),
    );
    try std.testing.expectError(
        error.ProcessorDeinitialized,
        runtime.reset(),
    );
    runtime.deinit();

    try std.testing.expect(
        @hasDecl(plugin.plugin, "OfflineRenderer"),
    );
    const Adapter = plugin.Vst3Processor(InstalledRuntimeGain);
    var adapter =
        try Adapter.initWithAllocator(std.testing.allocator);
    defer adapter.deinit();
    try std.testing.expect(adapter.supportsSampleType(f32));
    try std.testing.expect(!adapter.supportsSampleType(f64));
}

test "installed package exposes multiple auxiliary process buses and metadata" {
    const main = [_]f32{ 0.1, 0.2 };
    const key_mono = [_]f32{ 0.7, 0.8 };
    const key_left = [_]f32{ 0.5, 0.6 };
    const key_right = [_]f32{ 0.3, 0.4 };
    var output = [_]f32{ 0.0, 0.0 };
    var auxiliary_output_mono = [_]f32{ 0.0, 0.0 };
    var auxiliary_output_left = [_]f32{ 0.0, 0.0 };
    var auxiliary_output_right = [_]f32{ 0.0, 0.0 };
    const context = try plugin.process.ProcessContext(f32).initWithOptions(.{
        .sample_rate = 48_000.0,
        .input_channels = &[_][]const f32{&main},
        .sidechain_input_channels = &[_][]const f32{
            &key_mono,
            &key_left,
            &key_right,
        },
        .auxiliary_input_bus_channel_counts = &.{ 1, 2 },
        .output_channels = &[_][]f32{&output},
        .auxiliary_output_channels = &[_][]f32{
            &auxiliary_output_mono,
            &auxiliary_output_left,
            &auxiliary_output_right,
        },
        .auxiliary_output_bus_channel_counts = &.{ 1, 2 },
    });

    try std.testing.expectEqual(@as(usize, 3), context.sidechainInputChannelCount());
    try std.testing.expectEqual(@as(?f32, 0.8), context.sidechainInputSample(0, 1));
    try std.testing.expectEqual(@as(usize, 2), context.auxiliaryInputBusCount());
    try std.testing.expectEqual(
        @as(f32, 0.4),
        context.auxiliaryInputBus(1).?.channel(1).?[1],
    );
    context.auxiliaryOutputBus(1).?.channel(1).?[1] = 0.25;
    try std.testing.expectEqual(@as(f32, 0.25), auxiliary_output_right[1]);

    const Ducker = struct {
        pub const name = "Installed Sidechain Ducker";
        pub const vendor = "zig-vst3";
        pub const audio_auxiliary_input_layouts: []const plugin.plugin.AudioBusLayout = &.{ .mono, .stereo };
        pub const audio_auxiliary_output_layouts: []const plugin.plugin.AudioBusLayout = &.{ .mono, .stereo };
        pub const Params = struct {};
    };
    const Spec = plugin.plugin.PluginSpec(Ducker);
    try std.testing.expectEqual(plugin.plugin.AudioBusLayout.mono, Spec.audio_sidechain_layout);
    try std.testing.expectEqual(plugin.plugin.AudioBusLayout.mono, Spec.audio_auxiliary_output_layout);
    try std.testing.expectEqual(@as(usize, 2), Spec.audio_auxiliary_input_layouts.len);
    try std.testing.expectEqual(@as(usize, 2), Spec.audio_auxiliary_output_layouts.len);
}

test "installed package exposes bounded dynamic audio topology" {
    const layouts = try plugin.plugin.AudioBusLayoutSet.init(
        &.{ .stereo, .surround_5_1 },
    );
    var topology = try plugin.plugin.DynamicAudioBusTopology.init(
        try plugin.plugin.DynamicAudioBus.init(
            .stereo,
            layouts,
            true,
        ),
        try plugin.plugin.DynamicAudioBus.fixed(.stereo, true),
    );
    _ = try topology.addAuxiliary(
        .input,
        try plugin.plugin.DynamicAudioBus.fixed(.mono, false),
    );
    _ = try topology.setLayout(.input, 0, .surround_5_1);
    _ = try topology.setActive(.input, 1, true);
    try std.testing.expectEqual(
        plugin.plugin.AudioBusLayout.surround_5_1,
        topology.bus(.input, 0).?.layout,
    );
    try std.testing.expect(topology.bus(.input, 1).?.active);
    const snapshot = try topology.snapshot();
    try std.testing.expect(snapshot.valid());
    try std.testing.expect(snapshot.bus(.input, 1).?.active);
    try std.testing.expect(!snapshot.bus(.input, 1).?.default_active);
    var encoded: [plugin.plugin.DynamicAudioBusTopology.maximum_encoded_size]u8 =
        undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try topology.writeState(&writer);
    var reader = std.Io.Reader.fixed(writer.buffered());
    const restored =
        try plugin.plugin.DynamicAudioBusTopology.readState(&reader);
    try std.testing.expectEqual(
        plugin.plugin.AudioBusLayout.surround_5_1,
        restored.bus(.input, 0).?.layout,
    );
    try std.testing.expect(restored.bus(.input, 1).?.active);
    _ = try topology.removeAuxiliary(.input, 0);
    try std.testing.expectEqual(
        @as(usize, 1),
        topology.busCount(.input),
    );
}

test "installed package selects dynamic audio topology capacity" {
    const Topology =
        plugin.plugin.BoundedDynamicAudioBusTopology(12);
    var topology = try Topology.init(
        try plugin.plugin.DynamicAudioBus.fixed(.stereo, true),
        null,
    );
    for (0..Topology.auxiliary_capacity) |_|
        _ = try topology.addAuxiliary(
            .input,
            try plugin.plugin.DynamicAudioBus.fixed(.mono, false),
        );
    try std.testing.expectEqual(
        @as(usize, 13),
        topology.busCount(.input),
    );
    const snapshot = try topology.snapshot();
    try std.testing.expectEqual(
        @as(usize, 13),
        snapshot.busCount(.input),
    );
    var encoded: [Topology.maximum_encoded_size]u8 = undefined;
    var writer = std.Io.Writer.fixed(&encoded);
    try topology.writeState(&writer);
    var reader = std.Io.Reader.fixed(writer.buffered());
    const restored = try Topology.readState(&reader);
    try std.testing.expectEqual(
        @as(usize, 13),
        restored.busCount(.input),
    );
}

test "installed package carries selected bus capacity through authoring types" {
    const LargeBusPlugin = struct {
        pub const name = "Installed Large Bus Plugin";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const Topology =
            plugin.plugin.BoundedDynamicAudioBusTopology(12);
        pub const audio_bus_topology = makeTopology();

        fn makeTopology() Topology {
            var topology = Topology.init(
                plugin.plugin.DynamicAudioBus.fixed(
                    .stereo,
                    true,
                ) catch unreachable,
                null,
            ) catch unreachable;
            for (0..Topology.auxiliary_capacity) |_|
                _ = topology.addAuxiliary(
                    .input,
                    plugin.plugin.DynamicAudioBus.fixed(
                        .mono,
                        false,
                    ) catch unreachable,
                ) catch unreachable;
            return topology;
        }
    };
    const Spec = plugin.plugin.PluginSpec(LargeBusPlugin);
    const Context =
        plugin.process.BoundedProcessContext(f32, 12);
    const Router =
        plugin.plugin.BoundedDeviceChannelRouter(f32, 1, 12);
    var main_output = [_]f32{ 0.0, 0.0 };

    try std.testing.expectEqual(
        @as(usize, 12),
        Spec.auxiliary_audio_bus_capacity,
    );
    try std.testing.expectEqual(
        LargeBusPlugin.Topology,
        Spec.AudioBusTopology,
    );
    const context = try Context.initWithOptions(.{
        .sample_rate = 48_000.0,
        .output_channels = &.{&main_output},
    });
    try std.testing.expectEqual(
        @as(usize, 12),
        Context.auxiliary_bus_capacity,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        context.auxiliaryInputBusCount(),
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        @typeInfo(
            @FieldType(Router, "auxiliary_input_bus_channel_counts"),
        ).array.len,
    );
}

test "installed package exposes MIDI 1 channel message utilities" {
    const message = try plugin.process.Midi1Message.parse(&.{ 0x92, 64, 127 });
    try std.testing.expectEqual(plugin.process.Midi1MessageKind.note_on, message.kind().?);
    try std.testing.expectEqual(@as(u8, 2), message.channel().?);
    try std.testing.expectEqualSlices(u8, &.{ 0x92, 64, 127 }, message.bytes());

    const event = message.toEvent(7, 1).?;
    try std.testing.expectEqual(plugin.process.EventKind.note_on, event.kind);
    try std.testing.expectEqual(@as(usize, 7), event.sample_offset);
    try std.testing.expectEqual(@as(i32, 1), event.bus_index);

    var decoder = plugin.process.Midi1StreamDecoder{};
    try std.testing.expect((try decoder.push(0x90)) == null);
    try std.testing.expect((try decoder.push(60)) == null);
    const streamed = (try decoder.push(100)).?;
    try std.testing.expectEqualSlices(u8, &.{ 0x90, 60, 100 }, streamed.bytes());
}

test "installed package parses and writes bounded Standard MIDI Files" {
    var storage: [96]u8 = undefined;
    var writer = try plugin.process.MidiFileWriter.init(
        &storage,
        .single_track,
        1,
        .{ .ticks_per_quarter_note = 480 },
    );
    try writer.beginTrack();
    try writer.writeMeta(0, 0x51, &.{ 0x07, 0xA1, 0x20 });
    try writer.writeMessage(0, try plugin.process.Midi1Message.noteOn(0, 60, 100));
    try writer.writeMessage(480, try plugin.process.Midi1Message.noteOff(0, 60, 64));
    try writer.endTrack(0);

    const file = try plugin.process.MidiFile.parse(try writer.finish());
    try std.testing.expectEqual(plugin.process.MidiFileFormat.single_track, file.format);
    try std.testing.expectEqual(@as(u16, 480), file.division.ticks_per_quarter_note);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), try file.secondsAtTick(0, 480), 0.000_001);

    var events = file.track(0).?.iterator();
    try std.testing.expectEqual(@as(?u32, 500_000), (try events.next()).?.payload.meta.tempoMicrosecondsPerQuarterNote());
    try std.testing.expectEqual(plugin.process.Midi1MessageKind.note_on, (try events.next()).?.payload.message.kind().?);
    try std.testing.expectEqual(plugin.process.Midi1MessageKind.note_off, (try events.next()).?.payload.message.kind().?);
}

test "installed package exposes checked MPE zone layouts" {
    var layout = try plugin.process.MpeZoneLayout.init(
        try plugin.process.MpeZone.init(.lower, 8, 48, 2),
        try plugin.process.MpeZone.init(.upper, 6, 24, 2),
    );
    try std.testing.expectEqual(plugin.process.MpeZoneType.lower, layout.memberZone(8).?);
    try std.testing.expectEqual(plugin.process.MpeZoneType.upper, layout.memberZone(9).?);
    try std.testing.expectEqual(plugin.process.MpeZoneType.lower, layout.masterZone(0).?);
    try std.testing.expectEqual(plugin.process.MpeZoneType.upper, layout.masterZone(15).?);

    const before = layout;
    try std.testing.expectError(
        error.OverlappingMpeZones,
        layout.setLower(try plugin.process.MpeZone.init(.lower, 9, 48, 2)),
    );
    try std.testing.expectEqualDeep(before, layout);

    var synchronizer = try plugin.process.MpeZoneSynchronizer.init(layout);
    const configure = try plugin.process.mpeConfigurationMessages(.upper, 10);
    for (configure) |message| {
        _ = try synchronizer.push(message);
    }
    try std.testing.expectEqual(@as(u8, 10), synchronizer.layout.upper.member_channel_count);
    try std.testing.expectEqual(@as(u8, 4), synchronizer.layout.lower.member_channel_count);

    const bend_range = try plugin.process.mpePitchBendRangeMessages(15, 12);
    for (bend_range) |message| {
        _ = try synchronizer.push(message);
    }
    try std.testing.expectEqual(@as(u8, 12), synchronizer.layout.upper.master_pitch_bend_range);

    var rpn_decoder = plugin.process.MidiRpnDecoder{};
    const rpn_messages = try plugin.process.midiRpnFineMessages(3, 130, 5, 6);
    var rpn_event: ?plugin.process.MidiRpnEvent = null;
    for (rpn_messages) |message| {
        rpn_event = try rpn_decoder.push(message);
    }
    try std.testing.expectEqual(@as(u14, 646), rpn_event.?.value());
}

test "installed package exposes MPE note tracking and channel allocation" {
    const layout = try plugin.process.MpeZoneLayout.init(
        try plugin.process.MpeZone.init(.lower, 2, 48, 2),
        try plugin.process.MpeZone.init(.upper, 0, 48, 2),
    );
    const Instrument = plugin.process.MpeInstrument(4);
    var instrument = try Instrument.init(layout);
    for (instrument.notes_storage) |active_note|
        try std.testing.expectEqualDeep(plugin.process.MpeNote{}, active_note);
    const added = try instrument.process(try plugin.process.Midi1Message.noteOn(1, 60, 100));
    try std.testing.expectEqual(plugin.process.MpeInstrumentChangeKind.note_added, added.kind);
    _ = try instrument.process(try plugin.process.Midi1Message.pitchBend(1, 16383));
    try std.testing.expectApproxEqAbs(
        @as(f32, 48.0),
        instrument.notes()[0].total_pitch_bend_semitones,
        0.0001,
    );
    try std.testing.expectEqual(@as(usize, 1), instrument.allNotesOff());
    for (instrument.notes_storage) |active_note|
        try std.testing.expectEqualDeep(plugin.process.MpeNote{}, active_note);

    var allocator = try plugin.process.MpeMemberChannelAllocator.init(layout.lower);
    for (allocator.assignments_storage) |assignment|
        try std.testing.expectEqualDeep(
            plugin.process.MpeMemberChannelAssignment{},
            assignment,
        );
    const first = try allocator.allocate(60, .reject);
    const second = try allocator.allocate(64, .reject);
    try std.testing.expectEqual(@as(u8, 1), first.assignment.channel_index);
    try std.testing.expectEqual(@as(u8, 2), second.assignment.channel_index);
    const replacement = try allocator.allocate(67, .oldest);
    try std.testing.expectEqual(first.assignment.id, replacement.stolen.?.id);
    try std.testing.expectEqual(@as(u8, 1), replacement.assignment.channel_index);
    try std.testing.expectEqualDeep(second.assignment, allocator.release(second.assignment.id).?);
    try std.testing.expectEqualDeep(
        plugin.process.MpeMemberChannelAssignment{},
        allocator.assignments_storage[1],
    );
}

test "installed package exposes checked UMP messages and SysEx7 assembly" {
    const source = try plugin.process.Midi1Message.noteOn(3, 60, 100);
    const packet = try plugin.process.umpFromMidi1(7, source);
    try std.testing.expectEqual(plugin.process.UmpMessageType.midi1_channel_voice, packet.messageType().?);
    try std.testing.expectEqual(@as(?u4, 7), packet.group());

    const decoded = try plugin.process.umpToMidi1(packet);
    try std.testing.expectEqual(@as(u4, 7), decoded.group);
    try std.testing.expectEqualSlices(u8, source.bytes(), decoded.message.bytes());

    var iterator = plugin.process.UmpIterator{
        .source = &.{ packet.storage[0], 0x4090_3C00, 0xFFFF_0000 },
    };
    try std.testing.expectEqual(
        plugin.process.UmpMessageType.midi1_channel_voice,
        (try iterator.next()).?.messageType().?,
    );
    try std.testing.expectEqual(
        plugin.process.UmpMessageType.midi2_channel_voice,
        (try iterator.next()).?.messageType().?,
    );
    try std.testing.expect((try iterator.next()) == null);
    try std.testing.expectEqual(
        @as(u7, 100),
        plugin.process.umpScale16To7(plugin.process.umpScale7To16(100)),
    );

    const midi2 = plugin.process.Midi2ChannelMessage{
        .group = 4,
        .channel = 3,
        .payload = .{ .note_on = .{
            .note = 64,
            .attribute = @intFromEnum(plugin.process.Midi2NoteAttribute.pitch_7_9),
            .velocity = 0xBEEF,
            .attribute_data = 0x1234,
        } },
    };
    try std.testing.expectEqualDeep(
        midi2,
        try plugin.process.Midi2ChannelMessage.parse(try midi2.packet()),
    );

    const transport = plugin.process.MidiSystemMessage{
        .group = 4,
        .payload = .{ .song_position = 0x1234 },
    };
    try std.testing.expectEqualDeep(
        transport,
        try plugin.process.MidiSystemMessage.parse(try transport.packet()),
    );

    const timestamp = plugin.process.MidiUtilityMessage{
        .payload = .{ .delta_clockstamp = 0xABCDE },
    };
    try std.testing.expectEqualDeep(
        timestamp,
        try plugin.process.MidiUtilityMessage.parse(try timestamp.packet()),
    );

    const endpoint = plugin.process.MidiStreamMessage{
        .payload = .{ .endpoint_info = .{
            .version_major = 1,
            .version_minor = 2,
            .function_block_count = 1,
            .static_function_blocks = true,
            .supports_midi1 = true,
            .supports_midi2 = true,
            .supports_receive_jr = true,
            .supports_transmit_jr = true,
        } },
    };
    try std.testing.expectEqualDeep(
        endpoint,
        try plugin.process.MidiStreamMessage.parse(try endpoint.packet()),
    );
    const start_of_clip = plugin.process.MidiStreamMessage{
        .payload = .{ .start_of_clip = {} },
    };
    try std.testing.expectEqualDeep(
        start_of_clip,
        try plugin.process.MidiStreamMessage.parse(try start_of_clip.packet()),
    );

    const tempo = plugin.process.MidiFlexMessage{
        .target = .{ .group = 4, .address = .group },
        .payload = .{ .set_tempo = 50_000_000 },
    };
    try std.testing.expectEqualDeep(
        tempo,
        try plugin.process.MidiFlexMessage.parse(try tempo.packet()),
    );

    var title_packetizer = try plugin.process.MidiFlexTextPacketizer.init(
        .{ .group = 4, .address = .group },
        .composition_name,
        "Installed Composition Name",
    );
    const TitleReassembler = plugin.process.MidiFlexTextReassembler(32);
    var title_reassembler = TitleReassembler{};
    while (try title_packetizer.next()) |title_packet| {
        _ = try title_reassembler.push(title_packet);
    }
    title_packetizer.emitted_empty = true;
    try std.testing.expect(!title_packetizer.valid());
    try std.testing.expectError(
        error.InvalidFlexTextPacketizerState,
        title_packetizer.next(),
    );
    title_packetizer.emitted_empty = false;
    try std.testing.expect(title_packetizer.valid());
    try std.testing.expectEqualStrings(
        "Installed Composition Name",
        title_reassembler.text().?,
    );
    title_reassembler.target = .{ .group = 4, .address = .group, .channel = 1 };
    try std.testing.expect(!title_reassembler.valid());
    try std.testing.expectEqual(@as(?[]const u8, null), title_reassembler.bytes());
    title_reassembler.target = .{ .group = 4, .address = .group };
    try std.testing.expect(title_reassembler.valid());
    for (title_reassembler.storage[title_reassembler.count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    title_reassembler.reset();
    for (title_reassembler.storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);

    const mixed_metadata = plugin.process.MidiMixedDataMetadata{
        .group = 4,
        .mds_id = 2,
        .chunk_count = 1,
        .chunk_number = 1,
        .manufacturer_id = 0x007D,
        .device_id = 0xFFFF,
        .sub_id_1 = 1,
        .sub_id_2 = 2,
    };
    var mixed_packetizer = try plugin.process.MidiMixedDataPacketizer.init(
        mixed_metadata,
        "Installed mixed data",
    );
    mixed_packetizer.header.valid_byte_count += 1;
    try std.testing.expect(!mixed_packetizer.valid());
    try std.testing.expectError(
        error.InvalidMixedDataPacketizerState,
        mixed_packetizer.next(),
    );
    mixed_packetizer.header.valid_byte_count -= 1;
    try std.testing.expect(mixed_packetizer.valid());
    const MixedReassembler = plugin.process.MidiMixedDataReassembler(32);
    var mixed_reassembler = MixedReassembler{};
    while (try mixed_packetizer.next()) |mixed_packet| {
        _ = try mixed_reassembler.push(mixed_packet);
    }
    try std.testing.expectEqualStrings(
        "Installed mixed data",
        mixed_reassembler.bytes().?,
    );
    for (mixed_reassembler.storage[mixed_reassembler.count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    mixed_reassembler.reset();
    for (mixed_reassembler.storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);

    const sysex_source = [_]u8{ 0x7D, 1, 2, 3, 4, 5, 6, 7 };
    var packetizer = try plugin.process.Sysex7Packetizer.init(2, &sysex_source);
    const Reassembler = plugin.process.Sysex7Reassembler(sysex_source.len);
    var reassembler = Reassembler{};
    while (try packetizer.next()) |sysex_packet| {
        _ = try reassembler.push(sysex_packet);
    }
    packetizer.emitted_empty = true;
    try std.testing.expect(!packetizer.valid());
    try std.testing.expectError(
        error.InvalidSysex7PacketizerState,
        packetizer.next(),
    );
    packetizer.emitted_empty = false;
    try std.testing.expect(packetizer.valid());
    try std.testing.expectEqualSlices(
        u7,
        &.{ 0x7D, 1, 2, 3, 4, 5, 6, 7 },
        reassembler.message().?,
    );
    reassembler.reset();
    for (reassembler.storage) |byte|
        try std.testing.expectEqual(@as(u7, 0), byte);

    const sysex8_source = [_]u8{ 0, 0x80, 0xFF, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 };
    var packetizer8 = try plugin.process.Sysex8Packetizer.init(3, 0xA5, &sysex8_source);
    const Reassembler8 = plugin.process.Sysex8Reassembler(sysex8_source.len);
    var reassembler8 = Reassembler8{};
    while (try packetizer8.next()) |sysex_packet| {
        _ = try reassembler8.push(sysex_packet);
    }
    try std.testing.expectEqualSlices(u8, &sysex8_source, reassembler8.message().?);
    reassembler8.reset();
    for (reassembler8.storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);

    var name_packetizer = try plugin.process.MidiStreamTextPacketizer.init(
        .endpoint_name,
        null,
        "Installed Endpoint Name",
    );
    const NameReassembler = plugin.process.MidiStreamTextReassembler(32);
    var name_reassembler = NameReassembler{};
    while (try name_packetizer.next()) |name_packet| {
        _ = try name_reassembler.push(name_packet);
    }
    try std.testing.expectEqualStrings("Installed Endpoint Name", name_reassembler.text().?);
    name_reassembler.storage[0] = 0;
    try std.testing.expect(!name_reassembler.valid());
    try std.testing.expectEqual(@as(?[]const u8, null), name_reassembler.bytes());
    name_reassembler.storage[0] = 'I';
    try std.testing.expect(name_reassembler.valid());
    for (name_reassembler.storage[name_reassembler.count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    name_reassembler.reset();
    for (name_reassembler.storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);

    const installed_block_info = plugin.process.MidiFunctionBlockInfo{
        .block = 0,
        .enabled = true,
        .ui_hint = .bidirectional,
        .midi1_proxy = .inapplicable,
        .direction = .bidirectional,
        .first_group = 0,
        .group_count = 1,
        .ci_version = 1,
        .max_sysex8_streams = 1,
    };
    const installed_blocks = [_]plugin.process.MidiFunctionBlockDescriptor{
        .{ .info = installed_block_info, .name = "Installed Block" },
    };
    var endpoint_responder = try plugin.process.MidiEndpointResponder.init(.{
        .info = endpoint.payload.endpoint_info,
        .identity = .{
            .manufacturer = .{ 0x7D, 0, 0 },
            .family = .{ 1, 0 },
            .model = .{ 1, 0 },
            .revision = .{ 1, 0, 0, 0 },
        },
        .name = "Installed Endpoint",
        .product_instance_id = "INSTALLED-1",
        .configuration = .{ .protocol = .midi1 },
        .function_blocks = &installed_blocks,
    });
    var endpoint_requester = plugin.process.MidiEndpointRequester{};
    const discovery = try endpoint_requester.endpointDiscovery(1, 1, .{
        .endpoint_info = true,
        .stream_configuration = true,
    });
    var discovery_replies = try endpoint_responder.handlePacket(discovery);
    while (try discovery_replies.next()) |reply| {
        try endpoint_requester.acceptPacket(reply);
    }
    const configuration = plugin.process.MidiStreamConfiguration{
        .protocol = .midi2,
        .transmit_jr_timestamps = true,
        .receive_jr_timestamps = true,
    };
    const configuration_request =
        try endpoint_requester.configurationRequest(configuration);
    var configuration_replies =
        try endpoint_responder.handlePacket(configuration_request);
    while (try configuration_replies.next()) |reply| {
        try endpoint_requester.acceptPacket(reply);
    }
    const function_discovery = try endpoint_requester.functionBlockDiscovery(
        .all,
        .{ .info = true },
    );
    var function_replies = try endpoint_responder.handlePacket(function_discovery);
    while (try function_replies.next()) |reply| {
        try endpoint_requester.acceptPacket(reply);
    }
    try std.testing.expect(endpoint_requester.functionBlockDiscoveryComplete());
    try std.testing.expect(endpoint_requester.valid());
    try std.testing.expect(endpoint_responder.valid());

    const ci_initiator = plugin.process.MidiCiParticipant{
        .muid = try plugin.process.MidiCiMuid.init(1),
        .identity = .{
            .manufacturer = .{ 0x7D, 0, 0 },
            .family = .{ 1, 0 },
            .model = .{ 1, 0 },
            .revision = .{ 1, 0, 0, 0 },
        },
        .categories = .{ .profile_configuration = true },
        .maximum_sysex_size = 512,
    };
    const ci_responder_participant = plugin.process.MidiCiParticipant{
        .muid = try plugin.process.MidiCiMuid.init(2),
        .identity = ci_initiator.identity,
        .categories = .{ .property_exchange = true },
        .maximum_sysex_size = 512,
    };
    const ci_transaction =
        try plugin.process.MidiCiDiscoveryTransaction.init(ci_initiator, 4);
    const ci_responder =
        try plugin.process.MidiCiDiscoveryResponder.init(ci_responder_participant, 0);
    var ci_storage: [31]u8 = undefined;
    const ci_inquiry_bytes = try ci_transaction.inquiry().encode(&ci_storage);
    var ci_packetizer = try plugin.process.Sysex7Packetizer.init(0, ci_inquiry_bytes);
    const CiReassembler = plugin.process.Sysex7Reassembler(31);
    var ci_reassembler = CiReassembler{};
    while (try ci_packetizer.next()) |ci_packet| {
        _ = try ci_reassembler.push(ci_packet);
    }
    const ci_inquiry =
        try plugin.process.MidiCiDiscoveryMessage.parse(ci_reassembler.message().?);
    const ci_reply_message = try ci_responder.handle(ci_inquiry);
    const ci_reply = try ci_transaction.accept(ci_reply_message);
    try std.testing.expectEqual(@as(u28, 2), ci_reply.participant.muid.value);
    try std.testing.expectEqual(@as(?u5, 0), ci_reply.function_block);

    const ci_invalidation = plugin.process.MidiCiInvalidation{
        .source = ci_initiator.muid,
        .target = ci_responder_participant.muid,
    };
    var ci_invalidation_storage: [17]u8 = undefined;
    const ci_invalidation_bytes =
        try ci_invalidation.encode(&ci_invalidation_storage);
    const parsed_ci_invalidation =
        try plugin.process.MidiCiInvalidation.parse(ci_invalidation_bytes);
    try std.testing.expect(parsed_ci_invalidation.targets(ci_responder_participant.muid));

    const InstalledMidiCiDevice = plugin.process.MidiCiDevice(.{
        .remote_capacity = 2,
        .profile_capacity = 4,
        .property_session_capacity = 2,
        .subscription_capacity = 2,
        .property_header_capacity = 32,
        .property_data_capacity = 64,
    });
    var ci_device = try InstalledMidiCiDevice.init(.{
        .participant = .{
            .muid = ci_initiator.muid,
            .identity = ci_initiator.identity,
            .categories = .{
                .profile_configuration = true,
                .property_exchange = true,
                .process_inquiry = true,
            },
            .maximum_sysex_size = 512,
        },
        .product_instance_id = try plugin.process.MidiCiProductInstanceId.init("LOCAL-1"),
        .process_features = .{ .midi_message_report = true },
        .simultaneous_property_requests = 2,
    });
    for (ci_device.remotes) |slot|
        try std.testing.expectEqualDeep(@TypeOf(slot){}, slot);
    for (ci_device.pending_properties) |pending|
        try std.testing.expectEqualDeep(@TypeOf(pending){}, pending);
    const remote_handle = (try ci_device.handleDiscovery(.{ .discovery = .{
        .participant = .{
            .muid = ci_responder_participant.muid,
            .identity = ci_responder_participant.identity,
            .categories = .{
                .profile_configuration = true,
                .property_exchange = true,
                .process_inquiry = true,
            },
            .maximum_sysex_size = 512,
        },
    } })).handle;
    try std.testing.expectEqual(
        ci_responder_participant.muid.value,
        (try ci_device.remote(remote_handle)).participant.muid.value,
    );
    try std.testing.expectEqual(
        ci_responder_participant.muid.value,
        (try ci_device.profileInquiry(
            remote_handle,
            .function_block,
        )).destination.value,
    );
    const installed_profile = plugin.process.MidiCiProfileId.standard(
        0,
        1,
        1,
        0,
    );
    var installed_profile_delegate = InstalledProfileDelegate{};
    var installed_profile_host =
        try ci_device.profileHost(&installed_profile_delegate);
    _ = try installed_profile_host.addProfile(
        .function_block,
        installed_profile,
    );
    const installed_profile_reply =
        try installed_profile_host.handleInquiry(.{
            .source = ci_responder_participant.muid,
            .destination = ci_initiator.muid,
        }, .function_block);
    try std.testing.expectEqual(
        @as(usize, 1),
        installed_profile_reply.disabled.slice().len,
    );
    _ = try installed_profile_host.handleSet(.{
        .kind = .on,
        .source = ci_responder_participant.muid,
        .destination = ci_initiator.muid,
        .profile = installed_profile,
    });
    try std.testing.expectEqual(
        @as(usize, 1),
        installed_profile_delegate.requests,
    );
    _ = try installed_profile_host.removeProfile(
        .function_block,
        installed_profile,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        ci_device.local_profile_count,
    );
    try std.testing.expectEqualDeep(
        plugin.process.MidiCiProfileHostEntry{},
        ci_device.local_profiles[0],
    );
    const installed_property_responder =
        try plugin.process.MidiCiPropertyCapabilitiesResponder.init(.{
            .source = ci_responder_participant.muid,
            .destination = ci_initiator.muid,
            .simultaneous_requests = 2,
            .property_exchange_major = 1,
            .property_exchange_minor = 0,
        });
    _ = try ci_device.acceptPropertyCapabilities(
        remote_handle,
        try installed_property_responder.handle(
            try ci_device.propertyCapabilitiesInquiry(remote_handle),
        ),
    );
    const installed_get = try ci_device.beginPropertyGet(
        remote_handle,
        .{ .resource = "DeviceInfo" },
    );
    const installed_pending =
        ci_device.pending_properties[installed_get.request_id];
    for (installed_pending.resource_storage[installed_pending.resource_count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (installed_pending.res_id_storage[installed_pending.res_id_count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    _ = try ci_device.acceptPropertyGet(
        std.testing.allocator,
        try plugin.process.MidiCiPropertyDataMessage(32, 64).init(
            .get_reply,
            2,
            ci_responder_participant.muid,
            ci_initiator.muid,
            installed_get.request_id,
            "{\"status\":200}",
            1,
            1,
            "{\"manufacturer\":\"Installed\"}",
        ),
    );
    try std.testing.expectEqualDeep(
        @TypeOf(ci_device.pending_properties[installed_get.request_id]){},
        ci_device.pending_properties[installed_get.request_id],
    );
    try std.testing.expectEqualStrings(
        "{\"manufacturer\":\"Installed\"}",
        (try ci_device.cachedProperty(
            remote_handle,
            "DeviceInfo",
            null,
        )).data,
    );
    var installed_cache_snapshot: [128]u8 = undefined;
    const installed_cache_bytes =
        try ci_device.writePropertyCacheSnapshot(&installed_cache_snapshot);
    try std.testing.expectEqual(
        try ci_device.propertyCacheSnapshotSize(),
        installed_cache_bytes.len,
    );
    ci_device.clearPropertyCache();
    try ci_device.restorePropertyCacheSnapshot(installed_cache_bytes);
    try std.testing.expectEqualStrings(
        "{\"manufacturer\":\"Installed\"}",
        (try ci_device.cachedProperty(
            remote_handle,
            "DeviceInfo",
            null,
        )).data,
    );

    var installed_property_delegate = InstalledPropertyDelegate{};
    var installed_property_host =
        try ci_device.propertyHost(&installed_property_delegate);
    const installed_host_reply = try installed_property_host.accept(
        std.testing.allocator,
        try plugin.process.MidiCiPropertyDataMessage(32, 64).init(
            .get,
            2,
            ci_responder_participant.muid,
            ci_initiator.muid,
            7,
            "{\"resource\":\"LocalState\"}",
            1,
            1,
            &.{},
        ),
    );
    try std.testing.expectEqualStrings(
        "{\"active\":true}",
        installed_host_reply.reply.data(),
    );
    const deterministic_property_message =
        try plugin.process.MidiCiPropertyDataMessage(32, 64).init(
            .notify,
            2,
            ci_responder_participant.muid,
            ci_initiator.muid,
            8,
            "{}",
            1,
            1,
            "ok",
        );
    for (deterministic_property_message.header_storage[2..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (deterministic_property_message.data_storage[2..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    var deterministic_reassembly =
        plugin.process.MidiCiPropertyReassembler(32, 64){};
    _ = try deterministic_reassembly.push(deterministic_property_message);
    deterministic_reassembly.reset();
    for (deterministic_reassembly.header_storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (deterministic_reassembly.data_storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);

    const device_cleanup =
        (try ci_device.acceptInvalidation(ci_invalidation)).remote;
    try std.testing.expectEqual(@as(usize, 1), device_cleanup.remotes);
    try std.testing.expectEqual(@as(usize, 1), device_cleanup.cached_properties);
    try std.testing.expectEqualDeep(
        @TypeOf(ci_device.remotes[remote_handle]){},
        ci_device.remotes[remote_handle],
    );

    const InstalledPropertyCache =
        plugin.process.MidiCiPropertyRemoteCache(2, 36, 36, 64);
    var property_cache = InstalledPropertyCache{};
    const cache_key = plugin.process.MidiCiPropertyCacheKey{
        .remote = ci_responder_participant.muid,
        .resource = "DeviceInfo",
    };
    const cache_index =
        try property_cache.put(cache_key, "{\"manufacturer\":\"Example\"}");
    const installed_cache_slot = property_cache.slots[cache_index];
    for (installed_cache_slot.resource_storage[installed_cache_slot.resource_count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (installed_cache_slot.res_id_storage[installed_cache_slot.res_id_count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (installed_cache_slot.data_storage[installed_cache_slot.data_count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectEqualStrings(
        "{\"manufacturer\":\"Example\"}",
        (try property_cache.get(cache_key)).data,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        property_cache.releaseRemote(ci_responder_participant.muid),
    );
    try std.testing.expectEqualDeep(
        @TypeOf(property_cache.slots[cache_index]){},
        property_cache.slots[cache_index],
    );

    const endpoint_information_transaction =
        try plugin.process.MidiCiEndpointInformationTransaction.init(
            ci_initiator.muid,
            ci_responder_participant.muid,
        );
    const endpoint_information_responder =
        try plugin.process.MidiCiEndpointInformationResponder.init(
            ci_responder_participant.muid,
            try plugin.process.MidiCiProductInstanceId.init("INSTALLED-1"),
        );
    const endpoint_information_reply_message =
        try endpoint_information_responder.handle(
            endpoint_information_transaction.inquiry(),
        );
    const endpoint_information_reply =
        try endpoint_information_transaction.accept(
            endpoint_information_reply_message,
        );
    try std.testing.expectEqual(@as(usize, 11), endpoint_information_reply
        .product_instance_id.text().len);

    const ci_ack = plugin.process.MidiCiAcknowledgement{
        .kind = .ack,
        .source = ci_responder_participant.muid,
        .destination = ci_initiator.muid,
        .original_sub_id = 0x72,
        .message = try plugin.process.MidiCiMessageText.init("accepted"),
    };
    var ci_ack_storage: [126]u8 = undefined;
    const ci_ack_bytes = try ci_ack.encode(&ci_ack_storage);
    try std.testing.expectEqualDeep(
        ci_ack,
        try plugin.process.MidiCiAcknowledgement.parse(ci_ack_bytes),
    );

    const process_inquiry_transaction =
        try plugin.process.MidiCiProcessInquiryTransaction.init(
            ci_initiator.muid,
            ci_responder_participant.muid,
        );
    const process_inquiry_responder =
        try plugin.process.MidiCiProcessInquiryResponder.init(
            ci_responder_participant.muid,
            .{ .midi_message_report = true },
        );
    const process_inquiry_reply_message =
        try process_inquiry_responder.handle(
            process_inquiry_transaction.inquiry(),
        );
    const process_inquiry_reply =
        try process_inquiry_transaction.accept(
            process_inquiry_reply_message,
        );
    try std.testing.expect(
        process_inquiry_reply.features.midi_message_report,
    );

    const report_inquiry = plugin.process.MidiCiMessageReportInquiry{
        .source = ci_initiator.muid,
        .destination = ci_responder_participant.muid,
        .data_control = .capability_only,
        .requests = .{
            .channel = .{ .control_change = true },
            .note = .{ .notes = true },
        },
    };
    var report_transaction =
        try plugin.process.MidiCiMessageReportTransaction.init(
            report_inquiry,
        );
    const report_responder =
        try plugin.process.MidiCiMessageReportResponder.init(
            ci_responder_participant.muid,
            .{ .channel = .{ .control_change = true } },
        );
    const report_begin =
        try report_responder.begin(report_transaction.inquiry());
    const report_reply = try report_transaction.acceptBegin(report_begin);
    try std.testing.expect(report_reply.requests.channel.control_change);
    try std.testing.expect(!report_reply.requests.note.notes);
    try report_transaction.acceptEnd(
        try report_responder.end(report_inquiry),
    );

    const InstalledProfileList = plugin.process.MidiCiProfileList(4);
    const InstalledProfileReply = plugin.process.MidiCiProfileReply(4);
    const profile = plugin.process.MidiCiProfileId.standard(0, 1, 1, 0);
    var profile_inquiry =
        try plugin.process.MidiCiProfileInquiryTransaction.init(.{
            .source = ci_initiator.muid,
            .destination = ci_responder_participant.muid,
        });
    try std.testing.expect(try profile_inquiry.accept(
        InstalledProfileReply{
            .source = ci_responder_participant.muid,
            .destination = ci_initiator.muid,
            .enabled = try InstalledProfileList.init(&.{profile}),
            .disabled = try InstalledProfileList.init(&.{}),
        },
    ));
    const installed_profile_list = try InstalledProfileList.init(&.{profile});
    for (installed_profile_list.storage[1..]) |item|
        try std.testing.expectEqual(
            @as([5]u7, @splat(0)),
            item.bytes,
        );
    var profile_set = try plugin.process.MidiCiProfileSetTransaction.init(.{
        .kind = .off,
        .source = ci_initiator.muid,
        .destination = ci_responder_participant.muid,
        .profile = profile,
    });
    try std.testing.expect(try profile_set.accept(.{
        .kind = .disabled,
        .source = ci_responder_participant.muid,
        .profile = profile,
    }));
    const InstalledDetailsReply =
        plugin.process.MidiCiProfileDetailsReply(4);
    var profile_details =
        try plugin.process.MidiCiProfileDetailsTransaction.init(.{
            .address = .{ .channel = 0 },
            .source = ci_initiator.muid,
            .destination = ci_responder_participant.muid,
            .profile = profile,
            .target = 0,
        });
    const profile_details_reply = try InstalledDetailsReply.init(
        .{ .channel = 0 },
        ci_responder_participant.muid,
        ci_initiator.muid,
        profile,
        0,
        &.{ 1, 0, 8, 0 },
    );
    try profile_details.accept(profile_details_reply);
    try std.testing.expectEqualDeep(
        plugin.process.MidiCiProfileChannelCountDetails{
            .active = 1,
            .maximum = 8,
        },
        try plugin.process.MidiCiProfileChannelCountDetails.parse(
            profile_details_reply.data(),
        ),
    );
    const InstalledProfileData =
        plugin.process.MidiCiProfileSpecificData(8);
    const profile_data = try InstalledProfileData.init(
        .{ .channel = 0 },
        2,
        ci_initiator.muid,
        ci_responder_participant.muid,
        profile,
        &.{ 1, 2, 3 },
    );
    var profile_data_storage: [25]u8 = undefined;
    const profile_data_bytes =
        try profile_data.encode(&profile_data_storage);
    const parsed_profile_data =
        try InstalledProfileData.parse(profile_data_bytes);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3 },
        parsed_profile_data.data(),
    );
    for (profile_data.storage[3..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (parsed_profile_data.storage[3..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    const property_transaction =
        try plugin.process.MidiCiPropertyCapabilitiesTransaction.init(.{
            .source = ci_initiator.muid,
            .destination = ci_responder_participant.muid,
            .simultaneous_requests = 2,
        });
    const property_responder =
        try plugin.process.MidiCiPropertyCapabilitiesResponder.init(.{
            .source = ci_responder_participant.muid,
            .destination = ci_initiator.muid,
            .simultaneous_requests = 1,
        });
    var property_storage: [16]u8 = undefined;
    const property_inquiry_bytes =
        try property_transaction.inquiry().encode(&property_storage);
    const property_reply = try property_responder.handle(
        try plugin.process.MidiCiPropertyCapabilitiesMessage.parse(
            property_inquiry_bytes,
        ),
    );
    const property_reply_bytes =
        try property_reply.encode(&property_storage);
    const property_agreement = try property_transaction.accept(
        try plugin.process.MidiCiPropertyCapabilitiesMessage.parse(
            property_reply_bytes,
        ),
    );
    try std.testing.expectEqual(
        @as(u7, 1),
        property_agreement.simultaneous_requests,
    );
    const InstalledPropertyData =
        plugin.process.MidiCiPropertyDataMessage(32, 32);
    const property_get = try InstalledPropertyData.init(
        .get,
        2,
        ci_initiator.muid,
        ci_responder_participant.muid,
        1,
        &.{ 0x7B, 0x7D },
        1,
        1,
        &.{},
    );
    var property_data_storage: [86]u8 = undefined;
    const property_get_bytes =
        try property_get.encode(&property_data_storage);
    const parsed_property_get =
        try InstalledPropertyData.parse(property_get_bytes);
    try std.testing.expectEqual(
        plugin.process.MidiCiPropertyDataKind.get,
        parsed_property_get.kind,
    );
    const InstalledPropertyReassembler =
        plugin.process.MidiCiPropertyReassembler(32, 32);
    var property_reassembler = InstalledPropertyReassembler{};
    try std.testing.expectEqual(
        plugin.process.MidiCiPropertyChunkResult.complete,
        try property_reassembler.push(parsed_property_get),
    );
    property_reassembler.declared_total = 0;
    try std.testing.expect(!property_reassembler.valid());
    try std.testing.expectEqual(@as(usize, 0), property_reassembler.header().len);
    try std.testing.expectError(
        error.InvalidMidiCiPropertyReassemblyState,
        property_reassembler.push(parsed_property_get),
    );
    property_reassembler.declared_total = 1;
    try property_reassembler.validate();
    const InstalledPropertyRequestIds =
        plugin.process.MidiCiPropertyRequestIds(2);
    var property_request_ids = InstalledPropertyRequestIds{};
    const property_request_id = try property_request_ids.acquire();
    try property_request_ids.release(property_request_id);
    property_request_ids.next = 2;
    try std.testing.expect(!property_request_ids.valid());
    try std.testing.expectEqual(@as(usize, 0), property_request_ids.count());
    try std.testing.expectError(
        error.InvalidMidiCiPropertyRequestIdsState,
        property_request_ids.acquire(),
    );
    property_request_ids.next = 0;
    try std.testing.expect(property_request_ids.valid());
    const InstalledPropertyInitiator =
        plugin.process.MidiCiPropertyInitiator(2, 32, 32);
    const InstalledPropertyResponder =
        plugin.process.MidiCiPropertyResponder(2, 32, 32);
    var property_initiator = try InstalledPropertyInitiator.init(
        ci_initiator.muid,
        2,
    );
    try property_initiator.validate();
    property_initiator.request_ids.next = 2;
    try std.testing.expect(!property_initiator.valid());
    try std.testing.expectEqual(@as(usize, 0), property_initiator.activeCount());
    property_initiator.request_ids.next = 0;
    try property_initiator.validate();
    var property_data_responder = try InstalledPropertyResponder.init(
        ci_responder_participant.muid,
    );
    try property_data_responder.validate();
    property_data_responder.source = plugin.process.midi_ci.Muid.broadcast();
    try std.testing.expect(!property_data_responder.valid());
    property_data_responder.source = ci_responder_participant.muid;
    try property_data_responder.validate();
    const session_get = try property_initiator.begin(
        .get,
        ci_responder_participant.muid,
        "{\"resource\":\"DeviceInfo\"}",
        1,
        &.{},
    );
    const session_handle = switch (try property_data_responder.push(session_get)) {
        .complete => |value| value,
        else => return error.UnexpectedPropertySessionResult,
    };
    const session_reply = try property_data_responder.reply(
        session_handle,
        "{\"status\":200}",
        1,
        "{}",
    );
    switch (try property_initiator.accept(session_reply)) {
        .complete => {},
        else => return error.UnexpectedPropertySessionResult,
    }
    try std.testing.expectEqualSlices(
        u8,
        "{}",
        (try property_initiator.response(session_get.request_id)).data(),
    );
    try property_initiator.release(session_get.request_id);
    const InstalledSubscriptionRegistry =
        plugin.process.MidiCiPropertySubscriptionRegistry(2);
    var subscriptions = InstalledSubscriptionRegistry{};
    for (subscriptions.entries) |entry|
        try std.testing.expectEqualDeep(@TypeOf(entry){}, entry);
    const subscription_handle = try subscriptions.register(
        ci_responder_participant.muid,
        "ChannelList",
        "sub_1",
    );
    const installed_subscription = subscriptions.entries[subscription_handle];
    for (installed_subscription.resource_storage[installed_subscription.resource_count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (installed_subscription.id_storage[installed_subscription.id_count..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectEqualStrings(
        "ChannelList",
        (try subscriptions.get(subscription_handle)).resource,
    );
    subscriptions.entries[subscription_handle].resource_storage[0] = '_';
    try std.testing.expect(!subscriptions.valid());
    try std.testing.expectError(
        error.InvalidMidiCiPropertySubscriptionState,
        subscriptions.get(subscription_handle),
    );
    subscriptions.entries[subscription_handle].resource_storage[0] = 'C';
    try subscriptions.validate();
    try subscriptions.release(subscription_handle);
    try std.testing.expectEqualDeep(
        @TypeOf(subscriptions.entries[subscription_handle]){},
        subscriptions.entries[subscription_handle],
    );

    const property_header = plugin.process.MidiCiPropertyRequestHeader{
        .resource = "ChannelList",
        .pagination = .{ .offset = 0, .limit = 16 },
    };
    var property_json: std.Io.Writer.Allocating =
        .init(std.testing.allocator);
    defer property_json.deinit();
    try property_header.writeJson(&property_json.writer);
    const parsed_property_header =
        try plugin.process.MidiCiPropertyRequestHeader.parseJson(
            std.testing.allocator,
            property_json.written(),
        );
    defer parsed_property_header.deinit();
    try std.testing.expectEqualStrings(
        "ChannelList",
        parsed_property_header.value.resource,
    );

    const channels = [_]plugin.process.MidiCiPropertyChannel{.{
        .title = "Main",
        .channel = 1,
        .bank_program = .{ 0, 0, 4 },
    }};
    const channel_list = plugin.process.MidiCiPropertyChannelList{
        .entries = &channels,
    };
    property_json.clearRetainingCapacity();
    try channel_list.writeJson(&property_json.writer);
    const parsed_channel_list =
        try plugin.process.MidiCiPropertyChannelList.parseJson(
            std.testing.allocator,
            property_json.written(),
        );
    defer parsed_channel_list.deinit();
    try std.testing.expectEqual(
        @as(u16, 1),
        parsed_channel_list.value.entries[0].channel,
    );

    const categories = [_][]const u8{"Keyboard"};
    const programs = [_]plugin.process.MidiCiPropertyProgram{.{
        .title = "Concert Grand",
        .bank_program = .{ 0, 0, 0 },
        .categories = &categories,
    }};
    const program_list = plugin.process.MidiCiPropertyProgramList{
        .entries = &programs,
    };
    property_json.clearRetainingCapacity();
    try program_list.writeJson(&property_json.writer);
    const parsed_program_list =
        try plugin.process.MidiCiPropertyProgramList.parseJson(
            std.testing.allocator,
            property_json.written(),
        );
    defer parsed_program_list.deinit();
    try std.testing.expectEqualStrings(
        "Concert Grand",
        parsed_program_list.value.entries[0].title,
    );

    const resources = [_]plugin.process.MidiCiPropertyResource{
        .{ .resource = "DeviceInfo" },
        .{ .resource = "ChannelList", .can_subscribe = true },
        plugin.process.midi_ci_property_program_list_resource,
    };
    const resource_list = plugin.process.MidiCiPropertyResourceList{
        .entries = &resources,
    };
    property_json.clearRetainingCapacity();
    try resource_list.writeJson(&property_json.writer);
    const parsed_resource_list =
        try plugin.process.MidiCiPropertyResourceList.parseJson(
            std.testing.allocator,
            property_json.written(),
        );
    defer parsed_resource_list.deinit();
    try std.testing.expect(
        parsed_resource_list.value.entries[1].can_subscribe,
    );

    const modes = [_]plugin.process.MidiCiPropertyMode{.{
        .mode_id = "multi_channel",
        .title = "Multi Channel",
    }};
    property_json.clearRetainingCapacity();
    try (plugin.process.MidiCiPropertyModeList{
        .entries = &modes,
    }).writeJson(&property_json.writer);
    const parsed_modes = try plugin.process.MidiCiPropertyModeList.parseJson(
        std.testing.allocator,
        property_json.written(),
    );
    defer parsed_modes.deinit();
    try std.testing.expectEqualStrings(
        "multi_channel",
        parsed_modes.value.entries[0].mode_id,
    );

    const controller_index = [_]u7{74};
    const controllers = [_]plugin.process.MidiCiPropertyController{.{
        .title = "Brightness",
        .controller_type = .cc,
        .controller_index = &controller_index,
        .type_hint = .continuous,
    }};
    property_json.clearRetainingCapacity();
    try (plugin.process.MidiCiPropertyChannelControllerList{
        .entries = &controllers,
    }).writeJson(&property_json.writer);
    const parsed_controllers =
        try plugin.process.MidiCiPropertyChannelControllerList.parseJson(
            std.testing.allocator,
            property_json.written(),
        );
    defer parsed_controllers.deinit();
    try std.testing.expectEqual(
        plugin.process.MidiCiPropertyControllerType.cc,
        parsed_controllers.value.entries[0].controller_type,
    );

    var encoded_property: [9]u8 = undefined;
    var decoded_property: [8]u8 = undefined;
    const encoded_property_bytes =
        try plugin.process.MidiCiPropertyMcoded7.encode(
            &.{ 0x80, 0x7f, 0xff },
            &encoded_property,
        );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x80, 0x7f, 0xff },
        try plugin.process.MidiCiPropertyMcoded7.decode(
            encoded_property_bytes,
            &decoded_property,
        ),
    );
    var compressed_property: [64]u8 = undefined;
    var compression_work: [plugin.process.MidiCiPropertyZlibMcoded7.work_buffer_length]u8 =
        undefined;
    var compressed_encoded_property: [80]u8 = undefined;
    var compressed_staging_property: [16]u8 = undefined;
    var compressed_decoded_property: [16]u8 = undefined;
    const compressed_property_bytes =
        try plugin.process.MidiCiPropertyZlibMcoded7.encode(
            "property",
            &compressed_property,
            &compression_work,
            &compressed_encoded_property,
        );
    try std.testing.expectEqualStrings(
        "property",
        try plugin.process.MidiCiPropertyZlibMcoded7.decode(
            compressed_property_bytes,
            &compressed_property,
            &compression_work,
            &compressed_staging_property,
            &compressed_decoded_property,
        ),
    );
}

test "installed package exposes toolkit-neutral GUI models" {
    const range = try plugin.gui_graph.Range.init(0.0, 1.0);
    const Envelope = plugin.gui_graph.EditableEnvelope(4);
    var envelope = try Envelope.init(range, range, .{}, &.{
        .{ .id = 1, .position = .{ .x = 0.0, .y = 0.0 } },
        .{ .id = 2, .position = .{ .x = 1.0, .y = 1.0 } },
    });
    try std.testing.expectEqualDeep(
        plugin.gui_graph.EditablePoint{},
        envelope.points[2],
    );
    for (envelope.transaction_points) |point|
        try std.testing.expectEqualDeep(plugin.gui_graph.EditablePoint{}, point);
    try envelope.begin();
    _ = try envelope.add(.{ .x = 0.5, .y = 0.25 });
    envelope.finish();
    try std.testing.expect(envelope.valid());
    for (envelope.transaction_points) |point|
        try std.testing.expectEqualDeep(plugin.gui_graph.EditablePoint{}, point);
    var malformed_envelope = envelope;
    malformed_envelope.points[1].position.x = std.math.nan(f64);
    try std.testing.expect(!malformed_envelope.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_envelope.slice().len,
    );

    const Series = plugin.gui_graph.FixedSeries(3);
    var series = try Series.init(&.{
        .{ .x = 0.0, .y = 1.0 },
        .{ .x = 1.0, .y = 0.0 },
    });
    try std.testing.expectEqualDeep(plugin.gui_graph.Point{}, series.points[2]);
    series.points[0].y = std.math.inf(f64);
    try std.testing.expect(!series.valid());
    try std.testing.expectEqual(@as(usize, 0), series.slice().len);

    var snapshot_series = plugin.gui_graph.SnapshotSeries(2).init();
    snapshot_series.editorOpened();
    try std.testing.expect(snapshot_series.publish(&.{.{
        .x = 0.25,
        .y = 0.75,
    }}));
    var snapshot_points: [2]plugin.gui_graph.Point = undefined;
    snapshot_series.points[0].y.bits.store(
        @bitCast(std.math.inf(f64)),
        .release,
    );
    try std.testing.expect(snapshot_series.read(&snapshot_points) == null);
    snapshot_series.points[0].y.store(0.75);
    try std.testing.expectEqual(
        @as(?usize, 1),
        snapshot_series.read(&snapshot_points),
    );

    var stored_envelope = try plugin.editor_state.Envelope.init(&.{.{
        .id = 1,
        .x = 0.5,
        .y = 0.25,
    }});
    stored_envelope.points[0].x = std.math.nan(f64);
    try std.testing.expect(!stored_envelope.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        stored_envelope.slice().len,
    );
    try std.testing.expectError(
        error.InvalidEditorStateTextEncoding,
        plugin.editor_state.Text.init(&.{ 0xc3, 0x28 }),
    );
    const unicode_text = try plugin.editor_state.Text.init("Hall \xe2\x98\x83");
    try std.testing.expect(unicode_text.valid());

    const viewport_config = plugin.gui_viewport.Config{ .initial_zoom = 2.0 };
    var viewport = try plugin.gui_viewport.State.init(viewport_config);
    try std.testing.expect(viewport.zoomIn(viewport_config, 0.5, 0.5));
    try std.testing.expect(viewport.valid(viewport_config));
    try std.testing.expectEqual(
        @as(f64, 0.0),
        viewport.project(
            viewport_config,
            std.math.floatMax(f64),
            true,
        ),
    );

    const selection_config = plugin.gui_range_selection.Config{
        .minimum = 0.0,
        .maximum = 1.0,
        .initial_start = 0.2,
        .initial_end = 0.8,
        .minimum_span = 0.1,
        .step = 0.01,
    };
    var selection = try plugin.gui_range_selection.State.init(selection_config);
    try std.testing.expect(selection.set(selection_config, .start, 0.3));
    try std.testing.expect(selection.valid(selection_config));
    try std.testing.expectError(
        error.InvalidRangeSelectionBounds,
        (plugin.gui_range_selection.Config{
            .minimum = -std.math.floatMax(f64),
            .maximum = std.math.floatMax(f64),
            .initial_start = -1.0,
            .initial_end = 1.0,
            .step = 1.0,
        }).validate(),
    );

    const Presets = plugin.gui_preset_browser.Browser(3);
    var presets = Presets{};
    for (presets.presets) |preset|
        try std.testing.expectEqualDeep(plugin.gui_preset_browser.Preset{}, preset);
    try presets.add(try plugin.gui_preset_browser.Preset.init(1, "Clean"));
    try presets.add(try plugin.gui_preset_browser.Preset.init(2, "Driven"));
    try std.testing.expectEqualDeep(
        plugin.gui_preset_browser.Preset{},
        presets.presets[2],
    );
    try presets.setSearch("drive");
    try std.testing.expectEqual(@as(usize, 1), presets.matchingCount());

    const PresetState = plugin.editor_state.Store(1, &.{
        .{ .id = 1, .default = .{ .text = plugin.editor_state.Text{} } },
        .{ .id = 2, .default = .{ .index = 0 } },
    });
    var preset_state = PresetState.init();
    try preset_state.set(1, .{
        .text = try plugin.editor_state.Text.init("clean"),
    });
    try preset_state.setUnsigned(2, 99);
    _ = try presets.beginLoad();
    try presets.restore(&preset_state, .{ .search = 1, .selection = 2 });
    try std.testing.expectEqualStrings("clean", presets.search.slice());
    try std.testing.expectEqual(@as(?u32, 1), presets.selected_id);
    try std.testing.expectEqual(
        plugin.gui_preset_browser.LoadStatus.idle,
        presets.load_status,
    );

    const DropZone = plugin.gui_file_drop.DropZone(2, 1);
    var drop_zone = try DropZone.init(&.{".wav"});
    try std.testing.expectEqual(
        plugin.gui_file_drop.Status.acceptable,
        drop_zone.inspect(&.{"/samples/kick.wav"}),
    );
    for (drop_zone.paths[0].bytes[drop_zone.paths[0].len..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    try std.testing.expectEqualDeep(plugin.gui_file_drop.Path{}, drop_zone.paths[1]);
    drop_zone.reset();
    for (drop_zone.paths) |path|
        try std.testing.expectEqualDeep(plugin.gui_file_drop.Path{}, path);

    const reference = try plugin.resource.Reference(64, 32).init(
        "/models/example.nam",
        plugin.resource.Identity.fromBytes("fixture"),
        1,
        "Linear",
    );
    try std.testing.expect(reference.valid());
    for (reference.path.bytes[reference.path.length..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (reference.metadata.bytes[reference.metadata.length..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    const reference_state = plugin.resource.ReferenceState(64, 32){ .linked = reference };
    try std.testing.expect(reference_state.valid());
    try std.testing.expectEqual(
        plugin.resource.RecoveryStatus.ready,
        reference.classifyCandidate("/models/example.nam", plugin.resource.Identity.fromBytes("fixture")),
    );
}

test "installed package exposes bounded realtime models" {
    const Piano = plugin.gui_piano.Keyboard(24);
    var piano = try Piano.init(48, 24);
    _ = try piano.press(60, 0.75);
    try std.testing.expect(piano.valid());
    piano.active[0] |= @as(u64, 1) << 47;
    try std.testing.expect(!piano.valid());
    try std.testing.expectError(error.InvalidState, piano.release(60));
    piano.active[0] = @as(u64, 1) << 60;
    try std.testing.expect(piano.valid());

    const Sequencer = plugin.gui_step_sequencer.Sequencer(8);
    var sequencer = try Sequencer.init(8, 0b0101, 0b0001);
    try std.testing.expect(sequencer.moveCursor(.next, false));
    try std.testing.expect(sequencer.valid());

    var output_samples = [_]f32{ 0.0, 0.0 };
    const output_channels = [_][]f32{&output_samples};
    const outputs = try plugin.process.AudioOutputs(f32).init(&output_channels);
    try std.testing.expect(outputs.valid());
    outputs.fill(0.25);
    try std.testing.expectEqual(@as(f32, 0.25), output_samples[1]);

    var event_storage: [2]plugin.process.Event = undefined;
    var event_writer = plugin.process.EventWriter.init(&event_storage, 2);
    try event_writer.append(plugin.process.Event.noteOn(0, 0, 60, 1.0));
    try std.testing.expect(event_writer.valid());
    event_writer.count = std.math.maxInt(usize);
    try std.testing.expect(!event_writer.valid());
    try std.testing.expectEqual(@as(usize, 0), event_writer.eventCount());
    try std.testing.expectEqual(@as(usize, 0), event_writer.frameCount());
    var invalid_event_segments = event_writer.blockSegments();
    try std.testing.expectEqual(@as(?plugin.process.BlockSegment, null), invalid_event_segments.next());

    var player: plugin.gui_sample_player.Player(2, 1) = .{};
    try player.store.begin(.{ .generation = 1, .sample_rate = 48_000, .channels = 1, .frames = 2 });
    try player.store.write(1, 0, &.{ 0.5, 1.0 });
    try player.store.commit(1);
    try std.testing.expect(player.adoptPending());
    player.noteOn(60, 1.0, .{ .envelope = .{ .attack_seconds = 0.0, .sustain = 1.0 } });
    try std.testing.expectEqual(@as(f32, 0.5), player.processFrame(.{ .envelope = .{ .attack_seconds = 0.0, .sustain = 1.0 } })[0]);
    player.voices[0].level = std.math.floatMax(f64);
    try std.testing.expectEqual(
        @as([2]f32, .{ 0.0, 0.0 }),
        player.processFrame(.{}),
    );
    try std.testing.expectEqual(@as(?f64, null), player.playhead());
}
