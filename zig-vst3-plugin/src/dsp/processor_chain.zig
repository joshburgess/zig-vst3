const std = @import("std");
const buffer_regions = @import("buffer_regions.zig");

pub fn ProcessorChain(
    comptime Sample: type,
    comptime Processors: type,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("ProcessorChain supports f32 and f64 samples");
    const fields = std.meta.fields(Processors);
    if (fields.len == 0)
        @compileError("ProcessorChain requires at least one processor");
    if (@typeInfo(Processors) != .@"struct" or
        !@typeInfo(Processors).@"struct".is_tuple)
        @compileError("ProcessorChain processors must be a tuple");

    return struct {
        const Self = @This();

        processors: Processors,
        bypassed: [fields.len]bool = @splat(false),

        pub fn init(processors: Processors) Self {
            return .{ .processors = processors };
        }

        pub fn get(
            self: *Self,
            comptime index: usize,
        ) *fields[index].type {
            if (index >= fields.len)
                @compileError("ProcessorChain index is out of range");
            return &@field(self.processors, fields[index].name);
        }

        pub fn setBypassed(
            self: *Self,
            comptime index: usize,
            bypassed: bool,
        ) void {
            if (index >= fields.len)
                @compileError("ProcessorChain index is out of range");
            self.bypassed[index] = bypassed;
        }

        pub fn isBypassed(self: *const Self, comptime index: usize) bool {
            if (index >= fields.len)
                @compileError("ProcessorChain index is out of range");
            return self.bypassed[index];
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            var output = if (std.math.isFinite(input)) input else 0.0;
            inline for (fields, 0..) |field, index| {
                if (!self.bypassed[index]) {
                    output = @field(
                        self.processors,
                        field.name,
                    ).processSample(output);
                    if (!std.math.isFinite(output)) return 0.0;
                }
            }
            return output;
        }

        pub fn process(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len)
                return error.ProcessorChainBufferLengthMismatch;
            if (!buffer_regions.exactOrDisjoint(Sample, input, output))
                return error.ProcessorChainBufferOverlap;
            for (input, output) |input_sample, *output_sample|
                output_sample.* = self.processSample(input_sample);
        }

        pub fn valid(self: *const Self) bool {
            inline for (fields, 0..) |field, index| {
                _ = self.bypassed[index];
                const Processor = field.type;
                if (@hasDecl(Processor, "valid") and
                    !@field(self.processors, field.name).valid())
                    return false;
            }
            return true;
        }
    };
}

const Gain = struct {
    value: f32,

    fn processSample(self: *Gain, input: f32) f32 {
        return input * self.value;
    }

    fn valid(self: *const Gain) bool {
        return std.math.isFinite(self.value);
    }
};

const Bias = struct {
    value: f32,

    fn processSample(self: *Bias, input: f32) f32 {
        return input + self.value;
    }
};

test "processor chain runs tuple members in order" {
    const Chain = ProcessorChain(f32, struct { Gain, Bias });
    var chain = Chain.init(.{
        .{ .value = 2.0 },
        .{ .value = 0.25 },
    });
    try std.testing.expectEqual(
        @as(f32, 1.25),
        chain.processSample(0.5),
    );
    chain.get(0).value = 3.0;
    try std.testing.expectEqual(
        @as(f32, 1.75),
        chain.processSample(0.5),
    );
}

test "processor chain supports compile-time bypass and block processing" {
    const Chain = ProcessorChain(f32, struct { Gain, Bias });
    var chain = Chain.init(.{
        .{ .value = 2.0 },
        .{ .value = 0.25 },
    });
    chain.setBypassed(0, true);
    try std.testing.expect(chain.isBypassed(0));
    try std.testing.expect(!chain.isBypassed(1));
    var output: [3]f32 = undefined;
    try chain.process(&.{ 0.0, 0.5, 1.0 }, &output);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.25, 0.75, 1.25 },
        &output,
    );
}

test "processor chain reports invalid members and contains non-finite output" {
    const Chain = ProcessorChain(f32, struct { Gain, Bias });
    var chain = Chain.init(.{
        .{ .value = 2.0 },
        .{ .value = 0.25 },
    });
    try std.testing.expect(chain.valid());
    chain.get(0).value = std.math.nan(f32);
    try std.testing.expect(!chain.valid());
    try std.testing.expectEqual(@as(f32, 0.0), chain.processSample(1.0));
}

test "processor chain permits in-place buffers and rejects shifted overlap" {
    const Chain = ProcessorChain(f32, struct { Gain, Bias });
    var chain = Chain.init(.{
        .{ .value = 2.0 },
        .{ .value = 0.25 },
    });
    var storage = [_]f32{ 0.0, 0.5, 1.0, 2.0 };
    const retained = storage;
    const chain_before = chain;
    try std.testing.expectError(
        error.ProcessorChainBufferOverlap,
        chain.process(storage[0..3], storage[1..4]),
    );
    try std.testing.expectEqualDeep(chain_before, chain);
    try std.testing.expectEqualSlices(f32, &retained, &storage);

    try chain.process(&storage, &storage);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.25, 1.25, 2.25, 4.25 },
        &storage,
    );
}
