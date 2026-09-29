const std = @import("std");
const fir_design = @import("fir_design.zig");
const window = @import("window.zig");

pub fn Bank(
    comptime Sample: type,
    comptime phase_count: usize,
    comptime taps_per_phase: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("polyphase FIR banks support f32 and f64 samples");
    if (phase_count == 0 or taps_per_phase == 0)
        @compileError("polyphase FIR dimensions must be nonzero");

    const capacity = phase_count * taps_per_phase;
    const Designer = fir_design.Designer(Sample);

    return struct {
        const Self = @This();

        coefficients: [phase_count][taps_per_phase]Sample =
            @splat(@splat(0.0)),
        prototype_length: usize = 0,

        pub fn init(prototype: []const Sample) !Self {
            var bank: Self = .{};
            try bank.configure(prototype);
            return bank;
        }

        pub fn lowPass(
            prototype_length: usize,
            cutoff: Sample,
            window_kind: window.Kind,
        ) !Self {
            if (prototype_length > capacity)
                return error.PolyphaseFirCapacityExceeded;
            var prototype: [capacity]Sample = undefined;
            try Designer.lowPass(
                prototype[0..prototype_length],
                cutoff,
                window_kind,
            );
            return init(prototype[0..prototype_length]);
        }

        pub fn configure(
            self: *Self,
            prototype: []const Sample,
        ) !void {
            if (prototype.len == 0 or prototype.len > capacity)
                return error.PolyphaseFirCapacityExceeded;
            for (prototype) |coefficient| {
                if (!std.math.isFinite(coefficient))
                    return error.InvalidPolyphaseFirCoefficient;
            }

            var replacement: Self = .{
                .prototype_length = prototype.len,
            };
            for (prototype, 0..) |coefficient, index| {
                const phase_index = index % phase_count;
                const tap = index / phase_count;
                replacement.coefficients[phase_index][tap] = coefficient;
            }
            self.* = replacement;
        }

        pub fn reset(self: *Self) void {
            self.* = .{};
        }

        pub fn phase(self: *const Self, index: usize) ![]const Sample {
            if (!self.valid() or index >= phase_count)
                return error.InvalidPolyphaseFirPhase;
            return self.coefficients[index][0..self.activeTaps(index)];
        }

        pub fn processPhase(
            self: *const Self,
            phase_index: usize,
            newest_first_history: []const Sample,
        ) !Sample {
            const coefficients = try self.phase(phase_index);
            if (newest_first_history.len < coefficients.len)
                return error.PolyphaseFirHistoryTooShort;
            var output: Sample = 0.0;
            for (
                coefficients,
                newest_first_history[0..coefficients.len],
            ) |coefficient, sample| {
                if (!std.math.isFinite(sample))
                    return error.InvalidPolyphaseFirInput;
                output += coefficient * sample;
                if (!std.math.isFinite(output))
                    return error.InvalidPolyphaseFirOutput;
            }
            return output;
        }

        pub fn writePrototype(
            self: *const Self,
            output: []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidPolyphaseFirState;
            if (output.len < self.prototype_length)
                return error.PolyphaseFirOutputTooShort;
            for (0..self.prototype_length) |index| {
                output[index] = self.coefficients[index % phase_count][index / phase_count];
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.prototype_length > capacity) return false;
            for (self.coefficients, 0..) |phase_coefficients, phase_index| {
                for (phase_coefficients, 0..) |coefficient, tap| {
                    if (!std.math.isFinite(coefficient)) return false;
                    const prototype_index = tap * phase_count + phase_index;
                    if (prototype_index >= self.prototype_length and
                        coefficient != 0.0)
                        return false;
                }
            }
            return true;
        }

        fn activeTaps(self: *const Self, phase_index: usize) usize {
            if (phase_index >= self.prototype_length) return 0;
            return (self.prototype_length - 1 - phase_index) /
                phase_count + 1;
        }
    };
}

test "polyphase FIR bank round trips its prototype" {
    const Polyphase = Bank(f64, 3, 4);
    const prototype = [_]f64{
        0.01, 0.02, 0.03,
        0.04, 0.05, 0.06,
        0.07, 0.08,
    };
    const bank = try Polyphase.init(&prototype);
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.01, 0.04, 0.07 },
        try bank.phase(0),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.03, 0.06 },
        try bank.phase(2),
    );
    var reconstructed: [prototype.len]f64 = undefined;
    try bank.writePrototype(&reconstructed);
    try std.testing.expectEqualSlices(f64, &prototype, &reconstructed);
}

test "polyphase FIR phase processing matches direct dot products" {
    const Polyphase = Bank(f32, 2, 3);
    const bank = try Polyphase.init(&.{ 1.0, 2.0, 3.0, 4.0, 5.0 });
    const history = [_]f32{ 0.5, 0.25, 0.125 };
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.875),
        try bank.processPhase(0, &history),
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 2.0),
        try bank.processPhase(1, &history),
        0.000_001,
    );
}

test "polyphase FIR interpolation matches SciPy 1.17 upfirdn" {
    const Polyphase = Bank(f64, 3, 3);
    const bank = try Polyphase.init(
        &.{ 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7 },
    );
    const expected = [_]f64{
        0.1,
        0.2,
        0.3,
        0.35,
        0.4,
        0.45,
        0.525,
        -0.2,
        -0.225,
        -0.05,
        0.525,
        0.75,
        0.975,
        1.0,
        1.2,
        1.4,
    };
    var history = [_]f64{ 0.0, 0.0, 0.0 };
    var output: [expected.len]f64 = undefined;
    var output_index: usize = 0;
    for ([_]f64{ 1.0, -0.5, 0.25, 2.0 }) |sample| {
        std.mem.copyBackwards(
            f64,
            history[1..],
            history[0 .. history.len - 1],
        );
        history[0] = sample;
        for (0..3) |phase_index| {
            output[output_index] =
                try bank.processPhase(phase_index, &history);
            output_index += 1;
        }
    }
    while (output_index < output.len) {
        std.mem.copyBackwards(
            f64,
            history[1..],
            history[0 .. history.len - 1],
        );
        history[0] = 0.0;
        for (0..3) |phase_index| {
            if (output_index == output.len) break;
            output[output_index] =
                try bank.processPhase(phase_index, &history);
            output_index += 1;
        }
    }
    for (output, expected) |actual, reference| {
        try std.testing.expectApproxEqAbs(reference, actual, 1.0e-14);
    }
}

test "polyphase FIR low-pass design reconstructs a normalized prototype" {
    const Polyphase = Bank(f64, 4, 16);
    const bank = try Polyphase.lowPass(63, 0.125, .blackman);
    var prototype: [63]f64 = undefined;
    try bank.writePrototype(&prototype);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        fir_design.Designer(f64).magnitude(&prototype, 0.0),
        0.000_000_000_001,
    );
    try std.testing.expect(
        fir_design.Designer(f64).magnitude(&prototype, 0.4) < 0.001,
    );
}

test "polyphase FIR reconfiguration is transactional" {
    const Polyphase = Bank(f32, 2, 2);
    var bank = try Polyphase.init(&.{ 0.25, 0.5, 0.25 });
    const before = bank;
    try std.testing.expectError(
        error.InvalidPolyphaseFirCoefficient,
        bank.configure(&.{ 0.5, std.math.nan(f32) }),
    );
    try std.testing.expectEqualDeep(before, bank);
    try std.testing.expectError(
        error.PolyphaseFirHistoryTooShort,
        bank.processPhase(0, &.{}),
    );
    try std.testing.expectError(
        error.InvalidPolyphaseFirPhase,
        bank.phase(2),
    );
}
