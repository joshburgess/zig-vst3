const core = @import("zig-vst3-plugin-core");
const vst3 = @import("zig-vst3");
const ara = @import("zig-vst3-ara");
const core_audio = @import("zig-vst3-coreaudio");
const core_midi = @import("zig-vst3-coremidi");
const wasapi = @import("zig-vst3-wasapi");
const alsa = @import("zig-vst3-alsa");
const alsa_midi = @import("zig-vst3-alsamidi");
const alsa_ump = @import("zig-vst3-alsaump");
const win_midi = @import("zig-vst3-winmidi");
const win_ump = @import("zig-vst3-winump");
const win_window = @import("zig-vst3-winwindow");
const cocoa_window = @import("zig-vst3-cocoawindow");
const x11_window = @import("zig-vst3-x11window");
const wayland_window = @import("zig-vst3-waylandwindow");
const std = @import("std");

test "installed core package exposes grouped MIDI protocol modules" {
    try std.testing.expect(
        core.process.midi.protocol_1.Message ==
            core.process.Midi1Message,
    );
    try std.testing.expect(
        core.process.midi.protocol_2.ChannelMessage ==
            core.process.Midi2ChannelMessage,
    );
    try std.testing.expect(
        core.process.midi.ump.Packet ==
            core.process.UmpPacket,
    );
    try std.testing.expect(
        core.process.midi.ci.device.Device ==
            core.process.MidiCiDevice,
    );
    try std.testing.expect(
        core.process.midi.ci.property.session.Initiator ==
            core.process.MidiCiPropertyInitiator,
    );
    try std.testing.expect(
        core.process.midi.expression.instrument.Instrument ==
            core.process.MpeInstrument,
    );
}

test "installed core package exposes format-neutral processor and editor contracts" {
    try std.testing.expect(@hasDecl(core.plugin, "ProcessorRuntime"));
    try std.testing.expect(@hasDecl(core.plugin, "OfflineRenderer"));
    try std.testing.expect(@hasDecl(core.audio_unit, "RenderAdapter"));
    try std.testing.expect(
        @hasDecl(core.audio_unit_v2, "AudioComponentPlugInInterface"),
    );
    try std.testing.expect(
        @hasDecl(core.audio_unit_v2, "RenderPropertyAdapter"),
    );
    try std.testing.expect(
        @hasDecl(core.audio_unit_v2, "ComponentFactory"),
    );
    try std.testing.expect(
        @hasDecl(core.audio_unit_v2, "AURenderCallbackStruct"),
    );
    try std.testing.expect(
        @hasDecl(core.audio_unit_v2, "AudioTimeStamp"),
    );
    try std.testing.expect(
        @hasDecl(core.audio_unit_v2, "AudioUnitParameterInfo"),
    );
    try std.testing.expect(
        @hasDecl(core.audio_unit_v2, "AudioUnitParameterEvent"),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        core.audio_unit_v2.timestamp_flag.sample_time_valid,
    );
    try std.testing.expectEqual(
        @as(i16, 0x000e),
        core.audio_unit_v2.selector.render,
    );
    try std.testing.expectEqual(
        @as(i16, 0x0006),
        core.audio_unit_v2.selector.get_parameter,
    );
    try std.testing.expect(@hasDecl(core.plugin, "HostChange"));
    try std.testing.expectEqual(
        @as(u4, 11),
        @intFromEnum(core.plugin.HostChange.parameter_id_mapping),
    );
    try std.testing.expect(@hasDecl(core_audio, "Backend"));
    try std.testing.expect(@hasDecl(core_audio, "CallbackStatistics"));
    try std.testing.expect(@hasDecl(core_audio, "DeviceRuntimeInfo"));
    try std.testing.expect(
        @hasDecl(core_audio.Backend(f32), "failureSource"),
    );
    try std.testing.expect(
        @hasDecl(core_audio.Backend(f32), "startSplit"),
    );
    try std.testing.expect(
        @hasDecl(core_audio, "DirectionalDeviceFailures"),
    );
    try std.testing.expect(@hasDecl(core_midi, "Backend"));
    try std.testing.expect(@hasDecl(core_midi, "InputStatistics"));
    try std.testing.expect(@hasDecl(alsa_ump, "Backend"));
    try std.testing.expect(@hasDecl(alsa_ump, "InputStatistics"));
    try std.testing.expect(@hasDecl(wasapi, "Backend"));
    try std.testing.expect(@hasDecl(wasapi, "Statistics"));
    try std.testing.expect(
        @hasDecl(wasapi.Backend(f32), "startSplit"),
    );
    try std.testing.expect(@hasDecl(alsa, "Backend"));
    try std.testing.expect(@hasDecl(alsa, "Statistics"));
    try std.testing.expect(
        @hasDecl(alsa.Backend(f32), "startSplit"),
    );
    try std.testing.expect(@hasDecl(alsa_midi, "Backend"));
    try std.testing.expect(@hasDecl(alsa_midi, "InputStatistics"));
    try std.testing.expect(@hasDecl(win_midi, "Backend"));
    try std.testing.expect(@hasDecl(win_midi, "InputStatistics"));
    try std.testing.expect(@hasDecl(win_ump, "Backend"));
    try std.testing.expect(@hasDecl(win_ump, "InputStatistics"));
    try std.testing.expect(@hasDecl(win_ump, "OutputStatistics"));
    try std.testing.expect(@hasDecl(win_window, "Backend"));
    try std.testing.expect(@hasDecl(cocoa_window, "Backend"));
    try std.testing.expect(@hasDecl(x11_window, "Backend"));
    try std.testing.expect(@hasDecl(wayland_window, "Backend"));
    try std.testing.expect(
        @hasDecl(
            vst3.vst_wayland_standalone_frame,
            "StandaloneBridge",
        ),
    );
    try std.testing.expect(
        @hasDecl(vst3.vstgui_lv2_backend, "Backend"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_vst3, "IPlugInEntryPoint2"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_model, "Document"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_document_controller, "Controller"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_extension, "Extension"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_playback_renderer, "Renderer"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_content_fades, "Analyzer"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_tempo_warp, "Builder"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_playback_renderer, "FadeDescription"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_playback_renderer, "FadeCurve"),
    );
    try std.testing.expectEqual(
        vst3.ara_playback_renderer.Interpolation.windowed_sinc_8,
        .windowed_sinc_8,
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_source_cache, "Cache"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_source_cache, "PagedCache"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_tuning_analysis, "Analyzer"),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_music_analysis, "Analyzer"),
    );
    try std.testing.expect(
        @hasDecl(
            vst3.ara_tuning_analysis,
            "detectEqualTemperament",
        ),
    );
    try std.testing.expect(
        @hasDecl(
            vst3.ara_tuning_analysis,
            "detectTempoEnvelope",
        ),
    );
    const InstalledAraController =
        vst3.ara_document_controller.Controller(.{});
    const InstalledTuningAnalyzer =
        vst3.ara_tuning_analysis.Analyzer(
            InstalledAraController,
            .{
                .sources = 1,
                .channels = 1,
                .frames = 64,
            },
        );
    try std.testing.expectEqual(
        @as(usize, 2),
        InstalledTuningAnalyzer.processing_algorithm_count,
    );
    try std.testing.expect(
        @hasDecl(
            vst3.ara_registration,
            "MainFactoryRegistration",
        ),
    );
    try std.testing.expect(
        @hasDecl(
            vst3.ara_registration,
            "appendMainFactoryClass",
        ),
    );
    try std.testing.expect(
        @hasDecl(vst3.ara_factory, "Factory"),
    );
    try std.testing.expectEqual(
        @as(ara.raw.ARAAPIGeneration, 6),
        ara.current_generation,
    );
    try std.testing.expect(
        @hasDecl(core.plugin, "DeviceRecoveryController"),
    );
    try std.testing.expect(
        @hasDecl(core.plugin, "DeviceRecoveryCallback"),
    );
    try std.testing.expect(
        @hasDecl(core.plugin, "DeviceFailureSource"),
    );
    try std.testing.expect(
        @hasDecl(core.plugin, "DeviceFailureMonitor"),
    );
    try std.testing.expect(
        @hasDecl(core.plugin, "StandaloneShell"),
    );
    try std.testing.expect(
        @hasDecl(
            core.plugin.StandaloneShell(1),
            "setDeviceFailureSource",
        ),
    );
    try std.testing.expect(
        @hasDecl(core.plugin, "StandaloneWindowBackend"),
    );
    try std.testing.expect(@hasDecl(core.gui, "Editor"));
    try std.testing.expect(@hasDecl(core.gui, "Context"));
    try std.testing.expect(@hasDecl(core.gui, "Adapter"));
    try std.testing.expect(@hasDecl(core.lv2, "ui"));
    try std.testing.expect(@hasDecl(core.lv2.ui, "Descriptor"));
    try std.testing.expect(@hasDecl(core.lv2.ui, "Adapter"));
    try std.testing.expect(@hasDecl(core.lv2, "StatePathFeatures"));
    try std.testing.expect(@hasDecl(core.lv2, "OwnedStatePath"));
    try std.testing.expect(@hasDecl(core.lv2, "StateMapPath"));
    try std.testing.expect(@hasDecl(core.lv2, "StateMakePath"));
    try std.testing.expect(@hasDecl(core.lv2, "StateFreePath"));
    try std.testing.expect(@hasDecl(core.lv2, "PatchProperty"));
    try std.testing.expect(@hasDecl(core.lv2, "PatchValue"));
    try std.testing.expect(@hasDecl(core.lv2, "PatchValueKind"));
    try std.testing.expect(@hasDecl(core.lv2, "AtomBool"));
    try std.testing.expect(@hasDecl(core.lv2, "AtomUrid"));
    const patch_property = core.lv2.PatchProperty{
        .uri = "https://example.test/property",
        .value_kind = .double,
        .readable = true,
    };
    try std.testing.expect(patch_property.readable);
    try std.testing.expectEqual(
        @as(f64, 0.5),
        (core.lv2.PatchValue{ .double = 0.5 }).double,
    );
    try std.testing.expectEqual(
        @as(u8, 64),
        core.plugin.AudioBusLayout.ambisonic_seventh_order
            .channelCount(),
    );
    const extended_layouts =
        try core.plugin.AudioBusLayoutSet.init(
            &.{
                .stereo,
                .surround_5_1_4,
                .ambisonic_seventh_order,
            },
        );
    try std.testing.expect(
        extended_layouts.contains(.surround_5_1_4),
    );

    const policy = core.gui.ResizePolicy{
        .resizable = .{
            .minimum = .{ .width = 320, .height = 200 },
            .maximum = .{ .width = 960, .height = 720 },
        },
    };
    try std.testing.expectEqual(
        core.gui.Size{ .width = 960, .height = 200 },
        core.gui.constrained(
            policy,
            .{ .width = 2_000, .height = 100 },
        ),
    );
}

test "installed core package runs the Audio Unit render core" {
    try std.testing.expect(@hasDecl(
        core.audio_unit_v2,
        "NativeComponentFactory",
    ));
    const ramp = core.process.ParameterRamp{
        .id = 0,
        .start_offset = 0,
        .duration_frames = 4,
        .start_normalized = 0.0,
        .end_normalized = 1.0,
        .sequence = 0,
    };
    const automation = try core.process.ParameterChanges.initWithRamps(
        &.{},
        &.{},
        &.{ramp},
        4,
    );
    try std.testing.expectEqual(
        @as(f64, 0.5),
        automation.normalizedAtOrBeforeOr(0, 2, 0.0),
    );

    const Probe = struct {
        pub const name = "Installed Audio Unit";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
        pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            context: *core.process.ProcessContext(f32),
        ) void {
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            @memcpy(output, input);
        }
    };

    const Adapter = core.audio_unit.RenderAdapter(Probe, 16);
    var adapter = try Adapter.init(
        std.testing.allocator,
        .{},
        48_000.0,
        8,
    );
    defer adapter.deinit();

    const Properties =
        core.audio_unit_v2.RenderPropertyAdapter(Adapter);
    var properties = Properties.init(&adapter);
    var maximum_bytes: [@sizeOf(u32)]u8 = undefined;
    try std.testing.expectEqual(
        @as(u32, @sizeOf(u32)),
        try properties.getProperty(
            core.audio_unit_v2.property.maximum_frames_per_slice,
            core.audio_unit_v2.scope.global,
            0,
            &maximum_bytes,
        ),
    );
    try std.testing.expectEqual(
        @as(u32, 8),
        std.mem.bytesToValue(u32, &maximum_bytes),
    );

    try adapter.initialize();

    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0, 0 };
    try adapter.render(.{
        .input_channels = &.{&input},
        .output_channels = &.{&output},
    });
    try std.testing.expectEqualSlices(f32, &input, &output);
    try std.testing.expectEqual(
        @as(u64, 1),
        adapter.renderStatistics().rendered_blocks,
    );
}

test "installed package composes Wayland window and VST3 frame bridge" {
    const Loop = vst3.vst_linux_run_loop.RunLoop(1, 1);
    const Bridge =
        vst3.vst_wayland_standalone_frame.StandaloneBridge(
            wayland_window.Backend,
        );
    var window = try wayland_window.Backend.init(
        "Installed Wayland Bridge",
    );
    var loop = Loop{};
    var bridge = Bridge.init(&window, loop.asInterface());

    try bridge.validateDetached();
    try std.testing.expectEqual(
        @as(u32, 0),
        bridge.activeConnectionCount(),
    );
    _ = bridge.asPlugFrame();
    _ = bridge.asWaylandHost();
}

test "installed core package runs a live standalone callback" {
    const Probe = struct {
        pub const name = "Installed Standalone";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
        pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            context: *core.process.ProcessContext(f32),
        ) void {
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            @memcpy(output, input);
        }
    };

    const Runtime = core.plugin.StandaloneRuntime(Probe, f32);
    var runtime = try Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    try runtime.start(.{
        .sample_rate = 48_000.0,
        .max_block_size = 2,
        .input_channel_count = 1,
        .output_channel_count = 1,
    });
    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    try runtime.processCallback(.{
        .input_channels = &inputs,
        .output_channels = &outputs,
    });
    try std.testing.expectEqualSlices(f32, &input, &output);

    const Router = core.plugin.DeviceChannelRouter(f32, 2);
    var router = try Router.init(.{
        .sample_rate = 48_000.0,
        .max_block_size = 2,
        .input_channel_count = 1,
        .output_channel_count = 1,
    }, .{
        .device_input_channel_count = 2,
        .device_output_channel_count = 2,
        .input_routes = &.{1},
        .output_routes = &.{0},
    });
    const unused_input = [_]f32{ 1.0, 1.0 };
    const routed_inputs = [_][]const f32{ &unused_input, &input };
    var routed_output = [_]f32{ 0.0, 0.0 };
    var unused_output = [_]f32{ 1.0, 1.0 };
    const routed_outputs =
        [_][]f32{ &routed_output, &unused_output };
    try router.processCallback(&runtime, .{
        .frame_count = 2,
        .input_channels = &routed_inputs,
        .output_channels = &routed_outputs,
    });
    try std.testing.expectEqualSlices(f32, &input, &routed_output);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.0 },
        &unused_output,
    );
    try runtime.stop();
}

test "installed core package schedules timestamped MIDI input" {
    var scheduler = core.plugin.Midi1BlockScheduler(2){};
    const callback = scheduler.inputCallback();
    callback.receive(callback.context, .{
        .timestamp_nanoseconds = 1_001_000_000,
        .message = try core.process.Midi1Message.noteOn(
            0,
            60,
            100,
        ),
    });

    var events = core.plugin.Midi1EventBuffer(2){};
    const report = try scheduler.fillBlock(
        2,
        &events,
        1_000_000_000,
        1_000.0,
        4,
        0,
    );
    try std.testing.expectEqual(@as(usize, 1), report.scheduled);
    try std.testing.expectEqual(@as(usize, 1), events.count);
    try std.testing.expectEqual(
        @as(usize, 1),
        events.storage[0].sample_offset,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        scheduler.rejectedPacketCount(),
    );
    events.count = 3;
    try std.testing.expect(!events.valid());
    try std.testing.expectError(
        error.InvalidMidiEventBuffer,
        events.events(4),
    );
    events.reset();
    try std.testing.expect(events.valid());
}

test "installed core package schedules timestamped UMP input" {
    const OutputProbe = struct {
        timestamp_nanoseconds: ?u64 = null,

        fn send(
            context: *anyopaque,
            packet: core.plugin.TimestampedUmpPacket,
        ) !void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.timestamp_nanoseconds =
                packet.timestamp_nanoseconds;
        }
    };

    var scheduler = core.plugin.UmpBlockScheduler(2){};
    const callback = scheduler.inputCallback();
    callback.receive(callback.context, .{
        .timestamp_nanoseconds = 1_001_000_000,
        .packet = try core.process.UmpPacket.init(
            &.{ 0x4090_3C00, 0x7FFF_FFFF },
        ),
    });

    var packets = core.plugin.UmpBlockBuffer(2){};
    const report = try scheduler.fillBlock(
        2,
        &packets,
        1_000_000_000,
        1_000.0,
        4,
    );
    try std.testing.expectEqual(@as(usize, 1), report.scheduled);
    try std.testing.expectEqual(@as(usize, 1), packets.count);
    try std.testing.expectEqual(
        @as(usize, 1),
        packets.storage[0].sample_offset,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x4090_3C00, 0x7FFF_FFFF },
        packets.storage[0].packet.words(),
    );

    var probe = OutputProbe{};
    var output = core.plugin.UmpOutputDevice{
        .context = &probe,
        .send_output = OutputProbe.send,
    };
    const output_report = try output.sendBlock(
        try packets.packets(),
        2_000_000_000,
        1_000.0,
        4,
    );
    try std.testing.expectEqual(@as(usize, 1), output_report.sent);
    try std.testing.expectEqual(
        @as(?u64, 2_001_000_000),
        probe.timestamp_nanoseconds,
    );
    packets.count = 3;
    try std.testing.expect(!packets.valid());
    try std.testing.expectError(
        error.InvalidUmpBlockBuffer,
        packets.packets(),
    );
    packets.reset();
    try std.testing.expect(packets.valid());
}

test "installed package builds and edits an ARA document graph" {
    const Document = vst3.ara_model.Document(.{
        .musical_contexts = 1,
        .region_sequences = 1,
        .audio_sources = 1,
        .audio_modifications = 1,
        .playback_regions = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
    });
    var document = Document{};
    try document.beginEditing();
    const musical_context = try document.createMusicalContext(null, .{
        .name = "Song",
        .order_index = 0,
    });
    const sequence = try document.createRegionSequence(null, .{
        .name = "Verse",
        .order_index = 0,
        .musical_context = musical_context,
    });
    const source = try document.createAudioSource(null, .{
        .name = "Take",
        .persistent_id = "take-1",
        .sample_count = 96_000,
        .sample_rate = 48_000.0,
        .channel_count = 2,
    });
    const modification = try document.createAudioModification(
        source,
        null,
        .{
            .name = "Edited take",
            .persistent_id = "edit-1",
        },
    );
    const region = try document.createPlaybackRegion(
        modification,
        null,
        .{
            .name = "Verse region",
            .region_sequence = sequence,
            .transformation = .{
                .time_stretch = true,
                .reflect_tempo = true,
            },
            .start_in_modification_time = 0.0,
            .duration_in_modification_time = 2.0,
            .start_in_playback_time = 4.0,
            .duration_in_playback_time = 2.0,
        },
    );
    try std.testing.expect(try document.endEditing());
    try std.testing.expectEqual(@as(u64, 1), document.currentRevision());
    try std.testing.expectEqualStrings(
        "Take",
        document.audioSource(source).?.name.slice(),
    );
    try std.testing.expect(
        document.playbackRegion(region).?.transformation.reflect_tempo,
    );

    try document.beginEditing();
    try std.testing.expectError(
        error.ObjectInUse,
        document.destroyAudioSource(source),
    );
    try document.destroyPlaybackRegion(region);
    try document.destroyAudioModification(modification);
    try document.destroyAudioSource(source);
    try document.destroyRegionSequence(sequence);
    try document.destroyMusicalContext(musical_context);
    try std.testing.expect(try document.endEditing());
    try std.testing.expectEqual(@as(u64, 2), document.currentRevision());
    try std.testing.expect(document.audioSource(source) == null);
}

test "installed core package discovers and restores device selections" {
    const built_in = try core.plugin.DeviceDescriptor.init(
        .audio,
        "audio:built-in",
        "Built-in Audio",
        2,
        2,
        true,
    );
    const studio = try core.plugin.DeviceDescriptor.init(
        .audio,
        "audio:studio",
        "Studio Interface",
        8,
        8,
        false,
    );
    var catalog = core.plugin.DeviceCatalog(2){};
    try catalog.replace(&.{ built_in, studio });

    const selected = try core.plugin.DeviceIdentifier.init(
        "audio:studio",
    );
    const resolved = catalog.resolve(.audio, selected) orelse
        return error.MissingSelectedDevice;
    try std.testing.expectEqualStrings(
        "Studio Interface",
        resolved.name(),
    );

    const selection = core.plugin.DeviceSelection{
        .audio = selected,
    };
    var bytes: [core.plugin.DeviceSelection.maximum_encoded_size]u8 =
        undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try selection.writeTo(&writer);

    var restored = core.plugin.DeviceSelection{};
    var reader = std.Io.Reader.fixed(bytes[0..writer.end]);
    try restored.readFrom(&reader);
    try std.testing.expect(restored.audio.?.eql(&selected));

    var tracker = try core.plugin.DeviceSelectionTracker.init(restored);
    const resolution = try tracker.reconcile(&catalog);
    try std.testing.expect(resolution.audio_changed);
    try std.testing.expect(!resolution.audio_uses_fallback);
}

test "installed core package persists directional audio selections" {
    const input = try core.plugin.DeviceDescriptor.init(
        .audio_input,
        "audio-input:installed",
        "Installed Input",
        2,
        0,
        true,
    );
    const output = try core.plugin.DeviceDescriptor.init(
        .audio_output,
        "audio-output:installed",
        "Installed Output",
        0,
        2,
        true,
    );
    var catalog = core.plugin.DeviceCatalog(2){};
    try catalog.replace(&.{ input, output });
    const selection = core.plugin.DeviceSelection{
        .audio_input = input.identifier,
        .audio_output = output.identifier,
    };
    var bytes: [core.plugin.DeviceSelection.maximum_encoded_size]u8 =
        undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try selection.writeTo(&writer);
    var restored = core.plugin.DeviceSelection{};
    var reader = std.Io.Reader.fixed(bytes[0..writer.end]);
    try restored.readFrom(&reader);
    var tracker = try core.plugin.DeviceSelectionTracker.init(
        restored,
    );
    const resolution = try tracker.reconcile(&catalog);
    try std.testing.expect(resolution.audio_input_changed);
    try std.testing.expect(resolution.audio_output_changed);
    try std.testing.expect(!resolution.audio_input_uses_fallback);
    try std.testing.expect(!resolution.audio_output_uses_fallback);
}

test "installed core package runs an LV2 audio control descriptor" {
    const Gain = struct {
        pub const name = "Installed LV2 Gain";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
        pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
        pub const Params = struct {
            gain: core.parameters.FloatParam = .{
                .id = 0,
                .name = "Gain",
                .min = 0.0,
                .max = 2.0,
                .default = 1.0,
            },
        };
        pub const units: core.units.Config = .{
            .program_lists = &.{.{
                .id = 5,
                .name = "Factory",
                .programs = &.{.{
                    .name = "Quiet",
                    .parameters = &.{
                        .{ .parameter_id = 0, .normalized = 0.25 },
                    },
                }},
            }},
        };

        pub fn processWithParameterView(
            _: *@This(),
            context: *core.process.ProcessContext(f32),
            parameters: core.parameters.ParameterView(Params),
        ) void {
            const input = context.inputChannel(0) orelse return;
            const output = context.outputChannel(0) orelse return;
            const gain: f32 = @floatCast(parameters.load("gain"));
            for (input, output) |sample, *destination|
                destination.* = sample * gain;
        }
    };
    const Adapter = core.lv2.CoreAdapter(
        Gain,
        "https://example.test/installed-lv2-gain",
        2,
    );
    const MapHost = struct {
        fn map(
            _: ?*anyopaque,
            URI: [*:0]const u8,
        ) callconv(.c) core.lv2.Urid {
            return @as(u32, @truncate(std.hash.Wyhash.hash(
                0,
                std.mem.span(URI),
            ))) | 1;
        }
    };
    var urid_map = core.lv2.UridMap{
        .handle = null,
        .map = MapHost.map,
    };
    var map_feature = core.lv2.Feature{
        .URI = core.lv2.urid_map_uri,
        .data = &urid_map,
    };
    const features =
        [_:null]?*const core.lv2.Feature{&map_feature};
    const descriptor = Adapter.descriptorAt(0) orelse
        return error.MissingLv2Descriptor;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/installed-lv2-gain.lv2",
        features[0..].ptr,
    ) orelse return error.Lv2InstantiateFailed;
    defer descriptor.cleanup(handle);

    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{0.0} ** input.len;
    var gain: f32 = 2.0;
    var latency: f32 = -1.0;
    descriptor.connect_port(handle, 0, @constCast(&input));
    descriptor.connect_port(handle, 1, &output);
    descriptor.connect_port(
        handle,
        Adapter.control_input_port_start,
        &gain,
    );
    descriptor.connect_port(
        handle,
        Adapter.latency_output_port,
        &latency,
    );
    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.5, -1.0 },
        &output,
    );
    try std.testing.expectEqual(@as(f32, 0.0), latency);
    const raw_programs = descriptor.extension_data(
        core.lv2.programs_interface_uri,
    ) orelse return error.MissingLv2ProgramsInterface;
    const programs: *const core.lv2.ProgramsInterface =
        @ptrCast(@alignCast(raw_programs));
    const program = programs.get_program(handle, 0) orelse
        return error.MissingLv2Program;
    try std.testing.expectEqual(@as(u32, 5), program.bank);
    try std.testing.expectEqualStrings(
        "Quiet",
        std.mem.span(program.name),
    );
    programs.select_program(handle, 5, 0);
    output = @splat(0.0);
    descriptor.run(handle, input.len);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ 0.125, -0.25 },
        &output,
    );

    const Metadata = core.lv2.metadata.Generator(
        Gain,
        Adapter,
        "https://example.test/installed-lv2-gain",
        .{},
    );
    var metadata_bytes: [4096]u8 = undefined;
    var metadata_writer = std.Io.Writer.fixed(&metadata_bytes);
    try Metadata.writePlugin(&metadata_writer, .{
        .description = "Installed metadata consumer.",
        .short_description = "Installed consumer",
        .is_live = true,
        .project = .{
            .uri = "https://example.test/installed-project",
            .name = "Installed Project",
            .license_uri = "https://example.test/license",
            .maintainer = .{
                .name = "Installed Maintainer",
                .email_uri = "mailto:maintainer@example.test",
                .homepage_uri = "https://example.test/maintainer",
            },
        },
        .ui = .{
            .uri = "https://example.test/installed-lv2-gain#ui",
            .binary_name = "installed_lv2_gain_ui.so",
            .class_uri = "http://lv2plug.in/ns/extensions/ui#X11UI",
        },
    });
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "lv2:symbol \"gain\"",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "lv2:optionalFeature ui:idleInterface , ui:resize , ui:touch",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "doap:license <https://example.test/license>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "pgm:Interface",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "pgm:UIInterface",
        ) != null,
    );
}

test "installed core package compiles typed LV2 Patch declarations" {
    const Probe = struct {
        mode: i32 = 3,

        pub const name = "Installed LV2 Patch Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
        pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
        pub const event_input = true;
        pub const event_output = true;
        pub const lv2_patch_response_capacity = 256;
        pub const lv2_patch_properties = &[_]core.lv2.PatchProperty{
            .{
                .uri = "https://example.test/installed-patch#mode",
                .value_kind = .int,
                .readable = true,
                .writable = true,
            },
        };
        pub const Params = struct {};

        pub fn process(
            _: *@This(),
            _: *core.process.ProcessContext(f32),
        ) void {}

        pub fn readLv2PatchProperty(
            self: *const @This(),
            property_index: usize,
        ) !core.lv2.PatchValue {
            if (property_index != 0)
                return error.UnknownPatchProperty;
            return .{ .int = self.mode };
        }

        pub fn writeLv2PatchProperty(
            self: *@This(),
            property_index: usize,
            value: core.lv2.PatchValue,
        ) !void {
            if (property_index != 0)
                return error.UnknownPatchProperty;
            self.mode = switch (value) {
                .int => |item| item,
                else => return error.InvalidPatchValue,
            };
        }
    };
    const Adapter = core.lv2.CoreAdapter(
        Probe,
        "https://example.test/installed-patch",
        16,
    );
    try std.testing.expect(Adapter.patch_enabled);
    try std.testing.expect(Adapter.patch_readable);
    try std.testing.expect(Adapter.patch_writable);
    try std.testing.expect(Adapter.event_input_port != null);
    try std.testing.expect(Adapter.event_output_port != null);
    try std.testing.expect(@sizeOf(Adapter) > 0);
    try std.testing.expect(Adapter.descriptorAt(0) != null);
}
