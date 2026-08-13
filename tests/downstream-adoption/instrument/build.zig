const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dependency = b.dependency("zig_vst3", .{ .target = target, .optimize = optimize });

    const module = b.createModule(.{
        .root_source_file = b.path("src/plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("zig-vst3", dependency.module("zig-vst3"));
    module.addImport("zig-vst3-plugin", dependency.module("zig-vst3-plugin"));

    const library = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "downstream_instrument",
        .root_module = module,
    });
    const tests = b.addTest(.{ .root_module = module });

    const bundle = b.step("bundle", "Build the native downstream instrument bundle");
    addNativeBundle(b, bundle, target, library);

    const test_step = b.step("test", "Test the downstream instrument and build its bundle");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(bundle);
}

fn addNativeBundle(
    b: *std.Build,
    bundle: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    library: *std.Build.Step.Compile,
) void {
    const relative_path = switch (target.result.os.tag) {
        .macos => "bundle/DownstreamInstrument.vst3/Contents/MacOS/downstream_instrument",
        .linux => b.fmt(
            "bundle/DownstreamInstrument.vst3/Contents/{s}-linux/downstream_instrument.so",
            .{@tagName(target.result.cpu.arch)},
        ),
        .windows => b.fmt(
            "bundle/DownstreamInstrument.vst3/Contents/{s}-win/downstream_instrument.vst3",
            .{@tagName(target.result.cpu.arch)},
        ),
        else => @panic("downstream instrument bundle requires macOS, Linux, or Windows"),
    };
    bundle.dependOn(&b.addInstallFile(library.getEmittedBin(), relative_path).step);
    bundle.dependOn(&b.addInstallFile(
        b.path("src/assets/wavetable.txt"),
        "bundle/DownstreamInstrument.vst3/Contents/Resources/wavetable.txt",
    ).step);
    if (target.result.os.tag == .macos) {
        bundle.dependOn(&b.addInstallFile(
            b.path("bundle/Info.plist"),
            "bundle/DownstreamInstrument.vst3/Contents/Info.plist",
        ).step);
        bundle.dependOn(&b.addInstallFile(
            b.path("bundle/PkgInfo"),
            "bundle/DownstreamInstrument.vst3/Contents/PkgInfo",
        ).step);
    }
}
