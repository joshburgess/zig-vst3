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
    const zig_vst3_plugin_core = b.addModule("zig-vst3-plugin-core", .{
        .root_source_file = b.path("zig-vst3-plugin/src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
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
    if (native_vstgui) {
        const build_vstgui = if (target.result.os.tag == .windows)
            b.addSystemCommand(&.{ "powershell", "-NoProfile", "-File", "scripts/build_vstgui.ps1" })
        else
            b.addSystemCommand(&.{"scripts/build_vstgui.sh"});
        vstgui_adapter_step.dependOn(&build_vstgui.step);
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
    };

    var example_plugins: [example_plugin_options.len]ExamplePluginSteps = undefined;
    for (example_plugin_options, 0..) |options, index| {
        example_plugins[index] = addExamplePlugin(b, target, optimize, zig_vst3, zig_vst3_plugin_core, zig_vst3_plugin, gui_options, native_vstgui, entry_symbols_step, vstgui_adapter_step, options);
    }

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
    vst3_test_module.addOptions("zig-vst3-gui-options", gui_options);
    if (native_vstgui) addVstguiAdapter(vst3_test_module, target);
    const vst3_tests = b.addTest(.{
        .root_module = vst3_test_module,
    });
    if (native_vstgui) vst3_tests.step.dependOn(vstgui_adapter_step);

    const zig_vst3_plugin_core_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig-vst3-plugin/src/core.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const zig_vst3_plugin_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig-vst3-plugin/src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    zig_vst3_plugin_tests.root_module.addImport("zig-vst3", zig_vst3);
    zig_vst3_plugin_tests.root_module.addImport("zig-vst3-plugin-core", zig_vst3_plugin_core);

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
    const benchmark_step = b.step("benchmark", "Run local zig-vst3 microbenchmarks");
    benchmark_step.dependOn(&b.addRunArtifact(benchmark).step);

    const test_step = b.step("test", "Run unit tests");
    addRunArtifactDependencies(b, test_step, &.{
        vst3_tests,
        zig_vst3_plugin_core_tests,
        zig_vst3_plugin_tests,
    });
    addExamplePluginTestDependencies(b, test_step, &example_plugins);

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
    };

    var raw_api_script_steps: [raw_api_script_checks.len]*std.Build.Step = undefined;
    for (raw_api_script_checks, 0..) |options, index| {
        raw_api_script_steps[index] = addScriptCheckStep(b, options);
    }

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
    } else {
        pluginval_step.dependOn(&b.addFail(b.fmt("{s} currently supports macOS, Linux, and Windows targets", .{step_name})).step);
    }
    return pluginval_step;
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
    const has_reference_editor = std.mem.eql(u8, options.short_name, "gain") or
        std.mem.eql(u8, options.short_name, "bypass") or
        std.mem.eql(u8, options.short_name, "mode-gain") or
        std.mem.eql(u8, options.short_name, "voice-mix") or
        std.mem.eql(u8, options.short_name, "editor-smoke") or
        std.mem.eql(u8, options.short_name, "channel-strip");
    const library = addVst3PluginLibrary(b, target, optimize, zig_vst3_plugin_core, .{
        .artifact_name = options.artifact_name,
        .root_source_file = options.root_source_file,
    });
    library.root_module.addImport("zig-vst3", zig_vst3);
    if (has_reference_editor) library.root_module.addOptions("zig-vst3-gui-options", gui_options);
    if (native_vstgui and has_reference_editor) {
        addVstguiAdapter(library.root_module, target);
        library.step.dependOn(vstgui_adapter_step);
    }
    addEntrySymbolsCheck(b, entry_symbols_step, library);

    const plugin_tests = addZigVst3PluginCoreTest(b, target, optimize, zig_vst3_plugin_core, options.root_source_file);
    plugin_tests.root_module.addImport("zig-vst3", zig_vst3);
    if (has_reference_editor) plugin_tests.root_module.addOptions("zig-vst3-gui-options", gui_options);
    if (native_vstgui and has_reference_editor) {
        addVstguiAdapter(plugin_tests.root_module, target);
        plugin_tests.step.dependOn(vstgui_adapter_step);
    }

    return .{
        .library = library,
        .bundles = addVst3BundleSteps(b, target, library, .{
            .short_name = options.short_name,
            .display_name = options.display_name,
            .artifact_name = options.artifact_name,
            .bundle_id = options.bundle_id,
        }),
        .plugin_tests = plugin_tests,
        .core_example_tests = addZigVst3PluginTest(b, target, optimize, zig_vst3_plugin, options.core_example_source_file),
    };
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
            "comctl32", "d2d1", "dwrite", "gdi32", "ole32", "shell32", "shlwapi", "user32", "uuid", "windowscodecs",
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
