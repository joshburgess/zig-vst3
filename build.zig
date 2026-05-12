const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const zig_vst3_plugin = b.addModule("zig-vst3-plugin", .{
        .root_source_file = b.path("zig-vst3-plugin/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zig_vst3_plugin.addImport("zig-vst3-plugin-core", zig_vst3_plugin_core);
    zig_vst3_plugin.addImport("zig-vst3", zig_vst3);

    const entry_symbols_step = b.step("entry-symbols", "Verify native VST3 module entry exports");

    const gain = addExamplePlugin(b, target, optimize, zig_vst3_plugin_core, zig_vst3_plugin, entry_symbols_step, .{
        .short_name = "gain",
        .display_name = "gain",
        .artifact_name = "zig_vst3_gain",
        .root_source_file = "zig-vst3/src/gain_plugin.zig",
        .core_example_source_file = "examples/gain_core.zig",
        .bundle_id = "dev.zig-vst3.gain",
    });
    const bypass = addExamplePlugin(b, target, optimize, zig_vst3_plugin_core, zig_vst3_plugin, entry_symbols_step, .{
        .short_name = "bypass",
        .display_name = "bypass",
        .artifact_name = "zig_vst3_bypass",
        .root_source_file = "zig-vst3/src/bypass_plugin.zig",
        .core_example_source_file = "examples/bypass_core.zig",
        .bundle_id = "dev.zig-vst3.bypass",
    });
    const mode_gain = addExamplePlugin(b, target, optimize, zig_vst3_plugin_core, zig_vst3_plugin, entry_symbols_step, .{
        .short_name = "mode-gain",
        .display_name = "mode gain",
        .artifact_name = "zig_vst3_mode_gain",
        .root_source_file = "zig-vst3/src/mode_gain_plugin.zig",
        .core_example_source_file = "examples/mode_gain_core.zig",
        .bundle_id = "dev.zig-vst3.mode-gain",
    });
    const voice_mix = addExamplePlugin(b, target, optimize, zig_vst3_plugin_core, zig_vst3_plugin, entry_symbols_step, .{
        .short_name = "voice-mix",
        .display_name = "voice mix",
        .artifact_name = "zig_vst3_voice_mix",
        .root_source_file = "zig-vst3/src/voice_mix_plugin.zig",
        .core_example_source_file = "examples/voice_mix_core.zig",
        .bundle_id = "dev.zig-vst3.voice-mix",
    });
    const note_gate = addExamplePlugin(b, target, optimize, zig_vst3_plugin_core, zig_vst3_plugin, entry_symbols_step, .{
        .short_name = "note-gate",
        .display_name = "note gate",
        .artifact_name = "zig_vst3_note_gate",
        .root_source_file = "zig-vst3/src/note_gate_plugin.zig",
        .core_example_source_file = "examples/note_gate_core.zig",
        .bundle_id = "dev.zig-vst3.note-gate",
    });
    const event_echo = addExamplePlugin(b, target, optimize, zig_vst3_plugin_core, zig_vst3_plugin, entry_symbols_step, .{
        .short_name = "event-echo",
        .display_name = "event echo",
        .artifact_name = "zig_vst3_event_echo",
        .root_source_file = "zig-vst3/src/event_echo_plugin.zig",
        .core_example_source_file = "examples/event_echo_core.zig",
        .bundle_id = "dev.zig-vst3.event-echo",
    });
    const event_monitor = addExamplePlugin(b, target, optimize, zig_vst3_plugin_core, zig_vst3_plugin, entry_symbols_step, .{
        .short_name = "event-monitor",
        .display_name = "event monitor",
        .artifact_name = "zig_vst3_event_monitor",
        .root_source_file = "zig-vst3/src/event_monitor_plugin.zig",
        .core_example_source_file = "examples/event_monitor_core.zig",
        .bundle_id = "dev.zig-vst3.event-monitor",
    });
    const sine_synth = addExamplePlugin(b, target, optimize, zig_vst3_plugin_core, zig_vst3_plugin, entry_symbols_step, .{
        .short_name = "sine-synth",
        .display_name = "sine synth",
        .artifact_name = "zig_vst3_sine_synth",
        .root_source_file = "zig-vst3/src/sine_synth_plugin.zig",
        .core_example_source_file = "examples/sine_synth_core.zig",
        .bundle_id = "dev.zig-vst3.sine-synth",
    });
    const example_bundle_steps = [_]Vst3BundleSteps{
        gain.bundles,
        bypass.bundles,
        mode_gain.bundles,
        voice_mix.bundles,
        note_gate.bundles,
        event_echo.bundles,
        event_monitor.bundles,
        sine_synth.bundles,
    };
    const vst3_test_module = b.createModule(.{
        .root_source_file = b.path("zig-vst3/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    vst3_test_module.addImport("zig-vst3-plugin-core", zig_vst3_plugin_core);
    const vst3_tests = b.addTest(.{
        .root_module = vst3_test_module,
    });

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

    const test_step = b.step("test", "Run unit tests");
    addRunArtifactDependencies(b, test_step, &.{
        vst3_tests,
        zig_vst3_plugin_core_tests,
        zig_vst3_plugin_tests,
        gain.plugin_tests,
        bypass.plugin_tests,
        mode_gain.plugin_tests,
        voice_mix.plugin_tests,
        note_gate.plugin_tests,
        event_echo.plugin_tests,
        event_monitor.plugin_tests,
        sine_synth.plugin_tests,
        gain.core_example_tests,
        bypass.core_example_tests,
        mode_gain.core_example_tests,
        voice_mix.core_example_tests,
        note_gate.core_example_tests,
        event_echo.core_example_tests,
        event_monitor.core_example_tests,
        sine_synth.core_example_tests,
    });

    const validate_step = b.step("validate", "Run the VST3 SDK validator for -Dplugin=path/to/Plugin.vst3");
    if (b.option([]const u8, "plugin", "Path to a .vst3 bundle to validate")) |plugin_path| {
        const validate = b.addSystemCommand(&.{ "scripts/validate.sh", plugin_path });
        validate_step.dependOn(&validate.step);
    } else {
        const missing_plugin = b.addFail("pass -Dplugin=path/to/Plugin.vst3");
        validate_step.dependOn(&missing_plugin.step);
    }

    const validate_gain_step = addVst3ValidationStep(b, target, gain.bundles.native, .{
        .short_name = "gain",
        .display_name = "gain",
        .artifact_name = "zig_vst3_gain",
    });
    const validate_bypass_step = addVst3ValidationStep(b, target, bypass.bundles.native, .{
        .short_name = "bypass",
        .display_name = "bypass",
        .artifact_name = "zig_vst3_bypass",
    });
    const validate_mode_gain_step = addVst3ValidationStep(b, target, mode_gain.bundles.native, .{
        .short_name = "mode-gain",
        .display_name = "mode gain",
        .artifact_name = "zig_vst3_mode_gain",
    });
    const validate_voice_mix_step = addVst3ValidationStep(b, target, voice_mix.bundles.native, .{
        .short_name = "voice-mix",
        .display_name = "voice mix",
        .artifact_name = "zig_vst3_voice_mix",
    });
    const validate_note_gate_step = addVst3ValidationStep(b, target, note_gate.bundles.native, .{
        .short_name = "note-gate",
        .display_name = "note gate",
        .artifact_name = "zig_vst3_note_gate",
    });
    const validate_event_echo_step = addVst3ValidationStep(b, target, event_echo.bundles.native, .{
        .short_name = "event-echo",
        .display_name = "event echo",
        .artifact_name = "zig_vst3_event_echo",
    });
    const validate_event_monitor_step = addVst3ValidationStep(b, target, event_monitor.bundles.native, .{
        .short_name = "event-monitor",
        .display_name = "event monitor",
        .artifact_name = "zig_vst3_event_monitor",
    });
    const validate_sine_synth_step = addVst3ValidationStep(b, target, sine_synth.bundles.native, .{
        .short_name = "sine-synth",
        .display_name = "sine synth",
        .artifact_name = "zig_vst3_sine_synth",
    });
    const validate_examples_step = b.step("validate-examples", "Build and validate all native VST3 example bundles");
    addStepDependencies(validate_examples_step, &.{
        validate_gain_step,
        validate_bypass_step,
        validate_mode_gain_step,
        validate_voice_mix_step,
        validate_note_gate_step,
        validate_event_echo_step,
        validate_event_monitor_step,
        validate_sine_synth_step,
    });

    const bundle_examples_step = b.step("bundle-examples", "Build native VST3 bundles for all example plugins");
    addVst3BundleDependencies(bundle_examples_step, &example_bundle_steps, .native);

    const clean_bundles_step = b.step("clean-bundles", "Remove generated VST3 bundles from zig-out/bundle");
    clean_bundles_step.dependOn(&b.addRemoveDirTree(b.path("zig-out/bundle")).step);

    const bundle_examples_linux_step = b.step("bundle-examples-linux", "Build Linux VST3 bundles for all example plugins");
    addVst3BundleDependencies(bundle_examples_linux_step, &example_bundle_steps, .linux);

    const bundle_examples_windows_step = b.step("bundle-examples-windows", "Build Windows VST3 bundles for all example plugins");
    addVst3BundleDependencies(bundle_examples_windows_step, &example_bundle_steps, .windows);
    const validator_step = b.step("validator", "Build Steinberg's VST3 SDK validator");
    const build_validator = b.addSystemCommand(&.{"scripts/build_validator.sh"});
    validator_step.dependOn(&build_validator.step);

    const tuid_abi_step = b.step("tuid-abi", "Compare Zig TUID bytes against the pinned VST3 SDK");
    const check_tuid_abi = b.addSystemCommand(&.{"scripts/check_tuid_abi.sh"});
    tuid_abi_step.dependOn(&check_tuid_abi.step);

    const pluginbase_abi_step = b.step("pluginbase-abi", "Compare Zig pluginbase layouts against the pinned VST3 SDK");
    const check_pluginbase_abi = b.addSystemCommand(&.{"scripts/check_pluginbase_abi.sh"});
    pluginbase_abi_step.dependOn(&check_pluginbase_abi.step);

    const ibstream_abi_step = b.step("ibstream-abi", "Compare Zig IBStream declarations against the pinned VST3 SDK");
    const check_ibstream_abi = b.addSystemCommand(&.{"scripts/check_ibstream_abi.sh"});
    ibstream_abi_step.dependOn(&check_ibstream_abi.step);

    const base_strings_error_abi_step = b.step("base-strings-error-abi", "Compare Zig base string and error declarations against the pinned VST3 SDK");
    const check_base_strings_error_abi = b.addSystemCommand(&.{"scripts/check_base_strings_error_abi.sh"});
    base_strings_error_abi_step.dependOn(&check_base_strings_error_abi.step);

    const base_persistence_abi_step = b.step("base-persistence-abi", "Compare Zig base persistence declarations against the pinned VST3 SDK");
    const check_base_persistence_abi = b.addSystemCommand(&.{"scripts/check_base_persistence_abi.sh"});
    base_persistence_abi_step.dependOn(&check_base_persistence_abi.step);

    const base_update_compatibility_abi_step = b.step("base-update-compatibility-abi", "Compare Zig base update and compatibility declarations against the pinned VST3 SDK");
    const check_base_update_compatibility_abi = b.addSystemCommand(&.{"scripts/check_base_update_compatibility_abi.sh"});
    base_update_compatibility_abi_step.dependOn(&check_base_update_compatibility_abi.step);

    const component_abi_step = b.step("component-abi", "Compare Zig IComponent declarations against the pinned VST3 SDK");
    const check_component_abi = b.addSystemCommand(&.{"scripts/check_component_abi.sh"});
    component_abi_step.dependOn(&check_component_abi.step);

    const audio_processor_abi_step = b.step("audio-processor-abi", "Compare Zig IAudioProcessor declarations against the pinned VST3 SDK");
    const check_audio_processor_abi = b.addSystemCommand(&.{"scripts/check_audio_processor_abi.sh"});
    audio_processor_abi_step.dependOn(&check_audio_processor_abi.step);

    const bypass_processor_abi_step = b.step("bypass-processor-abi", "Compare Zig bypass processor helper declarations against the pinned VST3 SDK");
    const check_bypass_processor_abi = b.addSystemCommand(&.{"scripts/check_bypass_processor_abi.sh"});
    bypass_processor_abi_step.dependOn(&check_bypass_processor_abi.step);

    const process_context_abi_step = b.step("process-context-abi", "Compare Zig process context declarations against the pinned VST3 SDK");
    const check_process_context_abi = b.addSystemCommand(&.{"scripts/check_process_context_abi.sh"});
    process_context_abi_step.dependOn(&check_process_context_abi.step);

    const edit_controller_abi_step = b.step("edit-controller-abi", "Compare Zig IEditController declarations against the pinned VST3 SDK");
    const check_edit_controller_abi = b.addSystemCommand(&.{"scripts/check_edit_controller_abi.sh"});
    edit_controller_abi_step.dependOn(&check_edit_controller_abi.step);

    const parameter_changes_abi_step = b.step("parameter-changes-abi", "Compare Zig parameter change declarations against the pinned VST3 SDK");
    const check_parameter_changes_abi = b.addSystemCommand(&.{"scripts/check_parameter_changes_abi.sh"});
    parameter_changes_abi_step.dependOn(&check_parameter_changes_abi.step);

    const events_abi_step = b.step("events-abi", "Compare Zig event declarations against the pinned VST3 SDK");
    const check_events_abi = b.addSystemCommand(&.{"scripts/check_events_abi.sh"});
    events_abi_step.dependOn(&check_events_abi.step);

    const host_message_abi_step = b.step("host-message-abi", "Compare Zig host/message declarations against the pinned VST3 SDK");
    const check_host_message_abi = b.addSystemCommand(&.{"scripts/check_host_message_abi.sh"});
    host_message_abi_step.dependOn(&check_host_message_abi.step);

    const plugview_abi_step = b.step("plugview-abi", "Compare Zig plug view declarations against the pinned VST3 SDK");
    const check_plugview_abi = b.addSystemCommand(&.{"scripts/check_plugview_abi.sh"});
    plugview_abi_step.dependOn(&check_plugview_abi.step);

    const units_abi_step = b.step("units-abi", "Compare Zig unit declarations against the pinned VST3 SDK");
    const check_units_abi = b.addSystemCommand(&.{"scripts/check_units_abi.sh"});
    units_abi_step.dependOn(&check_units_abi.step);

    const midi_mapping_abi_step = b.step("midi-mapping-abi", "Compare Zig MIDI mapping declarations against the pinned VST3 SDK");
    const check_midi_mapping_abi = b.addSystemCommand(&.{"scripts/check_midi_mapping_abi.sh"});
    midi_mapping_abi_step.dependOn(&check_midi_mapping_abi.step);

    const midi_controllers_abi_step = b.step("midi-controllers-abi", "Compare Zig MIDI controller constants against the pinned VST3 SDK");
    const check_midi_controllers_abi = b.addSystemCommand(&.{"scripts/check_midi_controllers_abi.sh"});
    midi_controllers_abi_step.dependOn(&check_midi_controllers_abi.step);

    const speaker_core_abi_step = b.step("speaker-core-abi", "Compare Zig speaker constants and helpers against the pinned VST3 SDK");
    const check_speaker_core_abi = b.addSystemCommand(&.{"scripts/check_speaker_core_abi.sh"});
    speaker_core_abi_step.dependOn(&check_speaker_core_abi.step);

    const preset_keys_abi_step = b.step("preset-keys-abi", "Compare Zig preset attribute constants against the pinned VST3 SDK");
    const check_preset_keys_abi = b.addSystemCommand(&.{"scripts/check_preset_keys_abi.sh"});
    preset_keys_abi_step.dependOn(&check_preset_keys_abi.step);

    const preset_file_abi_step = b.step("preset-file-abi", "Compare Zig preset file chunk declarations against the pinned VST3 SDK");
    const check_preset_file_abi = b.addSystemCommand(&.{"scripts/check_preset_file_abi.sh"});
    preset_file_abi_step.dependOn(&check_preset_file_abi.step);

    const note_expression_abi_step = b.step("note-expression-abi", "Compare Zig note expression declarations against the pinned VST3 SDK");
    const check_note_expression_abi = b.addSystemCommand(&.{"scripts/check_note_expression_abi.sh"});
    note_expression_abi_step.dependOn(&check_note_expression_abi.step);

    const capability_state_abi_step = b.step("capability-state-abi", "Compare Zig capability and state declarations against the pinned VST3 SDK");
    const check_capability_state_abi = b.addSystemCommand(&.{"scripts/check_capability_state_abi.sh"});
    capability_state_abi_step.dependOn(&check_capability_state_abi.step);

    const parameter_helpers_abi_step = b.step("parameter-helpers-abi", "Compare Zig parameter helper declarations against the pinned VST3 SDK");
    const check_parameter_helpers_abi = b.addSystemCommand(&.{"scripts/check_parameter_helpers_abi.sh"});
    parameter_helpers_abi_step.dependOn(&check_parameter_helpers_abi.step);

    const context_menu_abi_step = b.step("context-menu-abi", "Compare Zig context menu declarations against the pinned VST3 SDK");
    const check_context_menu_abi = b.addSystemCommand(&.{"scripts/check_context_menu_abi.sh"});
    context_menu_abi_step.dependOn(&check_context_menu_abi.step);

    const physical_channel_abi_step = b.step("physical-channel-abi", "Compare Zig physical UI and channel context declarations against the pinned VST3 SDK");
    const check_physical_channel_abi = b.addSystemCommand(&.{"scripts/check_physical_channel_abi.sh"});
    physical_channel_abi_step.dependOn(&check_physical_channel_abi.step);

    const data_exchange_abi_step = b.step("data-exchange-abi", "Compare Zig data exchange declarations against the pinned VST3 SDK");
    const check_data_exchange_abi = b.addSystemCommand(&.{"scripts/check_data_exchange_abi.sh"});
    data_exchange_abi_step.dependOn(&check_data_exchange_abi.step);

    const representation_abi_step = b.step("representation-abi", "Compare Zig XML representation declarations against the pinned VST3 SDK");
    const check_representation_abi = b.addSystemCommand(&.{"scripts/check_representation_abi.sh"});
    representation_abi_step.dependOn(&check_representation_abi.step);

    const wayland_frame_abi_step = b.step("wayland-frame-abi", "Compare Zig Wayland frame declarations against the pinned VST3 SDK");
    const check_wayland_frame_abi = b.addSystemCommand(&.{"scripts/check_wayland_frame_abi.sh"});
    wayland_frame_abi_step.dependOn(&check_wayland_frame_abi.step);

    const inter_app_audio_abi_step = b.step("inter-app-audio-abi", "Compare Zig Inter-App Audio declarations against the pinned VST3 SDK");
    const check_inter_app_audio_abi = b.addSystemCommand(&.{"scripts/check_inter_app_audio_abi.sh"});
    inter_app_audio_abi_step.dependOn(&check_inter_app_audio_abi.step);

    const test_plug_provider_abi_step = b.step("test-plug-provider-abi", "Compare Zig test plug provider declarations against the pinned VST3 SDK");
    const check_test_plug_provider_abi = b.addSystemCommand(&.{"scripts/check_test_plug_provider_abi.sh"});
    test_plug_provider_abi_step.dependOn(&check_test_plug_provider_abi.step);

    const test_interfaces_abi_step = b.step("test-interfaces-abi", "Compare Zig test interface declarations against the pinned VST3 SDK");
    const check_test_interfaces_abi = b.addSystemCommand(&.{"scripts/check_test_interfaces_abi.sh"});
    test_interfaces_abi_step.dependOn(&check_test_interfaces_abi.step);

    const funknown_harness_zig = b.addObject(.{
        .name = "funknown_harness_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/abi/funknown_harness.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    funknown_harness_zig.root_module.addImport("zig-vst3", zig_vst3);

    const funknown_harness = b.addExecutable(.{
        .name = "funknown_harness",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .sanitize_c = .off,
        }),
    });
    funknown_harness.root_module.addCSourceFile(.{
        .file = b.path("tests/abi/funknown_harness.c"),
        .flags = &.{},
    });
    funknown_harness.root_module.addObject(funknown_harness_zig);

    const funknown_abi_step = b.step("funknown-abi", "Run the C ABI harness for the FUnknown prototype");
    funknown_abi_step.dependOn(&b.addRunArtifact(funknown_harness).step);

    const multi_interface_harness_zig = b.addObject(.{
        .name = "multi_interface_harness_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/abi/multi_interface_harness.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    multi_interface_harness_zig.root_module.addImport("zig-vst3", zig_vst3);

    const multi_interface_harness = b.addExecutable(.{
        .name = "multi_interface_harness",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .sanitize_c = .off,
        }),
    });
    multi_interface_harness.root_module.addCSourceFile(.{
        .file = b.path("tests/abi/multi_interface_harness.c"),
        .flags = &.{},
    });
    multi_interface_harness.root_module.addObject(multi_interface_harness_zig);

    const multi_interface_abi_step = b.step("multi-interface-abi", "Run the C ABI harness for multi-interface query dispatch");
    multi_interface_abi_step.dependOn(&b.addRunArtifact(multi_interface_harness).step);

    const multi_interface_cpp_harness = b.addExecutable(.{
        .name = "multi_interface_cpp_harness",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .sanitize_c = .off,
        }),
    });
    multi_interface_cpp_harness.root_module.addCSourceFile(.{
        .file = b.path("tests/abi/multi_interface_harness.cpp"),
        .flags = &.{"-std=c++17"},
    });
    multi_interface_cpp_harness.root_module.addObject(multi_interface_harness_zig);

    const multi_interface_cpp_abi_step = b.step("multi-interface-cpp-abi", "Run the C++ ABI harness for multi-interface query dispatch");
    multi_interface_cpp_abi_step.dependOn(&b.addRunArtifact(multi_interface_cpp_harness).step);

    const multi_interface_sdk_harness = b.addExecutable(.{
        .name = "multi_interface_sdk_harness",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .sanitize_c = .off,
        }),
    });
    multi_interface_sdk_harness.root_module.addIncludePath(b.path(".vst3-sdk/vst3sdk"));
    multi_interface_sdk_harness.root_module.addCSourceFile(.{
        .file = b.path("tests/abi/multi_interface_sdk_harness.cpp"),
        .flags = &.{"-std=c++17"},
    });
    multi_interface_sdk_harness.root_module.addObject(multi_interface_harness_zig);

    const multi_interface_sdk_abi_step = b.step("multi-interface-sdk-abi", "Run the Steinberg SDK C++ ABI harness for multi-interface query dispatch");
    multi_interface_sdk_abi_step.dependOn(&b.addRunArtifact(multi_interface_sdk_harness).step);

    const layer1_abi_step = b.step("layer1-abi", "Run Layer 1 ABI and entry-symbol checks");
    layer1_abi_step.dependOn(entry_symbols_step);
    layer1_abi_step.dependOn(tuid_abi_step);
    layer1_abi_step.dependOn(pluginbase_abi_step);
    layer1_abi_step.dependOn(ibstream_abi_step);
    layer1_abi_step.dependOn(base_strings_error_abi_step);
    layer1_abi_step.dependOn(base_persistence_abi_step);
    layer1_abi_step.dependOn(base_update_compatibility_abi_step);
    layer1_abi_step.dependOn(component_abi_step);
    layer1_abi_step.dependOn(audio_processor_abi_step);
    layer1_abi_step.dependOn(bypass_processor_abi_step);
    layer1_abi_step.dependOn(process_context_abi_step);
    layer1_abi_step.dependOn(edit_controller_abi_step);
    layer1_abi_step.dependOn(parameter_changes_abi_step);
    layer1_abi_step.dependOn(events_abi_step);
    layer1_abi_step.dependOn(host_message_abi_step);
    layer1_abi_step.dependOn(plugview_abi_step);
    layer1_abi_step.dependOn(units_abi_step);
    layer1_abi_step.dependOn(midi_mapping_abi_step);
    layer1_abi_step.dependOn(midi_controllers_abi_step);
    layer1_abi_step.dependOn(speaker_core_abi_step);
    layer1_abi_step.dependOn(preset_keys_abi_step);
    layer1_abi_step.dependOn(preset_file_abi_step);
    layer1_abi_step.dependOn(note_expression_abi_step);
    layer1_abi_step.dependOn(capability_state_abi_step);
    layer1_abi_step.dependOn(parameter_helpers_abi_step);
    layer1_abi_step.dependOn(context_menu_abi_step);
    layer1_abi_step.dependOn(physical_channel_abi_step);
    layer1_abi_step.dependOn(data_exchange_abi_step);
    layer1_abi_step.dependOn(representation_abi_step);
    layer1_abi_step.dependOn(wayland_frame_abi_step);
    layer1_abi_step.dependOn(inter_app_audio_abi_step);
    layer1_abi_step.dependOn(test_plug_provider_abi_step);
    layer1_abi_step.dependOn(test_interfaces_abi_step);
    layer1_abi_step.dependOn(funknown_abi_step);
    layer1_abi_step.dependOn(multi_interface_abi_step);
    layer1_abi_step.dependOn(multi_interface_cpp_abi_step);
    layer1_abi_step.dependOn(multi_interface_sdk_abi_step);

    const phase1_step = b.step("phase1", "Run Phase 1 COM/vtable integration checks");
    phase1_step.dependOn(test_step);
    phase1_step.dependOn(layer1_abi_step);
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

fn addExamplePlugin(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    zig_vst3_plugin_core: *std.Build.Module,
    zig_vst3_plugin: *std.Build.Module,
    entry_symbols_step: *std.Build.Step,
    options: ExamplePluginOptions,
) ExamplePluginSteps {
    const library = addVst3PluginLibrary(b, target, optimize, zig_vst3_plugin_core, .{
        .artifact_name = options.artifact_name,
        .root_source_file = options.root_source_file,
    });
    addEntrySymbolsCheck(b, entry_symbols_step, library);

    return .{
        .library = library,
        .bundles = addVst3BundleSteps(b, target, library, .{
            .short_name = options.short_name,
            .display_name = options.display_name,
            .artifact_name = options.artifact_name,
            .bundle_id = options.bundle_id,
        }),
        .plugin_tests = addZigVst3PluginCoreTest(b, target, optimize, zig_vst3_plugin_core, options.root_source_file),
        .core_example_tests = addZigVst3PluginTest(b, target, optimize, zig_vst3_plugin, options.core_example_source_file),
    };
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
            "0.1.0",
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
            options.artifact_name,
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
            options.artifact_name,
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
