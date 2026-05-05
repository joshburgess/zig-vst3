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
}
