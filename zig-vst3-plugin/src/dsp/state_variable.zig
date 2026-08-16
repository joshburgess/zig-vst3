const std = @import("std");
const buffer_regions = @import("buffer_regions.zig");

pub const Kind = enum {
    low_pass,
    band_pass,
    high_pass,
    notch,
    all_pass,
};

pub const Config = struct {
    kind: Kind,
    sample_rate: f64,
    frequency_hz: f64,
    q: f64 = 1.0 / @sqrt(2.0),
};

pub fn StateVariableFilter(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("StateVariableFilter supports f32 and f64 samples");

    return struct {
        const Self = @This();

        config: Config,
        g: Sample,
        k: Sample,
        a1: Sample,
        a2: Sample,
        a3: Sample,
        ic1: Sample = 0.0,
        ic2: Sample = 0.0,

        pub fn init(config: Config) !Self {
            const coefficients = try calculate(Sample, config);
            return .{
                .config = config,
                .g = coefficients.g,
                .k = coefficients.k,
                .a1 = coefficients.a1,
                .a2 = coefficients.a2,
                .a3 = coefficients.a3,
            };
        }

        pub fn configure(self: *Self, config: Config) !void {
            const coefficients = try calculate(Sample, config);
            self.config = config;
            self.g = coefficients.g;
            self.k = coefficients.k;
            self.a1 = coefficients.a1;
            self.a2 = coefficients.a2;
            self.a3 = coefficients.a3;
        }

        pub fn reset(self: *Self) void {
            self.ic1 = 0.0;
            self.ic2 = 0.0;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const accepted = if (std.math.isFinite(input)) input else 0.0;
            if (!self.processingValid()) {
                self.reset();
                return accepted;
            }

            const v3 = accepted - self.ic2;
            const band = self.a1 * self.ic1 + self.a2 * v3;
            const low = self.ic2 + self.a2 * self.ic1 + self.a3 * v3;
            self.ic1 = 2.0 * band - self.ic1;
            self.ic2 = 2.0 * low - self.ic2;
            const high = accepted - self.k * band - low;
            const output = switch (self.config.kind) {
                .low_pass => low,
                .band_pass => band,
                .high_pass => high,
                .notch => low + high,
                .all_pass => low + high - self.k * band,
            };
            if (!std.math.isFinite(output) or
                !std.math.isFinite(self.ic1) or
                !std.math.isFinite(self.ic2))
            {
                self.reset();
                return 0.0;
            }
            return output;
        }

        pub fn process(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len)
                return error.StateVariableBufferLengthMismatch;
            if (!buffer_regions.exactOrDisjoint(Sample, input, output))
                return error.StateVariableBufferOverlap;
            for (input, output) |input_sample, *output_sample|
                output_sample.* = self.processSample(input_sample);
        }

        pub fn valid(self: *const Self) bool {
            const coefficients = calculate(Sample, self.config) catch
                return false;
            return self.g == coefficients.g and
                self.k == coefficients.k and
                self.a1 == coefficients.a1 and
                self.a2 == coefficients.a2 and
                self.a3 == coefficients.a3 and
                std.math.isFinite(self.ic1) and
                std.math.isFinite(self.ic2);
        }

        fn processingValid(self: *const Self) bool {
            validateConfig(self.config) catch return false;
            return std.math.isFinite(self.g) and
                self.g > 0.0 and
                std.math.isFinite(self.k) and
                self.k > 0.0 and
                std.math.isFinite(self.a1) and
                std.math.isFinite(self.a2) and
                std.math.isFinite(self.a3) and
                std.math.isFinite(self.ic1) and
                std.math.isFinite(self.ic2);
        }
    };
}

fn Coefficients(comptime Sample: type) type {
    return struct {
        g: Sample,
        k: Sample,
        a1: Sample,
        a2: Sample,
        a3: Sample,
    };
}

fn calculate(comptime Sample: type, config: Config) !Coefficients(Sample) {
    try validateConfig(config);
    const g64 = @tan(std.math.pi * config.frequency_hz / config.sample_rate);
    const k64 = 1.0 / config.q;
    const a1_64 = 1.0 / (1.0 + g64 * (g64 + k64));
    const a2_64 = g64 * a1_64;
    const result = Coefficients(Sample){
        .g = @floatCast(g64),
        .k = @floatCast(k64),
        .a1 = @floatCast(a1_64),
        .a2 = @floatCast(a2_64),
        .a3 = @floatCast(g64 * a2_64),
    };
    if (!std.math.isFinite(result.g) or
        !std.math.isFinite(result.k) or
        !std.math.isFinite(result.a1) or
        !std.math.isFinite(result.a2) or
        !std.math.isFinite(result.a3))
        return error.InvalidStateVariableConfig;
    return result;
}

fn validateConfig(config: Config) !void {
    if (!std.math.isFinite(config.sample_rate) or
        config.sample_rate < 1_000.0 or
        config.sample_rate > 768_000.0 or
        !std.math.isFinite(config.frequency_hz) or
        config.frequency_hz < 1.0 or
        config.frequency_hz >= config.sample_rate * 0.49 or
        !std.math.isFinite(config.q) or
        config.q < 0.1 or
        config.q > 100.0)
        return error.InvalidStateVariableConfig;
}

test "state-variable pass outputs separate low and high frequencies" {
    var low = try StateVariableFilter(f64).init(.{
        .kind = .low_pass,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    var high = try StateVariableFilter(f64).init(.{
        .kind = .high_pass,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    var low_frequency_energy: f64 = 0.0;
    var low_frequency_high_energy: f64 = 0.0;
    var high_frequency_energy: f64 = 0.0;
    var high_frequency_low_energy: f64 = 0.0;
    for (0..2_048) |index| {
        const phase: f64 = @floatFromInt(index);
        const input = @sin(std.math.tau * 100.0 * phase / 48_000.0);
        const low_output = low.processSample(input);
        const high_output = high.processSample(input);
        if (index >= 1_024) {
            low_frequency_energy += low_output * low_output;
            low_frequency_high_energy += high_output * high_output;
        }
    }
    low.reset();
    high.reset();
    for (0..2_048) |index| {
        const phase: f64 = @floatFromInt(index);
        const input = @sin(std.math.tau * 10_000.0 * phase / 48_000.0);
        const low_output = low.processSample(input);
        const high_output = high.processSample(input);
        if (index >= 1_024) {
            high_frequency_low_energy += low_output * low_output;
            high_frequency_energy += high_output * high_output;
        }
    }
    try std.testing.expect(low_frequency_energy >
        low_frequency_high_energy * 20.0);
    try std.testing.expect(high_frequency_energy >
        high_frequency_low_energy * 20.0);
}

test "state-variable processing is independent of block partitioning" {
    const Filter = StateVariableFilter(f32);
    const config = Config{
        .kind = .notch,
        .sample_rate = 48_000.0,
        .frequency_hz = 2_000.0,
        .q = 2.0,
    };
    var input: [128]f32 = undefined;
    for (&input, 0..) |*sample, index|
        sample.* = @sin(
            std.math.tau *
                440.0 *
                @as(f32, @floatFromInt(index)) /
                48_000.0,
        );
    var whole = try Filter.init(config);
    var whole_output: [128]f32 = undefined;
    try whole.process(&input, &whole_output);

    var split = try Filter.init(config);
    var split_output: [128]f32 = undefined;
    try split.process(input[0..43], split_output[0..43]);
    try split.process(input[43..], split_output[43..]);
    try std.testing.expectEqualSlices(f32, &whole_output, &split_output);
}

test "state-variable configuration is transactional and hostile state resets" {
    var filter = try StateVariableFilter(f32).init(.{
        .kind = .band_pass,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    const original = filter.config;
    try std.testing.expectError(
        error.InvalidStateVariableConfig,
        filter.configure(.{
            .kind = .band_pass,
            .sample_rate = 48_000.0,
            .frequency_hz = 30_000.0,
        }),
    );
    try std.testing.expectEqual(original, filter.config);
    filter.ic1 = std.math.nan(f32);
    try std.testing.expectEqual(@as(f32, 0.25), filter.processSample(0.25));
    try std.testing.expect(filter.valid());
}

test "state-variable permits in-place buffers and rejects shifted overlap" {
    const config = Config{
        .kind = .low_pass,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    };
    var storage = [_]f32{ 1.0, 0.5, 0.25, 0.0 };
    var shifted = try StateVariableFilter(f32).init(config);
    const before = shifted;
    const storage_before = storage;
    try std.testing.expectError(
        error.StateVariableBufferOverlap,
        shifted.process(storage[0..3], storage[1..4]),
    );
    try std.testing.expectEqualDeep(before, shifted);
    try std.testing.expectEqualDeep(storage_before, storage);

    var in_place = try StateVariableFilter(f32).init(config);
    try in_place.process(&storage, &storage);
    for (storage) |sample| try std.testing.expect(std.math.isFinite(sample));
}
