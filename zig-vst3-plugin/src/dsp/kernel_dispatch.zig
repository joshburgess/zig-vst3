const builtin = @import("builtin");
const std = @import("std");

pub const Features = struct {
    neon: bool = false,
    avx2: bool = false,
};

pub const Backend = enum {
    scalar,
    neon,
    avx2,
};

pub fn detectNative() Features {
    return switch (builtin.cpu.arch) {
        .aarch64 => .{ .neon = builtin.cpu.has(.aarch64, .neon) },
        .x86_64 => .{ .avx2 = detectX86Avx2() },
        else => .{},
    };
}

pub fn preferred(features: Features) Backend {
    if (features.avx2) return .avx2;
    if (features.neon) return .neon;
    return .scalar;
}

const CpuidLeaf = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

fn detectX86Avx2() bool {
    if (builtin.cpu.arch != .x86_64 or builtin.zig_backend == .stage2_c) return false;
    if (cpuid(0, 0).eax < 7) return false;
    const leaf1 = cpuid(1, 0);
    const osxsave = leaf1.ecx & (@as(u32, 1) << 27) != 0;
    const avx = leaf1.ecx & (@as(u32, 1) << 28) != 0;
    if (!osxsave or !avx or xcr0() & 0x6 != 0x6) return false;
    return cpuid(7, 0).ebx & (@as(u32, 1) << 5) != 0;
}

fn cpuid(leaf_id: u32, sub_id: u32) CpuidLeaf {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [_] "={eax}" (eax),
          [_] "={ebx}" (ebx),
          [_] "={ecx}" (ecx),
          [_] "={edx}" (edx),
        : [_] "{eax}" (leaf_id),
          [_] "{ecx}" (sub_id),
    );
    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

fn xcr0() u32 {
    return asm volatile (
        \\ xor %%ecx, %%ecx
        \\ xgetbv
        : [_] "={eax}" (-> u32),
        :
        : .{ .edx = true, .ecx = true });
}

test "kernel dispatch selects the strongest available backend" {
    try std.testing.expectEqual(Backend.scalar, preferred(.{}));
    try std.testing.expectEqual(Backend.neon, preferred(.{ .neon = true }));
    try std.testing.expectEqual(Backend.avx2, preferred(.{ .neon = true, .avx2 = true }));
}

test "native kernel features agree with the compiled architecture" {
    const features = detectNative();
    switch (builtin.cpu.arch) {
        .aarch64 => try std.testing.expectEqual(builtin.cpu.has(.aarch64, .neon), features.neon),
        .x86_64 => try std.testing.expect(!features.neon),
        else => try std.testing.expectEqual(Features{}, features),
    }
}
