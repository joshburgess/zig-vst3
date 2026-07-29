const builtin = @import("builtin");
const std = @import("std");

pub const supported = builtin.zig_backend != .stage2_c and
    (builtin.cpu.arch == .aarch64 or builtin.cpu.arch == .x86_64);

const Control = switch (builtin.cpu.arch) {
    .aarch64 => u64,
    .x86_64 => u32,
    else => u8,
};

const flush_mask: Control = switch (builtin.cpu.arch) {
    .aarch64 => @as(u64, 1) << 24,
    .x86_64 => @as(u32, 1) << 15,
    else => 0,
};

/// Restore on the same thread that entered the scope. Do not copy an active scope.
pub const Scope = struct {
    previous: Control = 0,
    changed: bool = false,

    pub fn enter() Scope {
        if (!supported) return .{};
        const previous = readControl();
        const enabled = previous | flush_mask;
        if (enabled != previous) writeControl(enabled);
        return .{ .previous = previous, .changed = enabled != previous };
    }

    pub fn leave(self: *Scope) void {
        if (!self.changed) return;
        writeControl(self.previous);
        self.changed = false;
    }
};

pub fn flushToZeroEnabled() bool {
    if (!supported) return false;
    return readControl() & flush_mask == flush_mask;
}

fn readControl() Control {
    if (!supported) return 0;
    return switch (comptime builtin.cpu.arch) {
        .aarch64 => asm volatile ("mrs %[value], fpcr"
            : [value] "=r" (-> u64),
        ),
        .x86_64 => readMxcsr(),
        else => 0,
    };
}

fn writeControl(value: Control) void {
    if (!supported) return;
    switch (comptime builtin.cpu.arch) {
        .aarch64 => asm volatile ("msr fpcr, %[value]"
            :
            : [value] "r" (value),
            : .{ .fpcr = true }),
        .x86_64 => writeMxcsr(value),
        else => {},
    }
}

fn readMxcsr() u32 {
    var value: u32 = undefined;
    asm volatile ("stmxcsr %[value]"
        : [value] "=m" (value),
    );
    return value;
}

fn writeMxcsr(value: u32) void {
    const stored = value;
    asm volatile ("ldmxcsr (%%rax)"
        :
        : [address] "{rax}" (&stored),
        : .{ .memory = true, .mxcsr = true });
}

test "flush-to-zero scope restores the exact control state" {
    if (!supported) return error.SkipZigTest;
    const before = readControl();
    var scope = Scope.enter();
    defer scope.leave();
    try std.testing.expect(flushToZeroEnabled());
    scope.leave();
    try std.testing.expectEqual(before, readControl());
}

test "nested flush-to-zero scopes preserve the outer scope" {
    if (!supported) return error.SkipZigTest;
    const before = readControl();
    var outer = Scope.enter();
    defer outer.leave();
    {
        var inner = Scope.enter();
        defer inner.leave();
        try std.testing.expect(flushToZeroEnabled());
    }
    try std.testing.expect(flushToZeroEnabled());
    outer.leave();
    try std.testing.expectEqual(before, readControl());
}

test "scope flushes subnormal results without leaking its policy" {
    if (!supported) return error.SkipZigTest;
    const before = readControl();
    defer writeControl(before);
    writeControl(before & ~flush_mask);

    var minimum_normal = std.math.floatMin(f32);
    var half: f32 = 0.5;
    std.mem.doNotOptimizeAway(&minimum_normal);
    std.mem.doNotOptimizeAway(&half);
    const unflushed = minimum_normal * half;
    try std.testing.expect(unflushed != 0.0);
    try std.testing.expect(!std.math.isNormal(unflushed));

    var scope = Scope.enter();
    defer scope.leave();
    std.mem.doNotOptimizeAway(&minimum_normal);
    std.mem.doNotOptimizeAway(&half);
    try std.testing.expectEqual(@as(f32, 0.0), minimum_normal * half);
}

test "recurrent and convolution silence tails settle to zero" {
    if (!supported) return error.SkipZigTest;
    var scope = Scope.enter();
    defer scope.leave();

    var recurrent_state = std.math.floatMin(f32) * 2.0;
    var decay: f32 = 0.5;
    std.mem.doNotOptimizeAway(&recurrent_state);
    std.mem.doNotOptimizeAway(&decay);
    for (0..64) |_| recurrent_state *= decay;
    try std.testing.expectEqual(@as(f32, 0.0), recurrent_state);

    var input: [16]f32 = @splat(std.math.floatMin(f32));
    var impulse_tail: [16]f32 = @splat(0.5);
    std.mem.doNotOptimizeAway(&input);
    std.mem.doNotOptimizeAway(&impulse_tail);
    var convolution: f32 = 0.0;
    for (input, impulse_tail) |sample, tap| convolution += sample * tap;
    try std.testing.expectEqual(@as(f32, 0.0), convolution);
}
