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

    const test_step = b.step("test", "Compile installed-package editor consumers");
    test_step.dependOn(&b.addRunArtifact(consumer_tests).step);
}
