const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vst3_zig = b.addModule("vst3-zig", .{
        .root_source_file = b.path("vst3-zig/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const nih_zig = b.addModule("nih-zig", .{
        .root_source_file = b.path("nih-zig/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    nih_zig.addImport("vst3-zig", vst3_zig);

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

    const nih_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("nih-zig/src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    nih_tests.root_module.addImport("vst3-zig", vst3_zig);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(vst3_tests).step);
    test_step.dependOn(&b.addRunArtifact(nih_tests).step);
}
