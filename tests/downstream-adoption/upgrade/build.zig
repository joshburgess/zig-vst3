const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dependency = b.dependency("zig_vst3", .{ .target = target, .optimize = optimize });

    const migrated_module = b.createModule(.{
        .root_source_file = b.path("src/upgrade.zig"),
        .target = target,
        .optimize = optimize,
    });
    addImports(migrated_module, dependency);
    const migrated_tests = b.addTest(.{ .root_module = migrated_module });
    const test_step = b.step("test", "Test the pre-candidate consumer upgrade");
    test_step.dependOn(&b.addRunArtifact(migrated_tests).step);

    const legacy_backend_module = b.createModule(.{
        .root_source_file = b.path("src/legacy_backend_version.zig"),
        .target = target,
        .optimize = optimize,
    });
    addImports(legacy_backend_module, dependency);
    const legacy_backend_tests = b.addTest(.{ .root_module = legacy_backend_module });
    const legacy_backend_step = b.step("legacy-backend-version", "Compile the retired backendVersion path");
    legacy_backend_step.dependOn(&legacy_backend_tests.step);

    const legacy_lv2_module = b.createModule(.{
        .root_source_file = b.path("src/legacy_lv2_metadata.zig"),
        .target = target,
        .optimize = optimize,
    });
    addImports(legacy_lv2_module, dependency);
    const legacy_lv2_tests = b.addTest(.{ .root_module = legacy_lv2_module });
    const legacy_lv2_step = b.step("legacy-lv2-metadata", "Compile the retired LV2 metadata path");
    legacy_lv2_step.dependOn(&legacy_lv2_tests.step);
}

fn addImports(module: *std.Build.Module, dependency: *std.Build.Dependency) void {
    module.addImport("zig-vst3", dependency.module("zig-vst3"));
    module.addImport("zig-vst3-plugin", dependency.module("zig-vst3-plugin"));
    module.addImport("zig-vst3-plugin-core", dependency.module("zig-vst3-plugin-core"));
}
