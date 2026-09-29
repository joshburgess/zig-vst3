# C DSP Kernels

A plugin may compile its own C DSP sources into the same dynamic library as its Zig code. `zig-vst3` does not own those sources or require a separate C library.

## Build recipe

Add the framework modules and C sources to the plugin root module. Each C source receives its own flags, so accelerated kernels can use relaxed floating-point rules without changing the plugin shell, model parser, or portable implementation.

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dependency = b.dependency("zig_vst3", .{
        .target = target,
        .optimize = optimize,
    });

    const module = b.createModule(.{
        .root_source_file = b.path("src/plugin.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("zig-vst3", dependency.module("zig-vst3"));
    module.addImport("zig-vst3-plugin", dependency.module("zig-vst3-plugin"));
    module.link_libc = true;
    module.addIncludePath(b.path("src/kernels"));
    module.addCSourceFile(.{
        .file = b.path("src/kernels/dense_portable.c"),
        .flags = portableFlags(target),
    });

    switch (target.result.cpu.arch) {
        .aarch64 => module.addCSourceFile(.{
            .file = b.path("src/kernels/dense_neon.c"),
            .flags = if (target.result.os.tag == .windows)
                &.{ "-std=c11", "-ffast-math" }
            else
                &.{ "-std=c11", "-ffast-math", "-fvisibility=hidden" },
        }),
        .x86_64 => module.addCSourceFile(.{
            .file = b.path("src/kernels/dense_avx2.c"),
            .flags = if (target.result.os.tag == .windows)
                &.{ "-std=c11", "-msse3", "-mavx2", "-ffast-math" }
            else
                &.{ "-std=c11", "-msse3", "-mavx2", "-ffast-math", "-fvisibility=hidden" },
        }),
        else => {},
    }

    const plugin = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "example_plugin",
        .root_module = module,
    });
    b.installArtifact(plugin);
}

fn portableFlags(target: std.Build.ResolvedTarget) []const []const u8 {
    return if (target.result.os.tag == .windows)
        &.{"-std=c11"}
    else
        &.{ "-std=c11", "-fvisibility=hidden" };
}

```

The [C Kernel Probe build function](../../build.zig) uses this pattern for every supported target. The [installed consumer fixture](../../tests/installed-consumer/build.zig) is the smallest complete portable example.

## Source layout

Keep the baseline and accelerated implementations separate:

```text
src/
  plugin.zig
  kernels/
    dense.h
    dense_portable.c
    dense_neon.c
    dense_avx2.c
```

This layout provides three useful boundaries:

- Every distribution target contains a portable implementation.
- Unsupported architecture headers never enter another target's compilation.
- Flags such as `-ffast-math` and `-mavx2` apply only to the selected source file.

## Runtime dispatch

Compile accelerated objects for the architecture, then select a function pointer once when the processor instance is initialized:

```zig
const builtin = @import("builtin");
const plug = @import("zig-vst3-plugin");

const RunFn = *const fn ([*]const f32, [*]const f32, [*]const f32, [*]f32) callconv(.c) void;

const Kernel = struct {
    name: []const u8,
    run: RunFn,
};

extern fn dense4Portable([*]const f32, [*]const f32, [*]const f32, [*]f32) callconv(.c) void;
extern fn dense4Neon([*]const f32, [*]const f32, [*]const f32, [*]f32) callconv(.c) void;
extern fn dense4Avx2([*]const f32, [*]const f32, [*]const f32, [*]f32) callconv(.c) void;

fn selectKernel() Kernel {
    const features = plug.dsp.kernel_dispatch.detectNative();
    return switch (comptime builtin.cpu.arch) {
        .aarch64 => if (features.neon)
            .{ .name = "neon", .run = dense4Neon }
        else
            .{ .name = "portable", .run = dense4Portable },
        .x86_64 => if (features.avx2)
            .{ .name = "avx2", .run = dense4Avx2 }
        else
            .{ .name = "portable", .run = dense4Portable },
        else => .{ .name = "portable", .run = dense4Portable },
    };
}
```

Store both the function pointer and backend name in the processor instance. Do not run feature detection or a backend switch inside the sample loop. A distribution compiled for baseline x86-64 may include an AVX2 object as long as no AVX2 function executes before runtime detection approves it.

## Ownership and ABI rules

Use caller-owned buffers across the Zig/C boundary:

```c
void dense4(
    const float *weights,
    const float *bias,
    const float *input,
    float *output);
```

The caller allocates, sizes, and releases every buffer. The C kernel must not retain a pointer after returning. Avoid APIs that allocate in C and free in Zig, or the reverse. This keeps allocator selection out of the ABI and makes audio-thread allocation audits meaningful.

All implementation symbols must remain private to the plugin dynamic library. Use hidden visibility on ELF and Mach-O targets. On Windows, omit `__declspec(dllexport)` from kernel declarations and export only the VST3 entry points.

## Validation

The C Kernel Probe checks the integration contract with:

- identical Zig, portable C, NEON, and AVX2 fixtures;
- allocation-free block processing;
- a separately staged package consumer that links its own C source;
- macOS universal, Linux aarch64/x86-64, and Windows x86-64 bundle builds;
- export-table checks that reject public kernel symbols;
- Steinberg validator coverage in 32-bit and 64-bit sample formats.

Run the focused checks with:

```sh
zig build test-c-kernel-builds
zig build validate-c-kernel
zig build benchmark
scripts/test_installed_package.sh
```
