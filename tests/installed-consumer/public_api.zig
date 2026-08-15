const std = @import("std");
const plug = @import("zig-vst3-plugin");
const core = @import("zig-vst3-plugin-core");
const vst3 = @import("zig-vst3");

fn requireDecls(comptime namespace: type, comptime names: []const []const u8) void {
    inline for (names) |name| {
        if (!@hasDecl(namespace, name))
            @compileError("missing public API declaration: " ++ name);
    }
}

test "installed package compiles compatibility-ready framework entry points" {
    comptime {
        requireDecls(plug, &.{
            "core",            "gui",                          "parameters",    "realtime_audit",              "lv2",        "dsp",
            "resource",        "plugin",                       "process",       "state",                       "units",      "version",
            "HostRequestSink", "HostChange",                   "Vst3Processor", "Vst3ProcessorWithParameters", "Vst3Effect", "Vst3EffectWithParameters",
            "Vst3Controller",  "Vst3ControllerWithParameters",
        });
        requireDecls(core.plugin, &.{
            "PluginSpec",                 "PluginInstance",                    "ProcessorRuntime",
            "OfflineRenderer",            "AudioCallback",                     "AudioDevice",
            "StandaloneRuntime",          "StandaloneApplication",             "StandaloneShell",
            "BoundedCaptureRateBridge",   "BoundedCaptureRateCallbackAdapter", "CaptureRateBridgeConfig",
            "CaptureRateLifecycleConfig", "CaptureRateRenderReport",           "SplitAudioCallback",
        });
        requireDecls(core.lv2, &.{
            "metadata",                  "ui",             "Descriptor",      "CoreAdapter",
            "CoreAdapterWithParameters", "StateInterface", "WorkerInterface", "ProgramsInterface",
        });
        requireDecls(core.audio_unit, &.{
            "RenderStatistics", "RenderOptions", "RenderAdapter",
        });
        requireDecls(core.audio_unit_v2, &.{
            "AudioComponentPlugInInterface", "ComponentDispatch",
            "ComponentFactory",              "NativeComponentFactory",
            "RenderPropertyAdapter",         "AudioTimeStamp",
            "AudioUnitParameterEvent",
        });
        requireDecls(plug.state, &.{
            "maximum_parameter_id_migrations",
            "readParameterStateWithMigrations",
            "readParameterStateWithMigrationsReport",
            "validateParameterIdMigrations",
        });
        requireDecls(vst3, &.{
            "ara_document_controller", "ara_extension",         "ara_factory",
            "ara_model",               "ara_playback_renderer", "ara_source_cache",
            "ara_spectral_transform",  "ara_tempo_warp",        "ara_tuning_analysis",
            "ara_vst3",                "vstgui",                "vstgui_lv2_backend",
        });
        requireDecls(vst3.vstgui, &.{
            "Parameter",     "Meter",         "Graph",        "Viewport",          "RangeSelection",
            "PresetBrowser", "ActionMenu",    "ActionButton", "EditableLabel",     "ProgressIndicator",
            "Piano",         "StepSequencer", "FileImporter", "AudioFileImporter", "Asset",
            "Canvas",        "Skin",          "Theme",        "Layout",            "EditorDescription",
            "createEditor",
        });
    }

    try std.testing.expect(!@hasDecl(plug, "backendVersion"));
    try std.testing.expect(!@hasDecl(core, "lv2_metadata"));
}

test "capture-rate callback records its stable owner address" {
    const Adapter = core.plugin.BoundedCaptureRateCallbackAdapter(
        f32,
        1,
        32,
        8,
        8,
        0,
    );
    const Callback = struct {
        fn process(_: *anyopaque, _: core.plugin.CallbackBlock(f32)) void {}
    };
    var context: u8 = 0;
    var adapter = try Adapter.init(.{
        .main_input_channel_count = 1,
        .capture_sample_rate = 48_000,
        .render_sample_rate = 48_000,
        .drift = .{ .target_buffer_frames = 16 },
    }, .{
        .context = &context,
        .process_block = Callback.process,
    });
    const callback = adapter.splitCallback();
    try std.testing.expectEqual(@intFromPtr(&adapter), @intFromPtr(callback.context));
}
