const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vst3_zig = b.addModule("vst3-zig", .{
        .root_source_file = b.path("vst3-zig/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zig_plug = b.addModule("zig-plug", .{
        .root_source_file = b.path("zig-plug/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zig_plug.addImport("vst3-zig", vst3_zig);

    const stub = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zig_vst3_stub",
        .root_module = b.createModule(.{
            .root_source_file = b.path("vst3-zig/src/stub_plugin.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(stub);

    const vst3_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("vst3-zig/src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const zig_plug_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig-plug/src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    zig_plug_tests.root_module.addImport("vst3-zig", vst3_zig);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(vst3_tests).step);
    test_step.dependOn(&b.addRunArtifact(zig_plug_tests).step);

    const validate_step = b.step("validate", "Run the VST3 SDK validator for -Dplugin=path/to/Plugin.vst3");
    if (b.option([]const u8, "plugin", "Path to a .vst3 bundle to validate")) |plugin_path| {
        const validate = b.addSystemCommand(&.{ "scripts/validate.sh", plugin_path });
        validate_step.dependOn(&validate.step);
    } else {
        const missing_plugin = b.addFail("pass -Dplugin=path/to/Plugin.vst3");
        validate_step.dependOn(&missing_plugin.step);
    }

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

    const component_abi_step = b.step("component-abi", "Compare Zig IComponent declarations against the pinned VST3 SDK");
    const check_component_abi = b.addSystemCommand(&.{"scripts/check_component_abi.sh"});
    component_abi_step.dependOn(&check_component_abi.step);

    const audio_processor_abi_step = b.step("audio-processor-abi", "Compare Zig IAudioProcessor declarations against the pinned VST3 SDK");
    const check_audio_processor_abi = b.addSystemCommand(&.{"scripts/check_audio_processor_abi.sh"});
    audio_processor_abi_step.dependOn(&check_audio_processor_abi.step);

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

    const phase1_step = b.step("phase1", "Run Phase 1 COM/vtable integration checks");
    phase1_step.dependOn(test_step);
    phase1_step.dependOn(tuid_abi_step);
    phase1_step.dependOn(pluginbase_abi_step);
    phase1_step.dependOn(ibstream_abi_step);
    phase1_step.dependOn(component_abi_step);
    phase1_step.dependOn(audio_processor_abi_step);
    phase1_step.dependOn(edit_controller_abi_step);
    phase1_step.dependOn(parameter_changes_abi_step);
    phase1_step.dependOn(events_abi_step);
    phase1_step.dependOn(host_message_abi_step);
    phase1_step.dependOn(plugview_abi_step);
    phase1_step.dependOn(units_abi_step);
    phase1_step.dependOn(midi_mapping_abi_step);
    phase1_step.dependOn(note_expression_abi_step);
    phase1_step.dependOn(capability_state_abi_step);
    phase1_step.dependOn(parameter_helpers_abi_step);
    phase1_step.dependOn(context_menu_abi_step);
    phase1_step.dependOn(physical_channel_abi_step);
    phase1_step.dependOn(data_exchange_abi_step);
    phase1_step.dependOn(representation_abi_step);
    phase1_step.dependOn(funknown_abi_step);
    phase1_step.dependOn(multi_interface_abi_step);
}
