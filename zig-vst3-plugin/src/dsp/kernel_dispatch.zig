const builtin = @import("builtin");
const std = @import("std");
const fast_math = @import("fast_math.zig");

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

pub const Dispatcher = struct {
    backend: Backend,

    pub fn initDetected() Dispatcher {
        return .{ .backend = preferred(detectNative()) };
    }

    pub fn init(features: Features) Dispatcher {
        return .{ .backend = preferred(features) };
    }

    pub fn laneCount(self: Dispatcher, comptime Sample: type) usize {
        if (Sample != f32 and Sample != f64)
            @compileError("kernel dispatch supports f32 and f64 samples");
        const vector_bytes: usize = switch (self.backend) {
            .scalar => @sizeOf(Sample),
            .neon => 16,
            .avx2 => 32,
        };
        return vector_bytes / @sizeOf(Sample);
    }

    pub fn processGain(
        self: Dispatcher,
        comptime Sample: type,
        samples: []Sample,
        gain: Sample,
    ) !void {
        if (!std.math.isFinite(gain))
            return error.InvalidDispatchedGain;
        for (samples) |sample| {
            const output = sample * gain;
            if (!std.math.isFinite(sample) or !std.math.isFinite(output))
                return error.InvalidDispatchedGain;
        }
        switch (self.backend) {
            .scalar => processGainScalar(Sample, samples, gain),
            .neon => processGainVector(
                Sample,
                16 / @sizeOf(Sample),
                samples,
                gain,
            ),
            .avx2 => processGainVector(
                Sample,
                32 / @sizeOf(Sample),
                samples,
                gain,
            ),
        }
    }

    pub fn processAffine(
        self: Dispatcher,
        comptime Sample: type,
        samples: []Sample,
        multiplier: Sample,
        addend: Sample,
    ) !void {
        if (!std.math.isFinite(multiplier) or !std.math.isFinite(addend))
            return error.InvalidDispatchedAffine;
        for (samples) |sample| {
            const output = sample * multiplier + addend;
            if (!std.math.isFinite(sample) or !std.math.isFinite(output))
                return error.InvalidDispatchedAffine;
        }
        switch (self.backend) {
            .scalar => processAffineScalar(
                Sample,
                samples,
                multiplier,
                addend,
            ),
            .neon => processAffineVector(
                Sample,
                16 / @sizeOf(Sample),
                samples,
                multiplier,
                addend,
            ),
            .avx2 => processAffineVector(
                Sample,
                32 / @sizeOf(Sample),
                samples,
                multiplier,
                addend,
            ),
        }
    }

    pub fn applyFastMath(
        self: Dispatcher,
        comptime Sample: type,
        operation: fast_math.Operation,
        samples: []Sample,
    ) !void {
        const FastMath = fast_math.Approximations(Sample);
        switch (self.backend) {
            .scalar => try FastMath.apply(operation, samples),
            .neon => try FastMath.applyVector(
                operation,
                samples,
                16 / @sizeOf(Sample),
            ),
            .avx2 => try FastMath.applyVector(
                operation,
                samples,
                32 / @sizeOf(Sample),
            ),
        }
    }

    pub fn copyBuffer(
        self: Dispatcher,
        comptime Sample: type,
        destination: []Sample,
        source: []const Sample,
    ) !void {
        if (destination.len != source.len)
            return error.InvalidDispatchedCopyShape;
        if (slicesOverlap(Sample, destination, source) and
            !sameSlice(destination, source))
            return error.DispatchedCopyBuffersOverlap;
        for (source) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidDispatchedCopy;
        }
        if (sameSlice(destination, source)) return;
        switch (self.backend) {
            .scalar => processCopyScalar(Sample, destination, source),
            .neon => processCopyVector(
                Sample,
                16 / @sizeOf(Sample),
                destination,
                source,
            ),
            .avx2 => processCopyVector(
                Sample,
                32 / @sizeOf(Sample),
                destination,
                source,
            ),
        }
    }

    pub fn addBuffer(
        self: Dispatcher,
        comptime Sample: type,
        destination: []Sample,
        source: []const Sample,
    ) !void {
        if (destination.len != source.len)
            return error.InvalidDispatchedAddShape;
        if (slicesOverlap(Sample, destination, source) and
            !sameSlice(destination, source))
            return error.DispatchedAddBuffersOverlap;
        for (destination, source) |left, right| {
            const output = left + right;
            if (!std.math.isFinite(left) or
                !std.math.isFinite(right) or
                !std.math.isFinite(output))
                return error.InvalidDispatchedAdd;
        }
        switch (self.backend) {
            .scalar => processAddScalar(Sample, destination, source),
            .neon => processAddVector(
                Sample,
                16 / @sizeOf(Sample),
                destination,
                source,
            ),
            .avx2 => processAddVector(
                Sample,
                32 / @sizeOf(Sample),
                destination,
                source,
            ),
        }
    }

    pub fn multiplyBuffer(
        self: Dispatcher,
        comptime Sample: type,
        destination: []Sample,
        source: []const Sample,
    ) !void {
        if (destination.len != source.len)
            return error.InvalidDispatchedMultiplyShape;
        if (slicesOverlap(Sample, destination, source) and
            !sameSlice(destination, source))
            return error.DispatchedMultiplyBuffersOverlap;
        for (destination, source) |left, right| {
            const output = left * right;
            if (!std.math.isFinite(left) or
                !std.math.isFinite(right) or
                !std.math.isFinite(output))
                return error.InvalidDispatchedMultiply;
        }
        switch (self.backend) {
            .scalar => processMultiplyScalar(Sample, destination, source),
            .neon => processMultiplyVector(
                Sample,
                16 / @sizeOf(Sample),
                destination,
                source,
            ),
            .avx2 => processMultiplyVector(
                Sample,
                32 / @sizeOf(Sample),
                destination,
                source,
            ),
        }
    }

    pub fn multiplyComplexBuffer(
        self: Dispatcher,
        comptime Sample: type,
        real: []Sample,
        imaginary: []Sample,
        multiplier_real: []const Sample,
        multiplier_imaginary: []const Sample,
    ) !void {
        if (Sample != f32 and Sample != f64)
            @compileError("complex kernel dispatch supports f32 and f64 samples");
        if (real.len != imaginary.len or
            real.len != multiplier_real.len or
            real.len != multiplier_imaginary.len)
            return error.InvalidDispatchedComplexShape;
        if (slicesOverlap(Sample, real, imaginary) or
            (slicesOverlap(Sample, real, multiplier_real) and
                !sameSlice(real, multiplier_real)) or
            slicesOverlap(Sample, real, multiplier_imaginary) or
            slicesOverlap(Sample, imaginary, multiplier_real) or
            (slicesOverlap(Sample, imaginary, multiplier_imaginary) and
                !sameSlice(imaginary, multiplier_imaginary)))
            return error.DispatchedComplexBuffersOverlap;
        for (
            real,
            imaginary,
            multiplier_real,
            multiplier_imaginary,
        ) |left_real, left_imaginary, right_real, right_imaginary| {
            const ac = left_real * right_real;
            const bd = left_imaginary * right_imaginary;
            const ad = left_real * right_imaginary;
            const bc = left_imaginary * right_real;
            if (!std.math.isFinite(left_real) or
                !std.math.isFinite(left_imaginary) or
                !std.math.isFinite(right_real) or
                !std.math.isFinite(right_imaginary) or
                !std.math.isFinite(ac) or
                !std.math.isFinite(bd) or
                !std.math.isFinite(ad) or
                !std.math.isFinite(bc) or
                !std.math.isFinite(ac - bd) or
                !std.math.isFinite(ad + bc))
                return error.InvalidDispatchedComplexMultiply;
        }
        switch (self.backend) {
            .scalar => processComplexMultiplyScalar(
                Sample,
                real,
                imaginary,
                multiplier_real,
                multiplier_imaginary,
            ),
            .neon => processComplexMultiplyVector(
                Sample,
                16 / @sizeOf(Sample),
                real,
                imaginary,
                multiplier_real,
                multiplier_imaginary,
            ),
            .avx2 => processComplexMultiplyVector(
                Sample,
                32 / @sizeOf(Sample),
                real,
                imaginary,
                multiplier_real,
                multiplier_imaginary,
            ),
        }
    }

    pub fn sum(
        self: Dispatcher,
        comptime Sample: type,
        samples: []const Sample,
    ) !Sample {
        for (samples) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidDispatchedReduction;
        }
        const result = switch (self.backend) {
            .scalar => reduceSumScalar(Sample, samples),
            .neon => reduceSumVector(
                Sample,
                16 / @sizeOf(Sample),
                samples,
            ),
            .avx2 => reduceSumVector(
                Sample,
                32 / @sizeOf(Sample),
                samples,
            ),
        };
        if (!std.math.isFinite(result))
            return error.InvalidDispatchedReduction;
        return result;
    }

    pub fn innerProduct(
        self: Dispatcher,
        comptime Sample: type,
        left: []const Sample,
        right: []const Sample,
    ) !Sample {
        if (left.len != right.len)
            return error.InvalidDispatchedReductionShape;
        for (left, right) |left_sample, right_sample| {
            if (!std.math.isFinite(left_sample) or
                !std.math.isFinite(right_sample) or
                !std.math.isFinite(left_sample * right_sample))
                return error.InvalidDispatchedReduction;
        }
        const result = switch (self.backend) {
            .scalar => reduceInnerProductScalar(Sample, left, right),
            .neon => reduceInnerProductVector(
                Sample,
                16 / @sizeOf(Sample),
                left,
                right,
            ),
            .avx2 => reduceInnerProductVector(
                Sample,
                32 / @sizeOf(Sample),
                left,
                right,
            ),
        };
        if (!std.math.isFinite(result))
            return error.InvalidDispatchedReduction;
        return result;
    }

    pub fn peakAbsolute(
        self: Dispatcher,
        comptime Sample: type,
        samples: []const Sample,
    ) !Sample {
        for (samples) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidDispatchedReduction;
        }
        return switch (self.backend) {
            .scalar => reducePeakAbsoluteScalar(Sample, samples),
            .neon => reducePeakAbsoluteVector(
                Sample,
                16 / @sizeOf(Sample),
                samples,
            ),
            .avx2 => reducePeakAbsoluteVector(
                Sample,
                32 / @sizeOf(Sample),
                samples,
            ),
        };
    }

    pub fn minimum(
        self: Dispatcher,
        comptime Sample: type,
        samples: []const Sample,
    ) !Sample {
        if (samples.len == 0)
            return error.DispatchedReductionRequiresSamples;
        for (samples) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidDispatchedReduction;
        }
        return switch (self.backend) {
            .scalar => reduceMinimumScalar(Sample, samples),
            .neon => reduceMinimumVector(
                Sample,
                16 / @sizeOf(Sample),
                samples,
            ),
            .avx2 => reduceMinimumVector(
                Sample,
                32 / @sizeOf(Sample),
                samples,
            ),
        };
    }

    pub fn maximum(
        self: Dispatcher,
        comptime Sample: type,
        samples: []const Sample,
    ) !Sample {
        if (samples.len == 0)
            return error.DispatchedReductionRequiresSamples;
        for (samples) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidDispatchedReduction;
        }
        return switch (self.backend) {
            .scalar => reduceMaximumScalar(Sample, samples),
            .neon => reduceMaximumVector(
                Sample,
                16 / @sizeOf(Sample),
                samples,
            ),
            .avx2 => reduceMaximumVector(
                Sample,
                32 / @sizeOf(Sample),
                samples,
            ),
        };
    }

    pub fn sumSquares(
        self: Dispatcher,
        comptime Sample: type,
        samples: []const Sample,
    ) !Sample {
        for (samples) |sample| {
            if (!std.math.isFinite(sample) or
                !std.math.isFinite(sample * sample))
                return error.InvalidDispatchedReduction;
        }
        const result = switch (self.backend) {
            .scalar => reduceSumSquaresScalar(Sample, samples),
            .neon => reduceSumSquaresVector(
                Sample,
                16 / @sizeOf(Sample),
                samples,
            ),
            .avx2 => reduceSumSquaresVector(
                Sample,
                32 / @sizeOf(Sample),
                samples,
            ),
        };
        if (!std.math.isFinite(result))
            return error.InvalidDispatchedReduction;
        return result;
    }

    pub fn rootMeanSquare(
        self: Dispatcher,
        comptime Sample: type,
        samples: []const Sample,
    ) !Sample {
        if (samples.len == 0) return 0;
        const scale = try self.peakAbsolute(Sample, samples);
        if (scale == 0) return 0;
        const normalized_energy = switch (self.backend) {
            .scalar => reduceScaledSumSquaresScalar(
                Sample,
                samples,
                scale,
            ),
            .neon => reduceScaledSumSquaresVector(
                Sample,
                16 / @sizeOf(Sample),
                samples,
                scale,
            ),
            .avx2 => reduceScaledSumSquaresVector(
                Sample,
                32 / @sizeOf(Sample),
                samples,
                scale,
            ),
        };
        const mean = normalized_energy /
            @as(Sample, @floatFromInt(samples.len));
        const result = scale * @sqrt(mean);
        if (!std.math.isFinite(result))
            return error.InvalidDispatchedReduction;
        return result;
    }

    pub fn mixBuffers(
        self: Dispatcher,
        comptime Sample: type,
        destination: []Sample,
        left: []const Sample,
        right: []const Sample,
        left_gain: Sample,
        right_gain: Sample,
    ) !void {
        if (destination.len != left.len or destination.len != right.len)
            return error.InvalidDispatchedMixShape;
        if ((slicesOverlap(Sample, destination, left) and
            !sameSlice(destination, left)) or
            (slicesOverlap(Sample, destination, right) and
                !sameSlice(destination, right)))
            return error.DispatchedMixBuffersOverlap;
        if (!std.math.isFinite(left_gain) or
            !std.math.isFinite(right_gain))
            return error.InvalidDispatchedMix;
        for (left, right) |left_sample, right_sample| {
            const output =
                left_sample * left_gain + right_sample * right_gain;
            if (!std.math.isFinite(left_sample) or
                !std.math.isFinite(right_sample) or
                !std.math.isFinite(output))
                return error.InvalidDispatchedMix;
        }
        switch (self.backend) {
            .scalar => processMixScalar(
                Sample,
                destination,
                left,
                right,
                left_gain,
                right_gain,
            ),
            .neon => processMixVector(
                Sample,
                16 / @sizeOf(Sample),
                destination,
                left,
                right,
                left_gain,
                right_gain,
            ),
            .avx2 => processMixVector(
                Sample,
                32 / @sizeOf(Sample),
                destination,
                left,
                right,
                left_gain,
                right_gain,
            ),
        }
    }

    pub fn interleaveStereo(
        self: Dispatcher,
        comptime Sample: type,
        destination: []Sample,
        left: []const Sample,
        right: []const Sample,
    ) !void {
        if (destination.len % 2 != 0 or
            left.len != right.len or
            left.len != destination.len / 2)
            return error.InvalidDispatchedStereoShape;
        if (slicesOverlap(Sample, destination, left) or
            slicesOverlap(Sample, destination, right))
            return error.DispatchedStereoBuffersOverlap;
        for (left, right) |left_sample, right_sample| {
            if (!std.math.isFinite(left_sample) or
                !std.math.isFinite(right_sample))
                return error.InvalidDispatchedStereoSample;
        }
        processInterleaveBlocked(
            Sample,
            self.laneCount(Sample),
            destination,
            left,
            right,
        );
    }

    pub fn deinterleaveStereo(
        self: Dispatcher,
        comptime Sample: type,
        left: []Sample,
        right: []Sample,
        source: []const Sample,
    ) !void {
        if (source.len % 2 != 0 or
            left.len != source.len / 2 or
            right.len != source.len / 2)
            return error.InvalidDispatchedStereoShape;
        if (slicesOverlap(Sample, left, right) or
            slicesOverlap(Sample, left, source) or
            slicesOverlap(Sample, right, source))
            return error.DispatchedStereoBuffersOverlap;
        for (source) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidDispatchedStereoSample;
        }
        processDeinterleaveBlocked(
            Sample,
            self.laneCount(Sample),
            left,
            right,
            source,
        );
    }
};

pub fn BufferProcessorDispatcher(
    comptime Sample: type,
    comptime Context: type,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("processor dispatch supports f32 and f64 samples");

    return struct {
        const Self = @This();

        pub const ProcessFn = *const fn (
            context: *Context,
            destination: []Sample,
            source: []const Sample,
        ) void;

        pub const Implementations = struct {
            scalar: ProcessFn,
            neon: ?ProcessFn = null,
            avx2: ?ProcessFn = null,
        };

        backend: Backend,
        process_fn: ProcessFn,

        pub fn initDetected(
            implementations: Implementations,
        ) Self {
            return init(detectNative(), implementations);
        }

        pub fn init(
            features: Features,
            implementations: Implementations,
        ) Self {
            if (features.avx2) {
                if (implementations.avx2) |process_fn|
                    return .{ .backend = .avx2, .process_fn = process_fn };
            }
            if (features.neon) {
                if (implementations.neon) |process_fn|
                    return .{ .backend = .neon, .process_fn = process_fn };
            }
            return .{
                .backend = .scalar,
                .process_fn = implementations.scalar,
            };
        }

        pub fn initBackend(
            backend: Backend,
            implementations: Implementations,
        ) !Self {
            const process_fn = switch (backend) {
                .scalar => implementations.scalar,
                .neon => implementations.neon orelse
                    return error.ProcessorBackendUnavailable,
                .avx2 => implementations.avx2 orelse
                    return error.ProcessorBackendUnavailable,
            };
            return .{ .backend = backend, .process_fn = process_fn };
        }

        pub fn laneCount(self: Self) usize {
            return (Dispatcher{ .backend = self.backend })
                .laneCount(Sample);
        }

        /// Invoke a backend that accepts arbitrary alignment, scalar tails, and exact in-place buffers.
        pub fn process(
            self: Self,
            context: *Context,
            destination: []Sample,
            source: []const Sample,
        ) !void {
            if (destination.len != source.len)
                return error.InvalidProcessorDispatchShape;
            if (slicesOverlap(Sample, destination, source) and
                !sameSlice(destination, source))
                return error.ProcessorDispatchBuffersOverlap;
            self.process_fn(context, destination, source);
        }

        pub fn processReplacing(
            self: Self,
            context: *Context,
            samples: []Sample,
        ) void {
            self.process_fn(context, samples, samples);
        }
    };
}

fn processGainScalar(
    comptime Sample: type,
    samples: []Sample,
    gain: Sample,
) void {
    for (samples) |*sample| sample.* *= gain;
}

fn processGainVector(
    comptime Sample: type,
    comptime lane_count: usize,
    samples: []Sample,
    gain: Sample,
) void {
    const Vector = @Vector(lane_count, Sample);
    const multiplier: Vector = @splat(gain);
    var offset: usize = 0;
    while (offset + lane_count <= samples.len) : (offset += lane_count) {
        const input = loadVector(Sample, lane_count, samples[offset..]);
        storeVector(
            Sample,
            lane_count,
            samples[offset..],
            input * multiplier,
        );
    }
    processGainScalar(Sample, samples[offset..], gain);
}

fn processAffineScalar(
    comptime Sample: type,
    samples: []Sample,
    multiplier: Sample,
    addend: Sample,
) void {
    for (samples) |*sample|
        sample.* = sample.* * multiplier + addend;
}

fn processAffineVector(
    comptime Sample: type,
    comptime lane_count: usize,
    samples: []Sample,
    multiplier: Sample,
    addend: Sample,
) void {
    const Vector = @Vector(lane_count, Sample);
    const multiplier_register: Vector = @splat(multiplier);
    const addend_register: Vector = @splat(addend);
    var offset: usize = 0;
    while (offset + lane_count <= samples.len) : (offset += lane_count) {
        const input = loadVector(Sample, lane_count, samples[offset..]);
        storeVector(
            Sample,
            lane_count,
            samples[offset..],
            input * multiplier_register + addend_register,
        );
    }
    processAffineScalar(
        Sample,
        samples[offset..],
        multiplier,
        addend,
    );
}

fn processCopyScalar(
    comptime Sample: type,
    destination: []Sample,
    source: []const Sample,
) void {
    @memcpy(destination, source);
}

fn processCopyVector(
    comptime Sample: type,
    comptime lane_count: usize,
    destination: []Sample,
    source: []const Sample,
) void {
    var offset: usize = 0;
    while (offset + lane_count <= destination.len) : (offset += lane_count) {
        storeVector(
            Sample,
            lane_count,
            destination[offset..],
            loadVector(Sample, lane_count, source[offset..]),
        );
    }
    processCopyScalar(
        Sample,
        destination[offset..],
        source[offset..],
    );
}

fn processAddScalar(
    comptime Sample: type,
    destination: []Sample,
    source: []const Sample,
) void {
    for (destination, source) |*output, input|
        output.* += input;
}

fn processAddVector(
    comptime Sample: type,
    comptime lane_count: usize,
    destination: []Sample,
    source: []const Sample,
) void {
    var offset: usize = 0;
    while (offset + lane_count <= destination.len) : (offset += lane_count) {
        storeVector(
            Sample,
            lane_count,
            destination[offset..],
            loadVector(Sample, lane_count, destination[offset..]) +
                loadVector(Sample, lane_count, source[offset..]),
        );
    }
    processAddScalar(
        Sample,
        destination[offset..],
        source[offset..],
    );
}

fn processMultiplyScalar(
    comptime Sample: type,
    destination: []Sample,
    source: []const Sample,
) void {
    for (destination, source) |*output, input|
        output.* *= input;
}

fn processMultiplyVector(
    comptime Sample: type,
    comptime lane_count: usize,
    destination: []Sample,
    source: []const Sample,
) void {
    var offset: usize = 0;
    while (offset + lane_count <= destination.len) : (offset += lane_count) {
        storeVector(
            Sample,
            lane_count,
            destination[offset..],
            loadVector(Sample, lane_count, destination[offset..]) *
                loadVector(Sample, lane_count, source[offset..]),
        );
    }
    processMultiplyScalar(
        Sample,
        destination[offset..],
        source[offset..],
    );
}

fn processComplexMultiplyScalar(
    comptime Sample: type,
    real: []Sample,
    imaginary: []Sample,
    multiplier_real: []const Sample,
    multiplier_imaginary: []const Sample,
) void {
    for (
        real,
        imaginary,
        multiplier_real,
        multiplier_imaginary,
    ) |*left_real, *left_imaginary, right_real, right_imaginary| {
        const original_real = left_real.*;
        const original_imaginary = left_imaginary.*;
        left_real.* =
            original_real * right_real -
            original_imaginary * right_imaginary;
        left_imaginary.* =
            original_real * right_imaginary +
            original_imaginary * right_real;
    }
}

fn processComplexMultiplyVector(
    comptime Sample: type,
    comptime lane_count: usize,
    real: []Sample,
    imaginary: []Sample,
    multiplier_real: []const Sample,
    multiplier_imaginary: []const Sample,
) void {
    var offset: usize = 0;
    while (offset + lane_count <= real.len) : (offset += lane_count) {
        const left_real =
            loadVector(Sample, lane_count, real[offset..]);
        const left_imaginary =
            loadVector(Sample, lane_count, imaginary[offset..]);
        const right_real =
            loadVector(Sample, lane_count, multiplier_real[offset..]);
        const right_imaginary =
            loadVector(Sample, lane_count, multiplier_imaginary[offset..]);
        storeVector(
            Sample,
            lane_count,
            real[offset..],
            left_real * right_real -
                left_imaginary * right_imaginary,
        );
        storeVector(
            Sample,
            lane_count,
            imaginary[offset..],
            left_real * right_imaginary +
                left_imaginary * right_real,
        );
    }
    processComplexMultiplyScalar(
        Sample,
        real[offset..],
        imaginary[offset..],
        multiplier_real[offset..],
        multiplier_imaginary[offset..],
    );
}

fn reduceSumScalar(
    comptime Sample: type,
    samples: []const Sample,
) Sample {
    var result: Sample = 0;
    for (samples) |sample| result += sample;
    return result;
}

fn reduceSumVector(
    comptime Sample: type,
    comptime lane_count: usize,
    samples: []const Sample,
) Sample {
    const Vector = @Vector(lane_count, Sample);
    var accumulator: Vector = @splat(0);
    var offset: usize = 0;
    while (offset + lane_count <= samples.len) : (offset += lane_count) {
        accumulator += loadVector(
            Sample,
            lane_count,
            samples[offset..],
        );
    }
    return @reduce(.Add, accumulator) +
        reduceSumScalar(Sample, samples[offset..]);
}

fn reduceInnerProductScalar(
    comptime Sample: type,
    left: []const Sample,
    right: []const Sample,
) Sample {
    var result: Sample = 0;
    for (left, right) |left_sample, right_sample|
        result += left_sample * right_sample;
    return result;
}

fn reduceInnerProductVector(
    comptime Sample: type,
    comptime lane_count: usize,
    left: []const Sample,
    right: []const Sample,
) Sample {
    const Vector = @Vector(lane_count, Sample);
    var accumulator: Vector = @splat(0);
    var offset: usize = 0;
    while (offset + lane_count <= left.len) : (offset += lane_count) {
        accumulator +=
            loadVector(Sample, lane_count, left[offset..]) *
            loadVector(Sample, lane_count, right[offset..]);
    }
    return @reduce(.Add, accumulator) +
        reduceInnerProductScalar(
            Sample,
            left[offset..],
            right[offset..],
        );
}

fn reducePeakAbsoluteScalar(
    comptime Sample: type,
    samples: []const Sample,
) Sample {
    var result: Sample = 0;
    for (samples) |sample| result = @max(result, @abs(sample));
    return result;
}

fn reducePeakAbsoluteVector(
    comptime Sample: type,
    comptime lane_count: usize,
    samples: []const Sample,
) Sample {
    const Vector = @Vector(lane_count, Sample);
    var accumulator: Vector = @splat(0);
    var offset: usize = 0;
    while (offset + lane_count <= samples.len) : (offset += lane_count) {
        accumulator = @max(
            accumulator,
            @abs(loadVector(
                Sample,
                lane_count,
                samples[offset..],
            )),
        );
    }
    return @max(
        @reduce(.Max, accumulator),
        reducePeakAbsoluteScalar(Sample, samples[offset..]),
    );
}

fn reduceMinimumScalar(
    comptime Sample: type,
    samples: []const Sample,
) Sample {
    var result = samples[0];
    for (samples[1..]) |sample| result = @min(result, sample);
    return result;
}

fn reduceMinimumVector(
    comptime Sample: type,
    comptime lane_count: usize,
    samples: []const Sample,
) Sample {
    if (samples.len < lane_count)
        return reduceMinimumScalar(Sample, samples);
    var accumulator =
        loadVector(Sample, lane_count, samples);
    var offset: usize = lane_count;
    while (offset + lane_count <= samples.len) : (offset += lane_count) {
        accumulator = @min(
            accumulator,
            loadVector(Sample, lane_count, samples[offset..]),
        );
    }
    var result = @reduce(.Min, accumulator);
    for (samples[offset..]) |sample| result = @min(result, sample);
    return result;
}

fn reduceMaximumScalar(
    comptime Sample: type,
    samples: []const Sample,
) Sample {
    var result = samples[0];
    for (samples[1..]) |sample| result = @max(result, sample);
    return result;
}

fn reduceMaximumVector(
    comptime Sample: type,
    comptime lane_count: usize,
    samples: []const Sample,
) Sample {
    if (samples.len < lane_count)
        return reduceMaximumScalar(Sample, samples);
    var accumulator =
        loadVector(Sample, lane_count, samples);
    var offset: usize = lane_count;
    while (offset + lane_count <= samples.len) : (offset += lane_count) {
        accumulator = @max(
            accumulator,
            loadVector(Sample, lane_count, samples[offset..]),
        );
    }
    var result = @reduce(.Max, accumulator);
    for (samples[offset..]) |sample| result = @max(result, sample);
    return result;
}

fn reduceSumSquaresScalar(
    comptime Sample: type,
    samples: []const Sample,
) Sample {
    var result: Sample = 0;
    for (samples) |sample| result += sample * sample;
    return result;
}

fn reduceSumSquaresVector(
    comptime Sample: type,
    comptime lane_count: usize,
    samples: []const Sample,
) Sample {
    const Vector = @Vector(lane_count, Sample);
    var accumulator: Vector = @splat(0);
    var offset: usize = 0;
    while (offset + lane_count <= samples.len) : (offset += lane_count) {
        const input =
            loadVector(Sample, lane_count, samples[offset..]);
        accumulator += input * input;
    }
    return @reduce(.Add, accumulator) +
        reduceSumSquaresScalar(Sample, samples[offset..]);
}

fn reduceScaledSumSquaresScalar(
    comptime Sample: type,
    samples: []const Sample,
    scale: Sample,
) Sample {
    var result: Sample = 0;
    for (samples) |sample| {
        const normalized = sample / scale;
        result += normalized * normalized;
    }
    return result;
}

fn reduceScaledSumSquaresVector(
    comptime Sample: type,
    comptime lane_count: usize,
    samples: []const Sample,
    scale: Sample,
) Sample {
    const Vector = @Vector(lane_count, Sample);
    const scale_vector: Vector = @splat(scale);
    var accumulator: Vector = @splat(0);
    var offset: usize = 0;
    while (offset + lane_count <= samples.len) : (offset += lane_count) {
        const normalized =
            loadVector(Sample, lane_count, samples[offset..]) /
            scale_vector;
        accumulator += normalized * normalized;
    }
    return @reduce(.Add, accumulator) +
        reduceScaledSumSquaresScalar(
            Sample,
            samples[offset..],
            scale,
        );
}

fn processMixScalar(
    comptime Sample: type,
    destination: []Sample,
    left: []const Sample,
    right: []const Sample,
    left_gain: Sample,
    right_gain: Sample,
) void {
    for (destination, left, right) |*output, left_sample, right_sample|
        output.* = left_sample * left_gain + right_sample * right_gain;
}

fn processMixVector(
    comptime Sample: type,
    comptime lane_count: usize,
    destination: []Sample,
    left: []const Sample,
    right: []const Sample,
    left_gain: Sample,
    right_gain: Sample,
) void {
    const Vector = @Vector(lane_count, Sample);
    const left_gain_register: Vector = @splat(left_gain);
    const right_gain_register: Vector = @splat(right_gain);
    var offset: usize = 0;
    while (offset + lane_count <= destination.len) : (offset += lane_count) {
        const left_input = loadVector(
            Sample,
            lane_count,
            left[offset..],
        );
        const right_input = loadVector(
            Sample,
            lane_count,
            right[offset..],
        );
        storeVector(
            Sample,
            lane_count,
            destination[offset..],
            left_input * left_gain_register +
                right_input * right_gain_register,
        );
    }
    processMixScalar(
        Sample,
        destination[offset..],
        left[offset..],
        right[offset..],
        left_gain,
        right_gain,
    );
}

fn loadVector(
    comptime Sample: type,
    comptime lane_count: usize,
    source: []const Sample,
) @Vector(lane_count, Sample) {
    const Vector = @Vector(lane_count, Sample);
    const pointer: *align(@alignOf(Sample)) const Vector =
        @ptrCast(source.ptr);
    return pointer.*;
}

fn storeVector(
    comptime Sample: type,
    comptime lane_count: usize,
    destination: []Sample,
    value: @Vector(lane_count, Sample),
) void {
    const Vector = @Vector(lane_count, Sample);
    const pointer: *align(@alignOf(Sample)) Vector =
        @ptrCast(destination.ptr);
    pointer.* = value;
}

fn processInterleaveBlocked(
    comptime Sample: type,
    lane_count: usize,
    destination: []Sample,
    left: []const Sample,
    right: []const Sample,
) void {
    var offset: usize = 0;
    while (offset + lane_count <= left.len) : (offset += lane_count) {
        for (0..lane_count) |lane| {
            destination[(offset + lane) * 2] = left[offset + lane];
            destination[(offset + lane) * 2 + 1] = right[offset + lane];
        }
    }
    for (offset..left.len) |index| {
        destination[index * 2] = left[index];
        destination[index * 2 + 1] = right[index];
    }
}

fn processDeinterleaveBlocked(
    comptime Sample: type,
    lane_count: usize,
    left: []Sample,
    right: []Sample,
    source: []const Sample,
) void {
    var offset: usize = 0;
    while (offset + lane_count <= left.len) : (offset += lane_count) {
        for (0..lane_count) |lane| {
            left[offset + lane] = source[(offset + lane) * 2];
            right[offset + lane] = source[(offset + lane) * 2 + 1];
        }
    }
    for (offset..left.len) |index| {
        left[index] = source[index * 2];
        right[index] = source[index * 2 + 1];
    }
}

fn slicesOverlap(
    comptime Sample: type,
    first: anytype,
    second: anytype,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    const first_start = @intFromPtr(first.ptr);
    const second_start = @intFromPtr(second.ptr);
    const first_end = first_start + first.len * @sizeOf(Sample);
    const second_end = second_start + second.len * @sizeOf(Sample);
    return first_start < second_end and second_start < first_end;
}

fn sameSlice(first: anytype, second: anytype) bool {
    return first.len == second.len and
        (first.len == 0 or @intFromPtr(first.ptr) == @intFromPtr(second.ptr));
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

test "processor dispatch selects implemented backends and scalar fallback" {
    const Probe = struct {
        backend: Backend = .scalar,
        calls: usize = 0,

        fn scalar(
            self: *@This(),
            destination: []f32,
            source: []const f32,
        ) void {
            run(self, .scalar, destination, source);
        }

        fn neon(
            self: *@This(),
            destination: []f32,
            source: []const f32,
        ) void {
            run(self, .neon, destination, source);
        }

        fn avx2(
            self: *@This(),
            destination: []f32,
            source: []const f32,
        ) void {
            run(self, .avx2, destination, source);
        }

        fn run(
            self: *@This(),
            backend: Backend,
            destination: []f32,
            source: []const f32,
        ) void {
            self.backend = backend;
            self.calls += 1;
            for (destination, source) |*output, input|
                output.* = input * 2.0;
        }
    };
    const Processor = BufferProcessorDispatcher(f32, Probe);
    const implementations = Processor.Implementations{
        .scalar = Probe.scalar,
        .neon = Probe.neon,
        .avx2 = Probe.avx2,
    };

    inline for (.{
        .{ Features{}, Backend.scalar },
        .{ Features{ .neon = true }, Backend.neon },
        .{ Features{ .avx2 = true }, Backend.avx2 },
        .{
            Features{ .neon = true, .avx2 = true },
            Backend.avx2,
        },
    }) |case| {
        const dispatcher = Processor.init(case[0], implementations);
        try std.testing.expectEqual(case[1], dispatcher.backend);
        try std.testing.expectEqual(
            (Dispatcher{ .backend = case[1] }).laneCount(f32),
            dispatcher.laneCount(),
        );
        var context = Probe{};
        var source_storage =
            [_]f32{ 99, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
        var destination_storage =
            [_]f32{ 99, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        try dispatcher.process(
            &context,
            destination_storage[1..],
            source_storage[1..],
        );
        try std.testing.expectEqual(case[1], context.backend);
        try std.testing.expectEqual(@as(usize, 1), context.calls);
        try std.testing.expectEqualSlices(
            f32,
            &.{ 2, 4, 6, 8, 10, 12, 14, 16, 18 },
            destination_storage[1..],
        );
    }

    const scalar_only = Processor.Implementations{
        .scalar = Probe.scalar,
    };
    try std.testing.expectEqual(
        Backend.scalar,
        Processor.init(
            .{ .neon = true, .avx2 = true },
            scalar_only,
        ).backend,
    );
    try std.testing.expectError(
        error.ProcessorBackendUnavailable,
        Processor.initBackend(.neon, scalar_only),
    );
}

test "processor dispatch permits replacement and rejects partial aliases" {
    const Probe = struct {
        calls: usize = 0,

        fn process(
            self: *@This(),
            destination: []f64,
            source: []const f64,
        ) void {
            self.calls += 1;
            for (destination, source) |*output, input|
                output.* = input + 0.25;
        }
    };
    const Processor = BufferProcessorDispatcher(f64, Probe);
    const dispatcher = Processor.init(.{}, .{
        .scalar = Probe.process,
    });

    var context = Probe{};
    var samples = [_]f64{ -1.0, 0.0, 1.0, 2.0, 3.0 };
    dispatcher.processReplacing(&context, &samples);
    try std.testing.expectEqualSlices(
        f64,
        &.{ -0.75, 0.25, 1.25, 2.25, 3.25 },
        &samples,
    );
    try std.testing.expectEqual(@as(usize, 1), context.calls);

    const before = samples;
    try std.testing.expectError(
        error.InvalidProcessorDispatchShape,
        dispatcher.process(
            &context,
            samples[0..2],
            samples[2..5],
        ),
    );
    try std.testing.expectError(
        error.ProcessorDispatchBuffersOverlap,
        dispatcher.process(
            &context,
            samples[1..5],
            samples[0..4],
        ),
    );
    try std.testing.expectEqualSlices(f64, &before, &samples);
    try std.testing.expectEqual(@as(usize, 1), context.calls);

    try dispatcher.process(
        &context,
        samples[0..0],
        samples[2..2],
    );
    try std.testing.expectEqual(@as(usize, 2), context.calls);
}

test "kernel dispatcher processes scalar and vector-width buffers" {
    inline for (.{
        Features{},
        Features{ .neon = true },
        Features{ .avx2 = true },
    }) |features| {
        const dispatcher = Dispatcher.init(features);
        var samples = [_]f32{ 1.0, -2.0, 3.0, -4.0, 5.0, -6.0, 7.0, -8.0, 9.0 };
        try dispatcher.processGain(f32, &samples, 0.5);
        try std.testing.expectEqualSlices(
            f32,
            &.{ 0.5, -1.0, 1.5, -2.0, 2.5, -3.0, 3.5, -4.0, 4.5 },
            &samples,
        );
    }
}

test "kernel dispatcher rejects invalid gain transactionally" {
    const dispatcher = Dispatcher.initDetected();
    var samples = [_]f64{ 1.0, std.math.floatMax(f64) };
    const before = samples;
    try std.testing.expectError(
        error.InvalidDispatchedGain,
        dispatcher.processGain(f64, &samples, 2.0),
    );
    try std.testing.expectEqualSlices(f64, &before, &samples);
}

test "kernel dispatcher affine processing matches every backend" {
    inline for (.{
        Features{},
        Features{ .neon = true },
        Features{ .avx2 = true },
    }) |features| {
        const dispatcher = Dispatcher.init(features);
        var samples = [_]f64{ -4.0, -1.0, 0.0, 2.0, 5.0 };
        try dispatcher.processAffine(f64, &samples, 0.25, 0.5);
        try std.testing.expectEqualSlices(
            f64,
            &.{ -0.5, 0.25, 0.5, 1.0, 1.75 },
            &samples,
        );
    }
}

test "kernel dispatcher handles unaligned affine slices and empty layouts" {
    const dispatcher = Dispatcher.init(.{ .avx2 = true });
    var storage = [_]f32{ 99.0, 1.0, 2.0, 3.0, 4.0, 99.0 };
    try dispatcher.processAffine(f32, storage[1..5], 2.0, -1.0);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 99.0, 1.0, 3.0, 5.0, 7.0, 99.0 },
        &storage,
    );

    var empty_destination: [0]f32 = .{};
    const empty_source: [0]f32 = .{};
    try dispatcher.interleaveStereo(
        f32,
        &empty_destination,
        &empty_source,
        &empty_source,
    );
    try dispatcher.deinterleaveStereo(
        f32,
        &empty_destination,
        &empty_destination,
        &empty_source,
    );
}

test "kernel dispatcher rejects invalid affine processing transactionally" {
    const dispatcher = Dispatcher.init(.{ .avx2 = true });
    var samples = [_]f32{ 1.0, std.math.floatMax(f32) };
    const before = samples;
    try std.testing.expectError(
        error.InvalidDispatchedAffine,
        dispatcher.processAffine(f32, &samples, 2.0, 1.0),
    );
    try std.testing.expectEqualSlices(f32, &before, &samples);
}

test "kernel dispatcher applies fast math across backends" {
    inline for (.{
        Features{},
        Features{ .neon = true },
        Features{ .avx2 = true },
    }) |features| {
        const dispatcher = Dispatcher.init(features);
        var samples = [_]f64{ -0.4, -0.2, 0.0, 0.2, 0.4 };
        try dispatcher.applyFastMath(f64, .exponential, &samples);
        for (samples, 0..) |actual, index| {
            const input =
                @as(f64, @floatFromInt(index)) * 0.2 - 0.4;
            try std.testing.expectApproxEqAbs(
                try fast_math.Approximations(f64).exp(input),
                actual,
                2.0e-12,
            );
        }
    }

    const dispatcher = Dispatcher.init(.{ .avx2 = true });
    var invalid = [_]f32{ 0.0, 0.25, 2.0, -0.25 };
    const before = invalid;
    try std.testing.expectError(
        error.FastMathInputOutOfRange,
        dispatcher.applyFastMath(f32, .tangent, &invalid),
    );
    try std.testing.expectEqualSlices(f32, &before, &invalid);
}

test "kernel dispatcher mixes buffers with scalar and vector parity" {
    inline for (.{
        Features{},
        Features{ .neon = true },
        Features{ .avx2 = true },
    }) |features| {
        const dispatcher = Dispatcher.init(features);
        const left = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
        const right = [_]f64{ -5.0, -4.0, -3.0, -2.0, -1.0 };
        var destination: [5]f64 = undefined;
        try dispatcher.mixBuffers(
            f64,
            &destination,
            &left,
            &right,
            0.25,
            0.5,
        );
        try std.testing.expectEqualSlices(
            f64,
            &.{ -2.25, -1.5, -0.75, 0.0, 0.75 },
            &destination,
        );
    }
}

test "kernel dispatcher reductions match backends and scalar tails" {
    inline for (.{ f32, f64 }) |Sample| {
        inline for (.{
            Features{},
            Features{ .neon = true },
            Features{ .avx2 = true },
        }) |features| {
            const dispatcher = Dispatcher.init(features);
            const left = [_]Sample{
                1.0,  -2.0, 3.0,  -4.0, 5.0,
                -6.0, 7.0,  -8.0, 9.0,
            };
            const right = [_]Sample{
                0.5, 0.25, -0.5, -0.25, 1.0,
                0.5, -1.0, -0.5, 0.25,
            };
            try std.testing.expectApproxEqAbs(
                @as(Sample, 5.0),
                try dispatcher.sum(Sample, &left),
                std.math.floatEps(Sample) * 16,
            );
            try std.testing.expectApproxEqAbs(
                @as(Sample, 0.75),
                try dispatcher.innerProduct(Sample, &left, &right),
                std.math.floatEps(Sample) * 32,
            );
            try std.testing.expectEqual(
                @as(Sample, 9.0),
                try dispatcher.peakAbsolute(Sample, &left),
            );
            try std.testing.expectEqual(
                @as(Sample, -8.0),
                try dispatcher.minimum(Sample, &left),
            );
            try std.testing.expectEqual(
                @as(Sample, 9.0),
                try dispatcher.maximum(Sample, &left),
            );
            try std.testing.expectApproxEqAbs(
                @as(Sample, 285.0),
                try dispatcher.sumSquares(Sample, &left),
                std.math.floatEps(Sample) * 64,
            );
            try std.testing.expectApproxEqAbs(
                @sqrt(@as(Sample, 285.0 / 9.0)),
                try dispatcher.rootMeanSquare(Sample, &left),
                std.math.floatEps(Sample) * 16,
            );
            try std.testing.expectEqual(
                @as(Sample, 0.0),
                try dispatcher.sum(Sample, &.{}),
            );
            try std.testing.expectEqual(
                @as(Sample, 0.0),
                try dispatcher.innerProduct(Sample, &.{}, &.{}),
            );
            try std.testing.expectEqual(
                @as(Sample, 0.0),
                try dispatcher.peakAbsolute(Sample, &.{}),
            );
            try std.testing.expectError(
                error.DispatchedReductionRequiresSamples,
                dispatcher.minimum(Sample, &.{}),
            );
            try std.testing.expectError(
                error.DispatchedReductionRequiresSamples,
                dispatcher.maximum(Sample, &.{}),
            );
            try std.testing.expectEqual(
                @as(Sample, 0.0),
                try dispatcher.sumSquares(Sample, &.{}),
            );
            try std.testing.expectEqual(
                @as(Sample, 0.0),
                try dispatcher.rootMeanSquare(Sample, &.{}),
            );
        }
    }
}

test "kernel dispatcher reductions reject invalid inputs" {
    const dispatcher = Dispatcher.init(.{ .avx2 = true });
    const finite = [_]f32{ 1.0, 2.0 };
    const invalid = [_]f32{ 1.0, std.math.nan(f32) };
    const overflow = [_]f32{
        std.math.floatMax(f32),
        std.math.floatMax(f32),
    };
    try std.testing.expectError(
        error.InvalidDispatchedReductionShape,
        dispatcher.innerProduct(f32, &finite, finite[0..1]),
    );
    try std.testing.expectError(
        error.InvalidDispatchedReduction,
        dispatcher.sum(f32, &invalid),
    );
    try std.testing.expectError(
        error.InvalidDispatchedReduction,
        dispatcher.innerProduct(f32, &overflow, &overflow),
    );
    try std.testing.expectError(
        error.InvalidDispatchedReduction,
        dispatcher.peakAbsolute(f32, &invalid),
    );
    try std.testing.expectError(
        error.InvalidDispatchedReduction,
        dispatcher.minimum(f32, &invalid),
    );
    try std.testing.expectError(
        error.InvalidDispatchedReduction,
        dispatcher.maximum(f32, &invalid),
    );
    try std.testing.expectError(
        error.InvalidDispatchedReduction,
        dispatcher.sumSquares(f32, &overflow),
    );
    try std.testing.expectEqual(
        std.math.floatMax(f32),
        try dispatcher.rootMeanSquare(f32, &overflow),
    );
}

test "kernel dispatcher multiplies complex buffers across backends" {
    inline for (.{ f32, f64 }) |Sample| {
        inline for (.{
            Features{},
            Features{ .neon = true },
            Features{ .avx2 = true },
        }) |features| {
            const dispatcher = Dispatcher.init(features);
            var real = [_]Sample{
                1, 2, 3, 4, 5, 6, 7, 8, 9,
            };
            var imaginary = [_]Sample{
                9, 8, 7, 6, 5, 4, 3, 2, 1,
            };
            const multiplier_real = [_]Sample{
                0.5, -1, 2, 0, 1, 0.25, -0.5, 3, 2,
            };
            const multiplier_imaginary = [_]Sample{
                -0.5, 2, 0, 1, -1, 0.75, 0.5, -2, 1,
            };
            try dispatcher.multiplyComplexBuffer(
                Sample,
                &real,
                &imaginary,
                &multiplier_real,
                &multiplier_imaginary,
            );
            try std.testing.expectEqualSlices(
                Sample,
                &.{ 5, -18, 6, -6, 10, -1.5, -5, 28, 17 },
                &real,
            );
            try std.testing.expectEqualSlices(
                Sample,
                &.{ 4, -4, 14, 4, 0, 5.5, 2, -10, 11 },
                &imaginary,
            );
        }
    }
}

test "kernel dispatcher complex multiply supports exact pair aliases" {
    const dispatcher = Dispatcher.init(.{ .avx2 = true });
    var real = [_]f32{ 1, 2, 3 };
    var imaginary = [_]f32{ 4, 5, 6 };
    try dispatcher.multiplyComplexBuffer(
        f32,
        &real,
        &imaginary,
        &real,
        &imaginary,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ -15, -21, -27 },
        &real,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 8, 20, 36 },
        &imaginary,
    );
}

test "kernel dispatcher complex multiply rejects failures transactionally" {
    const dispatcher = Dispatcher.init(.{ .neon = true });
    var storage = [_]f32{
        1, 2,  3,  4,
        5, 6,  7,  8,
        9, 10, 11, 12,
    };
    const before = storage;
    try std.testing.expectError(
        error.DispatchedComplexBuffersOverlap,
        dispatcher.multiplyComplexBuffer(
            f32,
            storage[0..4],
            storage[4..8],
            storage[1..5],
            storage[8..12],
        ),
    );
    try std.testing.expectEqualSlices(f32, &before, &storage);
    try std.testing.expectError(
        error.DispatchedComplexBuffersOverlap,
        dispatcher.multiplyComplexBuffer(
            f32,
            storage[0..4],
            storage[2..6],
            storage[8..12],
            &.{ 1, 1, 1, 1 },
        ),
    );
    try std.testing.expectEqualSlices(f32, &before, &storage);
    try std.testing.expectError(
        error.InvalidDispatchedComplexShape,
        dispatcher.multiplyComplexBuffer(
            f32,
            storage[0..3],
            storage[4..8],
            storage[8..12],
            &.{ 1, 1, 1, 1 },
        ),
    );
    try std.testing.expectEqualSlices(f32, &before, &storage);

    var real = [_]f32{ 1, 2 };
    var imaginary = [_]f32{ 3, 4 };
    const real_before = real;
    const imaginary_before = imaginary;
    try std.testing.expectError(
        error.InvalidDispatchedComplexMultiply,
        dispatcher.multiplyComplexBuffer(
            f32,
            &real,
            &imaginary,
            &.{ 1, std.math.nan(f32) },
            &.{ 0, 0 },
        ),
    );
    try std.testing.expectEqualSlices(f32, &real_before, &real);
    try std.testing.expectEqualSlices(
        f32,
        &imaginary_before,
        &imaginary,
    );

    var overflow_real = [_]f32{std.math.floatMax(f32)};
    var overflow_imaginary = [_]f32{0};
    try std.testing.expectError(
        error.InvalidDispatchedComplexMultiply,
        dispatcher.multiplyComplexBuffer(
            f32,
            &overflow_real,
            &overflow_imaginary,
            &.{2},
            &.{0},
        ),
    );
    try std.testing.expectEqual(
        std.math.floatMax(f32),
        overflow_real[0],
    );
    try std.testing.expectEqual(@as(f32, 0), overflow_imaginary[0]);
}

test "kernel dispatcher mix supports exact aliases" {
    const dispatcher = Dispatcher.init(.{ .avx2 = true });
    var left = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const right = [_]f32{ 5.0, 4.0, 3.0, 2.0, 1.0 };
    try dispatcher.mixBuffers(
        f32,
        &left,
        &left,
        &right,
        0.5,
        0.5,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 3.0, 3.0, 3.0, 3.0, 3.0 },
        &left,
    );
}

test "kernel dispatcher rejects invalid and overlapping mixes transactionally" {
    const dispatcher = Dispatcher.initDetected();
    var storage = [_]f32{
        1.0, 2.0, 3.0, 4.0,
        5.0, 6.0, 7.0, 8.0,
    };
    const before = storage;
    try std.testing.expectError(
        error.DispatchedMixBuffersOverlap,
        dispatcher.mixBuffers(
            f32,
            storage[1..5],
            storage[0..4],
            storage[4..8],
            0.5,
            0.5,
        ),
    );
    try std.testing.expectEqualSlices(f32, &before, &storage);

    const huge = [_]f32{ std.math.floatMax(f32), 1.0 };
    try std.testing.expectError(
        error.InvalidDispatchedMix,
        dispatcher.mixBuffers(
            f32,
            storage[0..2],
            &huge,
            &huge,
            2.0,
            2.0,
        ),
    );
    try std.testing.expectEqualSlices(f32, &before, &storage);
}

test "kernel dispatcher converts stereo layouts across backend boundaries" {
    inline for (.{
        Features{},
        Features{ .neon = true },
        Features{ .avx2 = true },
    }) |features| {
        const dispatcher = Dispatcher.init(features);
        const left = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 };
        const right = [_]f32{ -1.0, -2.0, -3.0, -4.0, -5.0 };
        var interleaved: [10]f32 = undefined;
        try dispatcher.interleaveStereo(
            f32,
            &interleaved,
            &left,
            &right,
        );
        try std.testing.expectEqualSlices(
            f32,
            &.{ 1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0, 5.0, -5.0 },
            &interleaved,
        );

        var restored_left: [5]f32 = undefined;
        var restored_right: [5]f32 = undefined;
        try dispatcher.deinterleaveStereo(
            f32,
            &restored_left,
            &restored_right,
            &interleaved,
        );
        try std.testing.expectEqualSlices(f32, &left, &restored_left);
        try std.testing.expectEqualSlices(f32, &right, &restored_right);
    }
}

test "kernel dispatcher rejects stereo shape and sample errors transactionally" {
    const dispatcher = Dispatcher.initDetected();
    const left = [_]f64{ 1.0, 2.0 };
    const invalid_right = [_]f64{ 3.0, std.math.nan(f64) };
    var destination = [_]f64{ 9.0, 9.0, 9.0, 9.0 };
    const before = destination;
    try std.testing.expectError(
        error.InvalidDispatchedStereoSample,
        dispatcher.interleaveStereo(
            f64,
            &destination,
            &left,
            &invalid_right,
        ),
    );
    try std.testing.expectEqualSlices(f64, &before, &destination);
    try std.testing.expectError(
        error.InvalidDispatchedStereoShape,
        dispatcher.interleaveStereo(
            f64,
            destination[0..3],
            &left,
            &left,
        ),
    );
    try std.testing.expectEqualSlices(f64, &before, &destination);
}

test "kernel dispatcher rejects overlapping stereo buffers" {
    const dispatcher = Dispatcher.init(.{ .neon = true });
    var storage = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 };
    const before = storage;
    try std.testing.expectError(
        error.DispatchedStereoBuffersOverlap,
        dispatcher.interleaveStereo(
            f32,
            storage[0..4],
            storage[0..2],
            storage[4..6],
        ),
    );
    try std.testing.expectEqualSlices(f32, &before, &storage);

    try std.testing.expectError(
        error.DispatchedStereoBuffersOverlap,
        dispatcher.deinterleaveStereo(
            f32,
            storage[0..2],
            storage[1..3],
            storage[2..6],
        ),
    );
    try std.testing.expectEqualSlices(f32, &before, &storage);
}

test "dispatched copy add and multiply enforce aliases transactionally" {
    const dispatcher = Dispatcher.init(.{ .avx2 = true });
    var exact = [_]f32{ 1.0, -2.0, 3.0, -4.0, 5.0 };
    try dispatcher.copyBuffer(f32, &exact, &exact);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1.0, -2.0, 3.0, -4.0, 5.0 },
        &exact,
    );
    try dispatcher.addBuffer(f32, &exact, &exact);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 2.0, -4.0, 6.0, -8.0, 10.0 },
        &exact,
    );
    try dispatcher.multiplyBuffer(f32, &exact, &exact);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 4.0, 16.0, 36.0, 64.0, 100.0 },
        &exact,
    );

    var storage = [_]f32{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 };
    const before = storage;
    try std.testing.expectError(
        error.DispatchedCopyBuffersOverlap,
        dispatcher.copyBuffer(f32, storage[1..5], storage[0..4]),
    );
    try std.testing.expectError(
        error.DispatchedAddBuffersOverlap,
        dispatcher.addBuffer(f32, storage[1..5], storage[0..4]),
    );
    try std.testing.expectError(
        error.DispatchedMultiplyBuffersOverlap,
        dispatcher.multiplyBuffer(f32, storage[1..5], storage[0..4]),
    );
    try std.testing.expectEqualSlices(f32, &before, &storage);

    const invalid = [_]f32{ 1.0, std.math.nan(f32) };
    try std.testing.expectError(
        error.InvalidDispatchedCopy,
        dispatcher.copyBuffer(f32, storage[0..2], &invalid),
    );
    var overflow_destination =
        [_]f32{ std.math.floatMax(f32), std.math.floatMax(f32) };
    const overflow_before = overflow_destination;
    const overflow_inputs =
        [_]f32{ std.math.floatMax(f32), std.math.floatMax(f32) };
    try std.testing.expectError(
        error.InvalidDispatchedAdd,
        dispatcher.addBuffer(
            f32,
            &overflow_destination,
            &overflow_inputs,
        ),
    );
    try std.testing.expectError(
        error.InvalidDispatchedMultiply,
        dispatcher.multiplyBuffer(
            f32,
            &overflow_destination,
            &overflow_inputs,
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &overflow_before,
        &overflow_destination,
    );
    try std.testing.expectEqualSlices(f32, &before, &storage);

    try std.testing.expectError(
        error.InvalidDispatchedCopyShape,
        dispatcher.copyBuffer(f32, storage[0..1], storage[2..4]),
    );
    try std.testing.expectError(
        error.InvalidDispatchedAddShape,
        dispatcher.addBuffer(f32, storage[0..1], storage[2..4]),
    );
    try std.testing.expectError(
        error.InvalidDispatchedMultiplyShape,
        dispatcher.multiplyBuffer(f32, storage[0..1], storage[2..4]),
    );
}

test "kernel dispatcher matches scalar tails across widths and alignments" {
    try expectDispatcherParity(f32);
    try expectDispatcherParity(f64);
}

fn expectDispatcherParity(comptime Sample: type) !void {
    const maximum_samples = 73;
    const tolerance: Sample =
        if (Sample == f32) 1.0e-6 else 1.0e-13;
    inline for (.{
        Features{},
        Features{ .neon = true },
        Features{ .avx2 = true },
    }) |features| {
        const dispatcher = Dispatcher.init(features);
        for (0..maximum_samples + 1) |sample_count| {
            var gain_storage: [maximum_samples + 2]Sample = @splat(99.0);
            for (
                gain_storage[1 .. sample_count + 1],
                0..,
            ) |*sample, index| {
                sample.* =
                    @as(Sample, @floatFromInt(index)) * 0.125 - 3.0;
            }
            var expected_gain = gain_storage;
            for (expected_gain[1 .. sample_count + 1]) |*sample|
                sample.* *= -0.375;
            try dispatcher.processGain(
                Sample,
                gain_storage[1 .. sample_count + 1],
                -0.375,
            );
            try expectApproxSlices(
                Sample,
                &expected_gain,
                &gain_storage,
                tolerance,
            );

            var affine_storage = gain_storage;
            var expected_affine = gain_storage;
            for (expected_affine[1 .. sample_count + 1]) |*sample|
                sample.* = sample.* * 1.25 + 0.0625;
            try dispatcher.processAffine(
                Sample,
                affine_storage[1 .. sample_count + 1],
                1.25,
                0.0625,
            );
            try expectApproxSlices(
                Sample,
                &expected_affine,
                &affine_storage,
                tolerance,
            );

            var left_storage: [maximum_samples + 2]Sample = @splat(77.0);
            var right_storage: [maximum_samples + 2]Sample = @splat(88.0);
            var mix_storage: [maximum_samples + 2]Sample = @splat(66.0);
            for (
                left_storage[1 .. sample_count + 1],
                right_storage[1 .. sample_count + 1],
                0..,
            ) |*left, *right, index| {
                left.* = @as(Sample, @floatFromInt(index)) * 0.25 - 2.0;
                right.* =
                    1.5 - @as(Sample, @floatFromInt(index)) * 0.0625;
            }
            var expected_mix = mix_storage;
            for (
                expected_mix[1 .. sample_count + 1],
                left_storage[1 .. sample_count + 1],
                right_storage[1 .. sample_count + 1],
            ) |*output, left, right| {
                output.* = left * 0.625 + right * -0.25;
            }
            try dispatcher.mixBuffers(
                Sample,
                mix_storage[1 .. sample_count + 1],
                left_storage[1 .. sample_count + 1],
                right_storage[1 .. sample_count + 1],
                0.625,
                -0.25,
            );
            try expectApproxSlices(
                Sample,
                &expected_mix,
                &mix_storage,
                tolerance,
            );

            var copy_storage: [maximum_samples + 2]Sample = @splat(55.0);
            var expected_copy = copy_storage;
            @memcpy(
                expected_copy[1 .. sample_count + 1],
                left_storage[1 .. sample_count + 1],
            );
            try dispatcher.copyBuffer(
                Sample,
                copy_storage[1 .. sample_count + 1],
                left_storage[1 .. sample_count + 1],
            );
            try expectApproxSlices(
                Sample,
                &expected_copy,
                &copy_storage,
                tolerance,
            );

            var add_storage = left_storage;
            var expected_add = left_storage;
            for (
                expected_add[1 .. sample_count + 1],
                right_storage[1 .. sample_count + 1],
            ) |*output, input| {
                output.* += input;
            }
            try dispatcher.addBuffer(
                Sample,
                add_storage[1 .. sample_count + 1],
                right_storage[1 .. sample_count + 1],
            );
            try expectApproxSlices(
                Sample,
                &expected_add,
                &add_storage,
                tolerance,
            );

            var multiply_storage = left_storage;
            var expected_multiply = left_storage;
            for (
                expected_multiply[1 .. sample_count + 1],
                right_storage[1 .. sample_count + 1],
            ) |*output, input| {
                output.* *= input;
            }
            try dispatcher.multiplyBuffer(
                Sample,
                multiply_storage[1 .. sample_count + 1],
                right_storage[1 .. sample_count + 1],
            );
            try expectApproxSlices(
                Sample,
                &expected_multiply,
                &multiply_storage,
                tolerance,
            );
        }
    }
}

fn expectApproxSlices(
    comptime Sample: type,
    expected: []const Sample,
    actual: []const Sample,
    tolerance: Sample,
) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expected_sample, actual_sample|
        try std.testing.expectApproxEqAbs(
            expected_sample,
            actual_sample,
            tolerance,
        );
}
