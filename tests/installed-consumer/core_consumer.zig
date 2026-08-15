const core = @import("zig-vst3-plugin-core");
const vst3 = @import("zig-vst3");
const ara = @import("zig-vst3-ara");
const core_audio = @import("zig-vst3-coreaudio");
const core_midi = @import("zig-vst3-coremidi");
const wasapi = @import("zig-vst3-wasapi");
const alsa = @import("zig-vst3-alsa");
const pipewire = @import("zig-vst3-pipewire");
const alsa_midi = @import("zig-vst3-alsamidi");
const alsa_ump = @import("zig-vst3-alsaump");
const win_midi = @import("zig-vst3-winmidi");
const win_ump = @import("zig-vst3-winump");
const win_window = @import("zig-vst3-winwindow");
const cocoa_window = @import("zig-vst3-cocoawindow");
const x11_window = @import("zig-vst3-x11window");
const wayland_window = @import("zig-vst3-waylandwindow");
const std = @import("std");

test "installed raw package contains malformed reference counts" {
    var saturated = std.atomic.Value(u32).init(std.math.maxInt(u32));
    try std.testing.expectEqual(
        std.math.maxInt(u32),
        vst3.funknown.incrementRefCount(&saturated, "Installed"),
    );

    var empty = std.atomic.Value(u32).init(0);
    try std.testing.expectEqual(
        std.math.maxInt(u32),
        vst3.funknown.decrementRefCount(&empty, "Installed"),
    );
    try std.testing.expectEqual(@as(u32, 0), empty.load(.monotonic));

    try std.testing.expectEqual(
        @as(i8, 0),
        vst3.pluginterfaces.vst.vsteventshelper.getMIDICCOutValue(
            -std.math.floatMax(f64),
        ),
    );
    try std.testing.expectEqual(
        @as(i16, 0),
        vst3.pluginterfaces.vst.vsteventshelper.getMIDI14BitValue(
            -std.math.floatMax(f64),
        ),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        vst3.vst_stream.streamPositionLen(
            std.math.maxInt(i64),
            8,
        ),
    );
}

test "installed core package rejects invalid direct preparation" {
    const Plugin = struct {
        prepared: bool = false,

        pub const name = "Installed Prepare Probe";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};

        pub fn prepare(
            self: *@This(),
            _: core.plugin.PrepareConfig,
        ) void {
            self.prepared = true;
        }
    };

    const Instance = core.plugin.PluginInstance(Plugin);
    var instance = try Instance.init(std.testing.allocator, .{});
    try std.testing.expectError(
        error.InvalidSampleRate,
        instance.prepare(.{
            .sample_rate = std.math.nan(f64),
            .max_block_size = 64,
        }),
    );
    try std.testing.expect(!instance.plugin.prepared);
}

test "installed core package contains realtime audit scope misuse" {
    const scope = core.realtime_audit.Scope.enter();
    const duplicate = scope;
    try std.testing.expect(scope.leave().clean());
    const report = duplicate.leave();
    try std.testing.expect(report.invalid_scope);
    try std.testing.expect(!report.clean());
}

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

test "installed core package contains MPE identity counter rollback" {
    const lower = try core.process.MpeZone.init(.lower, 2, 48, 2);
    const upper = try core.process.MpeZone.init(.upper, 0, 48, 2);
    const layout = try core.process.MpeZoneLayout.init(lower, upper);
    const note_on = try core.process.Midi1Message.noteOn(1, 60, 100);

    var instrument = try core.process.MpeInstrument(2).init(layout);
    _ = try instrument.process(note_on);
    instrument.next_id = instrument.notes_storage[0].id;
    try std.testing.expect(!instrument.valid());
    try std.testing.expectError(
        error.InvalidMpeInstrumentState,
        instrument.process(note_on),
    );

    var allocator = try core.process.MpeMemberChannelAllocator.init(lower);
    _ = try allocator.allocate(60, .reject);
    allocator.next_serial = allocator.assignments_storage[0].serial;
    try std.testing.expect(!allocator.valid());
    try std.testing.expectError(
        error.InvalidMpeAllocatorState,
        allocator.allocate(62, .reject),
    );
}

test "installed core package contains malformed transport tempo" {
    const transport = core.process.Transport{
        .project_time_samples = 0,
        .tempo_bpm = std.math.nan(f64),
    };
    try std.testing.expect(!transport.valid());
    try std.testing.expectEqual(@as(f64, 90.0), transport.tempoOr(90.0));
    try std.testing.expectEqual(
        @as(f64, 120.0),
        transport.tempoOr(std.math.inf(f64)),
    );
}

test "installed core package contains malformed MIDI file state" {
    const bytes = [_]u8{
        'M',  'T', 'h', 'd', 0, 0,  0,   6,
        0,    0,   0,   1,   0, 96, 'M', 'T',
        'r',  'k', 0,   0,   0, 4,  0,   0xff,
        0x2f, 0,
    };
    var file = try core.process.MidiFile.parse(&bytes);
    var limits = core.process.default_midi_file_limits;
    limits.max_file_bytes = bytes.len - 1;
    try std.testing.expectError(
        error.MidiFileByteLimitExceeded,
        core.process.MidiFile.parseWithLimits(&bytes, limits),
    );
    var track_iterator = file.track(0).?.iterator();
    track_iterator.position = 1;
    try std.testing.expect(!track_iterator.valid());
    try std.testing.expectError(
        error.InvalidMidiTrackIteratorState,
        track_iterator.next(),
    );
    try std.testing.expectEqual(@as(usize, 1), track_iterator.position);
    track_iterator = file.track(0).?.iterator();
    track_iterator.position = std.math.maxInt(usize);
    try std.testing.expect(!track_iterator.valid());
    try std.testing.expectError(
        error.InvalidMidiTrackIteratorState,
        track_iterator.next(),
    );
    file.bytes = file.bytes[0..14];
    try std.testing.expectError(
        error.InvalidMidiFileState,
        file.secondsAtTick(0, 96),
    );

    var storage = [_]u8{0} ** 32;
    var writer = try core.process.MidiFileWriter.init(
        &storage,
        .single_track,
        1,
        .{ .ticks_per_quarter_note = 96 },
    );
    writer.position = std.math.maxInt(usize);
    try std.testing.expectError(
        error.InvalidMidiWriterState,
        writer.beginTrack(),
    );
}

test "installed core package contains malformed MIDI-CI retained counts" {
    const Cache = core.process.MidiCiPropertyRemoteCache(1, 12, 12, 8);
    const remote = try core.process.MidiCiMuid.init(1);
    var cache = Cache{};
    _ = try cache.put(.{ .remote = remote, .resource = "State" }, "a");
    cache.active_count = std.math.maxInt(usize);
    try std.testing.expect(!cache.valid());
    try std.testing.expectEqual(@as(usize, 1), cache.count());
    try std.testing.expectError(
        error.InvalidMidiCiPropertyCacheState,
        cache.put(.{ .remote = remote, .resource = "Other" }, "b"),
    );
    try std.testing.expectEqual(@as(usize, 1), cache.releaseRemote(remote));
    try std.testing.expect(cache.valid());

    _ = try cache.put(.{ .remote = remote, .resource = "State" }, "a");
    const active_generation = (try cache.get(.{
        .remote = remote,
        .resource = "State",
    })).generation;
    cache.next_generation = active_generation;
    try std.testing.expect(!cache.valid());
    try std.testing.expectError(
        error.InvalidMidiCiPropertyCacheState,
        cache.put(.{ .remote = remote, .resource = "State" }, "b"),
    );

    const Delegate = struct {};
    var delegate = Delegate{};
    var host = try core.process.MidiCiProfileHost(
        1,
        0,
        Delegate,
    ).init(remote, 2, &delegate);
    host.count = std.math.maxInt(usize);
    try std.testing.expect(!host.valid());
    try std.testing.expectEqual(@as(usize, 0), host.profiles().len);
    try std.testing.expectError(
        error.InvalidMidiCiProfileHostState,
        host.addProfile(
            .function_block,
            core.process.MidiCiProfileId.standard(1, 2, 3, 4),
        ),
    );

    const PropertyReassembler =
        core.process.MidiCiPropertyReassembler(1, 1);
    var reassembler = PropertyReassembler{};
    reassembler.started = true;
    reassembler.header_count = std.math.maxInt(u14);
    reassembler.data_count = std.math.maxInt(u14);
    try std.testing.expect(!reassembler.valid());
    try std.testing.expectEqual(@as(usize, 0), reassembler.header().len);
    try std.testing.expectEqual(@as(usize, 0), reassembler.data().len);
}

test "installed core package contains malformed failure monitor counts" {
    const Probe = struct {
        fn snapshot(
            _: *anyopaque,
        ) anyerror!core.plugin.DeviceFailureSnapshot {
            return .{};
        }
    };
    var context: u8 = 0;
    const source = core.plugin.DeviceFailureSource{
        .context = &context,
        .read_snapshot = Probe.snapshot,
    };
    var monitors = core.plugin.DeviceFailureMonitorSet(1){};
    try std.testing.expectEqualDeep(
        core.plugin.DeviceFailureMonitor{},
        monitors.monitors[0],
    );
    monitors.count = std.math.maxInt(usize);
    try std.testing.expect(!monitors.valid());
    try std.testing.expectError(
        error.InvalidDeviceFailureMonitorSetState,
        monitors.poll(),
    );
    try std.testing.expectError(
        error.InvalidDeviceFailureMonitorSetState,
        monitors.add(source),
    );
    monitors.clear();
    try std.testing.expectEqualDeep(
        core.plugin.DeviceFailureMonitor{},
        monitors.monitors[0],
    );
    try monitors.add(source);
    try std.testing.expect(monitors.valid());
}

test "installed core package provides bounded growable output" {
    var bytes = try core.resource.ByteAccumulator.initCapacity(
        std.testing.allocator,
        32,
        2,
    );
    defer bytes.deinit();
    try bytes.append("state:");
    const output = try bytes.writer();
    try output.writeInt(u32, 0x1234_5678, .little);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 's', 't', 'a', 't', 'e', ':', 0x78, 0x56, 0x34, 0x12 },
        try bytes.bytes(),
    );
}

test "installed resource job snapshot validates active identity" {
    const Config = struct {
        pub const Request = void;
        pub const Result = void;
        pub const Failure = enum { unavailable };
        pub const maximum_work_units = 4;
        pub const maximum_result_units = 1;

        pub fn run(
            _: Request,
            _: *core.resource.job.WorkerContext,
        ) core.resource.job.Outcome(Result, Failure) {
            return .{ .success = .{ .value = {}, .result_units = 1 } };
        }
    };
    const Snapshot = core.resource.job.Job(Config).Snapshot;
    const pending = Snapshot{
        .status = .loading,
        .generation = 1,
        .completed_units = 2,
        .total_units = 4,
        .framework_failure = .none,
        .failure = null,
        .cancellation_pending = true,
        .result_available = false,
    };
    try std.testing.expect(pending.valid());
    try std.testing.expect(!pending.canCancel());

    var malformed = pending;
    malformed.generation = 0;
    try std.testing.expect(!malformed.valid());
    try std.testing.expectEqual(@as(f64, 0.0), malformed.progress());
    try std.testing.expect(!malformed.canCancel());
    try std.testing.expect(!malformed.canRetry());
}

test "installed resource job generation avoids retained active identity" {
    const Config = struct {
        pub const Request = u8;
        pub const Result = void;
        pub const Failure = enum { unused };
        pub const maximum_work_units = 1;
        pub const maximum_result_units = 1;

        pub fn run(
            _: Request,
            _: *core.resource.job.WorkerContext,
        ) core.resource.job.Outcome(Result, Failure) {
            return .{ .success = .{ .value = {}, .result_units = 1 } };
        }
    };
    const ResourceJob = core.resource.job.Job(Config);

    var resource_job = ResourceJob.init();
    defer resource_job.deinit();
    resource_job.generation = std.math.maxInt(u64);
    resource_job.running_generation.store(1, .release);
    resource_job.latest_generation.store(2, .release);
    resource_job.worker_running.store(true, .release);

    try std.testing.expect(resource_job.submit(9));
    try std.testing.expectEqual(@as(u64, 3), resource_job.snapshot().generation);
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
    try std.testing.expect(@hasDecl(pipewire, "Backend"));
    try std.testing.expect(@hasDecl(pipewire, "Statistics"));
    try std.testing.expect(
        @hasDecl(pipewire.Backend(f32), "startSplit"),
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
        @hasDecl(vst3.vstgui_lv2_backend, "PeakSource"),
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
    const silent_analysis: [64]f64 = @splat(0.0);
    try std.testing.expectError(
        error.InvalidSampleCount,
        vst3.ara_tuning_analysis.detectEqualTemperament(
            &silent_analysis,
            48_000.0,
            .{
                .minimum_frequency = 1.0e-300,
                .maximum_frequency = 2.0e-300,
            },
        ),
    );
    try std.testing.expectError(
        error.InvalidSampleCount,
        vst3.ara_tuning_analysis.detectTempoEnvelope(
            &silent_analysis,
            200.0,
            .{
                .minimum_bpm = 1.0e-300,
                .maximum_bpm = 2.0e-300,
            },
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
    try std.testing.expect(@hasDecl(core.gui, "HostValueRequest"));
    try std.testing.expect(@hasDecl(core.gui, "HostValueRequestStatus"));
    try std.testing.expect(@hasDecl(core.gui, "HostPeakSubscription"));
    try std.testing.expect(@hasDecl(core.gui, "HostPeakDelivery"));
    try std.testing.expect(@hasDecl(core.gui, "HostSubscriptionStatus"));
    try std.testing.expect(@hasDecl(core.gui, "HostPeakMeasurement"));
    try std.testing.expect(@hasDecl(core.gui, "HostAtomNotification"));
    try std.testing.expect(@hasDecl(core.gui, "HostAtomMessage"));
    try std.testing.expect(@hasDecl(core.gui, "PluginAtomMessage"));
    try std.testing.expect(@hasDecl(core.gui, "PluginMessageStatus"));
    try std.testing.expectEqual(
        @as(usize, 4096),
        core.gui.maximum_host_value_uri_bytes,
    );
    try std.testing.expectEqual(
        @as(usize, 16),
        core.gui.maximum_host_peak_subscriptions,
    );
    try std.testing.expectEqual(
        @as(usize, 16),
        core.gui.maximum_host_atom_notifications,
    );
    try std.testing.expectEqual(
        @as(usize, 64 * 1024),
        core.gui.maximum_host_atom_body_bytes,
    );
    try std.testing.expectEqual(
        @as(usize, 64 * 1024),
        core.gui.maximum_plugin_atom_body_bytes,
    );
    try std.testing.expect((core.gui.HostAtomMessage{
        .source_id = 4,
        .body = &.{ 1, 2, 3 },
    }).valid());
    try std.testing.expect(@hasDecl(core.lv2, "ui"));
    try std.testing.expect(@hasDecl(core.lv2.ui, "Descriptor"));
    try std.testing.expect(
        @hasDecl(core.lv2.metadata, "UiPortNotification"),
    );
    try std.testing.expect(@hasDecl(core.lv2.ui, "Adapter"));
    try std.testing.expect(@hasDecl(core.lv2.ui, "RequestValue"));
    try std.testing.expect(@hasDecl(core.lv2.ui, "PortMap"));
    try std.testing.expect(@hasDecl(core.lv2.ui, "PortSubscribe"));
    try std.testing.expect(@hasDecl(core.lv2.ui, "PeakData"));
    try std.testing.expect(@hasDecl(core.lv2.ui, "Atom"));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(core.lv2.ui.Atom));
    try std.testing.expect(@hasDecl(
        core.lv2.metadata,
        "UiPortProtocol",
    ));
    try std.testing.expectEqual(
        @as(core.lv2.ui.RequestValueStatus, 3),
        core.lv2.ui.request_value_unsupported,
    );
    try std.testing.expect(@hasDecl(
        core.lv2.metadata,
        "UiResizeBehavior",
    ));
    try std.testing.expect(@hasDecl(core.lv2, "StatePathFeatures"));
    try std.testing.expect(@hasDecl(core.lv2, "OwnedStatePath"));
    try std.testing.expectEqual(
        @as(usize, 4096),
        core.lv2.maximum_state_path_bytes,
    );
    try std.testing.expect(@hasDecl(core.lv2, "StateMapPath"));
    try std.testing.expect(@hasDecl(core.lv2, "StateMakePath"));
    try std.testing.expect(@hasDecl(core.lv2, "StateFreePath"));
    try std.testing.expect(@hasDecl(core.lv2, "StateMapPathSink"));
    try std.testing.expect(@hasDecl(core.lv2, "StateMakePathSink"));
    try std.testing.expect(@hasDecl(core.lv2, "StateFreePathSink"));
    const PathRelease = struct {
        fn release(
            handle: core.lv2.StateHandle,
            _: [*:0]u8,
        ) callconv(.c) void {
            const count: *usize = @ptrCast(
                @alignCast(handle orelse return),
            );
            count.* += 1;
        }
    };
    var path_release_count: usize = 0;
    var path_bytes = [_:0]u8{ 'p', 'a', 't', 'h' };
    var owned_path = core.lv2.OwnedStatePath{
        .pointer = path_bytes[0..path_bytes.len :0].ptr,
        .length = path_bytes.len,
        .free_path = .{
            .handle = &path_release_count,
            .free_path = PathRelease.release,
        },
    };
    try std.testing.expectEqualStrings("path", owned_path.bytes());
    owned_path.deinit();
    owned_path.deinit();
    try std.testing.expectEqual(@as(usize, 1), path_release_count);
    try std.testing.expectEqual(@as(usize, 0), owned_path.bytes().len);
    try std.testing.expect(@hasDecl(core.lv2, "PatchProperty"));
    try std.testing.expect(@hasDecl(core.lv2, "PatchValue"));
    try std.testing.expect(@hasDecl(core.lv2, "PatchValueKind"));
    try std.testing.expect(@hasDecl(core.lv2, "AtomBool"));
    try std.testing.expect(@hasDecl(core.lv2, "AtomUrid"));
    try std.testing.expect(@hasDecl(core.lv2, "ResizePortStatus"));
    try std.testing.expect(@hasDecl(core.lv2, "ResizePortFeature"));
    try std.testing.expect(@hasDecl(core.lv2, "PortResizeSink"));
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
    try std.testing.expect(properties.valid());
    for (properties.parameter_events) |event|
        try std.testing.expectEqualDeep(core.process.ParameterChange{}, event);
    for (properties.parameter_event_sequences) |sequence|
        try std.testing.expectEqual(@as(usize, 0), sequence);
    for (properties.parameter_ramps) |retained_ramp|
        try std.testing.expectEqualDeep(
            core.process.ParameterRamp{},
            retained_ramp,
        );
    for (properties.state_storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    properties.scheduled_parameter_event_count = std.math.maxInt(usize);
    try std.testing.expect(!properties.valid());
    try std.testing.expectError(
        error.InvalidAudioUnitParameterEventState,
        properties.scheduleParameters(&.{}),
    );
    properties.scheduled_parameter_event_count = 0;
    try std.testing.expect(properties.valid());
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
    for (events.storage) |event|
        try std.testing.expectEqualDeep(core.process.Event.other(0), event);
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
    for (packets.storage) |packet|
        try std.testing.expectEqualDeep(core.plugin.UmpBlockPacket{}, packet);
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
    try std.testing.expectError(
        error.InvalidPlaybackRange,
        document.createPlaybackRegion(modification, null, .{
            .name = "Overflowing region",
            .region_sequence = sequence,
            .start_in_modification_time = std.math.floatMax(f64),
            .duration_in_modification_time = std.math.floatMax(f64),
            .start_in_playback_time = std.math.floatMax(f64),
            .duration_in_playback_time = std.math.floatMax(f64),
        }),
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
    var malformed_source = document.audioSource(source).?.*;
    malformed_source.name.len = std.math.maxInt(u16);
    malformed_source.persistent_id.len = std.math.maxInt(u16);
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_source.name.slice().len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_source.persistent_id.slice().len,
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

test "installed package prepares bounded ARA spectral audio" {
    const Spectral = vst3.ara_spectral_transform.Processor(
        f32,
        16,
        4,
        1,
        32,
    );
    var processor = Spectral{};
    var input: [32]f32 = undefined;
    for (&input, 0..) |*sample, index|
        sample.* = @sin(
            std.math.tau * @as(f32, @floatFromInt(index)) / 11.0,
        );
    var output: [32]f32 = undefined;
    try processor.process(&.{&input}, &.{&output}, .{});
    for (input, output) |expected, actual|
        try std.testing.expectApproxEqAbs(expected, actual, 0.000_01);
}

test "installed package initializes retained ARA preparation state" {
    const Handle = struct {
        index: u16,
        generation: u32,
    };
    const Description = struct {
        model_revision: u64,
        playback_region: Handle,
        audio_modification: Handle,
        audio_source: Handle,
        source_sample_count: i64,
        source_sample_rate: f64,
        source_channel_count: i32,
        source_samples_access_enabled: bool,
        transformation: vst3.ara_model.PlaybackTransformation,
        start_in_modification_time: f64,
        duration_in_modification_time: f64,
        start_in_playback_time: f64,
        duration_in_playback_time: f64,
    };
    const Controller = struct {
        pub const PlaybackRegionRenderDescription = Description;
    };
    const FadeAnalyzer = vst3.ara_content_fades.Analyzer(
        Controller,
        f32,
        .{ .regions = 2, .channels = 1, .analysis_frames = 2 },
    );
    const fade_analyzer = try FadeAnalyzer.init(.{});
    for (fade_analyzer.entries) |entry| {
        try std.testing.expect(!entry.occupied);
        try std.testing.expectEqualDeep(
            std.mem.zeroes(Description),
            entry.description,
        );
    }

    const TempoBuilder = vst3.ara_tempo_warp.Builder(
        Controller,
        .{ .regions = 2, .tempo_points = 2, .warp_points = 3 },
    );
    const tempo_builder = try TempoBuilder.init(.{});
    for (tempo_builder.entries) |entry| {
        try std.testing.expect(!entry.occupied);
        try std.testing.expectEqualDeep(
            std.mem.zeroes(Description),
            entry.description,
        );
        for (entry.points) |point| {
            try std.testing.expectEqualDeep(
                vst3.ara_playback_renderer.TempoWarpPoint{
                    .playback_time = 0.0,
                    .modification_time = 0.0,
                },
                point,
            );
        }
    }

    const Prepared = vst3.ara_spectral_transform.PreparedSource(
        Controller,
        f32,
        16,
        4,
        1,
        4,
        3,
    );
    const prepared = Prepared{};
    for (prepared.publisher.slots) |slot| {
        try std.testing.expect(!slot.value.valid);
        try std.testing.expectEqualDeep(
            Handle{ .index = 0, .generation = 0 },
            slot.value.source_id,
        );
    }
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
    try std.testing.expectEqualDeep(
        @as([2]core.plugin.DeviceDescriptor, @splat(.{})),
        catalog.descriptors,
    );
    try catalog.replace(&.{ built_in, studio });
    for (built_in.identifier.storage[built_in.identifier.length..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (built_in.name_storage[built_in.name_length..]) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    var compacted_catalog = catalog;
    try compacted_catalog.replace(&.{built_in});
    try std.testing.expectEqualDeep(
        core.plugin.DeviceDescriptor{},
        compacted_catalog.descriptors[1],
    );

    const selected = try core.plugin.DeviceIdentifier.init(
        "audio:studio",
    );
    const resolved = catalog.resolve(.audio, selected) orelse
        return error.MissingSelectedDevice;
    try std.testing.expectEqualStrings(
        "Studio Interface",
        resolved.name(),
    );
    var malformed_identifier = selected;
    malformed_identifier.length = std.math.maxInt(u8);
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_identifier.slice().len,
    );
    try std.testing.expect(!malformed_identifier.eql(&selected));
    var malformed_catalog = catalog;
    malformed_catalog.descriptors[0].name_length =
        std.math.maxInt(u8);
    try std.testing.expect(!malformed_catalog.valid());
    try std.testing.expectEqual(
        @as(u64, 0),
        malformed_catalog.generation(),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        malformed_catalog.items().len,
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
        pub const event_input = true;
        pub const lv2_urid_unmap_required = true;
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

        urid_unmap: ?*const core.lv2.UridUnmapSink = null,

        pub fn bindLv2UridUnmap(
            self: *@This(),
            unmap: *const core.lv2.UridUnmapSink,
        ) void {
            self.urid_unmap = unmap;
        }

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
    const UnmapHost = struct {
        fn unmap(
            _: ?*anyopaque,
            urid: core.lv2.Urid,
        ) callconv(.c) ?[*:0]const u8 {
            return if (urid == 7)
                "https://example.test/installed-known"
            else
                null;
        }
    };
    var urid_unmap = core.lv2.UridUnmap{
        .handle = null,
        .unmap = UnmapHost.unmap,
    };
    var unmap_feature = core.lv2.Feature{
        .URI = core.lv2.urid_unmap_uri,
        .data = &urid_unmap,
    };
    const sequence_size: i32 = 4096;
    const sequence_options = [_]core.lv2.OptionsOption{
        .{
            .key = MapHost.map(
                null,
                core.lv2.buffer_sequence_size_uri,
            ),
            .size = @sizeOf(i32),
            .type = MapHost.map(null, core.lv2.atom_int_uri),
            .value = &sequence_size,
        },
        .{},
    };
    var options_feature = core.lv2.Feature{
        .URI = core.lv2.options_options_uri,
        .data = @constCast(&sequence_options),
    };
    const features =
        [_:null]?*const core.lv2.Feature{
            &map_feature,
            &unmap_feature,
            &options_feature,
        };
    const descriptor = Adapter.descriptorAt(0) orelse
        return error.MissingLv2Descriptor;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/installed-lv2-gain.lv2",
        features[0..].ptr,
    ) orelse return error.Lv2InstantiateFailed;
    defer descriptor.cleanup(handle);
    const adapter_instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingLv2Instance;
    try std.testing.expectEqual(
        @as(?usize, 4096),
        adapter_instance.configuredSequenceSize(),
    );
    const raw_options = descriptor.extension_data(
        core.lv2.options_interface_uri,
    ) orelse return error.MissingLv2OptionsInterface;
    const options: *const core.lv2.OptionsInterface =
        @ptrCast(@alignCast(raw_options));
    const maximum_key = MapHost.map(
        null,
        core.lv2.buffer_maximum_block_length_uri,
    );
    var unknown_key: core.lv2.Urid = 1;
    while (unknown_key == maximum_key or
        unknown_key == MapHost.map(
            null,
            core.lv2.buffer_minimum_block_length_uri,
        ) or
        unknown_key == MapHost.map(
            null,
            core.lv2.buffer_nominal_block_length_uri,
        ) or
        unknown_key == MapHost.map(
            null,
            core.lv2.buffer_sequence_size_uri,
        )) : (unknown_key += 1)
    {}
    var mixed_options_query = [_]core.lv2.OptionsOption{
        .{ .key = maximum_key },
        .{ .key = unknown_key },
        .{},
    };
    try std.testing.expectEqual(
        core.lv2.options_status_bad_key,
        options.get(handle, &mixed_options_query),
    );
    try std.testing.expectEqual(@as(u32, 0), mixed_options_query[0].size);
    try std.testing.expectEqual(
        @as(core.lv2.Urid, 0),
        mixed_options_query[0].type,
    );
    try std.testing.expect(mixed_options_query[0].value == null);
    const bound_unmap =
        adapter_instance.runtime.instance.plugin.urid_unmap orelse
        return error.MissingLv2UridUnmap;
    const known_uri = bound_unmap.unmap(7) orelse
        return error.MissingLv2KnownUri;
    try std.testing.expectEqualStrings(
        "https://example.test/installed-known",
        known_uri,
    );
    try std.testing.expectEqual(
        @as(usize, 4096),
        core.lv2.maximum_unmapped_uri_bytes,
    );

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
    var metadata_bytes: [8192]u8 = undefined;
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
            .event_input_messages = true,
            .port_notifications = &.{
                .{ .port_symbol = "gain", .protocol = .float },
                .{ .port_symbol = "output", .protocol = .peak },
            },
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
            "lv2:optionalFeature ui:idleInterface , ui:resize , ui:touch , ui:requestValue , ui:portMap , ui:portSubscribe , ui:peakProtocol",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "ui:peakProtocol , atom:eventTransfer , opts:options",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "opts:supportedOption ui:scaleFactor , ui:updateRate , ui:windowTitle ,\n" ++
                "                         ui:backgroundColor , ui:foregroundColor",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "ui:showInterface , opts:interface",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "lv2:symbol \"gain\" ;\n        ui:protocol ui:floatProtocol",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "lv2:symbol \"output\" ;\n        ui:protocol ui:peakProtocol",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "lv2:requiredFeature urid:map , urid:unmap",
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
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "bufsz:sequenceSize",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "pg:mainInput <https://example.test/installed-lv2-gain#main_input_group>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "a pg:OutputGroup , pg:MonoGroup",
        ) != null,
    );

    metadata_writer = std.Io.Writer.fixed(&metadata_bytes);
    try Metadata.writePlugin(&metadata_writer, .{
        .ui = .{
            .uri = "https://example.test/installed-lv2-gain#fixed-ui",
            .binary_name = "installed_fixed_ui.so",
            .class_uri = "http://lv2plug.in/ns/extensions/ui#X11UI",
            .resize_behavior = .fixed,
        },
    });
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "ui:fixedSize , ui:touch",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "ui:resize",
        ) == null,
    );

    const FragmentMetadata = core.lv2.metadata.Generator(
        Gain,
        Adapter,
        "https://example.test/installed-lv2-gain#plugin",
        .{},
    );
    metadata_writer = std.Io.Writer.fixed(&metadata_bytes);
    try FragmentMetadata.writePlugin(&metadata_writer, .{});
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "pg:mainInput <https://example.test/installed-lv2-gain#plugin/main_input_group>",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "#plugin#",
        ) == null,
    );
    metadata_writer = std.Io.Writer.fixed(&metadata_bytes);
    try std.testing.expectError(
        error.DuplicateLv2ResourceUri,
        FragmentMetadata.writePlugin(&metadata_writer, .{
            .ui = .{
                .uri = "https://example.test/installed-lv2-gain#plugin/main_input_group",
                .binary_name = "installed_lv2_gain_ui.so",
                .class_uri = "http://lv2plug.in/ns/extensions/ui#X11UI",
            },
        }),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        metadata_writer.buffered().len,
    );
}

test "installed core package projects a dynamic topology to LV2 ports" {
    const Probe = struct {
        const Topology =
            core.plugin.BoundedDynamicAudioBusTopology(1);

        pub const name = "Installed LV2 Topology Projection";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const event_input = false;
        pub const maximum_auxiliary_audio_buses = 1;
        pub const audio_bus_topology = makeTopology();

        fn makeTopology() Topology {
            var topology = Topology.init(
                core.plugin.DynamicAudioBus.fixed(
                    .mono,
                    true,
                ) catch unreachable,
                core.plugin.DynamicAudioBus.fixed(
                    .mono,
                    true,
                ) catch unreachable,
            ) catch unreachable;
            _ = topology.addAuxiliary(
                .input,
                core.plugin.DynamicAudioBus.fixed(
                    .mono,
                    true,
                ) catch unreachable,
            ) catch unreachable;
            _ = topology.addAuxiliary(
                .output,
                core.plugin.DynamicAudioBus.fixed(
                    .mono,
                    true,
                ) catch unreachable,
            ) catch unreachable;
            return topology;
        }

        pub fn process(
            _: *@This(),
            context: *core.process.BoundedProcessContext(
                f32,
                maximum_auxiliary_audio_buses,
            ),
        ) void {
            const main_input = context.inputChannel(0) orelse return;
            const main_output = context.outputChannel(0) orelse return;
            @memcpy(main_output, main_input);
            const auxiliary_input =
                context.sidechainInputChannel(0) orelse return;
            const auxiliary_output =
                context.auxiliaryOutputChannel(0) orelse return;
            @memcpy(auxiliary_output, auxiliary_input);
        }
    };
    const Adapter = core.lv2.CoreAdapter(
        Probe,
        "https://example.test/installed-lv2-topology-projection",
        2,
    );
    try std.testing.expect(Adapter.dynamic_audio_topology_projected);
    try std.testing.expectEqual(@as(usize, 5), Adapter.port_count);

    const descriptor = &Adapter.descriptor;
    const empty_features = [_:null]?*const core.lv2.Feature{};
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/installed-lv2-topology-projection.lv2",
        &empty_features,
    ) orelse return error.Lv2InstantiateFailed;
    defer descriptor.cleanup(handle);

    const main_input = [_]f32{ 0.25, -0.5 };
    const auxiliary_input = [_]f32{ 0.75, -1.0 };
    var main_output = [_]f32{0.0} ** 2;
    var auxiliary_output = [_]f32{0.0} ** 2;
    var latency: f32 = -1.0;
    const ports = [_]*anyopaque{
        @constCast(&main_input),
        @constCast(&auxiliary_input),
        &main_output,
        &auxiliary_output,
        &latency,
    };
    for (ports, 0..) |port, index|
        descriptor.connect_port(handle, @intCast(index), port);
    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, 2);
    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingLv2Instance;
    try std.testing.expectEqual(
        core.lv2.RunStatus.succeeded,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(f32, &main_input, &main_output);
    try std.testing.expectEqualSlices(
        f32,
        &auxiliary_input,
        &auxiliary_output,
    );

    descriptor.connect_port(handle, 1, null);
    descriptor.connect_port(handle, 3, null);
    main_output = @splat(0.0);
    descriptor.run(handle, 2);
    try std.testing.expectEqual(
        core.lv2.RunStatus.succeeded,
        instance.last_run_status,
    );
    try std.testing.expectEqualSlices(f32, &main_input, &main_output);

    const Generated = core.lv2.metadata.Generator(
        Probe,
        Adapter,
        "https://example.test/installed-lv2-topology-projection",
        .{},
    );
    var metadata_bytes: [8192]u8 = undefined;
    var metadata_writer = std.Io.Writer.fixed(&metadata_bytes);
    try Generated.writePlugin(&metadata_writer, .{});
    try std.testing.expectEqual(
        @as(usize, 2),
        std.mem.count(
            u8,
            metadata_writer.buffered(),
            "lv2:portProperty lv2:connectionOptional",
        ),
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "aux_1_input_group",
        ) != null,
    );
    try std.testing.expect(
        std.mem.indexOf(
            u8,
            metadata_writer.buffered(),
            "aux_1_output_group",
        ) != null,
    );
}

test "installed core package compiles typed LV2 Patch declarations" {
    const Probe = struct {
        mode: i32 = 3,
        graph_atom_type: core.lv2.Urid = 1,
        state_changed: ?*core.lv2.StateChangedSink = null,
        log: ?*core.lv2.LogSink = null,

        pub const name = "Installed LV2 Patch Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: core.plugin.AudioBusLayout = .mono;
        pub const audio_output_layout: core.plugin.AudioBusLayout = .mono;
        pub const event_input = true;
        pub const event_output = true;
        pub const lv2_thread_safe_restore = true;
        pub const lv2_patch_response_capacity = 256;
        pub const lv2_patch_graph_operations = true;
        pub const lv2_patch_graph_queries = true;
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

        pub fn bindLv2StateChanged(
            self: *@This(),
            state_changed: *core.lv2.StateChangedSink,
        ) void {
            self.state_changed = state_changed;
        }

        pub fn bindLv2Log(
            self: *@This(),
            log: *core.lv2.LogSink,
        ) void {
            self.log = log;
        }

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

        pub fn applyLv2PatchGraphRequest(
            _: *@This(),
            request: core.lv2.PatchGraphRequest,
        ) !void {
            switch (request.operation) {
                .put => |operation| {
                    if (operation.subject == 0 or
                        operation.body.atom_type == 0)
                        return error.InvalidPatchGraphRequest;
                },
                .insert => |operation| {
                    if (operation.subject == 0 or
                        operation.body.atom_type == 0)
                        return error.InvalidPatchGraphRequest;
                },
                .patch => |operation| {
                    if (operation.subject == 0 or
                        operation.add.atom_type == 0 or
                        operation.remove.atom_type == 0)
                        return error.InvalidPatchGraphRequest;
                },
                .delete => |operation| {
                    if (operation.subjects.len == 0 or
                        operation.subjects[0] == 0)
                        return error.InvalidPatchGraphRequest;
                },
                .copy => |operation| {
                    if (operation.subjects.len == 0 or
                        operation.subjects[0] == 0 or
                        operation.destination == 0)
                        return error.InvalidPatchGraphRequest;
                },
                .move => |operation| {
                    if (operation.subject == 0 or
                        operation.destination == 0)
                        return error.InvalidPatchGraphRequest;
                },
            }
        }

        pub fn readLv2PatchGraph(
            self: *const @This(),
            _: core.lv2.PatchGraphGetRequest,
        ) !core.lv2.PatchAtomValue {
            return .{
                .atom_type = self.graph_atom_type,
                .body = std.mem.asBytes(&self.mode),
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
    try std.testing.expect(Adapter.patch_graph_query_enabled);
    try std.testing.expect(Adapter.state_changed_enabled);
    try std.testing.expect(Adapter.log_enabled);
    try std.testing.expect(Adapter.thread_safe_restore_enabled);
    try std.testing.expect(Adapter.worker_enabled);
    const request_reference = core.lv2.PatchRequestReference{
        .atom_type = 1,
        .id = 2,
        .object_type = 3,
    };
    const graph_query = core.lv2.PatchGraphGetRequest{
        .subject = 4,
        .request = request_reference,
    };
    const retained_request = graph_query.request orelse
        return error.MissingPatchRequestReference;
    try std.testing.expectEqual(
        request_reference.id,
        retained_request.id,
    );
    try std.testing.expect(Adapter.event_input_port != null);
    try std.testing.expect(Adapter.event_output_port != null);
    try std.testing.expect(@sizeOf(Adapter) > 0);
    try std.testing.expect(Adapter.descriptorAt(0) != null);
}

test "installed core package preserves LV2 log format and payload" {
    const LogCapture = extern struct {
        call_count: u32 = 0,
        last_type: core.lv2.Urid = 0,
        result: c_int = 37,
        format_size: usize = 0,
        message_size: usize = 0,
        format: [16]u8 = @splat(0),
        message: [128]u8 = @splat(0),
    };
    const HostMap = struct {
        fn map(
            _: ?*anyopaque,
            uri: [*:0]const u8,
        ) callconv(.c) core.lv2.Urid {
            if (std.mem.eql(
                u8,
                std.mem.span(uri),
                core.lv2.log_trace_uri,
            )) return 71;
            return 1;
        }
    };
    const Probe = struct {
        pub const name = "Installed LV2 Log Probe";
        pub const vendor = "zig-vst3";
        pub const audio_input_layout: core.plugin.AudioBusLayout = .none;
        pub const audio_output_layout: core.plugin.AudioBusLayout = .none;
        pub const Params = struct {};

        log: ?*core.lv2.LogSink = null,
        result: ?c_int = null,

        pub fn bindLv2Log(
            self: *@This(),
            log: *core.lv2.LogSink,
        ) void {
            self.log = log;
        }

        pub fn process(
            self: *@This(),
            _: *core.process.ProcessContext(f32),
        ) void {
            const log = self.log orelse return;
            self.result = log.trace("installed process 100% complete");
        }
    };
    const Adapter = core.lv2.CoreAdapter(
        Probe,
        "https://example.test/installed-log",
        8,
    );
    var capture = LogCapture{};
    var map = core.lv2.UridMap{
        .handle = null,
        .map = HostMap.map,
    };
    var log = core.lv2.LogFeature{
        .handle = &capture,
        .printf = zig_lv2_log_capture_printf,
        .vprintf = null,
    };
    var map_feature = core.lv2.Feature{
        .URI = core.lv2.urid_map_uri,
        .data = &map,
    };
    var log_feature = core.lv2.Feature{
        .URI = core.lv2.log_log_uri,
        .data = &log,
    };
    const features = [_:null]?*const core.lv2.Feature{
        &map_feature,
        &log_feature,
    };
    const descriptor = &Adapter.descriptor;
    const handle = descriptor.instantiate(
        descriptor,
        48_000.0,
        "/tmp/installed-log.lv2",
        features[0..].ptr,
    ) orelse return error.InstantiateFailed;
    defer descriptor.cleanup(handle);
    var latency: f32 = -1;
    descriptor.connect_port(
        handle,
        Adapter.latency_output_port,
        &latency,
    );
    if (descriptor.activate) |activate| activate(handle);
    descriptor.run(handle, 8);
    const instance = Adapter.instanceFromHandle(handle) orelse
        return error.MissingInstance;
    try std.testing.expectEqual(
        @as(?c_int, 37),
        instance.runtime.instance.plugin.result,
    );
    try std.testing.expectEqual(@as(u32, 1), capture.call_count);
    try std.testing.expectEqual(@as(core.lv2.Urid, 71), capture.last_type);
    try std.testing.expectEqual(@as(usize, 2), capture.format_size);
    try std.testing.expectEqualSlices(u8, "%s", capture.format[0..2]);
    try std.testing.expectEqual(
        "installed process 100% complete".len,
        capture.message_size,
    );
    try std.testing.expectEqualSlices(
        u8,
        "installed process 100% complete",
        capture.message[0..capture.message_size],
    );
}

extern fn zig_lv2_log_capture_printf(
    raw_capture: ?*anyopaque,
    log_type: core.lv2.Urid,
    format: [*:0]const u8,
    ...,
) callconv(.c) c_int;

test "installed package exposes validated lazy MIDI endpoint replies" {
    const descriptor = core.process.MidiEndpointDescriptor{
        .info = .{
            .version_major = 1,
            .version_minor = 1,
            .function_block_count = 0,
            .static_function_blocks = false,
            .supports_midi1 = true,
            .supports_midi2 = false,
            .supports_receive_jr = false,
            .supports_transmit_jr = false,
        },
        .identity = .{
            .manufacturer = .{ 0x7d, 0, 0 },
            .family = .{ 1, 0 },
            .model = .{ 1, 0 },
            .revision = .{ 1, 0, 0, 0 },
        },
        .name = "Endpoint",
        .product_instance_id = "INSTALLED-1",
        .configuration = .{ .protocol = .midi1 },
        .function_blocks = &.{},
    };
    var responder = try core.process.MidiEndpointResponder.init(descriptor);
    var replies = try responder.handle(.{ .payload = .{
        .endpoint_discovery = .{
            .version_major = 1,
            .version_minor = 1,
            .filter = core.process.MidiEndpointFilter.all().bits(),
        },
    } });
    try std.testing.expect(replies.valid());
    var packet_count: usize = 0;
    while (try replies.next()) |_| packet_count += 1;
    try std.testing.expectEqual(@as(usize, 5), packet_count);
    try std.testing.expect(replies.valid());
}

test "installed package exposes validated UMP iteration" {
    const words = [_]u32{
        0x2090_3c7f,
        0x4090_3c00,
        0xffff_0000,
    };
    var iterator = core.process.UmpIterator{ .source = &words };
    try std.testing.expect(iterator.valid());
    try std.testing.expect((try iterator.next()) != null);
    try std.testing.expect((try iterator.next()) != null);
    try std.testing.expect((try iterator.next()) == null);
    iterator.cursor = 2;
    try std.testing.expect(!iterator.valid());
    try std.testing.expectError(
        error.InvalidUmpIteratorState,
        iterator.next(),
    );
    try std.testing.expectEqual(@as(usize, 2), iterator.cursor);
    iterator.cursor = words.len + 1;
    try std.testing.expect(!iterator.valid());
    try std.testing.expectError(
        error.InvalidUmpIteratorState,
        iterator.next(),
    );
    try std.testing.expectEqual(words.len + 1, iterator.cursor);
}

test "installed package contains malformed segment iterator state" {
    var parameter_items = [_]core.process.ParameterChange{
        .{ .id = 1, .sample_offset = 2, .normalized = 0.5 },
    };
    var event_items = [_]core.process.Event{
        core.process.Event.noteOn(3, 0, 60, 1.0),
    };
    const parameter_changes = try core.process.ParameterChanges.init(
        &parameter_items,
        4,
    );
    const events = try core.process.Events.init(&event_items, 4);

    var parameter_segments = parameter_changes.blockSegments(4);
    try std.testing.expect(parameter_segments.valid());
    parameter_segments.next_start = 5;
    try std.testing.expect(!parameter_segments.valid());
    try std.testing.expect(parameter_segments.next() == null);
    try std.testing.expectEqual(@as(usize, 5), parameter_segments.next_start);

    var event_segments = events.blockSegments(4);
    try std.testing.expect(event_segments.valid());
    event_segments.next_start = 5;
    try std.testing.expect(!event_segments.valid());
    try std.testing.expect(event_segments.next() == null);
    try std.testing.expectEqual(@as(usize, 5), event_segments.next_start);

    var process_segments = core.process.ProcessBlockSegmentIterator{
        .parameter_changes = parameter_changes,
        .events = events,
        .frame_count = 4,
        .next_start = 5,
    };
    try std.testing.expect(!process_segments.valid());
    try std.testing.expect(process_segments.next() == null);
    try std.testing.expectEqual(@as(usize, 5), process_segments.next_start);

    var parameter_filter = parameter_changes.forId(1);
    try std.testing.expect(parameter_filter.valid());
    _ = parameter_filter.next();
    parameter_filter.last_index = parameter_items.len;
    try std.testing.expect(!parameter_filter.valid());
    try std.testing.expect(parameter_filter.next() == null);

    var event_filter = events.ofKind(.note_on);
    try std.testing.expect(event_filter.valid());
    _ = event_filter.next();
    event_filter.last_index = event_items.len;
    try std.testing.expect(!event_filter.valid());
    try std.testing.expect(event_filter.next() == null);

    var mutated_parameter_filter = parameter_changes.forId(1);
    parameter_items[0].normalized = std.math.nan(f64);
    try std.testing.expect(!mutated_parameter_filter.valid());
    try std.testing.expect(mutated_parameter_filter.next() == null);
    try std.testing.expect(mutated_parameter_filter.last_offset == null);

    var mutated_event_filter = events.ofKind(.note_on);
    event_items[0].velocity = std.math.nan(f32);
    try std.testing.expect(!mutated_event_filter.valid());
    try std.testing.expect(mutated_event_filter.next() == null);
    try std.testing.expect(mutated_event_filter.last_offset == null);

    parameter_items[0].normalized = 0.5;
    var forged_parameter_extent = parameter_changes.forId(1);
    forged_parameter_extent.changes.frame_count = 8;
    parameter_items[0].sample_offset = 6;
    try std.testing.expect(!forged_parameter_extent.valid());
    try std.testing.expect(forged_parameter_extent.next() == null);
    try std.testing.expect(forged_parameter_extent.last_offset == null);

    event_items[0].velocity = 1.0;
    var forged_event_extent = events.ofKind(.note_on);
    forged_event_extent.events.frame_count = 8;
    event_items[0].sample_offset = 6;
    try std.testing.expect(!forged_event_extent.valid());
    try std.testing.expect(forged_event_extent.next() == null);
    try std.testing.expect(forged_event_extent.last_offset == null);
}
