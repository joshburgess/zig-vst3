const std = @import("std");
const polyphase_iir = @import("polyphase_iir.zig");

pub const Config = struct {
    normalized_transition_width: f64 = 0.1,
    stopband_attenuation_db: f64 = -90.0,
};

pub const Options = struct {
    use_integer_latency: bool = false,
};

pub fn Oversampler(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime factor: usize,
) type {
    requireSampleType(Sample);
    if (maximum_frames == 0)
        @compileError(
            "polyphase IIR oversampling frame capacity must be nonzero",
        );
    if (factor != 2 and factor != 4 and
        factor != 8 and factor != 16)
        @compileError(
            "polyphase IIR oversampling factor must be 2, 4, 8, or 16",
        );

    const stage_count = std.math.log2_int(usize, factor);
    const Design = polyphase_iir.Design(Sample);
    const Stage = HalfBandStage(Sample);
    const Compensator = FractionalAllpass(Sample);

    return struct {
        const Self = @This();

        const PendingBuffer = enum {
            none,
            first,
            second,
        };

        pub const oversampling_factor = factor;
        pub const oversampling_stage_count = stage_count;
        pub const maximum_base_rate_frames = maximum_frames;

        designs: [stage_count]Design,
        interpolation_stages: [stage_count]Stage,
        decimation_stages: [stage_count]Stage,
        latency_compensator: Compensator,
        use_integer_latency: bool,
        first_buffer: [maximum_frames * factor]Sample = undefined,
        second_buffer: [maximum_frames * factor]Sample = undefined,
        pending_frames: usize = 0,
        pending_buffer: PendingBuffer = .none,

        pub fn init(config: Config) !Self {
            return initWithOptions(config, .{});
        }

        pub fn initWithOptions(
            config: Config,
            options: Options,
        ) !Self {
            return initStagesWithOptions(@splat(config), options);
        }

        pub fn initStages(configs: [stage_count]Config) !Self {
            return initStagesWithOptions(configs, .{});
        }

        pub fn initStagesWithOptions(
            configs: [stage_count]Config,
            options: Options,
        ) !Self {
            var designs: [stage_count]Design = undefined;
            var interpolation_stages: [stage_count]Stage = undefined;
            var decimation_stages: [stage_count]Stage = undefined;
            for (configs, 0..) |config, index| {
                const design = try designForConfig(config);
                const stage = try Stage.init(design);
                designs[index] = design;
                interpolation_stages[index] = stage;
                decimation_stages[index] = stage;
            }
            const natural_latency = latencyForDesigns(designs);
            const compensation =
                if (options.use_integer_latency)
                    @ceil(natural_latency) - natural_latency
                else
                    0.0;
            return .{
                .designs = designs,
                .interpolation_stages = interpolation_stages,
                .decimation_stages = decimation_stages,
                .latency_compensator = try Compensator.init(compensation),
                .use_integer_latency = options.use_integer_latency,
            };
        }

        fn designForConfig(config: Config) !Design {
            const transition: Sample =
                @floatCast(config.normalized_transition_width);
            const attenuation: Sample =
                @floatCast(config.stopband_attenuation_db);
            if (!std.math.isFinite(transition) or
                !std.math.isFinite(attenuation))
                return error.InvalidPolyphaseIirOversamplingConfig;
            const design =
                polyphase_iir.Designer(Sample).halfBandLowPass(
                    transition,
                    attenuation,
                ) catch |design_error| switch (design_error) {
                    error.InvalidPolyphaseAllpassTransitionWidth,
                    error.InvalidPolyphaseAllpassStopband,
                    => return error.InvalidPolyphaseIirOversamplingConfig,
                    else => return design_error,
                };
            return design;
        }

        pub fn reset(self: *Self) void {
            for (&self.interpolation_stages) |*stage| stage.reset();
            for (&self.decimation_stages) |*stage| stage.reset();
            self.latency_compensator.reset();
            self.pending_frames = 0;
            self.pending_buffer = .none;
        }

        pub fn latencySamples(self: *const Self) !f64 {
            if (!self.valid())
                return error.InvalidPolyphaseIirOversamplerState;

            const natural_latency = latencyForDesigns(self.designs);
            return if (self.use_integer_latency)
                @ceil(natural_latency)
            else
                natural_latency;
        }

        pub fn upsample(
            self: *Self,
            input: []const Sample,
        ) ![]Sample {
            if (!self.valid())
                return error.InvalidPolyphaseIirOversamplerState;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            if (input.len > maximum_frames)
                return error.PolyphaseIirOversamplingCapacityExceeded;
            for (input) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFinitePolyphaseIirOversamplingInput;
            }
            if (input.len == 0) return self.first_buffer[0..0];

            errdefer self.reset();
            var source: []const Sample = input;
            inline for (0..stage_count) |stage_index| {
                const output_length = source.len * 2;
                const destination =
                    if (stage_index % 2 == 0)
                        self.first_buffer[0..output_length]
                    else
                        self.second_buffer[0..output_length];
                try self.interpolation_stages[stage_index]
                    .interpolate(source, destination);
                source = destination;
            }

            self.pending_frames = input.len;
            self.pending_buffer =
                if (stage_count % 2 == 1) .first else .second;
            return switch (self.pending_buffer) {
                .first => self.first_buffer[0 .. input.len * factor],
                .second => self.second_buffer[0 .. input.len * factor],
                .none => return error.InvalidPolyphaseIirOversamplerState,
            };
        }

        pub fn downsample(
            self: *Self,
            output: []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidPolyphaseIirOversamplerState;
            if (self.pending_frames == 0)
                return error.NoOversampledBlock;
            if (output.len != self.pending_frames)
                return error.PolyphaseIirOversamplingFrameMismatch;

            const high_rate_length = self.pending_frames * factor;
            const active =
                switch (self.pending_buffer) {
                    .first => self.first_buffer[0..high_rate_length],
                    .second => self.second_buffer[0..high_rate_length],
                    .none => return error.InvalidPolyphaseIirOversamplerState,
                };
            for (active) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFinitePolyphaseIirOversamplingInput;
            }

            errdefer self.reset();
            var source: []Sample = active;
            var source_is_first =
                self.pending_buffer == .first;
            inline for (0..stage_count) |reverse_index| {
                const stage_index = stage_count - 1 - reverse_index;
                const output_length = source.len / 2;
                const destination =
                    if (source_is_first)
                        self.second_buffer[0..output_length]
                    else
                        self.first_buffer[0..output_length];
                try self.decimation_stages[stage_index]
                    .decimate(source, destination);
                source = destination;
                source_is_first = !source_is_first;
            }

            if (self.use_integer_latency)
                try self.latency_compensator.processBlock(source);
            @memcpy(output, source);
            self.pending_frames = 0;
            self.pending_buffer = .none;
        }

        pub fn pendingHighRate(self: *Self) ![]Sample {
            if (!self.valid())
                return error.InvalidPolyphaseIirOversamplerState;
            if (self.pending_frames == 0)
                return error.NoOversampledBlock;
            const length = self.pending_frames * factor;
            return switch (self.pending_buffer) {
                .first => self.first_buffer[0..length],
                .second => self.second_buffer[0..length],
                .none => error.InvalidPolyphaseIirOversamplerState,
            };
        }

        pub fn valid(self: *const Self) bool {
            if (self.pending_frames > maximum_frames)
                return false;
            if ((self.pending_frames == 0) !=
                (self.pending_buffer == .none))
                return false;
            for (
                self.designs,
                self.interpolation_stages,
                self.decimation_stages,
            ) |design, interpolation, decimation| {
                if (!design.valid() or
                    !interpolation.valid(design) or
                    !decimation.valid(design))
                    return false;
            }
            if (!self.latency_compensator.valid())
                return false;
            return true;
        }

        fn latencyForDesigns(
            designs: [stage_count]Design,
        ) f64 {
            var result: f64 = 0.0;
            var rate_scale: f64 = 1.0;
            for (designs) |design| {
                var half_band_delay: f64 = 0.5;
                for (design.alpha[0..design.section_count]) |
                    coefficient,
                | {
                    const alpha: f64 = @floatCast(coefficient);
                    half_band_delay +=
                        (1.0 - alpha) / (1.0 + alpha);
                }
                result += half_band_delay / rate_scale;
                rate_scale *= 2.0;
            }
            return result;
        }
    };
}

pub fn RuntimeOversampler(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime maximum_stages: usize,
) type {
    requireSampleType(Sample);
    if (maximum_frames == 0)
        @compileError(
            "runtime polyphase IIR oversampling frame capacity must be nonzero",
        );
    if (maximum_stages == 0 or maximum_stages > 8)
        @compileError(
            "runtime polyphase IIR oversampling supports 1 through 8 stages",
        );

    const maximum_factor = @as(usize, 1) << maximum_stages;
    const Design = polyphase_iir.Design(Sample);
    const Stage = HalfBandStage(Sample);
    const Compensator = FractionalAllpass(Sample);

    return struct {
        const Self = @This();

        const PendingBuffer = enum {
            none,
            first,
            second,
        };

        pub const maximum_base_rate_frames = maximum_frames;
        pub const maximum_stage_count = maximum_stages;
        pub const maximum_oversampling_factor = maximum_factor;

        designs: [maximum_stages]Design = undefined,
        interpolation_stages: [maximum_stages]Stage = undefined,
        decimation_stages: [maximum_stages]Stage = undefined,
        latency_compensator: Compensator,
        use_integer_latency: bool,
        stage_count: usize,
        first_buffer: [maximum_frames * maximum_factor]Sample = undefined,
        second_buffer: [maximum_frames * maximum_factor]Sample = undefined,
        pending_frames: usize = 0,
        pending_buffer: PendingBuffer = .none,

        pub fn init(
            configs: []const Config,
        ) !Self {
            return initWithOptions(configs, .{});
        }

        pub fn initWithOptions(
            configs: []const Config,
            options: Options,
        ) !Self {
            if (configs.len > maximum_stages)
                return error.TooManyPolyphaseIirOversamplingStages;

            var result = Self{
                .latency_compensator = try Compensator.init(0.0),
                .use_integer_latency = options.use_integer_latency,
                .stage_count = configs.len,
            };
            for (configs, 0..) |config, index| {
                const design = try designForRuntimeConfig(config);
                const stage = try Stage.init(design);
                result.designs[index] = design;
                result.interpolation_stages[index] = stage;
                result.decimation_stages[index] = stage;
            }
            const natural_latency = result.naturalLatency();
            const compensation =
                if (options.use_integer_latency)
                    @ceil(natural_latency) - natural_latency
                else
                    0.0;
            result.latency_compensator =
                try Compensator.init(compensation);
            return result;
        }

        pub fn reconfigure(
            self: *Self,
            configs: []const Config,
            options: Options,
        ) !void {
            if (!self.valid())
                return error.InvalidPolyphaseIirOversamplerState;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            const replacement = try Self.initWithOptions(
                configs,
                options,
            );
            self.* = replacement;
        }

        pub fn reset(self: *Self) void {
            const active_count = @min(
                self.stage_count,
                maximum_stages,
            );
            for (self.interpolation_stages[0..active_count]) |*stage|
                stage.reset();
            for (self.decimation_stages[0..active_count]) |*stage|
                stage.reset();
            self.latency_compensator.reset();
            self.pending_frames = 0;
            self.pending_buffer = .none;
        }

        pub fn oversamplingFactor(self: *const Self) !usize {
            if (!self.valid())
                return error.InvalidPolyphaseIirOversamplerState;
            return @as(usize, 1) << @intCast(self.stage_count);
        }

        pub fn latencySamples(self: *const Self) !f64 {
            if (!self.valid())
                return error.InvalidPolyphaseIirOversamplerState;
            const natural_latency = self.naturalLatency();
            return if (self.use_integer_latency)
                @ceil(natural_latency)
            else
                natural_latency;
        }

        pub fn upsample(
            self: *Self,
            input: []const Sample,
        ) ![]Sample {
            if (!self.valid())
                return error.InvalidPolyphaseIirOversamplerState;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            if (input.len > maximum_frames)
                return error.PolyphaseIirOversamplingCapacityExceeded;
            for (input) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFinitePolyphaseIirOversamplingInput;
            }
            if (input.len == 0) return self.first_buffer[0..0];

            errdefer self.reset();
            if (self.stage_count == 0) {
                @memcpy(self.first_buffer[0..input.len], input);
                self.pending_frames = input.len;
                self.pending_buffer = .first;
                return self.first_buffer[0..input.len];
            }

            var source: []const Sample = input;
            for (
                self.interpolation_stages[0..self.stage_count],
                0..,
            ) |*stage, stage_index| {
                const output_length = source.len * 2;
                const destination =
                    if (stage_index % 2 == 0)
                        self.first_buffer[0..output_length]
                    else
                        self.second_buffer[0..output_length];
                try stage.interpolate(source, destination);
                source = destination;
            }

            const factor = @as(usize, 1) <<
                @intCast(self.stage_count);
            self.pending_frames = input.len;
            self.pending_buffer =
                if (self.stage_count % 2 == 1) .first else .second;
            return switch (self.pending_buffer) {
                .first => self.first_buffer[0 .. input.len * factor],
                .second => self.second_buffer[0 .. input.len * factor],
                .none => return error.InvalidPolyphaseIirOversamplerState,
            };
        }

        pub fn downsample(
            self: *Self,
            output: []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidPolyphaseIirOversamplerState;
            if (self.pending_frames == 0)
                return error.NoOversampledBlock;
            if (output.len != self.pending_frames)
                return error.PolyphaseIirOversamplingFrameMismatch;

            const factor = @as(usize, 1) <<
                @intCast(self.stage_count);
            const high_rate_length = self.pending_frames * factor;
            const active = switch (self.pending_buffer) {
                .first => self.first_buffer[0..high_rate_length],
                .second => self.second_buffer[0..high_rate_length],
                .none => return error.InvalidPolyphaseIirOversamplerState,
            };
            for (active) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFinitePolyphaseIirOversamplingInput;
            }

            errdefer self.reset();
            var source: []Sample = active;
            var source_is_first =
                self.pending_buffer == .first;
            var reverse_index: usize = 0;
            while (reverse_index < self.stage_count) : (reverse_index += 1) {
                const stage_index =
                    self.stage_count - 1 - reverse_index;
                const output_length = source.len / 2;
                const destination =
                    if (source_is_first)
                        self.second_buffer[0..output_length]
                    else
                        self.first_buffer[0..output_length];
                try self.decimation_stages[stage_index]
                    .decimate(source, destination);
                source = destination;
                source_is_first = !source_is_first;
            }

            if (self.use_integer_latency)
                try self.latency_compensator.processBlock(source);
            @memcpy(output, source);
            self.pending_frames = 0;
            self.pending_buffer = .none;
        }

        pub fn pendingHighRate(self: *Self) ![]Sample {
            if (!self.valid())
                return error.InvalidPolyphaseIirOversamplerState;
            if (self.pending_frames == 0)
                return error.NoOversampledBlock;
            const factor = @as(usize, 1) <<
                @intCast(self.stage_count);
            const length = self.pending_frames * factor;
            return switch (self.pending_buffer) {
                .first => self.first_buffer[0..length],
                .second => self.second_buffer[0..length],
                .none => error.InvalidPolyphaseIirOversamplerState,
            };
        }

        pub fn valid(self: *const Self) bool {
            if (self.stage_count > maximum_stages or
                self.pending_frames > maximum_frames)
                return false;
            if ((self.pending_frames == 0) !=
                (self.pending_buffer == .none))
                return false;
            for (
                self.designs[0..self.stage_count],
                self.interpolation_stages[0..self.stage_count],
                self.decimation_stages[0..self.stage_count],
            ) |design, interpolation, decimation| {
                if (!design.valid() or
                    !interpolation.valid(design) or
                    !decimation.valid(design))
                    return false;
            }
            return self.latency_compensator.valid();
        }

        fn naturalLatency(self: *const Self) f64 {
            var result: f64 = 0.0;
            var rate_scale: f64 = 1.0;
            for (self.designs[0..self.stage_count]) |design| {
                var half_band_delay: f64 = 0.5;
                for (design.alpha[0..design.section_count]) |
                    coefficient,
                | {
                    const alpha: f64 = @floatCast(coefficient);
                    half_band_delay +=
                        (1.0 - alpha) / (1.0 + alpha);
                }
                result += half_band_delay / rate_scale;
                rate_scale *= 2.0;
            }
            return result;
        }

        fn designForRuntimeConfig(config: Config) !Design {
            const transition: Sample =
                @floatCast(config.normalized_transition_width);
            const attenuation: Sample =
                @floatCast(config.stopband_attenuation_db);
            if (!std.math.isFinite(transition) or
                !std.math.isFinite(attenuation))
                return error.InvalidPolyphaseIirOversamplingConfig;
            return polyphase_iir.Designer(Sample).halfBandLowPass(
                transition,
                attenuation,
            ) catch |design_error| switch (design_error) {
                error.InvalidPolyphaseAllpassTransitionWidth,
                error.InvalidPolyphaseAllpassStopband,
                => error.InvalidPolyphaseIirOversamplingConfig,
                else => design_error,
            };
        }
    };
}

fn FractionalAllpass(comptime Sample: type) type {
    return struct {
        const Self = @This();

        coefficient: Sample,
        previous_input: Sample = 0.0,
        previous_output: Sample = 0.0,

        fn init(delay_samples: f64) !Self {
            if (!std.math.isFinite(delay_samples) or
                delay_samples < 0.0 or
                delay_samples >= 1.0)
                return error.InvalidPolyphaseIirLatencyCompensation;
            const coefficient: Sample = @floatCast(
                (1.0 - delay_samples) / (1.0 + delay_samples),
            );
            return .{ .coefficient = coefficient };
        }

        fn reset(self: *Self) void {
            self.previous_input = 0.0;
            self.previous_output = 0.0;
        }

        fn processBlock(
            self: *Self,
            samples: []Sample,
        ) !void {
            for (samples) |*sample| {
                const output =
                    self.coefficient * sample.* +
                    self.previous_input -
                    self.coefficient * self.previous_output;
                if (!std.math.isFinite(output))
                    return error.NonFinitePolyphaseIirOversamplingOutput;
                self.previous_input = sample.*;
                self.previous_output = output;
                sample.* = output;
            }
        }

        fn valid(self: Self) bool {
            return std.math.isFinite(self.coefficient) and
                self.coefficient >= 0.0 and
                self.coefficient <= 1.0 and
                std.math.isFinite(self.previous_input) and
                std.math.isFinite(self.previous_output);
        }
    };
}

pub fn HalfBandProcessor(comptime Sample: type) type {
    const Design = polyphase_iir.Design(Sample);

    return struct {
        const Self = @This();

        const FirstOrderAllpass = struct {
            alpha: Sample = 0.0,
            previous_input: Sample = 0.0,
            previous_output: Sample = 0.0,

            fn process(self: *FirstOrderAllpass, input: Sample) Sample {
                const output =
                    self.alpha * input +
                    self.previous_input -
                    self.alpha * self.previous_output;
                self.previous_input = input;
                self.previous_output = output;
                return output;
            }

            fn reset(self: *FirstOrderAllpass) void {
                self.previous_input = 0.0;
                self.previous_output = 0.0;
            }

            fn valid(self: FirstOrderAllpass) bool {
                return std.math.isFinite(self.alpha) and
                    std.math.isFinite(self.previous_input) and
                    std.math.isFinite(self.previous_output);
            }
        };

        direct: [polyphase_iir.maximum_sections]FirstOrderAllpass =
            @splat(.{}),
        delayed: [polyphase_iir.maximum_sections]FirstOrderAllpass =
            @splat(.{}),
        direct_count: usize = 0,
        delayed_count: usize = 0,
        previous_delayed: Sample = 0.0,

        pub fn init(design: Design) !Self {
            if (!design.valid())
                return error.InvalidPolyphaseAllpassDesign;
            var result: Self = .{
                .direct_count = design.directSectionCount(),
                .delayed_count = design.delayedSectionCount(),
            };
            for (0..result.direct_count) |index| {
                result.direct[index].alpha =
                    design.directAlpha(index) orelse
                    return error.InvalidPolyphaseAllpassDesign;
            }
            for (0..result.delayed_count) |index| {
                result.delayed[index].alpha =
                    design.delayedAlpha(index) orelse
                    return error.InvalidPolyphaseAllpassDesign;
            }
            return result;
        }

        pub fn reset(self: *Self) void {
            for (&self.direct) |*section| section.reset();
            for (&self.delayed) |*section| section.reset();
            self.previous_delayed = 0.0;
        }

        pub fn interpolate(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (output.len != input.len * 2)
                return error.PolyphaseIirOversamplingFrameMismatch;
            for (input, 0..) |sample, frame| {
                var direct = sample;
                var delayed = sample;
                for (self.direct[0..self.direct_count]) |*section|
                    direct = section.process(direct);
                for (self.delayed[0..self.delayed_count]) |*section|
                    delayed = section.process(delayed);
                if (!std.math.isFinite(direct) or
                    !std.math.isFinite(delayed))
                    return error.NonFinitePolyphaseIirOversamplingOutput;
                output[frame * 2] = direct;
                output[frame * 2 + 1] = delayed;
            }
        }

        pub fn decimate(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len * 2)
                return error.PolyphaseIirOversamplingFrameMismatch;
            for (output, 0..) |*sample, frame| {
                var direct = input[frame * 2];
                var delayed = input[frame * 2 + 1];
                for (self.direct[0..self.direct_count]) |*section|
                    direct = section.process(direct);
                for (self.delayed[0..self.delayed_count]) |*section|
                    delayed = section.process(delayed);
                const combined =
                    (direct + self.previous_delayed) * 0.5;
                self.previous_delayed = delayed;
                if (!std.math.isFinite(combined))
                    return error.NonFinitePolyphaseIirOversamplingOutput;
                sample.* = combined;
            }
        }

        pub fn valid(self: Self, design: Design) bool {
            if (self.direct_count != design.directSectionCount() or
                self.delayed_count != design.delayedSectionCount() or
                !std.math.isFinite(self.previous_delayed))
                return false;
            for (self.direct, 0..) |section, index| {
                if (!section.valid()) return false;
                if (index < self.direct_count) {
                    const alpha =
                        design.directAlpha(index) orelse return false;
                    if (section.alpha != alpha)
                        return false;
                } else if (section.alpha != 0.0) {
                    return false;
                }
            }
            for (self.delayed, 0..) |section, index| {
                if (!section.valid()) return false;
                if (index < self.delayed_count) {
                    const alpha =
                        design.delayedAlpha(index) orelse return false;
                    if (section.alpha != alpha)
                        return false;
                } else if (section.alpha != 0.0) {
                    return false;
                }
            }
            return true;
        }
    };
}

const HalfBandStage = HalfBandProcessor;

fn requireSampleType(comptime Sample: type) void {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "polyphase IIR oversampling supports f32 and f64 samples",
        );
}

test "polyphase IIR oversampling preserves steady gain at every factor" {
    inline for (.{ 2, 4, 8, 16 }) |current_factor| {
        const Processor = Oversampler(f64, 64, current_factor);
        var processor = try Processor.init(.{
            .normalized_transition_width = 0.08,
            .stopband_attenuation_db = -90.0,
        });
        var input: [64]f64 = @splat(0.25);
        var output: [64]f64 = undefined;
        for (0..16) |_| {
            const high_rate = try processor.upsample(&input);
            for (high_rate) |sample|
                try std.testing.expect(std.math.isFinite(sample));
            try processor.downsample(&output);
        }
        try std.testing.expectApproxEqAbs(
            @as(f64, 0.25),
            output[output.len - 1],
            1.0e-9,
        );
        try std.testing.expect(
            (try processor.latencySamples()) > 0.0,
        );
    }
}

test "polyphase IIR oversampling is partition independent" {
    const Processor = Oversampler(f64, 257, 8);
    var input: [257]f64 = undefined;
    for (&input, 0..) |*sample, index| {
        const position: f64 = @floatFromInt(index);
        sample.* =
            0.5 * @sin(std.math.tau * 0.031 * position) +
            0.2 * @cos(std.math.tau * 0.19 * position);
    }

    var whole = try Processor.init(.{});
    _ = try whole.upsample(&input);
    var whole_output: [257]f64 = undefined;
    try whole.downsample(&whole_output);

    var partitioned = try Processor.init(.{});
    _ = try partitioned.upsample(input[0..17]);
    var partitioned_output: [257]f64 = undefined;
    try partitioned.downsample(partitioned_output[0..17]);
    _ = try partitioned.upsample(input[17..103]);
    try partitioned.downsample(partitioned_output[17..103]);
    _ = try partitioned.upsample(input[103..]);
    try partitioned.downsample(partitioned_output[103..]);
    try std.testing.expectEqualSlices(
        f64,
        &whole_output,
        &partitioned_output,
    );
}

test "polyphase IIR oversampling accepts independent stage specifications" {
    const Processor = Oversampler(f64, 32, 8);
    var processor = try Processor.initStages(.{
        .{
            .normalized_transition_width = 0.16,
            .stopband_attenuation_db = -60.0,
        },
        .{
            .normalized_transition_width = 0.1,
            .stopband_attenuation_db = -80.0,
        },
        .{
            .normalized_transition_width = 0.06,
            .stopband_attenuation_db = -100.0,
        },
    });
    try std.testing.expect(
        processor.designs[0].section_count <
            processor.designs[2].section_count,
    );
    var input: [32]f64 = @splat(0.25);
    _ = try processor.upsample(&input);
    var output: [32]f64 = undefined;
    try processor.downsample(&output);
    for (output) |sample|
        try std.testing.expect(std.math.isFinite(sample));

    try std.testing.expectError(
        error.InvalidPolyphaseIirOversamplingConfig,
        Processor.initStages(.{
            .{},
            .{ .normalized_transition_width = 0.0 },
            .{},
        }),
    );
}

test "polyphase IIR reported latency matches impulse group delay" {
    const Processor = Oversampler(f64, 256, 8);
    var processor = try Processor.init(.{
        .normalized_transition_width = 0.1,
        .stopband_attenuation_db = -80.0,
    });
    const reported_latency = try processor.latencySamples();
    var input: [256]f64 = @splat(0.0);
    var output: [256]f64 = undefined;
    var response_sum: f64 = 0.0;
    var response_moment: f64 = 0.0;
    var output_index: usize = 0;
    for (0..64) |block| {
        input[0] = if (block == 0) 1.0 else 0.0;
        _ = try processor.upsample(&input);
        try processor.downsample(&output);
        for (output) |sample| {
            response_sum += sample;
            response_moment +=
                sample *
                @as(f64, @floatFromInt(output_index));
            output_index += 1;
        }
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        response_sum,
        1.0e-10,
    );
    try std.testing.expectApproxEqAbs(
        reported_latency,
        response_moment / response_sum,
        1.0e-8,
    );
}

test "polyphase IIR integer latency matches impulse group delay" {
    const Processor = Oversampler(f64, 256, 8);
    var processor = try Processor.initWithOptions(
        .{
            .normalized_transition_width = 0.1,
            .stopband_attenuation_db = -80.0,
        },
        .{ .use_integer_latency = true },
    );
    const reported_latency = try processor.latencySamples();
    try std.testing.expectEqual(@ceil(reported_latency), reported_latency);
    var input: [256]f64 = @splat(0.0);
    var output: [256]f64 = undefined;
    var response_sum: f64 = 0.0;
    var response_moment: f64 = 0.0;
    var output_index: usize = 0;
    for (0..64) |block| {
        input[0] = if (block == 0) 1.0 else 0.0;
        _ = try processor.upsample(&input);
        try processor.downsample(&output);
        for (output) |sample| {
            response_sum += sample;
            response_moment +=
                sample *
                @as(f64, @floatFromInt(output_index));
            output_index += 1;
        }
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        response_sum,
        1.0e-10,
    );
    try std.testing.expectApproxEqAbs(
        reported_latency,
        response_moment / response_sum,
        1.0e-8,
    );
}

test "polyphase IIR decimation rejects high-rate stopband energy" {
    const Processor = Oversampler(f64, 256, 2);
    var processor = try Processor.init(.{
        .normalized_transition_width = 0.1,
        .stopband_attenuation_db = -80.0,
    });
    var zero_input: [256]f64 = @splat(0.0);
    var output: [256]f64 = undefined;
    var maximum_tail: f64 = 0.0;
    var high_rate_position: usize = 0;
    for (0..16) |block| {
        const high_rate = try processor.upsample(&zero_input);
        for (high_rate) |*sample| {
            sample.* = @sin(
                std.math.tau *
                    0.4 *
                    @as(f64, @floatFromInt(high_rate_position)),
            );
            high_rate_position += 1;
        }
        try processor.downsample(&output);
        if (block >= 8) {
            for (output) |sample|
                maximum_tail = @max(maximum_tail, @abs(sample));
        }
    }
    try std.testing.expect(maximum_tail < 0.000_11);
}

test "polyphase IIR oversampling sequencing is transactional" {
    const Processor = Oversampler(f32, 8, 4);
    try std.testing.expectError(
        error.InvalidPolyphaseIirOversamplingConfig,
        Processor.init(.{
            .normalized_transition_width = 0.0,
        }),
    );

    var processor = try Processor.init(.{});
    try std.testing.expectError(
        error.PolyphaseIirOversamplingCapacityExceeded,
        processor.upsample(&([_]f32{0.0} ** 9)),
    );
    try std.testing.expectEqual(@as(usize, 0), processor.pending_frames);
    var invalid = [_]f32{ 0.0, std.math.nan(f32) };
    try std.testing.expectError(
        error.NonFinitePolyphaseIirOversamplingInput,
        processor.upsample(&invalid),
    );
    try std.testing.expectEqual(@as(usize, 0), processor.pending_frames);

    var input: [8]f32 = @splat(0.25);
    const high_rate = try processor.upsample(&input);
    try std.testing.expectEqual(@as(usize, 32), high_rate.len);
    try std.testing.expectError(
        error.OversampledBlockPending,
        processor.upsample(&input),
    );
    var short_output: [7]f32 = undefined;
    try std.testing.expectError(
        error.PolyphaseIirOversamplingFrameMismatch,
        processor.downsample(&short_output),
    );
    try std.testing.expectEqual(
        input.len,
        processor.pending_frames,
    );
    high_rate[3] = std.math.inf(f32);
    var output: [8]f32 = undefined;
    try std.testing.expectError(
        error.NonFinitePolyphaseIirOversamplingInput,
        processor.downsample(&output),
    );
    try std.testing.expectEqual(
        input.len,
        processor.pending_frames,
    );
    processor.reset();
    try std.testing.expect(processor.valid());
}

test "polyphase IIR oversampler contains hostile public state" {
    const Processor = Oversampler(f64, 16, 2);
    var processor = try Processor.init(.{});
    processor.pending_frames = 1;
    try std.testing.expect(!processor.valid());
    try std.testing.expectError(
        error.InvalidPolyphaseIirOversamplerState,
        processor.upsample(&.{}),
    );
    processor.reset();
    processor.interpolation_stages[0]
        .direct[0].previous_output = std.math.inf(f64);
    try std.testing.expect(!processor.valid());
    processor.reset();
    try std.testing.expect(processor.valid());
}

test "runtime polyphase IIR stages match fixed-factor processing" {
    const Fixed = Oversampler(f64, 17, 4);
    const Runtime = RuntimeOversampler(f64, 17, 4);
    const configs = [_]Config{
        .{
            .normalized_transition_width = 0.14,
            .stopband_attenuation_db = -70.0,
        },
        .{
            .normalized_transition_width = 0.08,
            .stopband_attenuation_db = -90.0,
        },
    };
    var fixed = try Fixed.initStages(configs);
    var runtime = try Runtime.init(&configs);
    try std.testing.expectEqual(
        @as(usize, 4),
        try runtime.oversamplingFactor(),
    );
    try std.testing.expectEqual(
        try fixed.latencySamples(),
        try runtime.latencySamples(),
    );

    var input: [17]f64 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* = @sin(
            std.math.tau * 0.07 *
                @as(f64, @floatFromInt(index)),
        );
    }
    const fixed_high_rate = try fixed.upsample(&input);
    const runtime_high_rate = try runtime.upsample(&input);
    try std.testing.expectEqualSlices(
        f64,
        fixed_high_rate,
        runtime_high_rate,
    );
    for (fixed_high_rate, runtime_high_rate) |
        *fixed_sample,
        *runtime_sample,
    | {
        fixed_sample.* *= 0.75;
        runtime_sample.* *= 0.75;
    }
    var fixed_output: [17]f64 = undefined;
    var runtime_output: [17]f64 = undefined;
    try fixed.downsample(&fixed_output);
    try runtime.downsample(&runtime_output);
    try std.testing.expectEqualSlices(
        f64,
        &fixed_output,
        &runtime_output,
    );
}

test "runtime polyphase IIR reconfiguration is transactional" {
    const Runtime = RuntimeOversampler(f32, 8, 4);
    var runtime = try Runtime.init(&.{});
    try std.testing.expectEqual(
        @as(usize, 1),
        try runtime.oversamplingFactor(),
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        try runtime.latencySamples(),
    );

    const input = [_]f32{ -0.5, 0.0, 0.25, 1.0 };
    const direct = try runtime.upsample(&input);
    for (direct) |*sample| sample.* *= 0.5;
    var output: [4]f32 = undefined;
    try runtime.downsample(&output);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ -0.25, 0.0, 0.125, 0.5 },
        &output,
    );

    const stages = [_]Config{ .{}, .{}, .{} };
    try runtime.reconfigure(
        &stages,
        .{ .use_integer_latency = true },
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        try runtime.oversamplingFactor(),
    );
    const latency = try runtime.latencySamples();
    try std.testing.expectEqual(@ceil(latency), latency);
    _ = try runtime.upsample(&input);
    try std.testing.expectError(
        error.OversampledBlockPending,
        runtime.reconfigure(&.{}, .{}),
    );
    try runtime.downsample(&output);

    try std.testing.expectError(
        error.InvalidPolyphaseIirOversamplingConfig,
        runtime.reconfigure(
            &.{.{ .normalized_transition_width = 0.0 }},
            .{},
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        try runtime.oversamplingFactor(),
    );
    try std.testing.expectError(
        error.TooManyPolyphaseIirOversamplingStages,
        runtime.reconfigure(&([_]Config{.{}} ** 5), .{}),
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        try runtime.oversamplingFactor(),
    );
}

test "runtime polyphase IIR validates tail and public state" {
    const Runtime = RuntimeOversampler(f64, 16, 3);
    var runtime = try Runtime.init(&.{.{}});
    var input: [7]f64 = @splat(0.25);
    const high_rate = try runtime.upsample(&input);
    try std.testing.expectEqual(@as(usize, 14), high_rate.len);
    high_rate[13] = std.math.inf(f64);
    var output: [7]f64 = undefined;
    try std.testing.expectError(
        error.NonFinitePolyphaseIirOversamplingInput,
        runtime.downsample(&output),
    );
    try std.testing.expectEqual(@as(usize, 7), runtime.pending_frames);
    runtime.reset();
    runtime.stage_count = 4;
    try std.testing.expect(!runtime.valid());
    runtime.reset();
    try std.testing.expect(!runtime.valid());
    try std.testing.expectError(
        error.InvalidPolyphaseIirOversamplerState,
        runtime.upsample(&input),
    );
}
