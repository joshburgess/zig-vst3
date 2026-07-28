const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const native_vstgui = target.result.os.tag == b.graph.host.result.os.tag and
        (target.result.os.tag == .macos or target.result.os.tag == .linux or target.result.os.tag == .windows);
    const gui_options = b.addOptions();
    gui_options.addOption(bool, "vstgui_adapter_enabled", native_vstgui);

    const zig_vst3 = b.addModule("zig-vst3", .{
        .root_source_file = b.path("zig-vst3/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ara_translate = b.addTranslateC(.{
        .root_source_file = b.path("vendor/ARA_API/ARAInterface.h"),
        .target = target,
        .optimize = optimize,
    });
    ara_translate.addIncludePath(b.path("vendor/ARA_API"));
    const ara_raw = ara_translate.createModule();
    const zig_vst3_ara = b.addModule("zig-vst3-ara", .{
        .root_source_file = b.path("zig-vst3/src/ara_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    zig_vst3_ara.addImport("ara-raw", ara_raw);
    zig_vst3.addImport("zig-vst3-ara", zig_vst3_ara);
    const zig_vst3_plugin_core = b.addModule("zig-vst3-plugin-core", .{
        .root_source_file = b.path("zig-vst3-plugin/src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zig_vst3_core_audio = b.addModule("zig-vst3-coreaudio", .{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/core_audio.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addCoreAudioBackend(b, zig_vst3_core_audio, target);
    zig_vst3_core_audio.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_wasapi = b.addModule("zig-vst3-wasapi", .{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/wasapi.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addWasapiBackend(b, zig_vst3_wasapi, target);
    zig_vst3_wasapi.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_alsa = b.addModule("zig-vst3-alsa", .{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/alsa.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addAlsaBackend(b, zig_vst3_alsa, target);
    zig_vst3_alsa.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_alsa_midi = b.addModule("zig-vst3-alsamidi", .{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/alsa_midi.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addAlsaMidiBackend(b, zig_vst3_alsa_midi, target);
    zig_vst3_alsa_midi.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_win_midi = b.addModule("zig-vst3-winmidi", .{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/win_midi.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addWinMidiBackend(b, zig_vst3_win_midi, target);
    zig_vst3_win_midi.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_win_window = b.addModule("zig-vst3-winwindow", .{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/win_window.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addWinWindowBackend(b, zig_vst3_win_window, target);
    zig_vst3_win_window.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_cocoa_window = b.addModule(
        "zig-vst3-cocoawindow",
        .{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/cocoa_window.zig",
            ),
            .target = target,
            .optimize = optimize,
        },
    );
    addCocoaWindowBackend(b, zig_vst3_cocoa_window, target);
    zig_vst3_cocoa_window.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_x11_window = b.addModule(
        "zig-vst3-x11window",
        .{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/x11_window.zig",
            ),
            .target = target,
            .optimize = optimize,
        },
    );
    addX11WindowBackend(b, zig_vst3_x11_window, target);
    zig_vst3_x11_window.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_wayland_window = b.addModule(
        "zig-vst3-waylandwindow",
        .{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/wayland_window.zig",
            ),
            .target = target,
            .optimize = optimize,
        },
    );
    addWaylandWindowBackend(b, zig_vst3_wayland_window, target);
    zig_vst3_wayland_window.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_core_midi = b.addModule("zig-vst3-coremidi", .{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/core_midi.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addCoreMidiBackend(b, zig_vst3_core_midi, target);
    zig_vst3_core_midi.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    zig_vst3.addImport("zig-vst3-plugin-core", zig_vst3_plugin_core);
    zig_vst3.addOptions("zig-vst3-gui-options", gui_options);

    const zig_vst3_plugin = b.addModule("zig-vst3-plugin", .{
        .root_source_file = b.path("zig-vst3-plugin/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zig_vst3_plugin.addImport("zig-vst3-plugin-core", zig_vst3_plugin_core);
    zig_vst3_plugin.addImport("zig-vst3", zig_vst3);

    const entry_symbols_step = b.step("entry-symbols", "Verify native VST3 module entry exports");
    const vstgui_adapter_step = b.step("vstgui-adapter", "Build the optional VSTGUI adapter");
    const vstgui_native_test_step = b.step("test-vstgui-native", "Run native VSTGUI interaction, accessibility, and visual tests");
    if (native_vstgui) {
        const build_vstgui = if (target.result.os.tag == .windows)
            b.addSystemCommand(&.{ "powershell", "-NoProfile", "-File", "scripts/build_vstgui.ps1" })
        else
            b.addSystemCommand(&.{"scripts/build_vstgui.sh"});
        vstgui_adapter_step.dependOn(&build_vstgui.step);

        const test_vstgui = if (target.result.os.tag == .windows)
            b.addSystemCommand(&.{ "powershell", "-NoProfile", "-File", "scripts/build_vstgui.ps1", "-Mode", "test" })
        else
            b.addSystemCommand(&.{ "scripts/build_vstgui.sh", "test" });
        test_vstgui.step.dependOn(vstgui_adapter_step);
        vstgui_native_test_step.dependOn(&test_vstgui.step);
    }

    const example_plugin_options = [_]ExamplePluginOptions{
        .{
            .short_name = "gain",
            .display_name = "gain",
            .artifact_name = "zig_vst3_gain",
            .root_source_file = "zig-vst3/src/gain_plugin.zig",
            .core_example_source_file = "examples/gain_core.zig",
            .bundle_id = "dev.zig-vst3.gain",
        },
        .{
            .short_name = "mono-gain",
            .display_name = "mono gain",
            .artifact_name = "zig_vst3_mono_gain",
            .root_source_file = "examples/mono_gain_plugin.zig",
            .core_example_source_file = "examples/mono_gain_core.zig",
            .bundle_id = "dev.zig-vst3.mono-gain",
        },
        .{
            .short_name = "surround-gain",
            .display_name = "surround gain",
            .artifact_name = "zig_vst3_surround_gain",
            .root_source_file = "examples/surround_gain_plugin.zig",
            .core_example_source_file = "examples/surround_gain_core.zig",
            .bundle_id = "dev.zig-vst3.surround-gain",
        },
        .{
            .short_name = "sidechain-ducker",
            .display_name = "sidechain ducker",
            .artifact_name = "zig_vst3_sidechain_ducker",
            .root_source_file = "examples/sidechain_ducker_plugin.zig",
            .core_example_source_file = "examples/sidechain_ducker_core.zig",
            .bundle_id = "dev.zig-vst3.sidechain-ducker",
        },
        .{
            .short_name = "aux-output-splitter",
            .display_name = "auxiliary output splitter",
            .artifact_name = "zig_vst3_aux_output_splitter",
            .root_source_file = "examples/aux_output_splitter_plugin.zig",
            .core_example_source_file = "examples/aux_output_splitter_core.zig",
            .bundle_id = "dev.zig-vst3.aux-output-splitter",
        },
        .{
            .short_name = "resource-swap",
            .display_name = "resource swap",
            .artifact_name = "zig_vst3_resource_swap",
            .root_source_file = "examples/resource_swap_plugin.zig",
            .core_example_source_file = "examples/resource_swap_core.zig",
            .bundle_id = "dev.zig-vst3.resource-swap",
        },
        .{
            .short_name = "fixed-rate",
            .display_name = "fixed rate processor",
            .artifact_name = "zig_vst3_fixed_rate",
            .root_source_file = "examples/fixed_rate_plugin.zig",
            .core_example_source_file = "examples/fixed_rate_core.zig",
            .bundle_id = "dev.zig-vst3.fixed-rate",
        },
        .{
            .short_name = "ara-playback",
            .display_name = "ARA playback",
            .artifact_name = "zig_vst3_ara_playback",
            .root_source_file = "examples/ara_playback_plugin.zig",
            .core_example_source_file = "examples/ara_playback_core.zig",
            .bundle_id = "dev.zig-vst3.ara-playback",
        },
        .{
            .short_name = "model-shell",
            .display_name = "model shell",
            .artifact_name = "zig_vst3_model_shell",
            .root_source_file = "examples/model_shell_plugin.zig",
            .core_example_source_file = "examples/model_shell_core.zig",
            .bundle_id = "dev.zig-vst3.model-shell",
        },
        .{
            .short_name = "c-kernel",
            .display_name = "C kernel probe",
            .artifact_name = "zig_vst3_c_kernel",
            .root_source_file = "examples/c_kernel_plugin.zig",
            .core_example_source_file = "examples/c_kernel_core.zig",
            .bundle_id = "dev.zig-vst3.c-kernel",
            .c_kernel = true,
        },
        .{
            .short_name = "bypass",
            .display_name = "bypass",
            .artifact_name = "zig_vst3_bypass",
            .root_source_file = "zig-vst3/src/bypass_plugin.zig",
            .core_example_source_file = "examples/bypass_core.zig",
            .bundle_id = "dev.zig-vst3.bypass",
        },
        .{
            .short_name = "mode-gain",
            .display_name = "mode gain",
            .artifact_name = "zig_vst3_mode_gain",
            .root_source_file = "zig-vst3/src/mode_gain_plugin.zig",
            .core_example_source_file = "examples/mode_gain_core.zig",
            .bundle_id = "dev.zig-vst3.mode-gain",
        },
        .{
            .short_name = "voice-mix",
            .display_name = "voice mix",
            .artifact_name = "zig_vst3_voice_mix",
            .root_source_file = "zig-vst3/src/voice_mix_plugin.zig",
            .core_example_source_file = "examples/voice_mix_core.zig",
            .bundle_id = "dev.zig-vst3.voice-mix",
        },
        .{
            .short_name = "note-gate",
            .display_name = "note gate",
            .artifact_name = "zig_vst3_note_gate",
            .root_source_file = "zig-vst3/src/note_gate_plugin.zig",
            .core_example_source_file = "examples/note_gate_core.zig",
            .bundle_id = "dev.zig-vst3.note-gate",
        },
        .{
            .short_name = "event-echo",
            .display_name = "event echo",
            .artifact_name = "zig_vst3_event_echo",
            .root_source_file = "zig-vst3/src/event_echo_plugin.zig",
            .core_example_source_file = "examples/event_echo_core.zig",
            .bundle_id = "dev.zig-vst3.event-echo",
        },
        .{
            .short_name = "event-monitor",
            .display_name = "event monitor",
            .artifact_name = "zig_vst3_event_monitor",
            .root_source_file = "zig-vst3/src/event_monitor_plugin.zig",
            .core_example_source_file = "examples/event_monitor_core.zig",
            .bundle_id = "dev.zig-vst3.event-monitor",
        },
        .{
            .short_name = "sine-synth",
            .display_name = "sine synth",
            .artifact_name = "zig_vst3_sine_synth",
            .root_source_file = "zig-vst3/src/sine_synth_plugin.zig",
            .core_example_source_file = "examples/sine_synth_core.zig",
            .bundle_id = "dev.zig-vst3.sine-synth",
        },
        .{
            .short_name = "editor-smoke",
            .display_name = "editor smoke",
            .artifact_name = "zig_vst3_editor_smoke",
            .root_source_file = "zig-vst3/src/editor_smoke_plugin.zig",
            .core_example_source_file = "examples/editor_smoke_core.zig",
            .bundle_id = "dev.zig-vst3.editor-smoke",
        },
        .{
            .short_name = "channel-strip",
            .display_name = "channel strip",
            .artifact_name = "zig_vst3_channel_strip",
            .root_source_file = "examples/channel_strip_plugin.zig",
            .core_example_source_file = "examples/channel_strip_core.zig",
            .bundle_id = "dev.zig-vst3.channel-strip",
        },
        .{
            .short_name = "parametric-eq",
            .display_name = "parametric EQ",
            .artifact_name = "zig_vst3_parametric_eq",
            .root_source_file = "examples/parametric_eq_plugin.zig",
            .core_example_source_file = "examples/parametric_eq_core.zig",
            .bundle_id = "dev.zig-vst3.parametric-eq",
        },
        .{
            .short_name = "resonant-filter",
            .display_name = "resonant filter",
            .artifact_name = "zig_vst3_resonant_filter",
            .root_source_file = "examples/resonant_filter_plugin.zig",
            .core_example_source_file = "examples/resonant_filter_core.zig",
            .bundle_id = "dev.zig-vst3.resonant-filter",
        },
        .{
            .short_name = "ir-loader",
            .display_name = "IR loader",
            .artifact_name = "zig_vst3_ir_loader",
            .root_source_file = "examples/ir_loader_plugin.zig",
            .core_example_source_file = "examples/ir_loader_core.zig",
            .bundle_id = "dev.zig-vst3.ir-loader",
        },
        .{
            .short_name = "sample-player",
            .display_name = "sample player",
            .artifact_name = "zig_vst3_sample_player",
            .root_source_file = "examples/sample_player_plugin.zig",
            .core_example_source_file = "examples/sample_player_core.zig",
            .bundle_id = "dev.zig-vst3.sample-player",
        },
    };

    var example_plugins: [example_plugin_options.len]ExamplePluginSteps = undefined;
    for (example_plugin_options, 0..) |options, index| {
        example_plugins[index] = addExamplePlugin(b, target, optimize, zig_vst3, zig_vst3_plugin_core, zig_vst3_plugin, gui_options, native_vstgui, entry_symbols_step, vstgui_adapter_step, options);
        if (options.c_kernel) {
            const c_kernel_test_step = b.step("test-c-kernel", "Run C Kernel Probe plugin and differential tests");
            c_kernel_test_step.dependOn(&b.addRunArtifact(example_plugins[index].plugin_tests).step);
            c_kernel_test_step.dependOn(&b.addRunArtifact(example_plugins[index].core_example_tests).step);
        }
        if (std.mem.eql(
            u8,
            options.short_name,
            "ara-playback",
        )) {
            const ara_product_vst3 = b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3/src/root.zig",
                ),
                .target = target,
                .optimize = optimize,
            });
            ara_product_vst3.addImport(
                "zig-vst3-plugin-core",
                zig_vst3_plugin_core,
            );
            ara_product_vst3.addImport(
                "zig-vst3-ara",
                zig_vst3_ara,
            );
            ara_product_vst3.addOptions(
                "zig-vst3-gui-options",
                gui_options,
            );
            const ara_product_module = b.createModule(.{
                .root_source_file = b.path(
                    options.root_source_file,
                ),
                .target = target,
                .optimize = optimize,
            });
            ara_product_module.addImport(
                "zig-vst3-plugin-core",
                zig_vst3_plugin_core,
            );
            ara_product_module.addImport(
                "zig-vst3",
                ara_product_vst3,
            );
            const ara_product_tests = b.addTest(.{
                .root_module = ara_product_module,
            });
            const ara_product_test_step = b.step(
                "test-ara-playback-product",
                "Test and build the concrete ARA playback product",
            );
            ara_product_test_step.dependOn(
                &b.addRunArtifact(
                    ara_product_tests,
                ).step,
            );
            ara_product_test_step.dependOn(
                &b.addRunArtifact(
                    example_plugins[index].core_example_tests,
                ).step,
            );
            ara_product_test_step.dependOn(
                example_plugins[index].bundles.native,
            );
        }
    }

    const gui_lifecycle_step = b.step("test-gui-lifecycle", "Run headless lifecycle stress for every example editor");
    for (example_plugin_options, example_plugins) |options, plugin| {
        if (!hasReferenceEditor(options.short_name)) continue;
        const plugin_step = b.step(
            b.fmt("test-gui-lifecycle-{s}", .{options.short_name}),
            b.fmt("Run headless lifecycle stress for the {s} editor", .{options.display_name}),
        );
        plugin_step.dependOn(&b.addRunArtifact(plugin.plugin_tests).step);
        gui_lifecycle_step.dependOn(plugin_step);
    }
    const gui_lifecycle_soak_step = b.step("soak-gui-lifecycle", "Repeat every headless editor lifecycle test with crash artifacts");
    gui_lifecycle_soak_step.dependOn(&b.addSystemCommand(&.{ "sh", "scripts/gui_lifecycle_soak.sh" }).step);

    var example_bundle_steps: [example_plugin_options.len]Vst3BundleSteps = undefined;
    for (example_plugins, 0..) |plugin, index| {
        example_bundle_steps[index] = plugin.bundles;
    }
    const vst3_test_module = b.createModule(.{
        .root_source_file = b.path("zig-vst3/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    vst3_test_module.addImport("zig-vst3-plugin-core", zig_vst3_plugin_core);
    vst3_test_module.addImport("zig-vst3-ara", zig_vst3_ara);
    vst3_test_module.addOptions("zig-vst3-gui-options", gui_options);
    if (native_vstgui) addVstguiAdapter(vst3_test_module, target);
    const vst3_tests = b.addTest(.{
        .root_module = vst3_test_module,
    });
    if (native_vstgui) vst3_tests.step.dependOn(vstgui_adapter_step);
    const focused_vst3_module = b.createModule(.{
        .root_source_file = b.path("zig-vst3/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    focused_vst3_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    focused_vst3_module.addImport(
        "zig-vst3-ara",
        zig_vst3_ara,
    );
    focused_vst3_module.addOptions(
        "zig-vst3-gui-options",
        gui_options,
    );
    if (native_vstgui)
        addVstguiAdapter(focused_vst3_module, target);
    const focused_vst3_tests = b.addTest(.{
        .root_module = focused_vst3_module,
    });
    if (native_vstgui)
        focused_vst3_tests.step.dependOn(vstgui_adapter_step);
    const vst3_module_test_step = b.step(
        "test-vst3-module",
        "Run the public VST3 module tests without visual benchmarks",
    );
    vst3_module_test_step.dependOn(
        &b.addRunArtifact(focused_vst3_tests).step,
    );

    const ara_tests = b.addTest(.{
        .root_module = zig_vst3_ara,
    });
    const ara_vst3_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig-vst3/src/ara_vst3.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const ara_model_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig-vst3/src/ara_model.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const ara_controller_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3/src/ara_document_controller.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    ara_controller_module.addImport(
        "zig-vst3-ara",
        zig_vst3_ara,
    );
    const ara_controller_tests = b.addTest(.{
        .root_module = ara_controller_module,
    });
    const ara_factory_module = b.createModule(.{
        .root_source_file = b.path("zig-vst3/src/ara_factory.zig"),
        .target = target,
        .optimize = optimize,
    });
    ara_factory_module.addImport(
        "zig-vst3-ara",
        zig_vst3_ara,
    );
    const ara_factory_tests = b.addTest(.{
        .root_module = ara_factory_module,
    });
    const ara_extension_module = b.createModule(.{
        .root_source_file = b.path("zig-vst3/src/ara_extension.zig"),
        .target = target,
        .optimize = optimize,
    });
    ara_extension_module.addImport(
        "zig-vst3-ara",
        zig_vst3_ara,
    );
    const ara_extension_tests = b.addTest(.{
        .root_module = ara_extension_module,
    });
    const ara_playback_renderer_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3/src/ara_playback_renderer.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    ara_playback_renderer_module.addImport(
        "zig-vst3-ara",
        zig_vst3_ara,
    );
    ara_playback_renderer_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const ara_playback_renderer_tests = b.addTest(.{
        .root_module = ara_playback_renderer_module,
    });
    const ara_content_fades_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3/src/ara_content_fades.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    ara_content_fades_module.addImport(
        "zig-vst3-ara",
        zig_vst3_ara,
    );
    ara_content_fades_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const ara_content_fades_tests = b.addTest(.{
        .root_module = ara_content_fades_module,
    });
    const ara_source_cache_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3/src/ara_source_cache.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    ara_source_cache_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const ara_source_cache_tests = b.addTest(.{
        .root_module = ara_source_cache_module,
    });
    const ara_tuning_analysis_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3/src/ara_tuning_analysis.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    ara_tuning_analysis_module.addImport(
        "zig-vst3-ara",
        zig_vst3_ara,
    );
    const ara_tuning_analysis_tests = b.addTest(.{
        .root_module = ara_tuning_analysis_module,
    });
    const ara_tempo_warp_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3/src/ara_tempo_warp.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    ara_tempo_warp_module.addImport(
        "zig-vst3-ara",
        zig_vst3_ara,
    );
    ara_tempo_warp_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const ara_tempo_warp_tests = b.addTest(.{
        .root_module = ara_tempo_warp_module,
    });
    const ara_registration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3/src/ara_registration.zig",
            ),
            .target = target,
            .optimize = optimize,
        }),
    });
    const ara_test_step = b.step(
        "test-ara",
        "Run ARA API, VST3 companion, ABI, and cross-build tests",
    );
    ara_test_step.dependOn(&b.addRunArtifact(ara_tests).step);
    ara_test_step.dependOn(
        &b.addRunArtifact(ara_vst3_tests).step,
    );
    ara_test_step.dependOn(
        &b.addRunArtifact(ara_model_tests).step,
    );
    ara_test_step.dependOn(
        &b.addRunArtifact(ara_controller_tests).step,
    );
    ara_test_step.dependOn(
        &b.addRunArtifact(ara_factory_tests).step,
    );
    ara_test_step.dependOn(
        &b.addRunArtifact(ara_extension_tests).step,
    );
    ara_test_step.dependOn(
        &b.addRunArtifact(
            ara_playback_renderer_tests,
        ).step,
    );
    ara_test_step.dependOn(
        &b.addRunArtifact(ara_content_fades_tests).step,
    );
    ara_test_step.dependOn(
        &b.addRunArtifact(ara_source_cache_tests).step,
    );
    ara_test_step.dependOn(
        &b.addRunArtifact(ara_tuning_analysis_tests).step,
    );
    ara_test_step.dependOn(
        &b.addRunArtifact(ara_tempo_warp_tests).step,
    );
    ara_test_step.dependOn(
        &b.addRunArtifact(ara_registration_tests).step,
    );
    const ara_cross_targets = [_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .gnu,
        }),
    };
    for (ara_cross_targets) |ara_target| {
        const ara_cross_translate = b.addTranslateC(.{
            .root_source_file = b.path(
                "vendor/ARA_API/ARAInterface.h",
            ),
            .target = ara_target,
            .optimize = .ReleaseSafe,
        });
        ara_cross_translate.addIncludePath(
            b.path("vendor/ARA_API"),
        );
        const ara_cross_module = b.createModule(.{
            .root_source_file = b.path("zig-vst3/src/ara_api.zig"),
            .target = ara_target,
            .optimize = .ReleaseSafe,
        });
        ara_cross_module.addImport(
            "ara-raw",
            ara_cross_translate.createModule(),
        );
        const ara_cross_tests = b.addTest(.{
            .root_module = ara_cross_module,
        });
        ara_test_step.dependOn(&ara_cross_tests.step);
        const ara_vst3_cross_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3/src/ara_vst3.zig",
                ),
                .target = ara_target,
                .optimize = .ReleaseSafe,
            }),
        });
        ara_test_step.dependOn(&ara_vst3_cross_tests.step);
        const ara_model_cross_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3/src/ara_model.zig",
                ),
                .target = ara_target,
                .optimize = .ReleaseSafe,
            }),
        });
        ara_test_step.dependOn(&ara_model_cross_tests.step);
        const ara_controller_cross_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3/src/ara_document_controller.zig",
            ),
            .target = ara_target,
            .optimize = .ReleaseSafe,
        });
        ara_controller_cross_module.addImport(
            "zig-vst3-ara",
            ara_cross_module,
        );
        const ara_controller_cross_tests = b.addTest(.{
            .root_module = ara_controller_cross_module,
        });
        ara_test_step.dependOn(&ara_controller_cross_tests.step);
        const ara_factory_cross_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3/src/ara_factory.zig",
            ),
            .target = ara_target,
            .optimize = .ReleaseSafe,
        });
        ara_factory_cross_module.addImport(
            "zig-vst3-ara",
            ara_cross_module,
        );
        const ara_factory_cross_tests = b.addTest(.{
            .root_module = ara_factory_cross_module,
        });
        ara_test_step.dependOn(&ara_factory_cross_tests.step);
        const ara_extension_cross_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3/src/ara_extension.zig",
            ),
            .target = ara_target,
            .optimize = .ReleaseSafe,
        });
        ara_extension_cross_module.addImport(
            "zig-vst3-ara",
            ara_cross_module,
        );
        const ara_extension_cross_tests = b.addTest(.{
            .root_module = ara_extension_cross_module,
        });
        ara_test_step.dependOn(&ara_extension_cross_tests.step);
        const ara_playback_renderer_cross_module =
            b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3/src/ara_playback_renderer.zig",
                ),
                .target = ara_target,
                .optimize = .ReleaseSafe,
            });
        ara_playback_renderer_cross_module.addImport(
            "zig-vst3-ara",
            ara_cross_module,
        );
        ara_playback_renderer_cross_module.addImport(
            "zig-vst3-plugin-core",
            zig_vst3_plugin_core,
        );
        const ara_playback_renderer_cross_tests = b.addTest(.{
            .root_module = ara_playback_renderer_cross_module,
        });
        ara_test_step.dependOn(
            &ara_playback_renderer_cross_tests.step,
        );
        const ara_content_fades_cross_module =
            b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3/src/ara_content_fades.zig",
                ),
                .target = ara_target,
                .optimize = .ReleaseSafe,
            });
        ara_content_fades_cross_module.addImport(
            "zig-vst3-ara",
            ara_cross_module,
        );
        ara_content_fades_cross_module.addImport(
            "zig-vst3-plugin-core",
            zig_vst3_plugin_core,
        );
        const ara_content_fades_cross_tests = b.addTest(.{
            .root_module = ara_content_fades_cross_module,
        });
        ara_test_step.dependOn(
            &ara_content_fades_cross_tests.step,
        );
        const ara_source_cache_cross_module =
            b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3/src/ara_source_cache.zig",
                ),
                .target = ara_target,
                .optimize = .ReleaseSafe,
            });
        ara_source_cache_cross_module.addImport(
            "zig-vst3-plugin-core",
            zig_vst3_plugin_core,
        );
        const ara_source_cache_cross_tests = b.addTest(.{
            .root_module = ara_source_cache_cross_module,
        });
        ara_test_step.dependOn(
            &ara_source_cache_cross_tests.step,
        );
        const ara_tuning_analysis_cross_module =
            b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3/src/ara_tuning_analysis.zig",
                ),
                .target = ara_target,
                .optimize = .ReleaseSafe,
            });
        ara_tuning_analysis_cross_module.addImport(
            "zig-vst3-ara",
            ara_cross_module,
        );
        const ara_tuning_analysis_cross_tests =
            b.addTest(.{
                .root_module = ara_tuning_analysis_cross_module,
            });
        ara_test_step.dependOn(
            &ara_tuning_analysis_cross_tests.step,
        );
        const ara_tempo_warp_cross_module =
            b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3/src/ara_tempo_warp.zig",
                ),
                .target = ara_target,
                .optimize = .ReleaseSafe,
            });
        ara_tempo_warp_cross_module.addImport(
            "zig-vst3-ara",
            ara_cross_module,
        );
        ara_tempo_warp_cross_module.addImport(
            "zig-vst3-plugin-core",
            zig_vst3_plugin_core,
        );
        const ara_tempo_warp_cross_tests = b.addTest(.{
            .root_module = ara_tempo_warp_cross_module,
        });
        ara_test_step.dependOn(
            &ara_tempo_warp_cross_tests.step,
        );
        const ara_registration_cross_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3/src/ara_registration.zig",
                ),
                .target = ara_target,
                .optimize = .ReleaseSafe,
            }),
        });
        ara_test_step.dependOn(
            &ara_registration_cross_tests.step,
        );
    }

    const zig_vst3_plugin_core_test_module = b.createModule(.{
        .root_source_file = b.path("zig-vst3-plugin/src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zig_vst3_core_audio_test_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/core_audio.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addCoreAudioBackend(
        b,
        zig_vst3_core_audio_test_module,
        target,
    );
    zig_vst3_core_audio_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_core_audio_tests = b.addTest(.{
        .root_module = zig_vst3_core_audio_test_module,
    });
    const run_core_audio_tests =
        b.addRunArtifact(zig_vst3_core_audio_tests);
    const core_audio_test_step = b.step(
        "test-coreaudio",
        "Run CoreAudio backend tests and non-macOS compile checks",
    );
    core_audio_test_step.dependOn(&run_core_audio_tests.step);
    const core_audio_cross_build_step = b.step(
        "test-coreaudio-builds",
        "Compile the optional CoreAudio module for non-macOS targets",
    );
    const core_audio_cross_targets =
        [_]std.Build.ResolvedTarget{
            b.resolveTargetQuery(.{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .gnu,
            }),
            b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .gnu,
            }),
            b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .gnu,
            }),
        };
    for (core_audio_cross_targets) |cross_target| {
        const cross_core = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core.zig",
            ),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_core_audio = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core_audio.zig",
            ),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        cross_core_audio.addImport(
            "zig-vst3-plugin-core",
            cross_core,
        );
        const cross_tests = b.addTest(.{
            .root_module = cross_core_audio,
        });
        core_audio_cross_build_step.dependOn(&cross_tests.step);
    }
    core_audio_test_step.dependOn(core_audio_cross_build_step);
    const zig_vst3_wasapi_test_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/wasapi.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addWasapiBackend(
        b,
        zig_vst3_wasapi_test_module,
        target,
    );
    zig_vst3_wasapi_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_wasapi_tests = b.addTest(.{
        .root_module = zig_vst3_wasapi_test_module,
    });
    const wasapi_test_step = b.step(
        "test-wasapi",
        "Run WASAPI contract tests and compile the Windows backend",
    );
    wasapi_test_step.dependOn(
        &b.addRunArtifact(zig_vst3_wasapi_tests).step,
    );
    const wasapi_windows_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .abi = .gnu,
    });
    const wasapi_windows_core = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/core.zig",
        ),
        .target = wasapi_windows_target,
        .optimize = .ReleaseSafe,
    });
    const wasapi_windows_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/wasapi.zig",
        ),
        .target = wasapi_windows_target,
        .optimize = .ReleaseSafe,
    });
    addWasapiBackend(
        b,
        wasapi_windows_module,
        wasapi_windows_target,
    );
    wasapi_windows_module.addImport(
        "zig-vst3-plugin-core",
        wasapi_windows_core,
    );
    const wasapi_windows_tests = b.addTest(.{
        .root_module = wasapi_windows_module,
    });
    wasapi_test_step.dependOn(&wasapi_windows_tests.step);
    const wasapi_link_smoke = b.addExecutable(.{
        .name = "wasapi-link-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "tests/wasapi_link_smoke.zig",
            ),
            .target = wasapi_windows_target,
            .optimize = .ReleaseSafe,
        }),
    });
    wasapi_link_smoke.root_module.addImport(
        "zig-vst3-plugin-core",
        wasapi_windows_core,
    );
    wasapi_link_smoke.root_module.addImport(
        "zig-vst3-wasapi",
        wasapi_windows_module,
    );
    wasapi_test_step.dependOn(&wasapi_link_smoke.step);
    const zig_vst3_alsa_test_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/alsa.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addAlsaBackend(b, zig_vst3_alsa_test_module, target);
    zig_vst3_alsa_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_alsa_tests = b.addTest(.{
        .root_module = zig_vst3_alsa_test_module,
    });
    const alsa_test_step = b.step(
        "test-alsa",
        "Run ALSA contract tests and compile Linux backends",
    );
    alsa_test_step.dependOn(
        &b.addRunArtifact(zig_vst3_alsa_tests).step,
    );
    const alsa_targets = [_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
    };
    for (alsa_targets) |alsa_target| {
        const alsa_core = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core.zig",
            ),
            .target = alsa_target,
            .optimize = .ReleaseSafe,
        });
        const alsa_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/alsa.zig",
            ),
            .target = alsa_target,
            .optimize = .ReleaseSafe,
        });
        addAlsaBackend(b, alsa_module, alsa_target);
        alsa_module.addImport(
            "zig-vst3-plugin-core",
            alsa_core,
        );
        const alsa_tests = b.addTest(.{
            .root_module = alsa_module,
        });
        alsa_test_step.dependOn(&alsa_tests.step);
        const alsa_link_smoke = b.addExecutable(.{
            .name = b.fmt(
                "alsa-link-smoke-{s}",
                .{@tagName(alsa_target.result.cpu.arch)},
            ),
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "tests/alsa_link_smoke.zig",
                ),
                .target = alsa_target,
                .optimize = .ReleaseSafe,
            }),
        });
        alsa_link_smoke.root_module.addImport(
            "zig-vst3-plugin-core",
            alsa_core,
        );
        alsa_link_smoke.root_module.addImport(
            "zig-vst3-alsa",
            alsa_module,
        );
        alsa_test_step.dependOn(&alsa_link_smoke.step);
    }
    const zig_vst3_alsa_midi_test_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/alsa_midi.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addAlsaMidiBackend(
        b,
        zig_vst3_alsa_midi_test_module,
        target,
    );
    zig_vst3_alsa_midi_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_alsa_midi_tests = b.addTest(.{
        .root_module = zig_vst3_alsa_midi_test_module,
    });
    const alsa_midi_test_step = b.step(
        "test-alsamidi",
        "Run ALSA RawMIDI tests and compile Linux backends",
    );
    const midi_scheduler_queue_test = b.addExecutable(.{
        .name = "midi-scheduler-queue-test",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .link_libc = true,
        }),
    });
    midi_scheduler_queue_test.root_module.addIncludePath(
        b.path("zig-vst3-plugin/src/plugin"),
    );
    midi_scheduler_queue_test.root_module.addCSourceFile(.{
        .file = b.path("tests/abi/midi_scheduler_queue.c"),
        .flags = &.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
        },
    });
    const run_midi_scheduler_queue_test =
        b.addRunArtifact(midi_scheduler_queue_test);
    alsa_midi_test_step.dependOn(
        &b.addRunArtifact(zig_vst3_alsa_midi_tests).step,
    );
    alsa_midi_test_step.dependOn(
        &run_midi_scheduler_queue_test.step,
    );
    for (alsa_targets) |alsa_target| {
        const alsa_midi_core = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core.zig",
            ),
            .target = alsa_target,
            .optimize = .ReleaseSafe,
        });
        const alsa_midi_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/alsa_midi.zig",
            ),
            .target = alsa_target,
            .optimize = .ReleaseSafe,
        });
        addAlsaMidiBackend(
            b,
            alsa_midi_module,
            alsa_target,
        );
        alsa_midi_module.addImport(
            "zig-vst3-plugin-core",
            alsa_midi_core,
        );
        const alsa_midi_tests = b.addTest(.{
            .root_module = alsa_midi_module,
        });
        alsa_midi_test_step.dependOn(&alsa_midi_tests.step);
        const alsa_midi_link_smoke = b.addExecutable(.{
            .name = b.fmt(
                "alsa-midi-link-smoke-{s}",
                .{@tagName(alsa_target.result.cpu.arch)},
            ),
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "tests/alsa_midi_link_smoke.zig",
                ),
                .target = alsa_target,
                .optimize = .ReleaseSafe,
            }),
        });
        alsa_midi_link_smoke.root_module.addImport(
            "zig-vst3-plugin-core",
            alsa_midi_core,
        );
        alsa_midi_link_smoke.root_module.addImport(
            "zig-vst3-alsamidi",
            alsa_midi_module,
        );
        alsa_midi_test_step.dependOn(
            &alsa_midi_link_smoke.step,
        );
    }
    const zig_vst3_win_midi_test_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/win_midi.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addWinMidiBackend(
        b,
        zig_vst3_win_midi_test_module,
        target,
    );
    zig_vst3_win_midi_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_win_midi_tests = b.addTest(.{
        .root_module = zig_vst3_win_midi_test_module,
    });
    const win_midi_test_step = b.step(
        "test-winmidi",
        "Run Windows MIDI tests and compile the WinMM backend",
    );
    win_midi_test_step.dependOn(
        &b.addRunArtifact(zig_vst3_win_midi_tests).step,
    );
    win_midi_test_step.dependOn(
        &run_midi_scheduler_queue_test.step,
    );
    const win_midi_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .abi = .gnu,
    });
    const win_midi_core = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/core.zig",
        ),
        .target = win_midi_target,
        .optimize = .ReleaseSafe,
    });
    const win_midi_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/win_midi.zig",
        ),
        .target = win_midi_target,
        .optimize = .ReleaseSafe,
    });
    addWinMidiBackend(b, win_midi_module, win_midi_target);
    win_midi_module.addImport(
        "zig-vst3-plugin-core",
        win_midi_core,
    );
    const win_midi_tests = b.addTest(.{
        .root_module = win_midi_module,
    });
    win_midi_test_step.dependOn(&win_midi_tests.step);
    const win_midi_link_smoke = b.addExecutable(.{
        .name = "win-midi-link-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "tests/win_midi_link_smoke.zig",
            ),
            .target = win_midi_target,
            .optimize = .ReleaseSafe,
        }),
    });
    win_midi_link_smoke.root_module.addImport(
        "zig-vst3-plugin-core",
        win_midi_core,
    );
    win_midi_link_smoke.root_module.addImport(
        "zig-vst3-winmidi",
        win_midi_module,
    );
    win_midi_test_step.dependOn(&win_midi_link_smoke.step);
    const zig_vst3_win_window_test_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/win_window.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addWinWindowBackend(
        b,
        zig_vst3_win_window_test_module,
        target,
    );
    zig_vst3_win_window_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_win_window_tests = b.addTest(.{
        .root_module = zig_vst3_win_window_test_module,
    });
    const win_window_test_step = b.step(
        "test-winwindow",
        "Run standalone Win32 window tests and link the backend",
    );
    win_window_test_step.dependOn(
        &b.addRunArtifact(zig_vst3_win_window_tests).step,
    );
    const win_window_core = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/core.zig",
        ),
        .target = win_midi_target,
        .optimize = .ReleaseSafe,
    });
    const win_window_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/win_window.zig",
        ),
        .target = win_midi_target,
        .optimize = .ReleaseSafe,
    });
    addWinWindowBackend(
        b,
        win_window_module,
        win_midi_target,
    );
    win_window_module.addImport(
        "zig-vst3-plugin-core",
        win_window_core,
    );
    const win_window_tests = b.addTest(.{
        .root_module = win_window_module,
    });
    win_window_test_step.dependOn(&win_window_tests.step);
    const win_window_link_smoke = b.addExecutable(.{
        .name = "win-window-link-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "tests/win_window_link_smoke.zig",
            ),
            .target = win_midi_target,
            .optimize = .ReleaseSafe,
        }),
    });
    win_window_link_smoke.root_module.addImport(
        "zig-vst3-plugin-core",
        win_window_core,
    );
    win_window_link_smoke.root_module.addImport(
        "zig-vst3-winwindow",
        win_window_module,
    );
    win_window_test_step.dependOn(
        &win_window_link_smoke.step,
    );
    const zig_vst3_cocoa_window_test_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/cocoa_window.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addCocoaWindowBackend(
        b,
        zig_vst3_cocoa_window_test_module,
        target,
    );
    zig_vst3_cocoa_window_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_cocoa_window_tests = b.addTest(.{
        .root_module = zig_vst3_cocoa_window_test_module,
    });
    const cocoa_window_test_step = b.step(
        "test-cocoawindow",
        "Run standalone Cocoa window tests and link the backend",
    );
    cocoa_window_test_step.dependOn(
        &b.addRunArtifact(zig_vst3_cocoa_window_tests).step,
    );
    const cocoa_window_link_smoke = b.addExecutable(.{
        .name = "cocoa-window-link-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "tests/cocoa_window_link_smoke.zig",
            ),
            .target = target,
            .optimize = .ReleaseSafe,
        }),
    });
    cocoa_window_link_smoke.root_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    cocoa_window_link_smoke.root_module.addImport(
        "zig-vst3-cocoawindow",
        zig_vst3_cocoa_window,
    );
    cocoa_window_test_step.dependOn(
        &cocoa_window_link_smoke.step,
    );
    for ([_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .gnu,
        }),
    }) |cross_target| {
        const cross_core = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core.zig",
            ),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_cocoa_window = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/cocoa_window.zig",
            ),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        cross_cocoa_window.addImport(
            "zig-vst3-plugin-core",
            cross_core,
        );
        const cross_tests = b.addTest(.{
            .root_module = cross_cocoa_window,
        });
        cocoa_window_test_step.dependOn(&cross_tests.step);
    }
    const zig_vst3_x11_window_test_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/x11_window.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addX11WindowBackend(
        b,
        zig_vst3_x11_window_test_module,
        target,
    );
    zig_vst3_x11_window_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_x11_window_tests = b.addTest(.{
        .root_module = zig_vst3_x11_window_test_module,
    });
    const x11_window_test_step = b.step(
        "test-x11window",
        "Run standalone X11 window tests and link Linux backends",
    );
    x11_window_test_step.dependOn(
        &b.addRunArtifact(zig_vst3_x11_window_tests).step,
    );
    for ([_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
    }, 0..) |linux_target, index| {
        const x11_core = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core.zig",
            ),
            .target = linux_target,
            .optimize = .ReleaseSafe,
        });
        const x11_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/x11_window.zig",
            ),
            .target = linux_target,
            .optimize = .ReleaseSafe,
        });
        addX11WindowBackend(b, x11_module, linux_target);
        x11_module.addImport(
            "zig-vst3-plugin-core",
            x11_core,
        );
        const x11_tests = b.addTest(.{
            .root_module = x11_module,
        });
        x11_window_test_step.dependOn(&x11_tests.step);
        const x11_link_smoke = b.addExecutable(.{
            .name = if (index == 0)
                "x11-window-link-smoke-x86_64"
            else
                "x11-window-link-smoke-aarch64",
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "tests/x11_window_link_smoke.zig",
                ),
                .target = linux_target,
                .optimize = .ReleaseSafe,
            }),
        });
        x11_link_smoke.root_module.addImport(
            "zig-vst3-plugin-core",
            x11_core,
        );
        x11_link_smoke.root_module.addImport(
            "zig-vst3-x11window",
            x11_module,
        );
        x11_window_test_step.dependOn(
            &x11_link_smoke.step,
        );
    }
    const windows_x11_core = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/core.zig",
        ),
        .target = win_midi_target,
        .optimize = .ReleaseSafe,
    });
    const windows_x11 = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/x11_window.zig",
        ),
        .target = win_midi_target,
        .optimize = .ReleaseSafe,
    });
    windows_x11.addImport(
        "zig-vst3-plugin-core",
        windows_x11_core,
    );
    const windows_x11_tests = b.addTest(.{
        .root_module = windows_x11,
    });
    x11_window_test_step.dependOn(
        &windows_x11_tests.step,
    );
    const zig_vst3_wayland_window_test_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/wayland_window.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addWaylandWindowBackend(
        b,
        zig_vst3_wayland_window_test_module,
        target,
    );
    zig_vst3_wayland_window_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_wayland_window_tests = b.addTest(.{
        .root_module = zig_vst3_wayland_window_test_module,
    });
    const wayland_window_test_step = b.step(
        "test-waylandwindow",
        "Run standalone Wayland window tests and link Linux backends",
    );
    wayland_window_test_step.dependOn(
        &b.addRunArtifact(zig_vst3_wayland_window_tests).step,
    );
    for ([_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
    }, 0..) |linux_target, index| {
        const wayland_core = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core.zig",
            ),
            .target = linux_target,
            .optimize = .ReleaseSafe,
        });
        const wayland_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/wayland_window.zig",
            ),
            .target = linux_target,
            .optimize = .ReleaseSafe,
        });
        addWaylandWindowBackend(b, wayland_module, linux_target);
        wayland_module.addImport(
            "zig-vst3-plugin-core",
            wayland_core,
        );
        const wayland_tests = b.addTest(.{
            .root_module = wayland_module,
        });
        wayland_window_test_step.dependOn(&wayland_tests.step);
        const wayland_link_smoke = b.addExecutable(.{
            .name = if (index == 0)
                "wayland-window-link-smoke-x86_64"
            else
                "wayland-window-link-smoke-aarch64",
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "tests/wayland_window_link_smoke.zig",
                ),
                .target = linux_target,
                .optimize = .ReleaseSafe,
            }),
        });
        wayland_link_smoke.root_module.addImport(
            "zig-vst3-plugin-core",
            wayland_core,
        );
        wayland_link_smoke.root_module.addImport(
            "zig-vst3-waylandwindow",
            wayland_module,
        );
        wayland_window_test_step.dependOn(
            &wayland_link_smoke.step,
        );
    }
    const windows_wayland_core = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/core.zig",
        ),
        .target = win_midi_target,
        .optimize = .ReleaseSafe,
    });
    const windows_wayland = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/wayland_window.zig",
        ),
        .target = win_midi_target,
        .optimize = .ReleaseSafe,
    });
    windows_wayland.addImport(
        "zig-vst3-plugin-core",
        windows_wayland_core,
    );
    const windows_wayland_tests = b.addTest(.{
        .root_module = windows_wayland,
    });
    wayland_window_test_step.dependOn(
        &windows_wayland_tests.step,
    );
    const wayland_standalone_frame_test_step = b.step(
        "test-wayland-standalone-frame",
        "Run standalone VST3 Wayland host and frame bridge tests",
    );
    const native_wayland_frame_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3/src/vst_wayland_standalone_frame.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    native_wayland_frame_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const native_wayland_frame_tests = b.addTest(.{
        .root_module = native_wayland_frame_module,
    });
    wayland_standalone_frame_test_step.dependOn(
        &b.addRunArtifact(native_wayland_frame_tests).step,
    );
    for ([_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .gnu,
        }),
    }) |cross_target| {
        const cross_core = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core.zig",
            ),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_wayland_frame = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3/src/vst_wayland_standalone_frame.zig",
            ),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        cross_wayland_frame.addImport(
            "zig-vst3-plugin-core",
            cross_core,
        );
        const cross_tests = b.addTest(.{
            .root_module = cross_wayland_frame,
        });
        wayland_standalone_frame_test_step.dependOn(
            &cross_tests.step,
        );
    }
    const linux_run_loop_test_step = b.step(
        "test-linux-run-loop",
        "Run standalone Linux run-loop tests and portability builds",
    );
    const native_linux_run_loop_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3/src/vst_linux_run_loop.zig",
            ),
            .target = target,
            .optimize = optimize,
        }),
    });
    linux_run_loop_test_step.dependOn(
        &b.addRunArtifact(native_linux_run_loop_tests).step,
    );
    for ([_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        win_midi_target,
    }) |run_loop_target| {
        const cross_linux_run_loop_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3/src/vst_linux_run_loop.zig",
                ),
                .target = run_loop_target,
                .optimize = .ReleaseSafe,
            }),
        });
        linux_run_loop_test_step.dependOn(
            &cross_linux_run_loop_tests.step,
        );
    }
    const zig_vst3_core_midi_test_module = b.createModule(.{
        .root_source_file = b.path(
            "zig-vst3-plugin/src/core_midi.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    addCoreMidiBackend(
        b,
        zig_vst3_core_midi_test_module,
        target,
    );
    zig_vst3_core_midi_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const zig_vst3_core_midi_tests = b.addTest(.{
        .root_module = zig_vst3_core_midi_test_module,
    });
    const run_core_midi_tests =
        b.addRunArtifact(zig_vst3_core_midi_tests);
    const core_midi_test_step = b.step(
        "test-coremidi",
        "Run CoreMIDI backend tests and non-macOS compile checks",
    );
    core_midi_test_step.dependOn(&run_core_midi_tests.step);
    const core_midi_cross_build_step = b.step(
        "test-coremidi-builds",
        "Compile the optional CoreMIDI module for non-macOS targets",
    );
    const core_midi_cross_targets =
        [_]std.Build.ResolvedTarget{
            b.resolveTargetQuery(.{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .gnu,
            }),
            b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .gnu,
            }),
            b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .gnu,
            }),
        };
    for (core_midi_cross_targets) |cross_target| {
        const cross_core = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core.zig",
            ),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_core_midi = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core_midi.zig",
            ),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        cross_core_midi.addImport(
            "zig-vst3-plugin-core",
            cross_core,
        );
        const cross_tests = b.addTest(.{
            .root_module = cross_core_midi,
        });
        core_midi_cross_build_step.dependOn(&cross_tests.step);
    }
    core_midi_test_step.dependOn(core_midi_cross_build_step);
    const zig_vst3_plugin_core_tests = b.addTest(.{
        .root_module = zig_vst3_plugin_core_test_module,
    });
    const audio_unit_test_step = b.step(
        "test-audio-unit",
        "Run Audio Unit render, AUv2 ABI, and cross-target checks",
    );
    const audio_unit_v2_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/audio_unit_v2.zig",
            ),
            .target = target,
            .optimize = optimize,
        }),
    });
    audio_unit_test_step.dependOn(
        &b.addRunArtifact(audio_unit_v2_tests).step,
    );
    const audio_unit_cross_build_step = b.step(
        "test-audio-unit-builds",
        "Compile Audio Unit render and AUv2 modules for supported targets",
    );
    const audio_unit_cross_targets =
        [_]std.Build.ResolvedTarget{
            b.resolveTargetQuery(.{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .gnu,
            }),
            b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .gnu,
            }),
            b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .gnu,
            }),
        };
    for (audio_unit_cross_targets) |cross_target| {
        const cross_v2_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "zig-vst3-plugin/src/audio_unit_v2.zig",
                ),
                .target = cross_target,
                .optimize = .ReleaseSafe,
            }),
        });
        audio_unit_cross_build_step.dependOn(&cross_v2_tests.step);
        const cross_audio_unit_core = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/core.zig",
            ),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        const cross_auxiliary_output_audio_unit = b.createModule(.{
            .root_source_file = b.path(
                "examples/aux_output_splitter_audio_unit.zig",
            ),
            .target = cross_target,
            .optimize = .ReleaseSafe,
        });
        cross_auxiliary_output_audio_unit.addImport(
            "zig-vst3-plugin-core",
            cross_audio_unit_core,
        );
        const cross_auxiliary_output_library = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "zig_vst3_aux_output_splitter_auv2",
            .root_module = cross_auxiliary_output_audio_unit,
        });
        audio_unit_cross_build_step.dependOn(
            &cross_auxiliary_output_library.step,
        );
    }
    const audio_unit_v2_abi_object = b.addObject(.{
        .name = "audio-unit-v2-abi-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/audio_unit_v2.zig",
            ),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    const audio_unit_v2_abi_harness = b.addExecutable(.{
        .name = "audio-unit-v2-abi-harness",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .link_libc = true,
        }),
    });
    audio_unit_v2_abi_harness.root_module.addCSourceFile(.{
        .file = b.path("tests/abi/audio_unit_v2_layout.c"),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" },
    });
    audio_unit_v2_abi_harness.root_module.addObject(
        audio_unit_v2_abi_object,
    );
    audio_unit_v2_abi_harness.root_module.linkFramework(
        "AudioToolbox",
        .{},
    );
    const run_audio_unit_v2_abi =
        b.addRunArtifact(audio_unit_v2_abi_harness);
    audio_unit_test_step.dependOn(&run_audio_unit_v2_abi.step);
    audio_unit_test_step.dependOn(audio_unit_cross_build_step);

    const mono_gain_audio_unit_module = b.createModule(.{
        .root_source_file = b.path(
            "examples/mono_gain_audio_unit.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    mono_gain_audio_unit_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    addAudioUnitV2ClassInfo(
        b,
        mono_gain_audio_unit_module,
        target,
    );
    const mono_gain_audio_unit = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zig_vst3_mono_gain_auv2",
        .root_module = mono_gain_audio_unit_module,
    });
    b.installArtifact(mono_gain_audio_unit);
    const auxiliary_output_audio_unit_module = b.createModule(.{
        .root_source_file = b.path(
            "examples/aux_output_splitter_audio_unit.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    auxiliary_output_audio_unit_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    addAudioUnitV2ClassInfo(
        b,
        auxiliary_output_audio_unit_module,
        target,
    );
    const auxiliary_output_audio_unit = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zig_vst3_aux_output_splitter_auv2",
        .root_module = auxiliary_output_audio_unit_module,
    });
    b.installArtifact(auxiliary_output_audio_unit);
    const audio_unit_host_smoke = b.addExecutable(.{
        .name = "audio-unit-v2-host-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "tests/audio_unit_v2_host_smoke.zig",
            ),
            .target = target,
            .optimize = .ReleaseSafe,
        }),
    });
    audio_unit_host_smoke.root_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    if (target.result.os.tag == .macos)
        audio_unit_host_smoke.root_module.linkFramework(
            "CoreFoundation",
            .{},
        );
    const run_audio_unit_host_smoke =
        b.addRunArtifact(audio_unit_host_smoke);
    run_audio_unit_host_smoke.addFileArg(
        mono_gain_audio_unit.getEmittedBin(),
    );
    audio_unit_test_step.dependOn(
        &run_audio_unit_host_smoke.step,
    );
    const audio_unit_multi_output_host_smoke = b.addExecutable(.{
        .name = "audio-unit-v2-multi-output-host-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "tests/audio_unit_v2_multi_output_host_smoke.zig",
            ),
            .target = target,
            .optimize = .ReleaseSafe,
        }),
    });
    audio_unit_multi_output_host_smoke.root_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const run_audio_unit_multi_output_host_smoke =
        b.addRunArtifact(audio_unit_multi_output_host_smoke);
    run_audio_unit_multi_output_host_smoke.addFileArg(
        auxiliary_output_audio_unit.getEmittedBin(),
    );
    audio_unit_test_step.dependOn(
        &run_audio_unit_multi_output_host_smoke.step,
    );
    const mono_gain_audio_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "examples/mono_gain_audio_unit.zig",
            ),
            .target = target,
            .optimize = optimize,
        }),
    });
    mono_gain_audio_unit_tests.root_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    addAudioUnitV2ClassInfo(
        b,
        mono_gain_audio_unit_tests.root_module,
        target,
    );
    audio_unit_test_step.dependOn(
        &b.addRunArtifact(mono_gain_audio_unit_tests).step,
    );
    const auxiliary_output_audio_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "examples/aux_output_splitter_audio_unit.zig",
            ),
            .target = target,
            .optimize = optimize,
        }),
    });
    auxiliary_output_audio_unit_tests.root_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    addAudioUnitV2ClassInfo(
        b,
        auxiliary_output_audio_unit_tests.root_module,
        target,
    );
    audio_unit_test_step.dependOn(
        &b.addRunArtifact(auxiliary_output_audio_unit_tests).step,
    );
    const mono_gain_audio_unit_bundle_step = b.step(
        "bundle-audio-unit-mono-gain",
        "Build the native Mono Gain Audio Unit v2 component",
    );
    const auxiliary_output_audio_unit_bundle_step = b.step(
        "bundle-audio-unit-aux-output-splitter",
        "Build the native multi-output Audio Unit v2 component",
    );
    if (target.result.os.tag == .macos) {
        const mono_gain_component_path = b.getInstallPath(
            .prefix,
            "bundle/zig_vst3_mono_gain.component",
        );
        const bundle_audio_unit = b.addSystemCommand(
            &.{"scripts/bundle_macos_auv2.sh"},
        );
        bundle_audio_unit.addFileArg(
            mono_gain_audio_unit.getEmittedBin(),
        );
        bundle_audio_unit.addArgs(&.{
            mono_gain_component_path,
            "dev.zig-vst3.mono-gain-auv2",
            "0.2.1",
            "zig_vst3_mono_gain",
            "aufx",
            "ZMGn",
            "Zig3",
            "zig-vst3: Mono Gain",
            "ZigVst3MonoGainFactory",
            "513",
        });
        mono_gain_audio_unit_bundle_step.dependOn(
            &bundle_audio_unit.step,
        );
        const test_audio_unit_bundle = b.addSystemCommand(
            &.{"scripts/test_auv2_bundle.sh"},
        );
        test_audio_unit_bundle.addArg(mono_gain_component_path);
        test_audio_unit_bundle.addArgs(&.{
            "zig_vst3_mono_gain",
            "aufx",
            "ZMGn",
            "Zig3",
            "ZigVst3MonoGainFactory",
            "513",
        });
        test_audio_unit_bundle.step.dependOn(
            &bundle_audio_unit.step,
        );
        mono_gain_audio_unit_bundle_step.dependOn(
            &test_audio_unit_bundle.step,
        );
        audio_unit_test_step.dependOn(
            mono_gain_audio_unit_bundle_step,
        );

        const auxiliary_output_component_path = b.getInstallPath(
            .prefix,
            "bundle/zig_vst3_aux_output_splitter.component",
        );
        const bundle_auxiliary_output_audio_unit =
            b.addSystemCommand(
                &.{"scripts/bundle_macos_auv2.sh"},
            );
        bundle_auxiliary_output_audio_unit.addFileArg(
            auxiliary_output_audio_unit.getEmittedBin(),
        );
        bundle_auxiliary_output_audio_unit.addArgs(&.{
            auxiliary_output_component_path,
            "dev.zig-vst3.aux-output-splitter-auv2",
            "0.2.1",
            "zig_vst3_aux_output_splitter",
            "aufx",
            "ZAux",
            "Zig3",
            "zig-vst3: Auxiliary Output Splitter",
            "ZigVst3AuxOutputSplitterFactory",
            "513",
        });
        auxiliary_output_audio_unit_bundle_step.dependOn(
            &bundle_auxiliary_output_audio_unit.step,
        );
        const test_auxiliary_output_audio_unit_bundle =
            b.addSystemCommand(
                &.{"scripts/test_auv2_bundle.sh"},
            );
        test_auxiliary_output_audio_unit_bundle.addArg(
            auxiliary_output_component_path,
        );
        test_auxiliary_output_audio_unit_bundle.addArgs(&.{
            "zig_vst3_aux_output_splitter",
            "aufx",
            "ZAux",
            "Zig3",
            "ZigVst3AuxOutputSplitterFactory",
            "513",
        });
        test_auxiliary_output_audio_unit_bundle.step.dependOn(
            &bundle_auxiliary_output_audio_unit.step,
        );
        auxiliary_output_audio_unit_bundle_step.dependOn(
            &test_auxiliary_output_audio_unit_bundle.step,
        );
        audio_unit_test_step.dependOn(
            auxiliary_output_audio_unit_bundle_step,
        );
    }

    const zig_vst3_plugin_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig-vst3-plugin/src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    zig_vst3_plugin_tests.root_module.addImport("zig-vst3", zig_vst3);
    zig_vst3_plugin_tests.root_module.addImport("zig-vst3-plugin-core", zig_vst3_plugin_core);

    const realtime_source_audit = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/realtime_source_audit.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const gui_examples = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/gui_examples.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gui_examples.root_module.addImport("zig-vst3", zig_vst3);
    gui_examples.root_module.addImport("zig-vst3-plugin", zig_vst3_plugin);

    const mono_gain_lv2_module = b.createModule(.{
        .root_source_file = b.path("examples/mono_gain_lv2.zig"),
        .target = target,
        .optimize = optimize,
    });
    mono_gain_lv2_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const mono_gain_lv2 = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zig_vst3_mono_gain_lv2",
        .root_module = mono_gain_lv2_module,
    });
    b.installArtifact(mono_gain_lv2);

    var mono_gain_lv2_ui: ?*std.Build.Step.Compile = null;
    var mono_gain_lv2_ui_tests: ?*std.Build.Step.Run = null;
    var mono_gain_lv2_vstgui_host_smoke: ?*std.Build.Step.Run = null;
    if (native_vstgui) {
        const ui_module = b.createModule(.{
            .root_source_file = b.path(
                "examples/mono_gain_lv2_ui.zig",
            ),
            .target = target,
            .optimize = optimize,
        });
        ui_module.addImport(
            "zig-vst3-plugin-core",
            zig_vst3_plugin_core,
        );
        ui_module.addImport("zig-vst3", zig_vst3);
        addVstguiAdapter(ui_module, target);
        const ui_library = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "zig_vst3_mono_gain_lv2_ui",
            .root_module = ui_module,
        });
        ui_library.step.dependOn(vstgui_adapter_step);
        b.installArtifact(ui_library);
        mono_gain_lv2_ui = ui_library;

        const ui_test_module = b.createModule(.{
            .root_source_file = b.path(
                "examples/mono_gain_lv2_ui.zig",
            ),
            .target = target,
            .optimize = optimize,
        });
        ui_test_module.addImport(
            "zig-vst3-plugin-core",
            zig_vst3_plugin_core,
        );
        ui_test_module.addImport("zig-vst3", zig_vst3);
        addVstguiAdapter(ui_test_module, target);
        const ui_tests = b.addTest(.{
            .root_module = ui_test_module,
        });
        ui_tests.step.dependOn(vstgui_adapter_step);
        mono_gain_lv2_ui_tests =
            b.addRunArtifact(ui_tests);

        const ui_host_smoke = b.addExecutable(.{
            .name = "lv2-vstgui-ui-host-smoke",
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "tests/lv2_vstgui_ui_host_smoke.zig",
                ),
                .target = b.graph.host,
                .optimize = .ReleaseSafe,
                .link_libc = true,
            }),
        });
        ui_host_smoke.root_module.addImport(
            "zig-vst3-plugin-core",
            zig_vst3_plugin_core,
        );
        const run_ui_host_smoke =
            b.addRunArtifact(ui_host_smoke);
        run_ui_host_smoke.addFileArg(
            ui_library.getEmittedBin(),
        );
        mono_gain_lv2_vstgui_host_smoke =
            run_ui_host_smoke;
    }

    const mono_gain_lv2_metadata_module = b.createModule(.{
        .root_source_file = b.path(
            "tools/generate_mono_gain_lv2_metadata.zig",
        ),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    });
    mono_gain_lv2_metadata_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    mono_gain_lv2_metadata_module.addImport(
        "mono-gain-lv2",
        mono_gain_lv2_module,
    );
    const mono_gain_lv2_metadata = b.addExecutable(.{
        .name = "generate-mono-gain-lv2-metadata",
        .root_module = mono_gain_lv2_metadata_module,
    });

    const component_state_lv2_module = b.createModule(.{
        .root_source_file = b.path(
            "tests/fixtures/lv2_component_state_plugin.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    component_state_lv2_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const component_state_lv2 = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zig_vst3_component_state_lv2",
        .root_module = component_state_lv2_module,
    });

    const lv2_ui_module = b.createModule(.{
        .root_source_file = b.path(
            "tests/fixtures/lv2_ui_plugin.zig",
        ),
        .target = target,
        .optimize = optimize,
    });
    lv2_ui_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const lv2_ui_library = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zig_vst3_lv2_ui_probe",
        .root_module = lv2_ui_module,
    });

    const mono_gain_lv2_test_module = b.createModule(.{
        .root_source_file = b.path("examples/mono_gain_lv2.zig"),
        .target = target,
        .optimize = optimize,
    });
    mono_gain_lv2_test_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const mono_gain_lv2_tests = b.addTest(.{
        .root_module = mono_gain_lv2_test_module,
    });

    const mono_gain_lv2_bundle_step = b.step(
        "bundle-lv2-mono-gain",
        "Build the native Mono Gain LV2 bundle",
    );
    const mono_gain_lv2_bundle = b.addSystemCommand(
        &.{"scripts/bundle_lv2.sh"},
    );
    mono_gain_lv2_bundle.addFileArg(mono_gain_lv2.getEmittedBin());
    mono_gain_lv2_bundle.addArg(
        b.getInstallPath(
            .prefix,
            "bundle/zig_vst3_mono_gain.lv2",
        ),
    );
    mono_gain_lv2_bundle.addFileArg(
        mono_gain_lv2_metadata.getEmittedBin(),
    );
    if (mono_gain_lv2_ui) |ui_library|
        mono_gain_lv2_bundle.addFileArg(
            ui_library.getEmittedBin(),
        );
    mono_gain_lv2_bundle_step.dependOn(
        &mono_gain_lv2_bundle.step,
    );

    const mono_gain_lv2_entry_check = b.addSystemCommand(
        &.{"scripts/check_lv2_entry_symbol.sh"},
    );
    mono_gain_lv2_entry_check.addFileArg(
        mono_gain_lv2.getEmittedBin(),
    );
    var mono_gain_lv2_ui_entry_check: ?*std.Build.Step.Run = null;
    if (mono_gain_lv2_ui) |ui_library| {
        const check = b.addSystemCommand(
            &.{"scripts/check_lv2_entry_symbol.sh"},
        );
        check.addFileArg(ui_library.getEmittedBin());
        check.addArg("lv2ui_descriptor");
        mono_gain_lv2_ui_entry_check = check;
    }

    const lv2_host_smoke = b.addExecutable(.{
        .name = "lv2-host-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lv2_host_smoke.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .link_libc = true,
        }),
    });
    lv2_host_smoke.root_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const run_lv2_host_smoke = b.addRunArtifact(lv2_host_smoke);
    run_lv2_host_smoke.addFileArg(mono_gain_lv2.getEmittedBin());

    const lv2_component_state_host_smoke = b.addExecutable(.{
        .name = "lv2-component-state-host-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "tests/lv2_component_state_host_smoke.zig",
            ),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .link_libc = true,
        }),
    });
    lv2_component_state_host_smoke.root_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const run_lv2_component_state_host_smoke =
        b.addRunArtifact(lv2_component_state_host_smoke);
    run_lv2_component_state_host_smoke.addFileArg(
        component_state_lv2.getEmittedBin(),
    );

    const lv2_ui_host_smoke = b.addExecutable(.{
        .name = "lv2-ui-host-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "tests/lv2_ui_host_smoke.zig",
            ),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .link_libc = true,
        }),
    });
    lv2_ui_host_smoke.root_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const run_lv2_ui_host_smoke =
        b.addRunArtifact(lv2_ui_host_smoke);
    run_lv2_ui_host_smoke.addFileArg(
        lv2_ui_library.getEmittedBin(),
    );

    const lv2_abi_object = b.addObject(.{
        .name = "lv2-core-abi-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/abi/lv2_core_harness.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    lv2_abi_object.root_module.addImport(
        "zig-vst3-plugin-core",
        zig_vst3_plugin_core,
    );
    const lv2_abi_harness = b.addExecutable(.{
        .name = "lv2-core-abi-harness",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .link_libc = true,
        }),
    });
    lv2_abi_harness.root_module.addCSourceFile(.{
        .file = b.path("tests/abi/lv2_core_harness.c"),
        .flags = &.{"-std=c11"},
    });
    lv2_abi_harness.root_module.addObject(lv2_abi_object);
    const run_lv2_abi_harness =
        b.addRunArtifact(lv2_abi_harness);
    const lv2_abi_step = b.step(
        "test-lv2-abi",
        "Run the LV2 C ABI layout harness",
    );
    lv2_abi_step.dependOn(&run_lv2_abi_harness.step);

    const lv2_cross_build_step = b.step(
        "test-lv2-builds",
        "Compile LV2 libraries for supported cross targets",
    );
    const lv2_cross_targets = [_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .gnu,
        }),
        b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .windows,
            .abi = .gnu,
        }),
    };
    for (lv2_cross_targets) |lv2_target| {
        const target_core = b.createModule(.{
            .root_source_file = b.path("zig-vst3-plugin/src/core.zig"),
            .target = lv2_target,
            .optimize = .ReleaseSafe,
        });
        const target_module = b.createModule(.{
            .root_source_file = b.path("examples/mono_gain_lv2.zig"),
            .target = lv2_target,
            .optimize = .ReleaseSafe,
        });
        target_module.addImport(
            "zig-vst3-plugin-core",
            target_core,
        );
        const target_library = b.addLibrary(.{
            .linkage = .dynamic,
            .name = b.fmt(
                "zig_vst3_mono_gain_lv2_{s}_{s}",
                .{
                    @tagName(lv2_target.result.cpu.arch),
                    @tagName(lv2_target.result.os.tag),
                },
            ),
            .root_module = target_module,
        });
        lv2_cross_build_step.dependOn(&target_library.step);

        const target_component_state_module = b.createModule(.{
            .root_source_file = b.path(
                "tests/fixtures/lv2_component_state_plugin.zig",
            ),
            .target = lv2_target,
            .optimize = .ReleaseSafe,
        });
        target_component_state_module.addImport(
            "zig-vst3-plugin-core",
            target_core,
        );
        const target_component_state_library = b.addLibrary(.{
            .linkage = .dynamic,
            .name = b.fmt(
                "zig_vst3_component_state_lv2_{s}_{s}",
                .{
                    @tagName(lv2_target.result.cpu.arch),
                    @tagName(lv2_target.result.os.tag),
                },
            ),
            .root_module = target_component_state_module,
        });
        lv2_cross_build_step.dependOn(
            &target_component_state_library.step,
        );

        const target_ui_module = b.createModule(.{
            .root_source_file = b.path(
                "tests/fixtures/lv2_ui_plugin.zig",
            ),
            .target = lv2_target,
            .optimize = .ReleaseSafe,
        });
        target_ui_module.addImport(
            "zig-vst3-plugin-core",
            target_core,
        );
        const target_ui_library = b.addLibrary(.{
            .linkage = .dynamic,
            .name = b.fmt(
                "zig_vst3_lv2_ui_probe_{s}_{s}",
                .{
                    @tagName(lv2_target.result.cpu.arch),
                    @tagName(lv2_target.result.os.tag),
                },
            ),
            .root_module = target_ui_module,
        });
        lv2_cross_build_step.dependOn(
            &target_ui_library.step,
        );
    }

    const lv2_test_step = b.step(
        "test-lv2",
        "Run LV2 ABI, host, bundle, and cross-build tests",
    );
    lv2_test_step.dependOn(
        &b.addRunArtifact(mono_gain_lv2_tests).step,
    );
    lv2_test_step.dependOn(mono_gain_lv2_bundle_step);
    lv2_test_step.dependOn(&mono_gain_lv2_entry_check.step);
    if (mono_gain_lv2_ui_entry_check) |check|
        lv2_test_step.dependOn(&check.step);
    if (mono_gain_lv2_ui_tests) |ui_tests|
        lv2_test_step.dependOn(&ui_tests.step);
    if (mono_gain_lv2_vstgui_host_smoke) |host_smoke|
        lv2_test_step.dependOn(&host_smoke.step);
    lv2_test_step.dependOn(&run_lv2_host_smoke.step);
    lv2_test_step.dependOn(
        &run_lv2_component_state_host_smoke.step,
    );
    lv2_test_step.dependOn(&run_lv2_ui_host_smoke.step);
    lv2_test_step.dependOn(&run_lv2_abi_harness.step);
    lv2_test_step.dependOn(lv2_cross_build_step);
    const test_lv2_bundle =
        b.addSystemCommand(&.{"scripts/test_lv2_bundle.sh"});
    test_lv2_bundle.addFileArg(
        mono_gain_lv2_metadata.getEmittedBin(),
    );
    lv2_test_step.dependOn(&test_lv2_bundle.step);

    if (native_vstgui) {
        vst3_tests.step.dependOn(vstgui_native_test_step);
        zig_vst3_plugin_core_tests.step.dependOn(vstgui_native_test_step);
        zig_vst3_plugin_tests.step.dependOn(vstgui_native_test_step);
        realtime_source_audit.step.dependOn(vstgui_native_test_step);
        gui_examples.step.dependOn(vstgui_native_test_step);
        for (example_plugins) |plugin| plugin.plugin_tests.step.dependOn(vstgui_native_test_step);
    }

    const benchmark = b.addExecutable(.{
        .name = "zig-vst3-benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/benchmark.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
    });
    benchmark.root_module.addImport("zig-vst3", zig_vst3);
    benchmark.root_module.addImport("zig-vst3-plugin", zig_vst3_plugin);
    benchmark.root_module.addImport("zig-vst3-plugin-core", zig_vst3_plugin_core);
    benchmark.root_module.addCSourceFile(.{
        .file = b.path("tools/denormal_workloads.c"),
        .flags = if (target.result.os.tag == .windows)
            &.{ "-std=c11", "-fno-fast-math" }
        else
            &.{ "-std=c11", "-fno-fast-math", "-fvisibility=hidden" },
    });
    const c_kernel_benchmark = b.createModule(.{
        .root_source_file = b.path("examples/c_kernel_core.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    c_kernel_benchmark.addImport("zig-vst3-plugin", zig_vst3_plugin);
    addCKernelSources(c_kernel_benchmark, target);
    benchmark.root_module.addImport("c-kernel-core", c_kernel_benchmark);
    const benchmark_step = b.step("benchmark", "Run local zig-vst3 microbenchmarks");
    benchmark_step.dependOn(&b.addRunArtifact(benchmark).step);

    const fixture_generator = b.addExecutable(.{
        .name = "sample-player-fixtures",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/sample_player_fixtures.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    const generate_fixtures_step = b.step("generate-sample-player-fixtures", "Generate bounded WAV and AIFF sample-player fixtures");
    generate_fixtures_step.dependOn(&b.addRunArtifact(fixture_generator).step);

    const vorbis_interop_fixture = b.addExecutable(.{
        .name = "vorbis-interop-fixture",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/vorbis_interop_fixture.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    vorbis_interop_fixture.root_module.addImport(
        "zig-vst3-plugin",
        zig_vst3_plugin,
    );
    const run_vorbis_interop_fixture =
        b.addRunArtifact(vorbis_interop_fixture);
    const vorbis_interop_ogg =
        run_vorbis_interop_fixture.addOutputFileArg(
            "vorbis-interop.ogg",
        );
    const generate_vorbis_interop_step = b.step(
        "generate-vorbis-interop-fixture",
        "Generate a deterministic Ogg Vorbis interoperability fixture",
    );
    generate_vorbis_interop_step.dependOn(
        &run_vorbis_interop_fixture.step,
    );
    const test_vorbis_interop = b.addSystemCommand(
        &.{"scripts/test_vorbis_interop.sh"},
    );
    test_vorbis_interop.addFileArg(vorbis_interop_ogg);

    const dsp_reference_renderer = b.addExecutable(.{
        .name = "dsp-reference-renderer",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
            .link_libc = true,
            .link_libcpp = true,
            .sanitize_c = .off,
        }),
    });
    dsp_reference_renderer.root_module.addCSourceFile(.{
        .file = b.path("tests/fixtures/dsp_reference_renderer.cpp"),
        .flags = &.{ "-std=c++17", "-ffp-contract=off" },
    });
    const render_dsp_reference = b.addRunArtifact(dsp_reference_renderer);
    const dsp_input_wav = render_dsp_reference.addOutputFileArg("dsp-input-f32.wav");
    const dsp_reference_f32_wav = render_dsp_reference.addOutputFileArg("dsp-reference-f32.wav");
    const dsp_reference_f64_wav = render_dsp_reference.addOutputFileArg("dsp-reference-f64.wav");

    const dsp_fixture_parity = b.addExecutable(.{
        .name = "dsp-fixture-parity",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/dsp_fixture_parity.zig"),
            .target = target,
            .optimize = .ReleaseSafe,
        }),
    });
    dsp_fixture_parity.root_module.addImport("zig-vst3-plugin", zig_vst3_plugin);
    const run_dsp_fixture_parity = b.addRunArtifact(dsp_fixture_parity);
    run_dsp_fixture_parity.addFileArg(dsp_input_wav);
    run_dsp_fixture_parity.addFileArg(dsp_reference_f32_wav);
    run_dsp_fixture_parity.addFileArg(dsp_reference_f64_wav);
    const dsp_fixture_parity_step = b.step("test-dsp-fixtures", "Compare fixed and randomized blocks with C++ reference WAV renders");
    dsp_fixture_parity_step.dependOn(&run_dsp_fixture_parity.step);

    const dsp_fixture_builds_step = b.step("test-dsp-fixture-builds", "Compile DSP fixture tooling for supported cross targets");
    const dsp_fixture_targets = [_]std.Build.ResolvedTarget{
        b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu }),
        b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu }),
        b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu }),
    };
    for (dsp_fixture_targets) |fixture_target| {
        const fixture_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("zig-vst3-plugin/src/dsp/fixture_runner.zig"),
                .target = fixture_target,
                .optimize = .ReleaseSafe,
            }),
        });
        dsp_fixture_builds_step.dependOn(&fixture_tests.step);
    }

    const test_step = b.step("test", "Run unit tests");
    addRunArtifactDependencies(b, test_step, &.{
        vst3_tests,
        zig_vst3_plugin_core_tests,
        zig_vst3_plugin_tests,
        realtime_source_audit,
        gui_examples,
    });
    test_step.dependOn(core_midi_test_step);
    test_step.dependOn(audio_unit_cross_build_step);
    test_step.dependOn(&run_audio_unit_v2_abi.step);
    test_step.dependOn(ara_test_step);
    test_step.dependOn(core_audio_test_step);
    test_step.dependOn(wasapi_test_step);
    test_step.dependOn(alsa_test_step);
    test_step.dependOn(alsa_midi_test_step);
    test_step.dependOn(win_midi_test_step);
    test_step.dependOn(win_window_test_step);
    test_step.dependOn(cocoa_window_test_step);
    test_step.dependOn(x11_window_test_step);
    test_step.dependOn(wayland_window_test_step);
    test_step.dependOn(wayland_standalone_frame_test_step);
    test_step.dependOn(linux_run_loop_test_step);
    addExamplePluginTestDependencies(b, test_step, &example_plugins);
    test_step.dependOn(&b.addSystemCommand(&.{"scripts/test_pluginval_runner.sh"}).step);
    test_step.dependOn(&b.addSystemCommand(&.{"scripts/test_validator_runner.sh"}).step);
    test_step.dependOn(&b.addSystemCommand(&.{"scripts/test_gui_lifecycle_soak_runner.sh"}).step);
    test_step.dependOn(&b.addSystemCommand(&.{"scripts/test_vstgui_sanitizer_soak_runner.sh"}).step);
    test_step.dependOn(&b.addSystemCommand(&.{"scripts/test_vstgui_thread_sanitizer_runner.sh"}).step);
    test_step.dependOn(&b.addSystemCommand(&.{"scripts/test_vstgui_build_modes.sh"}).step);
    test_step.dependOn(&b.addSystemCommand(&.{"scripts/test_bundle_scripts.sh"}).step);
    test_step.dependOn(&b.addSystemCommand(&.{"scripts/check_public_gui_examples.sh"}).step);
    test_step.dependOn(&b.addSystemCommand(&.{"scripts/test_installed_package.sh"}).step);
    test_step.dependOn(generate_fixtures_step);
    test_step.dependOn(dsp_fixture_parity_step);
    test_step.dependOn(
        &b.addSystemCommand(
            &.{"scripts/test_vorbis_interop_runner.sh"},
        ).step,
    );
    test_step.dependOn(&test_vorbis_interop.step);
    test_step.dependOn(dsp_fixture_builds_step);
    test_step.dependOn(lv2_test_step);

    const sanitizer_step = addScriptCheckStep(b, .{
        .step_name = "test-vstgui-sanitizers",
        .description = "Run native VSTGUI tests with address and undefined-behavior sanitizers",
        .script = "scripts/test_vstgui_sanitizers.sh",
    });
    _ = sanitizer_step;
    const sanitizer_soak_step = addScriptCheckStep(b, .{
        .step_name = "soak-vstgui-sanitizers",
        .description = "Repeat native VSTGUI sanitizer tests with failure artifacts",
        .script = "scripts/vstgui_sanitizer_soak.sh",
    });
    _ = sanitizer_soak_step;
    const thread_sanitizer_step = addScriptCheckStep(b, .{
        .step_name = "test-vstgui-thread-sanitizer",
        .description = "Run native VSTGUI concurrency tests with the thread sanitizer",
        .script = "scripts/test_vstgui_thread_sanitizer.sh",
    });
    _ = thread_sanitizer_step;

    const resource_thread_sanitizer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig-vst3-plugin/src/resource.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
            .sanitize_thread = true,
        }),
    });
    const resource_thread_sanitizer_step = b.step("test-resource-thread-sanitizer", "Run resource job and exchange tests with the thread sanitizer");
    resource_thread_sanitizer_step.dependOn(&b.addRunArtifact(resource_thread_sanitizer_tests).step);

    const dsp_thread_sanitizer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(
                "zig-vst3-plugin/src/dsp/realtime_snapshot.zig",
            ),
            .target = b.graph.host,
            .optimize = .Debug,
            .sanitize_thread = true,
        }),
    });
    const dsp_thread_sanitizer_step = b.step(
        "test-dsp-thread-sanitizer",
        "Run realtime DSP publication tests with the thread sanitizer",
    );
    dsp_thread_sanitizer_step.dependOn(
        &b.addRunArtifact(dsp_thread_sanitizer_tests).step,
    );

    const plugin_path_option = b.option([]const u8, "plugin", "Path to a .vst3 bundle to validate");

    const validate_step = b.step("validate", "Run the VST3 SDK validator for -Dplugin=path/to/Plugin.vst3");
    if (plugin_path_option) |plugin_path| {
        const validate = b.addSystemCommand(&.{ "scripts/validate.sh", plugin_path });
        validate_step.dependOn(&validate.step);
    } else {
        const missing_plugin = b.addFail("pass -Dplugin=path/to/Plugin.vst3");
        validate_step.dependOn(&missing_plugin.step);
    }

    const pluginval_step = b.step("pluginval", "Run pluginval for -Dplugin=path/to/Plugin.vst3");
    if (plugin_path_option) |plugin_path| {
        const pluginval = b.addSystemCommand(&.{ "scripts/pluginval.sh", plugin_path });
        pluginval_step.dependOn(&pluginval.step);
    } else {
        const missing_plugin = b.addFail("pass -Dplugin=path/to/Plugin.vst3");
        pluginval_step.dependOn(&missing_plugin.step);
    }

    var validate_example_steps: [example_plugin_options.len]*std.Build.Step = undefined;
    for (example_plugin_options, example_plugins, 0..) |options, plugin, index| {
        validate_example_steps[index] = addVst3ValidationStep(b, target, plugin.bundles.native, .{
            .short_name = options.short_name,
            .display_name = options.display_name,
            .artifact_name = options.artifact_name,
        });
    }
    const validate_examples_step = b.step("validate-examples", "Build and validate all native VST3 example bundles");
    addStepDependencies(validate_examples_step, &validate_example_steps);

    var pluginval_example_steps: [example_plugin_options.len]*std.Build.Step = undefined;
    var pluginval_strict_example_steps: [example_plugin_options.len]*std.Build.Step = undefined;
    for (example_plugin_options, example_plugins, 0..) |options, plugin, index| {
        pluginval_example_steps[index] = addPluginvalStep(b, target, plugin.bundles.native, .{
            .short_name = options.short_name,
            .display_name = options.display_name,
            .artifact_name = options.artifact_name,
            .strictness = null,
        });
        pluginval_strict_example_steps[index] = addPluginvalStep(b, target, plugin.bundles.native, .{
            .short_name = b.fmt("{s}-strict", .{options.short_name}),
            .display_name = options.display_name,
            .artifact_name = options.artifact_name,
            .strictness = "10",
        });
    }
    for (1..example_plugin_options.len) |index| {
        pluginval_example_steps[index].dependOn(pluginval_example_steps[index - 1]);
        pluginval_strict_example_steps[index].dependOn(pluginval_strict_example_steps[index - 1]);
    }
    const pluginval_examples_step = b.step("pluginval-examples", "Build and run pluginval for all native VST3 example bundles");
    addStepDependencies(pluginval_examples_step, &pluginval_example_steps);
    const pluginval_strict_examples_step = b.step("pluginval-strict-examples", "Build and run pluginval strictness 10 for all native VST3 example bundles");
    addStepDependencies(pluginval_strict_examples_step, &pluginval_strict_example_steps);

    const bundle_examples_step = b.step("bundle-examples", "Build native VST3 bundles for all example plugins");
    addVst3BundleDependencies(bundle_examples_step, &example_bundle_steps, .native);

    const clean_bundles_step = b.step("clean-bundles", "Remove generated VST3 bundles from zig-out/bundle");
    clean_bundles_step.dependOn(&b.addSystemCommand(&.{ "rm", "-rf", "zig-out/bundle" }).step);

    const bundle_examples_linux_step = b.step("bundle-examples-linux", "Build Linux VST3 bundles for all example plugins");
    addVst3BundleDependencies(bundle_examples_linux_step, &example_bundle_steps, .linux);

    const bundle_examples_windows_step = b.step("bundle-examples-windows", "Build Windows VST3 bundles for all example plugins");
    addVst3BundleDependencies(bundle_examples_windows_step, &example_bundle_steps, .windows);
    const c_kernel_matrix_step = b.step("test-c-kernel-builds", "Build and inspect the C Kernel Probe platform matrix");
    c_kernel_matrix_step.dependOn(&b.addSystemCommand(&.{"scripts/build_c_kernel_matrix.sh"}).step);
    const validator_step = b.step("validator", "Build Steinberg's VST3 SDK validator");
    const build_validator = b.addSystemCommand(&.{"scripts/build_validator.sh"});
    validator_step.dependOn(&build_validator.step);

    const raw_api_script_checks = [_]ScriptCheckOptions{
        .{ .step_name = "tuid-abi", .description = "Compare Zig TUID bytes against the pinned VST3 SDK", .script = "scripts/check_tuid_abi.sh" },
        .{ .step_name = "pluginbase-abi", .description = "Compare Zig pluginbase layouts against the pinned VST3 SDK", .script = "scripts/check_pluginbase_abi.sh" },
        .{ .step_name = "ibstream-abi", .description = "Compare Zig IBStream declarations against the pinned VST3 SDK", .script = "scripts/check_ibstream_abi.sh" },
        .{ .step_name = "base-strings-error-abi", .description = "Compare Zig base string and error declarations against the pinned VST3 SDK", .script = "scripts/check_base_strings_error_abi.sh" },
        .{ .step_name = "base-persistence-abi", .description = "Compare Zig base persistence declarations against the pinned VST3 SDK", .script = "scripts/check_base_persistence_abi.sh" },
        .{ .step_name = "base-update-compatibility-abi", .description = "Compare Zig base update and compatibility declarations against the pinned VST3 SDK", .script = "scripts/check_base_update_compatibility_abi.sh" },
        .{ .step_name = "component-abi", .description = "Compare Zig IComponent declarations against the pinned VST3 SDK", .script = "scripts/check_component_abi.sh" },
        .{ .step_name = "audio-processor-abi", .description = "Compare Zig IAudioProcessor declarations against the pinned VST3 SDK", .script = "scripts/check_audio_processor_abi.sh" },
        .{ .step_name = "bypass-processor-abi", .description = "Compare Zig bypass processor helper declarations against the pinned VST3 SDK", .script = "scripts/check_bypass_processor_abi.sh" },
        .{ .step_name = "process-context-abi", .description = "Compare Zig process context declarations against the pinned VST3 SDK", .script = "scripts/check_process_context_abi.sh" },
        .{ .step_name = "edit-controller-abi", .description = "Compare Zig IEditController declarations against the pinned VST3 SDK", .script = "scripts/check_edit_controller_abi.sh" },
        .{ .step_name = "parameter-changes-abi", .description = "Compare Zig parameter change declarations against the pinned VST3 SDK", .script = "scripts/check_parameter_changes_abi.sh" },
        .{ .step_name = "events-abi", .description = "Compare Zig event declarations against the pinned VST3 SDK", .script = "scripts/check_events_abi.sh" },
        .{ .step_name = "host-message-abi", .description = "Compare Zig host/message declarations against the pinned VST3 SDK", .script = "scripts/check_host_message_abi.sh" },
        .{ .step_name = "plugview-abi", .description = "Compare Zig plug view declarations against the pinned VST3 SDK", .script = "scripts/check_plugview_abi.sh" },
        .{ .step_name = "units-abi", .description = "Compare Zig unit declarations against the pinned VST3 SDK", .script = "scripts/check_units_abi.sh" },
        .{ .step_name = "midi-mapping-abi", .description = "Compare Zig MIDI mapping declarations against the pinned VST3 SDK", .script = "scripts/check_midi_mapping_abi.sh" },
        .{ .step_name = "midi-controllers-abi", .description = "Compare Zig MIDI controller constants against the pinned VST3 SDK", .script = "scripts/check_midi_controllers_abi.sh" },
        .{ .step_name = "speaker-core-abi", .description = "Compare Zig speaker constants and helpers against the pinned VST3 SDK", .script = "scripts/check_speaker_core_abi.sh" },
        .{ .step_name = "preset-keys-abi", .description = "Compare Zig preset attribute constants against the pinned VST3 SDK", .script = "scripts/check_preset_keys_abi.sh" },
        .{ .step_name = "preset-file-abi", .description = "Compare Zig preset file chunk declarations against the pinned VST3 SDK", .script = "scripts/check_preset_file_abi.sh" },
        .{ .step_name = "note-expression-abi", .description = "Compare Zig note expression declarations against the pinned VST3 SDK", .script = "scripts/check_note_expression_abi.sh" },
        .{ .step_name = "capability-state-abi", .description = "Compare Zig capability and state declarations against the pinned VST3 SDK", .script = "scripts/check_capability_state_abi.sh" },
        .{ .step_name = "parameter-helpers-abi", .description = "Compare Zig parameter helper declarations against the pinned VST3 SDK", .script = "scripts/check_parameter_helpers_abi.sh" },
        .{ .step_name = "context-menu-abi", .description = "Compare Zig context menu declarations against the pinned VST3 SDK", .script = "scripts/check_context_menu_abi.sh" },
        .{ .step_name = "physical-channel-abi", .description = "Compare Zig physical UI and channel context declarations against the pinned VST3 SDK", .script = "scripts/check_physical_channel_abi.sh" },
        .{ .step_name = "data-exchange-abi", .description = "Compare Zig data exchange declarations against the pinned VST3 SDK", .script = "scripts/check_data_exchange_abi.sh" },
        .{ .step_name = "representation-abi", .description = "Compare Zig XML representation declarations against the pinned VST3 SDK", .script = "scripts/check_representation_abi.sh" },
        .{ .step_name = "wayland-frame-abi", .description = "Compare Zig Wayland frame declarations against the pinned VST3 SDK", .script = "scripts/check_wayland_frame_abi.sh" },
        .{ .step_name = "inter-app-audio-abi", .description = "Compare Zig Inter-App Audio declarations against the pinned VST3 SDK", .script = "scripts/check_inter_app_audio_abi.sh" },
        .{ .step_name = "test-plug-provider-abi", .description = "Compare Zig test plug provider declarations against the pinned VST3 SDK", .script = "scripts/check_test_plug_provider_abi.sh" },
        .{ .step_name = "test-interfaces-abi", .description = "Compare Zig test interface declarations against the pinned VST3 SDK", .script = "scripts/check_test_interfaces_abi.sh" },
        .{ .step_name = "ara-vst3-abi", .description = "Compare Zig ARA API and VST3 companion declarations against the official ARA SDK", .script = "scripts/check_ara_vst3_abi.sh" },
    };

    var raw_api_script_steps: [raw_api_script_checks.len]*std.Build.Step = undefined;
    for (raw_api_script_checks, 0..) |options, index| {
        raw_api_script_steps[index] = addScriptCheckStep(b, options);
    }
    ara_test_step.dependOn(
        raw_api_script_steps[raw_api_script_steps.len - 1],
    );

    const funknown_harness_zig = addAbiHarnessObject(b, target, optimize, zig_vst3, .{
        .name = "funknown_harness_zig",
        .root_source_file = "tests/abi/funknown_harness.zig",
    });
    const multi_interface_harness_zig = addAbiHarnessObject(b, target, optimize, zig_vst3, .{
        .name = "multi_interface_harness_zig",
        .root_source_file = "tests/abi/multi_interface_harness.zig",
    });

    const abi_harness_options = [_]AbiHarnessOptions{
        .{
            .step_name = "funknown-abi",
            .description = "Run the C ABI harness for the FUnknown prototype",
            .artifact_name = "funknown_harness",
            .source_file = "tests/abi/funknown_harness.c",
            .object = funknown_harness_zig,
        },
        .{
            .step_name = "multi-interface-abi",
            .description = "Run the C ABI harness for multi-interface query dispatch",
            .artifact_name = "multi_interface_harness",
            .source_file = "tests/abi/multi_interface_harness.c",
            .object = multi_interface_harness_zig,
        },
        .{
            .step_name = "multi-interface-cpp-abi",
            .description = "Run the C++ ABI harness for multi-interface query dispatch",
            .artifact_name = "multi_interface_cpp_harness",
            .source_file = "tests/abi/multi_interface_harness.cpp",
            .source_flags = &.{"-std=c++17"},
            .link_libcpp = true,
            .object = multi_interface_harness_zig,
        },
        .{
            .step_name = "multi-interface-sdk-abi",
            .description = "Run the Steinberg SDK C++ ABI harness for multi-interface query dispatch",
            .artifact_name = "multi_interface_sdk_harness",
            .source_file = "tests/abi/multi_interface_sdk_harness.cpp",
            .source_flags = &.{"-std=c++17"},
            .include_path = ".vst3-sdk/vst3sdk",
            .link_libcpp = true,
            .object = multi_interface_harness_zig,
        },
    };
    var abi_harness_steps: [abi_harness_options.len]*std.Build.Step = undefined;
    for (abi_harness_options, 0..) |options, index| {
        abi_harness_steps[index] = addAbiHarnessStep(b, target, optimize, options);
    }

    const raw_api_abi_step = b.step("raw-api-abi", "Run raw API ABI and entry-symbol checks");
    raw_api_abi_step.dependOn(entry_symbols_step);
    addStepDependencies(raw_api_abi_step, &raw_api_script_steps);
    addStepDependencies(raw_api_abi_step, &abi_harness_steps);

    const phase1_step = b.step("phase1", "Run Phase 1 COM/vtable integration checks");
    phase1_step.dependOn(test_step);
    phase1_step.dependOn(raw_api_abi_step);
    if (target.result.os.tag == .macos) {
        phase1_step.dependOn(validate_examples_step);
    }
}

fn linuxPlatformDir(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .x86_64 => "x86_64-linux",
        .aarch64 => "aarch64-linux",
        else => "unknown-linux",
    };
}

fn windowsPlatformDir(arch: std.Target.Cpu.Arch) []const u8 {
    return switch (arch) {
        .x86_64 => "x86_64-win",
        .aarch64 => "aarch64-win",
        else => "unknown-win",
    };
}

const Vst3PluginLibraryOptions = struct {
    artifact_name: []const u8,
    root_source_file: []const u8,
};

fn addVst3PluginLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zig_vst3_plugin_core: *std.Build.Module,
    options: Vst3PluginLibraryOptions,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path(options.root_source_file),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("zig-vst3-plugin-core", zig_vst3_plugin_core);

    const library = b.addLibrary(.{
        .linkage = .dynamic,
        .name = options.artifact_name,
        .root_module = module,
    });
    b.installArtifact(library);
    return library;
}

fn addZigVst3PluginCoreTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zig_vst3_plugin_core: *std.Build.Module,
    root_source_file: []const u8,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("zig-vst3-plugin-core", zig_vst3_plugin_core);
    return b.addTest(.{
        .root_module = module,
    });
}

fn addZigVst3PluginTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zig_vst3_plugin: *std.Build.Module,
    root_source_file: []const u8,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path(root_source_file),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("zig-vst3-plugin", zig_vst3_plugin);
    return b.addTest(.{
        .root_module = module,
    });
}

fn addCoreMidiBackend(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .macos) return;
    module.link_libc = true;
    module.addIncludePath(b.path("zig-vst3-plugin/src/plugin"));
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/plugin/core_midi_shim.c",
        ),
        .flags = &.{
            "-std=c11",
            "-fblocks",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wno-deprecated-declarations",
        },
    });
    module.linkFramework("CoreFoundation", .{});
    module.linkFramework("CoreMIDI", .{});
}

fn addAudioUnitV2ClassInfo(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .macos) return;
    module.link_libc = true;
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/audio_unit_v2_class_info.c",
        ),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" },
    });
    module.linkFramework("AudioToolbox", .{});
    module.linkFramework("CoreFoundation", .{});
}

fn addCoreAudioBackend(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .macos) return;
    module.link_libc = true;
    module.addIncludePath(b.path("zig-vst3-plugin/src/plugin"));
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/plugin/core_audio_shim.c",
        ),
        .flags = &.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wno-deprecated-declarations",
        },
    });
    module.linkFramework("AudioToolbox", .{});
    module.linkFramework("CoreAudio", .{});
    module.linkFramework("CoreFoundation", .{});
}

fn addWasapiBackend(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .windows) return;
    module.link_libc = true;
    module.addIncludePath(b.path("zig-vst3-plugin/src/plugin"));
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/plugin/wasapi_shim.c",
        ),
        .flags = &.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
        },
    });
    module.linkSystemLibrary("ole32", .{});
    module.linkSystemLibrary("oleaut32", .{});
    module.linkSystemLibrary("avrt", .{});
    module.linkSystemLibrary("uuid", .{});
}

fn addAlsaBackend(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .linux) return;
    module.link_libc = true;
    module.addIncludePath(b.path("zig-vst3-plugin/src/plugin"));
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/plugin/alsa_shim.c",
        ),
        .flags = &.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
        },
    });
    module.linkSystemLibrary("dl", .{});
    module.linkSystemLibrary("pthread", .{});
}

fn addAlsaMidiBackend(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .linux) return;
    module.link_libc = true;
    module.addIncludePath(b.path("zig-vst3-plugin/src/plugin"));
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/plugin/alsa_midi_shim.c",
        ),
        .flags = &.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
        },
    });
    module.linkSystemLibrary("dl", .{});
    module.linkSystemLibrary("pthread", .{});
}

fn addWinMidiBackend(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .windows) return;
    module.link_libc = true;
    module.addIncludePath(b.path("zig-vst3-plugin/src/plugin"));
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/plugin/win_midi_shim.c",
        ),
        .flags = &.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
        },
    });
    module.linkSystemLibrary("winmm", .{});
}

fn addWinWindowBackend(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .windows) return;
    module.link_libc = true;
    module.addIncludePath(b.path("zig-vst3-plugin/src/plugin"));
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/plugin/win_window_shim.c",
        ),
        .flags = &.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
        },
    });
    module.linkSystemLibrary("user32", .{});
}

fn addCocoaWindowBackend(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .macos) return;
    module.link_libc = true;
    module.addIncludePath(b.path("zig-vst3-plugin/src/plugin"));
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/plugin/cocoa_window_shim.m",
        ),
        .flags = &.{
            "-fno-objc-arc",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wno-deprecated-declarations",
        },
    });
    module.linkFramework("AppKit", .{});
    module.linkFramework("Foundation", .{});
}

fn addX11WindowBackend(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .linux) return;
    module.link_libc = true;
    module.addIncludePath(b.path("zig-vst3-plugin/src/plugin"));
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/plugin/x11_window_shim.c",
        ),
        .flags = &.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wpedantic",
        },
    });
    module.linkSystemLibrary("dl", .{});
}

fn addWaylandWindowBackend(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) void {
    if (target.result.os.tag != .linux) return;
    module.link_libc = true;
    module.addIncludePath(b.path("zig-vst3-plugin/src/plugin"));
    module.addCSourceFile(.{
        .file = b.path(
            "zig-vst3-plugin/src/plugin/wayland_window_shim.c",
        ),
        .flags = &.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-Wpedantic",
        },
    });
    module.linkSystemLibrary("dl", .{});
}

fn addEntrySymbolsCheck(
    b: *std.Build,
    step: *std.Build.Step,
    library: *std.Build.Step.Compile,
) void {
    const check_entry_symbols = b.addSystemCommand(&.{"scripts/check_entry_symbols.sh"});
    check_entry_symbols.addFileArg(library.getEmittedBin());
    step.dependOn(&check_entry_symbols.step);
}

const Vst3ValidationOptions = struct {
    short_name: []const u8,
    display_name: []const u8,
    artifact_name: []const u8,
    strictness: ?[]const u8 = null,
};

fn addVst3ValidationStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    bundle_step: *std.Build.Step,
    options: Vst3ValidationOptions,
) *std.Build.Step {
    const step_name = b.fmt("validate-{s}", .{options.short_name});
    const validate_step = b.step(step_name, b.fmt("Build and validate the native {s} VST3 bundle", .{options.display_name}));
    if (target.result.os.tag == .macos or target.result.os.tag == .linux) {
        validate_step.dependOn(bundle_step);
        const validate = b.addSystemCommand(&.{
            "scripts/validate.sh",
            b.getInstallPath(.prefix, b.fmt("bundle/{s}.vst3", .{options.artifact_name})),
        });
        validate.step.dependOn(bundle_step);
        validate_step.dependOn(&validate.step);
    } else {
        validate_step.dependOn(&b.addFail(b.fmt("{s} currently supports macOS and Linux targets", .{step_name})).step);
    }
    return validate_step;
}

fn addPluginvalStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    bundle_step: *std.Build.Step,
    options: Vst3ValidationOptions,
) *std.Build.Step {
    const step_name = b.fmt("pluginval-{s}", .{options.short_name});
    const pluginval_step = b.step(step_name, b.fmt("Build and run pluginval for the native {s} VST3 bundle", .{options.display_name}));
    if (target.result.os.tag == .macos or target.result.os.tag == .linux or target.result.os.tag == .windows) {
        pluginval_step.dependOn(bundle_step);
        const pluginval = b.addSystemCommand(&.{
            "scripts/pluginval.sh",
            b.getInstallPath(.prefix, b.fmt("bundle/{s}.vst3", .{options.artifact_name})),
        });
        if (options.strictness) |strictness| {
            pluginval.setEnvironmentVariable("PLUGINVAL_STRICTNESS", strictness);
        }
        pluginval.step.dependOn(bundle_step);
        pluginval_step.dependOn(&pluginval.step);
        return &pluginval.step;
    } else {
        const failure = &b.addFail(b.fmt("{s} currently supports macOS, Linux, and Windows targets", .{step_name})).step;
        pluginval_step.dependOn(failure);
        return failure;
    }
}

const Vst3BundleOptions = struct {
    short_name: []const u8,
    display_name: []const u8,
    artifact_name: []const u8,
    bundle_id: []const u8,
};

const Vst3BundleSteps = struct {
    native: *std.Build.Step,
    linux: *std.Build.Step,
    windows: *std.Build.Step,
};

const ExamplePluginOptions = struct {
    short_name: []const u8,
    display_name: []const u8,
    artifact_name: []const u8,
    root_source_file: []const u8,
    core_example_source_file: []const u8,
    bundle_id: []const u8,
    c_kernel: bool = false,
};

const ExamplePluginSteps = struct {
    library: *std.Build.Step.Compile,
    bundles: Vst3BundleSteps,
    plugin_tests: *std.Build.Step.Compile,
    core_example_tests: *std.Build.Step.Compile,
};

const ScriptCheckOptions = struct {
    step_name: []const u8,
    description: []const u8,
    script: []const u8,
};

const AbiHarnessObjectOptions = struct {
    name: []const u8,
    root_source_file: []const u8,
};

const AbiHarnessOptions = struct {
    step_name: []const u8,
    description: []const u8,
    artifact_name: []const u8,
    source_file: []const u8,
    source_flags: []const []const u8 = &.{},
    include_path: ?[]const u8 = null,
    link_libcpp: bool = false,
    object: *std.Build.Step.Compile,
};

const Vst3BundleKind = enum {
    native,
    linux,
    windows,
};

fn addStepDependencies(step: *std.Build.Step, dependencies: []const *std.Build.Step) void {
    for (dependencies) |dependency| {
        step.dependOn(dependency);
    }
}

fn addRunArtifactDependencies(
    b: *std.Build,
    step: *std.Build.Step,
    artifacts: []const *std.Build.Step.Compile,
) void {
    for (artifacts) |artifact| {
        step.dependOn(&b.addRunArtifact(artifact).step);
    }
}

fn addExamplePluginTestDependencies(
    b: *std.Build,
    step: *std.Build.Step,
    plugins: []const ExamplePluginSteps,
) void {
    for (plugins) |plugin| {
        step.dependOn(&b.addRunArtifact(plugin.plugin_tests).step);
        step.dependOn(&b.addRunArtifact(plugin.core_example_tests).step);
    }
}

fn addScriptCheckStep(b: *std.Build, options: ScriptCheckOptions) *std.Build.Step {
    const step = b.step(options.step_name, options.description);
    const check = b.addSystemCommand(&.{options.script});
    step.dependOn(&check.step);
    return step;
}

fn addAbiHarnessObject(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zig_vst3: *std.Build.Module,
    options: AbiHarnessObjectOptions,
) *std.Build.Step.Compile {
    const object = b.addObject(.{
        .name = options.name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(options.root_source_file),
            .target = target,
            .optimize = optimize,
        }),
    });
    object.root_module.addImport("zig-vst3", zig_vst3);
    return object;
}

fn addAbiHarnessStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: AbiHarnessOptions,
) *std.Build.Step {
    const harness = b.addExecutable(.{
        .name = options.artifact_name,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = options.link_libcpp,
            .sanitize_c = .off,
        }),
    });
    if (options.include_path) |include_path| {
        harness.root_module.addIncludePath(b.path(include_path));
    }
    harness.root_module.addCSourceFile(.{
        .file = b.path(options.source_file),
        .flags = options.source_flags,
    });
    harness.root_module.addObject(options.object);

    const step = b.step(options.step_name, options.description);
    step.dependOn(&b.addRunArtifact(harness).step);
    return step;
}

fn addExamplePlugin(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zig_vst3: *std.Build.Module,
    zig_vst3_plugin_core: *std.Build.Module,
    zig_vst3_plugin: *std.Build.Module,
    gui_options: *std.Build.Step.Options,
    native_vstgui: bool,
    entry_symbols_step: *std.Build.Step,
    vstgui_adapter_step: *std.Build.Step,
    options: ExamplePluginOptions,
) ExamplePluginSteps {
    const has_reference_editor = hasReferenceEditor(options.short_name);
    const library = addVst3PluginLibrary(b, target, optimize, zig_vst3_plugin_core, .{
        .artifact_name = options.artifact_name,
        .root_source_file = options.root_source_file,
    });
    library.root_module.addImport("zig-vst3", zig_vst3);
    if (usesFullPluginModule(options.short_name)) {
        library.root_module.addImport("zig-vst3-plugin", zig_vst3_plugin);
    }
    if (options.c_kernel) addCKernelSources(library.root_module, target);
    if (has_reference_editor) library.root_module.addOptions("zig-vst3-gui-options", gui_options);
    if (native_vstgui and has_reference_editor) {
        addVstguiAdapter(library.root_module, target);
        library.step.dependOn(vstgui_adapter_step);
    }
    addEntrySymbolsCheck(b, entry_symbols_step, library);

    const plugin_tests = addZigVst3PluginCoreTest(b, target, optimize, zig_vst3_plugin_core, options.root_source_file);
    plugin_tests.root_module.addImport("zig-vst3", zig_vst3);
    if (usesFullPluginModule(options.short_name)) {
        plugin_tests.root_module.addImport("zig-vst3-plugin", zig_vst3_plugin);
    }
    if (options.c_kernel) addCKernelSources(plugin_tests.root_module, target);
    if (has_reference_editor) plugin_tests.root_module.addOptions("zig-vst3-gui-options", gui_options);
    if (native_vstgui and has_reference_editor) {
        addVstguiAdapter(plugin_tests.root_module, target);
        plugin_tests.step.dependOn(vstgui_adapter_step);
    }

    const core_example_tests = addZigVst3PluginTest(b, target, optimize, zig_vst3_plugin, options.core_example_source_file);
    if (options.c_kernel) addCKernelSources(core_example_tests.root_module, target);

    return .{
        .library = library,
        .bundles = addVst3BundleSteps(b, target, library, .{
            .short_name = options.short_name,
            .display_name = options.display_name,
            .artifact_name = options.artifact_name,
            .bundle_id = options.bundle_id,
        }),
        .plugin_tests = plugin_tests,
        .core_example_tests = core_example_tests,
    };
}

fn usesFullPluginModule(short_name: []const u8) bool {
    return std.mem.eql(u8, short_name, "mono-gain") or
        std.mem.eql(u8, short_name, "surround-gain") or
        std.mem.eql(u8, short_name, "sidechain-ducker") or
        std.mem.eql(u8, short_name, "aux-output-splitter") or
        std.mem.eql(u8, short_name, "resource-swap") or
        std.mem.eql(u8, short_name, "fixed-rate") or
        std.mem.eql(u8, short_name, "model-shell") or
        std.mem.eql(u8, short_name, "c-kernel");
}

fn addCKernelSources(module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    const b = module.owner;
    module.link_libc = true;
    module.addIncludePath(b.path("examples/c_kernel"));
    module.addCSourceFile(.{
        .file = b.path("examples/c_kernel/dense_portable.c"),
        .flags = if (target.result.os.tag == .windows) &.{"-std=c11"} else &.{ "-std=c11", "-fvisibility=hidden" },
    });
    switch (target.result.cpu.arch) {
        .aarch64 => module.addCSourceFile(.{
            .file = b.path("examples/c_kernel/dense_neon.c"),
            .flags = if (target.result.os.tag == .windows)
                &.{ "-std=c11", "-ffast-math" }
            else
                &.{ "-std=c11", "-ffast-math", "-fvisibility=hidden" },
        }),
        .x86_64 => module.addCSourceFile(.{
            .file = b.path("examples/c_kernel/dense_avx2.c"),
            .flags = if (target.result.os.tag == .windows)
                &.{ "-std=c11", "-msse3", "-mavx2", "-ffast-math" }
            else
                &.{ "-std=c11", "-msse3", "-mavx2", "-ffast-math", "-fvisibility=hidden" },
        }),
        else => {},
    }
}

fn hasReferenceEditor(short_name: []const u8) bool {
    return std.mem.eql(u8, short_name, "gain") or
        std.mem.eql(u8, short_name, "bypass") or
        std.mem.eql(u8, short_name, "mode-gain") or
        std.mem.eql(u8, short_name, "voice-mix") or
        std.mem.eql(u8, short_name, "sine-synth") or
        std.mem.eql(u8, short_name, "editor-smoke") or
        std.mem.eql(u8, short_name, "channel-strip") or
        std.mem.eql(u8, short_name, "parametric-eq") or
        std.mem.eql(u8, short_name, "resonant-filter") or
        std.mem.eql(u8, short_name, "ir-loader") or
        std.mem.eql(u8, short_name, "sample-player");
}

fn addVstguiAdapter(module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    const b = module.owner;
    const library_path = if (target.result.os.tag == .windows)
        ".vst3-sdk/vstgui-adapter-build/Release/libs/vstgui.lib"
    else
        ".vst3-sdk/vstgui-adapter-build/Release/libs/libvstgui.a";
    const adapter_library_path = if (target.result.os.tag == .windows)
        ".vst3-sdk/vstgui-adapter-build/Release/libs/zig_vstgui_adapter.lib"
    else
        ".vst3-sdk/vstgui-adapter-build/Release/libs/libzig_vstgui_adapter.a";
    module.addObjectFile(b.path(adapter_library_path));
    module.addObjectFile(b.path(library_path));
    module.linkSystemLibrary("c++", .{});
    if (target.result.os.tag == .macos) {
        module.linkFramework("Cocoa", .{});
        module.linkFramework("QuartzCore", .{});
        module.linkFramework("Accelerate", .{});
        module.linkFramework("UniformTypeIdentifiers", .{});
    } else if (target.result.os.tag == .linux) {
        for ([_][]const u8{
            "X11",            "freetype2",      "xcb",         "xcb-util",       "xcb-cursor", "xcb-keysyms", "xcb-xkb",
            "xkbcommon",      "xkbcommon-x11",  "glib-2.0",    "cairo",          "pangocairo", "pangoft2",    "fontconfig",
            "wayland-client", "wayland-cursor", "wayland-egl", "wayland-server", "pthread",    "dl",
        }) |library| module.linkSystemLibrary(library, .{ .use_pkg_config = .yes });
    } else if (target.result.os.tag == .windows) {
        for ([_][]const u8{
            "comctl32", "d2d1", "dwrite",        "gdi32", "ole32", "oleaut32", "shell32", "shlwapi", "uiautomationcore",
            "user32",   "uuid", "windowscodecs",
        }) |library| module.linkSystemLibrary(library, .{ .use_pkg_config = .no });
    }
}

fn addVst3BundleDependencies(
    step: *std.Build.Step,
    bundles: []const Vst3BundleSteps,
    kind: Vst3BundleKind,
) void {
    for (bundles) |bundle| {
        step.dependOn(switch (kind) {
            .native => bundle.native,
            .linux => bundle.linux,
            .windows => bundle.windows,
        });
    }
}

fn addVst3BundleSteps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    library: *std.Build.Step.Compile,
    options: Vst3BundleOptions,
) Vst3BundleSteps {
    const native_step_name = b.fmt("bundle-{s}", .{options.short_name});
    const native_step = b.step(native_step_name, b.fmt("Build a native VST3 bundle for the {s} plugin", .{options.display_name}));
    if (target.result.os.tag == .macos) {
        const bundle = b.addSystemCommand(&.{"scripts/bundle_macos_vst3.sh"});
        bundle.addFileArg(library.getEmittedBin());
        bundle.addArgs(&.{
            b.getInstallPath(.prefix, b.fmt("bundle/{s}.vst3", .{options.artifact_name})),
            options.bundle_id,
            "0.2.1",
            options.artifact_name,
        });
        native_step.dependOn(&bundle.step);
    } else if (target.result.os.tag == .linux) {
        const bundle = b.addSystemCommand(&.{"scripts/bundle_linux_vst3.sh"});
        bundle.addFileArg(library.getEmittedBin());
        bundle.addArgs(&.{
            b.getInstallPath(.prefix, b.fmt("bundle/{s}.vst3", .{options.artifact_name})),
            linuxPlatformDir(target.result.cpu.arch),
            options.artifact_name,
        });
        native_step.dependOn(&bundle.step);
    } else {
        native_step.dependOn(&b.addFail(b.fmt("{s} currently supports macOS and Linux targets", .{native_step_name})).step);
    }

    const linux_step_name = b.fmt("bundle-{s}-linux", .{options.short_name});
    const linux_step = b.step(linux_step_name, b.fmt("Build a Linux VST3 bundle for the {s} plugin", .{options.display_name}));
    if (target.result.os.tag == .linux) {
        const bundle_linux = b.addSystemCommand(&.{"scripts/bundle_linux_vst3.sh"});
        bundle_linux.addFileArg(library.getEmittedBin());
        bundle_linux.addArgs(&.{
            b.getInstallPath(.prefix, b.fmt("bundle/{s}_linux.vst3", .{options.artifact_name})),
            linuxPlatformDir(target.result.cpu.arch),
            b.fmt("{s}_linux", .{options.artifact_name}),
        });
        linux_step.dependOn(&bundle_linux.step);
    } else {
        linux_step.dependOn(&b.addFail(b.fmt("{s} requires a Linux target", .{linux_step_name})).step);
    }

    const windows_step_name = b.fmt("bundle-{s}-windows", .{options.short_name});
    const windows_step = b.step(windows_step_name, b.fmt("Build a Windows VST3 bundle for the {s} plugin", .{options.display_name}));
    if (target.result.os.tag == .windows) {
        const bundle_windows = b.addSystemCommand(&.{"scripts/bundle_windows_vst3.sh"});
        bundle_windows.addFileArg(library.getEmittedBin());
        bundle_windows.addArgs(&.{
            b.getInstallPath(.prefix, b.fmt("bundle/{s}_windows.vst3", .{options.artifact_name})),
            windowsPlatformDir(target.result.cpu.arch),
            b.fmt("{s}_windows", .{options.artifact_name}),
        });
        windows_step.dependOn(&bundle_windows.step);
    } else {
        windows_step.dependOn(&b.addFail(b.fmt("{s} requires a Windows target", .{windows_step_name})).step);
    }

    return .{
        .native = native_step,
        .linux = linux_step,
        .windows = windows_step,
    };
}
