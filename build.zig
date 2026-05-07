const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vst3_zig = b.addModule("vst3-zig", .{
        .root_source_file = b.path("vst3-zig/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zig_plug_core = b.addModule("zig-plug-core", .{
        .root_source_file = b.path("zig-plug/src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    vst3_zig.addImport("zig-plug-core", zig_plug_core);

    const zig_plug = b.addModule("zig-plug", .{
        .root_source_file = b.path("zig-plug/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zig_plug.addImport("zig-plug-core", zig_plug_core);
    zig_plug.addImport("vst3-zig", vst3_zig);

    const gain = addVst3PluginLibrary(b, target, optimize, zig_plug_core, .{
        .artifact_name = "zig_vst3_gain",
        .root_source_file = "vst3-zig/src/gain_plugin.zig",
    });
    const bypass = addVst3PluginLibrary(b, target, optimize, zig_plug_core, .{
        .artifact_name = "zig_vst3_bypass",
        .root_source_file = "vst3-zig/src/bypass_plugin.zig",
    });
    const mode_gain = addVst3PluginLibrary(b, target, optimize, zig_plug_core, .{
        .artifact_name = "zig_vst3_mode_gain",
        .root_source_file = "vst3-zig/src/mode_gain_plugin.zig",
    });
    const voice_mix = addVst3PluginLibrary(b, target, optimize, zig_plug_core, .{
        .artifact_name = "zig_vst3_voice_mix",
        .root_source_file = "vst3-zig/src/voice_mix_plugin.zig",
    });

    const entry_symbols_step = b.step("entry-symbols", "Verify native VST3 module entry exports");
    addEntrySymbolsCheck(b, entry_symbols_step, gain);
    addEntrySymbolsCheck(b, entry_symbols_step, bypass);
    addEntrySymbolsCheck(b, entry_symbols_step, mode_gain);
    addEntrySymbolsCheck(b, entry_symbols_step, voice_mix);

    const bundle_gain_step = addVst3BundleSteps(b, target, gain, .{
        .short_name = "gain",
        .display_name = "gain",
        .artifact_name = "zig_vst3_gain",
        .bundle_id = "dev.zig-vst3.gain",
    });
    const bundle_bypass_step = addVst3BundleSteps(b, target, bypass, .{
        .short_name = "bypass",
        .display_name = "bypass",
        .artifact_name = "zig_vst3_bypass",
        .bundle_id = "dev.zig-vst3.bypass",
    });
    const bundle_mode_gain_step = addVst3BundleSteps(b, target, mode_gain, .{
        .short_name = "mode-gain",
        .display_name = "mode gain",
        .artifact_name = "zig_vst3_mode_gain",
        .bundle_id = "dev.zig-vst3.mode-gain",
    });
    const bundle_voice_mix_step = addVst3BundleSteps(b, target, voice_mix, .{
        .short_name = "voice-mix",
        .display_name = "voice mix",
        .artifact_name = "zig_vst3_voice_mix",
        .bundle_id = "dev.zig-vst3.voice-mix",
    });
    const vst3_test_module = b.createModule(.{
        .root_source_file = b.path("vst3-zig/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    vst3_test_module.addImport("zig-plug-core", zig_plug_core);
    const vst3_tests = b.addTest(.{
        .root_module = vst3_test_module,
    });

    const zig_plug_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig-plug/src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    zig_plug_tests.root_module.addImport("vst3-zig", vst3_zig);
    zig_plug_tests.root_module.addImport("zig-plug-core", zig_plug_core);

    const gain_test_module = b.createModule(.{
        .root_source_file = b.path("vst3-zig/src/gain_plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    gain_test_module.addImport("zig-plug-core", zig_plug_core);
    const gain_tests = b.addTest(.{
        .root_module = gain_test_module,
    });

    const bypass_test_module = b.createModule(.{
        .root_source_file = b.path("vst3-zig/src/bypass_plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    bypass_test_module.addImport("zig-plug-core", zig_plug_core);
    const bypass_tests = b.addTest(.{
        .root_module = bypass_test_module,
    });

    const mode_gain_test_module = b.createModule(.{
        .root_source_file = b.path("vst3-zig/src/mode_gain_plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    mode_gain_test_module.addImport("zig-plug-core", zig_plug_core);
    const mode_gain_tests = b.addTest(.{
        .root_module = mode_gain_test_module,
    });

    const voice_mix_test_module = b.createModule(.{
        .root_source_file = b.path("vst3-zig/src/voice_mix_plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    voice_mix_test_module.addImport("zig-plug-core", zig_plug_core);
    const voice_mix_tests = b.addTest(.{
        .root_module = voice_mix_test_module,
    });

    const gain_core_example_module = b.createModule(.{
        .root_source_file = b.path("examples/gain_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    gain_core_example_module.addImport("zig-plug-core", zig_plug_core);
    const gain_core_example_tests = b.addTest(.{
        .root_module = gain_core_example_module,
    });

    const bypass_core_example_module = b.createModule(.{
        .root_source_file = b.path("examples/bypass_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    bypass_core_example_module.addImport("zig-plug-core", zig_plug_core);
    const bypass_core_example_tests = b.addTest(.{
        .root_module = bypass_core_example_module,
    });

    const mode_gain_core_example_module = b.createModule(.{
        .root_source_file = b.path("examples/mode_gain_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    mode_gain_core_example_module.addImport("zig-plug-core", zig_plug_core);
    const mode_gain_core_example_tests = b.addTest(.{
        .root_module = mode_gain_core_example_module,
    });

    const voice_mix_core_example_module = b.createModule(.{
        .root_source_file = b.path("examples/voice_mix_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    voice_mix_core_example_module.addImport("zig-plug-core", zig_plug_core);
    const voice_mix_core_example_tests = b.addTest(.{
        .root_module = voice_mix_core_example_module,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(vst3_tests).step);
    test_step.dependOn(&b.addRunArtifact(zig_plug_tests).step);
    test_step.dependOn(&b.addRunArtifact(gain_tests).step);
    test_step.dependOn(&b.addRunArtifact(bypass_tests).step);
    test_step.dependOn(&b.addRunArtifact(mode_gain_tests).step);
    test_step.dependOn(&b.addRunArtifact(voice_mix_tests).step);
    test_step.dependOn(&b.addRunArtifact(gain_core_example_tests).step);
    test_step.dependOn(&b.addRunArtifact(bypass_core_example_tests).step);
    test_step.dependOn(&b.addRunArtifact(mode_gain_core_example_tests).step);
    test_step.dependOn(&b.addRunArtifact(voice_mix_core_example_tests).step);

    const validate_step = b.step("validate", "Run the VST3 SDK validator for -Dplugin=path/to/Plugin.vst3");
    if (b.option([]const u8, "plugin", "Path to a .vst3 bundle to validate")) |plugin_path| {
        const validate = b.addSystemCommand(&.{ "scripts/validate.sh", plugin_path });
        validate_step.dependOn(&validate.step);
    } else {
        const missing_plugin = b.addFail("pass -Dplugin=path/to/Plugin.vst3");
        validate_step.dependOn(&missing_plugin.step);
    }

    const validate_gain_step = b.step("validate-gain", "Build and validate the native gain VST3 bundle");
    if (target.result.os.tag == .macos) {
        validate_gain_step.dependOn(bundle_gain_step);
        const validate_gain = b.addSystemCommand(&.{
            "scripts/validate.sh",
            b.getInstallPath(.prefix, "bundle/zig_vst3_gain.vst3"),
        });
        validate_gain.step.dependOn(bundle_gain_step);
        validate_gain_step.dependOn(&validate_gain.step);
    } else {
        validate_gain_step.dependOn(&b.addFail("validate-gain currently supports macOS targets").step);
    }
    const validate_bypass_step = b.step("validate-bypass", "Build and validate the native bypass VST3 bundle");
    if (target.result.os.tag == .macos) {
        validate_bypass_step.dependOn(bundle_bypass_step);
        const validate_bypass = b.addSystemCommand(&.{
            "scripts/validate.sh",
            b.getInstallPath(.prefix, "bundle/zig_vst3_bypass.vst3"),
        });
        validate_bypass.step.dependOn(bundle_bypass_step);
        validate_bypass_step.dependOn(&validate_bypass.step);
    } else {
        validate_bypass_step.dependOn(&b.addFail("validate-bypass currently supports macOS targets").step);
    }
    const validate_mode_gain_step = b.step("validate-mode-gain", "Build and validate the native mode gain VST3 bundle");
    if (target.result.os.tag == .macos) {
        validate_mode_gain_step.dependOn(bundle_mode_gain_step);
        const validate_mode_gain = b.addSystemCommand(&.{
            "scripts/validate.sh",
            b.getInstallPath(.prefix, "bundle/zig_vst3_mode_gain.vst3"),
        });
        validate_mode_gain.step.dependOn(bundle_mode_gain_step);
        validate_mode_gain_step.dependOn(&validate_mode_gain.step);
    } else {
        validate_mode_gain_step.dependOn(&b.addFail("validate-mode-gain currently supports macOS targets").step);
    }
    const validate_voice_mix_step = b.step("validate-voice-mix", "Build and validate the native voice mix VST3 bundle");
    if (target.result.os.tag == .macos) {
        validate_voice_mix_step.dependOn(bundle_voice_mix_step);
        const validate_voice_mix = b.addSystemCommand(&.{
            "scripts/validate.sh",
            b.getInstallPath(.prefix, "bundle/zig_vst3_voice_mix.vst3"),
        });
        validate_voice_mix.step.dependOn(bundle_voice_mix_step);
        validate_voice_mix_step.dependOn(&validate_voice_mix.step);
    } else {
        validate_voice_mix_step.dependOn(&b.addFail("validate-voice-mix currently supports macOS targets").step);
    }
    const validate_examples_step = b.step("validate-examples", "Build and validate all native VST3 example bundles");
    validate_examples_step.dependOn(validate_gain_step);
    validate_examples_step.dependOn(validate_bypass_step);
    validate_examples_step.dependOn(validate_mode_gain_step);
    validate_examples_step.dependOn(validate_voice_mix_step);
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
    funknown_harness_zig.root_module.addImport("vst3-zig", vst3_zig);

    const funknown_harness = b.addExecutable(.{
        .name = "funknown_harness",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
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
    multi_interface_harness_zig.root_module.addImport("vst3-zig", vst3_zig);

    const multi_interface_harness = b.addExecutable(.{
        .name = "multi_interface_harness",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
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

    const phase1_step = b.step("phase1", "Run Phase 1 COM/vtable integration checks");
    phase1_step.dependOn(test_step);
    phase1_step.dependOn(entry_symbols_step);
    if (target.result.os.tag == .macos) {
        phase1_step.dependOn(validate_gain_step);
    }
    phase1_step.dependOn(tuid_abi_step);
    phase1_step.dependOn(pluginbase_abi_step);
    phase1_step.dependOn(ibstream_abi_step);
    phase1_step.dependOn(base_strings_error_abi_step);
    phase1_step.dependOn(base_persistence_abi_step);
    phase1_step.dependOn(base_update_compatibility_abi_step);
    phase1_step.dependOn(component_abi_step);
    phase1_step.dependOn(audio_processor_abi_step);
    phase1_step.dependOn(bypass_processor_abi_step);
    phase1_step.dependOn(process_context_abi_step);
    phase1_step.dependOn(edit_controller_abi_step);
    phase1_step.dependOn(parameter_changes_abi_step);
    phase1_step.dependOn(events_abi_step);
    phase1_step.dependOn(host_message_abi_step);
    phase1_step.dependOn(plugview_abi_step);
    phase1_step.dependOn(units_abi_step);
    phase1_step.dependOn(midi_mapping_abi_step);
    phase1_step.dependOn(midi_controllers_abi_step);
    phase1_step.dependOn(speaker_core_abi_step);
    phase1_step.dependOn(preset_keys_abi_step);
    phase1_step.dependOn(preset_file_abi_step);
    phase1_step.dependOn(note_expression_abi_step);
    phase1_step.dependOn(capability_state_abi_step);
    phase1_step.dependOn(parameter_helpers_abi_step);
    phase1_step.dependOn(context_menu_abi_step);
    phase1_step.dependOn(physical_channel_abi_step);
    phase1_step.dependOn(data_exchange_abi_step);
    phase1_step.dependOn(representation_abi_step);
    phase1_step.dependOn(wayland_frame_abi_step);
    phase1_step.dependOn(inter_app_audio_abi_step);
    phase1_step.dependOn(test_plug_provider_abi_step);
    phase1_step.dependOn(test_interfaces_abi_step);
    phase1_step.dependOn(funknown_abi_step);
    phase1_step.dependOn(multi_interface_abi_step);
    phase1_step.dependOn(multi_interface_cpp_abi_step);
    phase1_step.dependOn(multi_interface_sdk_abi_step);
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
    zig_plug_core: *std.Build.Module,
    options: Vst3PluginLibraryOptions,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path(options.root_source_file),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("zig-plug-core", zig_plug_core);

    const library = b.addLibrary(.{
        .linkage = .dynamic,
        .name = options.artifact_name,
        .root_module = module,
    });
    b.installArtifact(library);
    return library;
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

const Vst3BundleOptions = struct {
    short_name: []const u8,
    display_name: []const u8,
    artifact_name: []const u8,
    bundle_id: []const u8,
};

fn addVst3BundleSteps(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    library: *std.Build.Step.Compile,
    options: Vst3BundleOptions,
) *std.Build.Step {
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
    } else {
        native_step.dependOn(&b.addFail(b.fmt("{s} currently supports macOS targets", .{native_step_name})).step);
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

    return native_step;
}
