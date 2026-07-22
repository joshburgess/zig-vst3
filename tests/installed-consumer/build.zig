const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dependency = b.dependency("zig_vst3", .{ .target = target, .optimize = optimize });

    const consumer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("editors.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    consumer_tests.root_module.addImport("zig-vst3", dependency.module("zig-vst3"));
    consumer_tests.root_module.addImport("zig-vst3-plugin", dependency.module("zig-vst3-plugin"));

    const kernel_module = b.createModule(.{
        .root_source_file = b.path("kernel_plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    kernel_module.addImport("zig-vst3", dependency.module("zig-vst3"));
    kernel_module.addImport("zig-vst3-plugin-core", dependency.module("zig-vst3-plugin-core"));
    addPortableKernel(b, kernel_module, target);
    const kernel_plugin = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "installed_c_kernel",
        .root_module = kernel_module,
    });

    const kernel_test_module = b.createModule(.{
        .root_source_file = b.path("kernel_plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    kernel_test_module.addImport("zig-vst3", dependency.module("zig-vst3"));
    kernel_test_module.addImport("zig-vst3-plugin-core", dependency.module("zig-vst3-plugin-core"));
    addPortableKernel(b, kernel_test_module, target);
    const kernel_tests = b.addTest(.{ .root_module = kernel_test_module });

    const test_step = b.step("test", "Compile installed-package editor consumers");
    test_step.dependOn(&b.addRunArtifact(consumer_tests).step);
    test_step.dependOn(&kernel_plugin.step);
    test_step.dependOn(&b.addRunArtifact(kernel_tests).step);
}

fn addPortableKernel(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget) void {
    module.link_libc = true;
    module.addIncludePath(b.path("kernel"));
    module.addCSourceFile(.{
        .file = b.path("kernel/dense.c"),
        .flags = if (target.result.os.tag == .windows)
            &.{"-std=c11"}
        else
            &.{ "-std=c11", "-fvisibility=hidden" },
    });
}
