const builtin = @import("builtin");
const plug = @import("zig-vst3-plugin");
const std = @import("std");

extern fn zig_vst3_dense4_portable(
    weights: [*]const f32,
    bias: [*]const f32,
    input: [*]const f32,
    output: [*]f32,
) callconv(.c) void;
extern fn zig_vst3_dense4_neon(weights: [*]const f32, bias: [*]const f32, input: [*]const f32, output: [*]f32) callconv(.c) void;
extern fn zig_vst3_dense4_avx2(weights: [*]const f32, bias: [*]const f32, input: [*]const f32, output: [*]f32) callconv(.c) void;

pub const Backend = enum {
    zig,
    portable_c,
    neon_c,
    avx2_c,
};

pub fn backendName(backend: Backend) []const u8 {
    return switch (backend) {
        .zig => "zig",
        .portable_c => "portable-c",
        .neon_c => "neon-c",
        .avx2_c => "avx2-c",
    };
}

pub const DenseKernel = struct {
    const RunFn = *const fn (*const [16]f32, *const [4]f32, *const [4]f32) [4]f32;

    backend: Backend,
    run_fn: RunFn,

    pub fn init(backend: Backend) error{UnsupportedBackend}!DenseKernel {
        const run_fn: RunFn = switch (backend) {
            .zig => dense4Zig,
            .portable_c => dense4Portable,
            .neon_c => if (comptime builtin.cpu.arch == .aarch64) dense4Neon else return error.UnsupportedBackend,
            .avx2_c => if (comptime builtin.cpu.arch == .x86_64) dense4Avx2 else return error.UnsupportedBackend,
        };
        return .{ .backend = backend, .run_fn = run_fn };
    }

    pub fn initNative() DenseKernel {
        const features = plug.dsp.kernel_dispatch.detectNative();
        return switch (comptime builtin.cpu.arch) {
            .aarch64 => if (features.neon)
                .{ .backend = .neon_c, .run_fn = dense4Neon }
            else
                .{ .backend = .portable_c, .run_fn = dense4Portable },
            .x86_64 => if (features.avx2)
                .{ .backend = .avx2_c, .run_fn = dense4Avx2 }
            else
                .{ .backend = .portable_c, .run_fn = dense4Portable },
            else => .{ .backend = .portable_c, .run_fn = dense4Portable },
        };
    }

    pub fn run(self: DenseKernel, weights: *const [16]f32, bias: *const [4]f32, input: *const [4]f32) [4]f32 {
        return self.run_fn(weights, bias, input);
    }

    pub fn name(self: DenseKernel) []const u8 {
        return backendName(self.backend);
    }
};

fn dense4Zig(weights: *const [16]f32, bias: *const [4]f32, input: *const [4]f32) [4]f32 {
    var output: [4]f32 = undefined;
    for (&output, 0..) |*value, row| {
        var sum = bias[row];
        for (0..4) |column| sum += weights[row * 4 + column] * input[column];
        value.* = sum;
    }
    return output;
}

fn dense4Portable(weights: *const [16]f32, bias: *const [4]f32, input: *const [4]f32) [4]f32 {
    var output: [4]f32 = undefined;
    zig_vst3_dense4_portable(weights, bias, input, &output);
    return output;
}

fn dense4Neon(weights: *const [16]f32, bias: *const [4]f32, input: *const [4]f32) [4]f32 {
    var output: [4]f32 = undefined;
    zig_vst3_dense4_neon(weights, bias, input, &output);
    return output;
}

fn dense4Avx2(weights: *const [16]f32, bias: *const [4]f32, input: *const [4]f32) [4]f32 {
    var output: [4]f32 = undefined;
    zig_vst3_dense4_avx2(weights, bias, input, &output);
    return output;
}

const identity_weights = [16]f32{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
};
const zero_bias = [4]f32{ 0, 0, 0, 0 };

pub const Processor = struct {
    pub const name = "zig-vst3 C Kernel Probe";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .mono;
    pub const event_input = false;
    pub const Params = struct {};

    kernel: DenseKernel,

    pub fn init(_: std.mem.Allocator) !Processor {
        return .{ .kernel = DenseKernel.initNative() };
    }

    pub fn process(
        self: *Processor,
        context: *plug.process.ProcessContext(f32),
    ) void {
        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        for (input, output) |sample, *destination| {
            const features = [4]f32{ sample, 0, 0, 0 };
            destination.* = self.kernel.run(&identity_weights, &zero_bias, &features)[0];
        }
    }

    pub fn process64(
        _: *Processor,
        context: *plug.process.ProcessContext(f64),
    ) void {
        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        for (input, output) |sample, *destination| {
            destination.* = sample;
        }
    }

    pub fn kernelBackendName(self: *const Processor) []const u8 {
        return self.kernel.name();
    }
};

pub const CKernelProbe = Processor;

test "portable C dense kernel matches the Zig fallback" {
    const weights = [16]f32{
        0.25,   -0.5,  0.75,   1.0,
        -1.5,   0.125, 0.5,    -0.25,
        2.0,    -0.75, 0.0625, 0.5,
        -0.125, 0.25,  -0.5,   1.25,
    };
    const bias = [4]f32{ 0.1, -0.2, 0.3, -0.4 };
    const fixtures = [_][4]f32{
        .{ 0, 0, 0, 0 },
        .{ 1, -1, 0.5, -0.25 },
        .{ -4, 2, 0.125, 8 },
    };
    for (fixtures) |input| {
        const expected = (try DenseKernel.init(.zig)).run(&weights, &bias, &input);
        const actual = (try DenseKernel.init(.portable_c)).run(&weights, &bias, &input);
        for (expected, actual) |expected_value, actual_value| {
            try std.testing.expectApproxEqAbs(expected_value, actual_value, 1.0e-6);
        }
    }
    try std.testing.expectEqualStrings("portable-c", backendName(.portable_c));
}

test "accelerated dense kernel matches identical Zig fixtures" {
    const backend: Backend = switch (builtin.cpu.arch) {
        .aarch64 => .neon_c,
        .x86_64 => if (plug.dsp.kernel_dispatch.detectNative().avx2) .avx2_c else return error.SkipZigTest,
        else => return error.SkipZigTest,
    };
    const weights = [16]f32{
        0.25,   -0.5,  0.75,   1.0,
        -1.5,   0.125, 0.5,    -0.25,
        2.0,    -0.75, 0.0625, 0.5,
        -0.125, 0.25,  -0.5,   1.25,
    };
    const bias = [4]f32{ 0.1, -0.2, 0.3, -0.4 };
    const fixtures = [_][4]f32{
        .{ 0, 0, 0, 0 },
        .{ 1, -1, 0.5, -0.25 },
        .{ -4, 2, 0.125, 8 },
    };
    const zig_kernel = try DenseKernel.init(.zig);
    const accelerated = try DenseKernel.init(backend);
    for (fixtures) |input| {
        const expected = zig_kernel.run(&weights, &bias, &input);
        const actual = accelerated.run(&weights, &bias, &input);
        for (expected, actual) |expected_value, actual_value| {
            try std.testing.expectApproxEqAbs(expected_value, actual_value, 1.0e-5);
        }
    }
    try std.testing.expectEqualStrings(backendName(backend), accelerated.name());
}

test "C kernel probe processes mono blocks without allocation" {
    var processor = try Processor.init(std.testing.allocator);
    const input = [_]f32{ 0.25, -0.5, 1.0, -1.0 };
    var output = [_]f32{0} ** input.len;
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    var context = try plug.process.ProcessContext(f32).init(48_000, &inputs, &outputs);
    const scope = plug.realtime_audit.Scope.enter();
    processor.process(&context);
    const report = scope.leave();
    try std.testing.expect(report.clean());
    try std.testing.expectEqualSlices(f32, &input, &output);
    try std.testing.expectEqualStrings(backendName(processor.kernel.backend), processor.kernelBackendName());
}

test "C kernel probe supports in-place 64-bit audio buffers" {
    var processor = try Processor.init(std.testing.allocator);
    var samples = [_]f64{ 0.25, -0.5, 1.0, -1.0 };
    const expected = samples;
    const inputs = [_][]const f64{&samples};
    const outputs = [_][]f64{&samples};
    var context = try plug.process.ProcessContext(f64).init(
        48_000,
        &inputs,
        &outputs,
    );

    processor.process64(&context);

    try std.testing.expectEqualSlices(f64, &expected, &samples);
}
