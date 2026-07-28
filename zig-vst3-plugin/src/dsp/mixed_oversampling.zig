const std = @import("std");
const equiripple = @import("equiripple_design.zig");
const fir = @import("fir.zig");
const fir_design = @import("fir_design.zig");
const polyphase_iir = @import("polyphase_iir.zig");
const polyphase_oversampling =
    @import("polyphase_iir_oversampling.zig");

pub const FilterSpec = struct {
    normalized_transition_width: f64 = 0.1,
    stopband_attenuation_db: f64 = -90.0,
};

pub const DirectionalConfig = struct {
    up: FilterSpec = .{},
    down: FilterSpec = .{},
};

pub const StageConfig = union(enum) {
    dummy,
    fir_equiripple: DirectionalConfig,
    polyphase_iir: DirectionalConfig,
};

pub const Options = struct {
    use_integer_latency: bool = false,
};

pub fn Oversampler(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime maximum_stages: usize,
) type {
    requireSampleType(Sample);
    if (maximum_frames == 0)
        @compileError("mixed oversampling frame capacity must be nonzero");
    if (maximum_stages == 0 or maximum_stages > 8)
        @compileError("mixed oversampling supports 1 through 8 stages");

    const maximum_factor = @as(usize, 1) << maximum_stages;
    const Stage = MixedStage(Sample);
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

        stages: [maximum_stages]Stage = undefined,
        stage_count: usize,
        real_stage_count: usize,
        latency_compensator: Compensator,
        use_integer_latency: bool,
        first_buffer: [maximum_frames * maximum_factor]Sample = undefined,
        second_buffer: [maximum_frames * maximum_factor]Sample = undefined,
        pending_frames: usize = 0,
        pending_buffer: PendingBuffer = .none,

        pub fn init(configs: []const StageConfig) !Self {
            return initWithOptions(configs, .{});
        }

        pub fn initWithOptions(
            configs: []const StageConfig,
            options: Options,
        ) !Self {
            if (configs.len > maximum_stages)
                return error.TooManyOversamplingStages;
            var result = Self{
                .stage_count = configs.len,
                .real_stage_count = 0,
                .latency_compensator = try Compensator.init(0.0),
                .use_integer_latency = options.use_integer_latency,
            };
            for (configs, 0..) |config, index| {
                result.stages[index] = try Stage.init(config);
                result.real_stage_count +=
                    @intFromBool(config != .dummy);
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
            configs: []const StageConfig,
            options: Options,
        ) !void {
            if (!self.valid())
                return error.InvalidMixedOversamplerState;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            self.* = try Self.initWithOptions(configs, options);
        }

        pub fn reset(self: *Self) void {
            const active_count = @min(
                self.stage_count,
                maximum_stages,
            );
            for (self.stages[0..active_count]) |*stage|
                stage.reset();
            self.latency_compensator.reset();
            self.pending_frames = 0;
            self.pending_buffer = .none;
        }

        pub fn oversamplingFactor(self: *const Self) !usize {
            if (!self.valid())
                return error.InvalidMixedOversamplerState;
            return @as(usize, 1) <<
                @intCast(self.real_stage_count);
        }

        pub fn latencySamples(self: *const Self) !f64 {
            if (!self.valid())
                return error.InvalidMixedOversamplerState;
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
                return error.InvalidMixedOversamplerState;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            if (input.len > maximum_frames)
                return error.OversamplingCapacityExceeded;
            for (input) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFiniteOversamplingInput;
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
            for (self.stages[0..self.stage_count], 0..) |
                *stage,
                index,
            | {
                const output_length = stage.interpolatedLength(source.len);
                const destination =
                    if (index % 2 == 0)
                        self.first_buffer[0..output_length]
                    else
                        self.second_buffer[0..output_length];
                try stage.interpolate(source, destination);
                source = destination;
            }
            self.pending_frames = input.len;
            self.pending_buffer =
                if (self.stage_count % 2 == 1) .first else .second;
            return switch (self.pending_buffer) {
                .first => self.first_buffer[0..source.len],
                .second => self.second_buffer[0..source.len],
                .none => return error.InvalidMixedOversamplerState,
            };
        }

        pub fn downsample(
            self: *Self,
            output: []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidMixedOversamplerState;
            if (self.pending_frames == 0)
                return error.NoOversampledBlock;
            if (output.len != self.pending_frames)
                return error.OversamplingFrameMismatch;
            const factor = @as(usize, 1) <<
                @intCast(self.real_stage_count);
            const high_rate_length = self.pending_frames * factor;
            const active = switch (self.pending_buffer) {
                .first => self.first_buffer[0..high_rate_length],
                .second => self.second_buffer[0..high_rate_length],
                .none => return error.InvalidMixedOversamplerState,
            };
            for (active) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFiniteOversamplingInput;
            }

            errdefer self.reset();
            var source: []Sample = active;
            var source_is_first =
                self.pending_buffer == .first;
            var reverse_index: usize = 0;
            while (reverse_index < self.stage_count) : (reverse_index += 1) {
                const stage_index =
                    self.stage_count - 1 - reverse_index;
                const output_length =
                    self.stages[stage_index].decimatedLength(source.len);
                const destination =
                    if (source_is_first)
                        self.second_buffer[0..output_length]
                    else
                        self.first_buffer[0..output_length];
                try self.stages[stage_index].decimate(
                    source,
                    destination,
                );
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
                return error.InvalidMixedOversamplerState;
            if (self.pending_frames == 0)
                return error.NoOversampledBlock;
            const factor = @as(usize, 1) <<
                @intCast(self.real_stage_count);
            const length = self.pending_frames * factor;
            return switch (self.pending_buffer) {
                .first => self.first_buffer[0..length],
                .second => self.second_buffer[0..length],
                .none => error.InvalidMixedOversamplerState,
            };
        }

        pub fn valid(self: *const Self) bool {
            if (self.stage_count > maximum_stages or
                self.real_stage_count > self.stage_count or
                self.pending_frames > maximum_frames)
                return false;
            if ((self.pending_frames == 0) !=
                (self.pending_buffer == .none))
                return false;
            var counted_real_stages: usize = 0;
            for (self.stages[0..self.stage_count]) |stage| {
                if (!stage.valid()) return false;
                counted_real_stages += @intFromBool(!stage.isDummy());
            }
            return counted_real_stages == self.real_stage_count and
                self.latency_compensator.valid();
        }

        fn naturalLatency(self: *const Self) f64 {
            var result: f64 = 0.0;
            var rate_scale: f64 = 1.0;
            for (self.stages[0..self.stage_count]) |stage| {
                result += stage.latency() / rate_scale;
                if (!stage.isDummy()) rate_scale *= 2.0;
            }
            return result;
        }
    };
}

pub fn MultichannelOversampler(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime maximum_stages: usize,
    comptime maximum_channels: usize,
) type {
    if (maximum_channels == 0)
        @compileError("mixed multichannel oversampling requires channels");
    const ChannelProcessor = Oversampler(
        Sample,
        maximum_frames,
        maximum_stages,
    );

    return struct {
        const Self = @This();

        pub const maximum_channel_count = maximum_channels;
        pub const maximum_stage_count = maximum_stages;
        pub const maximum_oversampling_factor =
            ChannelProcessor.maximum_oversampling_factor;

        processors: [maximum_channels]ChannelProcessor,
        high_rate_views: [maximum_channels][]Sample = undefined,
        output_scratch: [maximum_channels][maximum_frames]Sample = undefined,
        channel_count: usize,
        pending_frames: usize = 0,

        pub fn init(
            channel_count: usize,
            configs: []const StageConfig,
        ) !Self {
            return initWithOptions(channel_count, configs, .{});
        }

        pub fn initWithOptions(
            channel_count: usize,
            configs: []const StageConfig,
            options: Options,
        ) !Self {
            if (channel_count == 0 or
                channel_count > maximum_channels)
                return error.InvalidOversamplingChannelCount;
            const prototype = try ChannelProcessor.initWithOptions(
                configs,
                options,
            );
            return .{
                .processors = @splat(prototype),
                .channel_count = channel_count,
            };
        }

        pub fn reconfigure(
            self: *Self,
            configs: []const StageConfig,
            options: Options,
        ) !void {
            if (!self.valid())
                return error.InvalidMixedMultichannelOversamplerState;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            const prototype = try ChannelProcessor.initWithOptions(
                configs,
                options,
            );
            self.processors = @splat(prototype);
        }

        pub fn setChannelCount(
            self: *Self,
            channel_count: usize,
        ) !void {
            if (channel_count == 0 or
                channel_count > maximum_channels)
                return error.InvalidOversamplingChannelCount;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            self.channel_count = channel_count;
            self.reset();
        }

        pub fn reset(self: *Self) void {
            for (&self.processors) |*processor| processor.reset();
            self.pending_frames = 0;
        }

        pub fn oversamplingFactor(self: *const Self) !usize {
            if (!self.valid())
                return error.InvalidMixedMultichannelOversamplerState;
            return self.processors[0].oversamplingFactor();
        }

        pub fn latencySamples(self: *const Self) !f64 {
            if (!self.valid())
                return error.InvalidMixedMultichannelOversamplerState;
            return self.processors[0].latencySamples();
        }

        pub fn upsample(
            self: *Self,
            input: []const []const Sample,
        ) ![]const []Sample {
            try self.validateInput(input);
            errdefer self.reset();
            for (input, 0..) |channel_samples, index| {
                self.high_rate_views[index] =
                    try self.processors[index].upsample(
                        channel_samples,
                    );
            }
            self.pending_frames = input[0].len;
            return self.high_rate_views[0..self.channel_count];
        }

        pub fn downsample(
            self: *Self,
            output: []const []Sample,
        ) !void {
            try self.validateOutput(output);
            for (self.processors[0..self.channel_count]) |*processor| {
                const high_rate = try processor.pendingHighRate();
                for (high_rate) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.NonFiniteOversamplingInput;
                }
            }

            errdefer self.reset();
            for (0..self.channel_count) |index| {
                try self.processors[index].downsample(
                    self.output_scratch[index][0..self.pending_frames],
                );
            }
            for (output, 0..) |channel_samples, index| {
                @memcpy(
                    channel_samples,
                    self.output_scratch[index][0..self.pending_frames],
                );
            }
            self.pending_frames = 0;
        }

        pub fn channel(
            self: *Self,
            index: usize,
        ) !*ChannelProcessor {
            if (index >= self.channel_count)
                return error.OversamplingChannelOutOfRange;
            return &self.processors[index];
        }

        pub fn valid(self: *const Self) bool {
            if (self.channel_count == 0 or
                self.channel_count > maximum_channels or
                self.pending_frames > maximum_frames)
                return false;
            for (self.processors[0..self.channel_count]) |processor| {
                if (!processor.valid() or
                    processor.pending_frames != self.pending_frames)
                    return false;
            }
            return true;
        }

        fn validateInput(
            self: *const Self,
            input: []const []const Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidMixedMultichannelOversamplerState;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            if (input.len != self.channel_count)
                return error.OversamplingChannelMismatch;
            const frame_count = input[0].len;
            if (frame_count == 0 or frame_count > maximum_frames)
                return error.OversamplingCapacityExceeded;
            for (input) |channel_samples| {
                if (channel_samples.len != frame_count)
                    return error.OversamplingFrameMismatch;
                for (channel_samples) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.NonFiniteOversamplingInput;
                }
            }
        }

        fn validateOutput(
            self: *const Self,
            output: []const []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidMixedMultichannelOversamplerState;
            if (self.pending_frames == 0)
                return error.NoOversampledBlock;
            if (output.len != self.channel_count)
                return error.OversamplingChannelMismatch;
            for (output) |channel_samples| {
                if (channel_samples.len != self.pending_frames)
                    return error.OversamplingFrameMismatch;
            }
        }
    };
}

fn MixedStage(comptime Sample: type) type {
    const FirPair = FirStagePair(Sample);
    const IirPair = IirStagePair(Sample);

    return union(enum) {
        const Self = @This();

        dummy,
        fir_equiripple: FirPair,
        polyphase_iir: IirPair,

        fn init(config: StageConfig) !Self {
            return switch (config) {
                .dummy => .dummy,
                .fir_equiripple => |directional| .{
                    .fir_equiripple = try FirPair.init(directional),
                },
                .polyphase_iir => |directional| .{
                    .polyphase_iir = try IirPair.init(directional),
                },
            };
        }

        fn reset(self: *Self) void {
            switch (self.*) {
                .dummy => {},
                .fir_equiripple => |*stage| stage.reset(),
                .polyphase_iir => |*stage| stage.reset(),
            }
        }

        fn interpolate(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            switch (self.*) {
                .dummy => {
                    if (output.len != input.len)
                        return error.OversamplingFrameMismatch;
                    @memcpy(output, input);
                },
                .fir_equiripple => |*stage| try stage.interpolate(input, output),
                .polyphase_iir => |*stage| try stage.interpolate(input, output),
            }
        }

        fn decimate(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            switch (self.*) {
                .dummy => {
                    if (output.len != input.len)
                        return error.OversamplingFrameMismatch;
                    @memcpy(output, input);
                },
                .fir_equiripple => |*stage| try stage.decimate(input, output),
                .polyphase_iir => |*stage| try stage.decimate(input, output),
            }
        }

        fn interpolatedLength(self: Self, input_length: usize) usize {
            return if (self.isDummy()) input_length else input_length * 2;
        }

        fn decimatedLength(self: Self, input_length: usize) usize {
            return if (self.isDummy()) input_length else input_length / 2;
        }

        fn latency(self: Self) f64 {
            return switch (self) {
                .dummy => 0.0,
                .fir_equiripple => |stage| stage.latency(),
                .polyphase_iir => |stage| stage.latency(),
            };
        }

        fn isDummy(self: Self) bool {
            return self == .dummy;
        }

        fn valid(self: Self) bool {
            return switch (self) {
                .dummy => true,
                .fir_equiripple => |stage| stage.valid(),
                .polyphase_iir => |stage| stage.valid(),
            };
        }
    };
}

fn FirStagePair(comptime Sample: type) type {
    const Filter = fir.FirFilter(Sample, equiripple.maximum_taps);

    return struct {
        const Self = @This();

        up: Filter,
        down: Filter,

        fn init(config: DirectionalConfig) !Self {
            var up_coefficients: [equiripple.maximum_taps]Sample = undefined;
            var down_coefficients: [equiripple.maximum_taps]Sample = undefined;
            const up_count = try designFirHalfBand(
                Sample,
                &up_coefficients,
                config.up,
            );
            const down_count = try designFirHalfBand(
                Sample,
                &down_coefficients,
                config.down,
            );
            return .{
                .up = try Filter.init(up_coefficients[0..up_count]),
                .down = try Filter.init(down_coefficients[0..down_count]),
            };
        }

        fn reset(self: *Self) void {
            self.up.reset();
            self.down.reset();
        }

        fn interpolate(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (output.len != input.len * 2)
                return error.OversamplingFrameMismatch;
            for (input, 0..) |sample, frame| {
                output[frame * 2] =
                    (try self.up.processSampleChecked(sample)) * 2.0;
                output[frame * 2 + 1] =
                    (try self.up.processSampleChecked(0.0)) * 2.0;
                if (!std.math.isFinite(output[frame * 2]) or
                    !std.math.isFinite(output[frame * 2 + 1]))
                    return error.NonFiniteOversamplingOutput;
            }
        }

        fn decimate(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len * 2)
                return error.OversamplingFrameMismatch;
            for (input, 0..) |sample, index| {
                const filtered =
                    try self.down.processSampleChecked(sample);
                if (index % 2 == 0)
                    output[index / 2] = filtered;
            }
        }

        fn latency(self: Self) f64 {
            return @as(f64, @floatFromInt(
                self.up.coefficient_count +
                    self.down.coefficient_count - 2,
            )) / 4.0;
        }

        fn valid(self: Self) bool {
            return self.up.valid() and self.down.valid() and
                self.up.coefficient_count % 2 == 1 and
                self.down.coefficient_count % 2 == 1;
        }
    };
}

fn IirStagePair(comptime Sample: type) type {
    const Design = polyphase_iir.Design(Sample);
    const Processor =
        polyphase_oversampling.HalfBandProcessor(Sample);

    return struct {
        const Self = @This();

        up_design: Design,
        down_design: Design,
        up: Processor,
        down: Processor,

        fn init(config: DirectionalConfig) !Self {
            const up_design = try designIirHalfBand(
                Sample,
                config.up,
            );
            const down_design = try designIirHalfBand(
                Sample,
                config.down,
            );
            return .{
                .up_design = up_design,
                .down_design = down_design,
                .up = try Processor.init(up_design),
                .down = try Processor.init(down_design),
            };
        }

        fn reset(self: *Self) void {
            self.up.reset();
            self.down.reset();
        }

        fn interpolate(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            try self.up.interpolate(input, output);
        }

        fn decimate(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            try self.down.decimate(input, output);
        }

        fn latency(self: Self) f64 {
            return (iirDesignLatency(self.up_design) +
                iirDesignLatency(self.down_design)) * 0.5;
        }

        fn valid(self: Self) bool {
            return self.up_design.valid() and
                self.down_design.valid() and
                self.up.valid(self.up_design) and
                self.down.valid(self.down_design);
        }
    };
}

fn designFirHalfBand(
    comptime Sample: type,
    coefficients: []Sample,
    spec: FilterSpec,
) !usize {
    try validateSpec(spec);
    const target = std.math.pow(
        f64,
        10.0,
        spec.stopband_attenuation_db / 20.0,
    );
    const estimated_order = @ceil(
        (-spec.stopband_attenuation_db - 8.0) /
            (2.285 * std.math.tau *
                spec.normalized_transition_width),
    );
    if (!std.math.isFinite(estimated_order))
        return error.InvalidMixedOversamplingConfig;
    var tap_count: usize = @max(
        7,
        @as(usize, @intFromFloat(@max(estimated_order, 2.0))) + 1,
    );
    if (tap_count % 2 == 0) tap_count += 1;
    const passband_end =
        0.25 - spec.normalized_transition_width * 0.5;
    const stopband_start =
        0.25 + spec.normalized_transition_width * 0.5;
    const bands = [_]equiripple.Band{
        .{
            .lower_frequency = 0.0,
            .upper_frequency = passband_end,
            .lower_gain = 1.0,
            .upper_gain = 1.0,
        },
        .{
            .lower_frequency = stopband_start,
            .upper_frequency = 0.5,
            .lower_gain = 0.0,
            .upper_gain = 0.0,
        },
    };
    while (tap_count <= equiripple.maximum_taps) : (tap_count += 2) {
        _ = equiripple.Designer(Sample).design(
            coefficients[0..tap_count],
            &bands,
            .{},
        ) catch continue;
        const dc_gain = fir_design.Designer(Sample).magnitude(
            coefficients[0..tap_count],
            0.0,
        );
        if (!std.math.isFinite(dc_gain) or dc_gain <= 0.0)
            continue;
        for (coefficients[0..tap_count]) |*coefficient|
            coefficient.* /= dc_gain;
        if (firMeetsSpec(
            Sample,
            coefficients[0..tap_count],
            passband_end,
            stopband_start,
            target,
        ))
            return tap_count;
    }
    return error.FirOversamplingCapacityExceeded;
}

fn firMeetsSpec(
    comptime Sample: type,
    coefficients: []const Sample,
    passband_end: f64,
    stopband_start: f64,
    target: f64,
) bool {
    const tolerance = target * 1.05;
    for (0..2_049) |index| {
        const unit = @as(f64, @floatFromInt(index)) / 2_048.0;
        const passband_frequency: Sample =
            @floatCast(passband_end * unit);
        const stopband_frequency: Sample =
            @floatCast(
                stopband_start +
                    (0.5 - stopband_start) * unit,
            );
        const passband = fir_design.Designer(Sample).magnitude(
            coefficients,
            passband_frequency,
        );
        const stopband = fir_design.Designer(Sample).magnitude(
            coefficients,
            stopband_frequency,
        );
        if (@abs(@as(f64, @floatCast(passband)) - 1.0) > tolerance or
            @as(f64, @floatCast(stopband)) > tolerance)
            return false;
    }
    return true;
}

fn designIirHalfBand(
    comptime Sample: type,
    spec: FilterSpec,
) !polyphase_iir.Design(Sample) {
    try validateSpec(spec);
    return polyphase_iir.Designer(Sample).halfBandLowPass(
        @floatCast(spec.normalized_transition_width),
        @floatCast(spec.stopband_attenuation_db),
    ) catch |design_error| switch (design_error) {
        error.InvalidPolyphaseAllpassTransitionWidth,
        error.InvalidPolyphaseAllpassStopband,
        => error.InvalidMixedOversamplingConfig,
        else => design_error,
    };
}

fn iirDesignLatency(design: anytype) f64 {
    var result: f64 = 0.5;
    for (design.alpha[0..design.section_count]) |coefficient| {
        const alpha: f64 = @floatCast(coefficient);
        result += (1.0 - alpha) / (1.0 + alpha);
    }
    return result;
}

fn validateSpec(spec: FilterSpec) !void {
    if (!std.math.isFinite(spec.normalized_transition_width) or
        spec.normalized_transition_width <= 0.0 or
        spec.normalized_transition_width >= 0.5 or
        !std.math.isFinite(spec.stopband_attenuation_db) or
        spec.stopband_attenuation_db >= 0.0)
        return error.InvalidMixedOversamplingConfig;
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
                return error.InvalidOversamplingLatencyCompensation;
            return .{
                .coefficient = @floatCast(
                    (1.0 - delay_samples) /
                        (1.0 + delay_samples),
                ),
            };
        }

        fn reset(self: *Self) void {
            self.previous_input = 0.0;
            self.previous_output = 0.0;
        }

        fn processBlock(self: *Self, samples: []Sample) !void {
            for (samples) |*sample| {
                const output =
                    self.coefficient * sample.* +
                    self.previous_input -
                    self.coefficient * self.previous_output;
                if (!std.math.isFinite(output))
                    return error.NonFiniteOversamplingOutput;
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

fn requireSampleType(comptime Sample: type) void {
    if (Sample != f32 and Sample != f64)
        @compileError("mixed oversampling supports f32 and f64 samples");
}

test "mixed oversampling designs FIR and IIR stages independently" {
    const Processor = Oversampler(f64, 32, 4);
    const configs = [_]StageConfig{
        .{ .fir_equiripple = .{
            .up = .{
                .normalized_transition_width = 0.14,
                .stopband_attenuation_db = -60.0,
            },
            .down = .{
                .normalized_transition_width = 0.1,
                .stopband_attenuation_db = -80.0,
            },
        } },
        .dummy,
        .{ .polyphase_iir = .{
            .up = .{
                .normalized_transition_width = 0.12,
                .stopband_attenuation_db = -70.0,
            },
            .down = .{
                .normalized_transition_width = 0.08,
                .stopband_attenuation_db = -90.0,
            },
        } },
    };
    var processor = try Processor.init(&configs);
    try std.testing.expectEqual(
        @as(usize, 4),
        try processor.oversamplingFactor(),
    );
    try std.testing.expect((try processor.latencySamples()) > 0.0);

    var input: [32]f64 = @splat(0.25);
    var output: [32]f64 = undefined;
    for (0..32) |_| {
        const high_rate = try processor.upsample(&input);
        try std.testing.expectEqual(@as(usize, 128), high_rate.len);
        try processor.downsample(&output);
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        output[31],
        0.000_001,
    );
    try std.testing.expect(processor.valid());
}

test "mixed oversampling reported latency matches impulse moment" {
    const Processor = Oversampler(f64, 256, 3);
    var processor = try Processor.init(&.{
        .{ .fir_equiripple = .{
            .up = .{
                .normalized_transition_width = 0.16,
                .stopband_attenuation_db = -60.0,
            },
            .down = .{
                .normalized_transition_width = 0.12,
                .stopband_attenuation_db = -70.0,
            },
        } },
        .{ .polyphase_iir = .{
            .up = .{
                .normalized_transition_width = 0.12,
                .stopband_attenuation_db = -70.0,
            },
            .down = .{
                .normalized_transition_width = 0.08,
                .stopband_attenuation_db = -90.0,
            },
        } },
    });
    const reported = try processor.latencySamples();
    var input: [256]f64 = @splat(0.0);
    var output: [256]f64 = undefined;
    var sum: f64 = 0.0;
    var moment: f64 = 0.0;
    var position: usize = 0;
    for (0..64) |block| {
        input[0] = if (block == 0) 1.0 else 0.0;
        _ = try processor.upsample(&input);
        try processor.downsample(&output);
        for (output) |sample| {
            sum += sample;
            moment += sample *
                @as(f64, @floatFromInt(position));
            position += 1;
        }
    }
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), sum, 1.0e-8);
    try std.testing.expectApproxEqAbs(
        reported,
        moment / sum,
        1.0e-6,
    );
}

test "mixed oversampling dummy stages and reconfiguration are transactional" {
    const Processor = Oversampler(f32, 8, 4);
    var processor = try Processor.init(&.{ .dummy, .dummy });
    try std.testing.expectEqual(
        @as(usize, 1),
        try processor.oversamplingFactor(),
    );
    const input = [_]f32{ -0.5, 0.0, 0.25, 1.0 };
    const processing = try processor.upsample(&input);
    try std.testing.expectEqual(input.len, processing.len);
    for (processing) |*sample| sample.* *= 0.5;
    var output: [4]f32 = undefined;
    try processor.downsample(&output);
    try std.testing.expectEqualSlices(
        f32,
        &[_]f32{ -0.25, 0.0, 0.125, 0.5 },
        &output,
    );

    try processor.reconfigure(
        &.{.{ .polyphase_iir = .{} }},
        .{ .use_integer_latency = true },
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        try processor.oversamplingFactor(),
    );
    const latency = try processor.latencySamples();
    try std.testing.expectEqual(@ceil(latency), latency);
    _ = try processor.upsample(&input);
    try std.testing.expectError(
        error.OversampledBlockPending,
        processor.reconfigure(&.{}, .{}),
    );
    try processor.downsample(&output);
    try std.testing.expectError(
        error.InvalidMixedOversamplingConfig,
        processor.reconfigure(
            &.{.{ .fir_equiripple = .{
                .up = .{ .normalized_transition_width = 0.0 },
            } }},
            .{},
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        try processor.oversamplingFactor(),
    );
}

test "automatic FIR stages meet directional response specifications" {
    const Pair = FirStagePair(f64);
    const config = DirectionalConfig{
        .up = .{
            .normalized_transition_width = 0.16,
            .stopband_attenuation_db = -60.0,
        },
        .down = .{
            .normalized_transition_width = 0.08,
            .stopband_attenuation_db = -90.0,
        },
    };
    const pair = try Pair.init(config);
    try std.testing.expect(
        pair.down.coefficient_count >
            pair.up.coefficient_count,
    );
    inline for (.{ pair.up, pair.down }, .{ config.up, config.down }) |
        filter,
        spec,
    | {
        const passband_end =
            0.25 - spec.normalized_transition_width * 0.5;
        const stopband_start =
            0.25 + spec.normalized_transition_width * 0.5;
        const target = std.math.pow(
            f64,
            10.0,
            spec.stopband_attenuation_db / 20.0,
        );
        try std.testing.expect(firMeetsSpec(
            f64,
            filter.coefficients[0..filter.coefficient_count],
            passband_end,
            stopband_start,
            target,
        ));
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            fir_design.Designer(f64).magnitude(
                filter.coefficients[0..filter.coefficient_count],
                0.0,
            ),
            1.0e-12,
        );
    }
}

test "mixed oversampling is partition independent" {
    const Processor = Oversampler(f32, 129, 3);
    const configs = [_]StageConfig{
        .{ .fir_equiripple = .{
            .up = .{ .stopband_attenuation_db = -60.0 },
            .down = .{ .stopband_attenuation_db = -70.0 },
        } },
        .dummy,
        .{ .polyphase_iir = .{} },
    };
    var input: [129]f32 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* = @sin(
            std.math.tau * 0.037 *
                @as(f32, @floatFromInt(index)),
        );
    }
    var whole = try Processor.init(&configs);
    _ = try whole.upsample(&input);
    var whole_output: [129]f32 = undefined;
    try whole.downsample(&whole_output);

    var partitioned = try Processor.init(&configs);
    var partitioned_output: [129]f32 = undefined;
    _ = try partitioned.upsample(input[0..41]);
    try partitioned.downsample(partitioned_output[0..41]);
    _ = try partitioned.upsample(input[41..]);
    try partitioned.downsample(partitioned_output[41..]);
    try std.testing.expectEqualSlices(
        f32,
        &whole_output,
        &partitioned_output,
    );
}

test "mixed multichannel oversampling isolates channels transactionally" {
    const Processor = MultichannelOversampler(f64, 16, 3, 4);
    const configs = [_]StageConfig{
        .{ .fir_equiripple = .{
            .up = .{ .stopband_attenuation_db = -60.0 },
            .down = .{ .stopband_attenuation_db = -70.0 },
        } },
        .{ .polyphase_iir = .{} },
    };
    var processor = try Processor.init(2, &configs);
    try std.testing.expectEqual(
        @as(usize, 4),
        try processor.oversamplingFactor(),
    );
    var left: [16]f64 = @splat(0.25);
    var right: [16]f64 = @splat(-0.5);
    var output_left: [16]f64 = undefined;
    var output_right: [16]f64 = undefined;
    for (0..64) |_| {
        const high_rate =
            try processor.upsample(&.{ left[0..], right[0..] });
        for (high_rate[0]) |*sample| sample.* *= 2.0;
        for (high_rate[1]) |*sample| sample.* *= 0.5;
        try processor.downsample(&.{
            output_left[0..],
            output_right[0..],
        });
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        output_left[15],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -0.25),
        output_right[15],
        0.000_001,
    );

    _ = try processor.upsample(&.{ left[0..], right[0..] });
    try std.testing.expectError(
        error.OversampledBlockPending,
        processor.reconfigure(&.{.dummy}, .{}),
    );
    const high_rate = try processor.channel(1);
    (try high_rate.pendingHighRate())[3] = std.math.nan(f64);
    output_left = @splat(123.0);
    output_right = @splat(456.0);
    try std.testing.expectError(
        error.NonFiniteOversamplingInput,
        processor.downsample(&.{
            output_left[0..],
            output_right[0..],
        }),
    );
    try std.testing.expectEqual([_]f64{123.0} ** 16, output_left);
    try std.testing.expectEqual([_]f64{456.0} ** 16, output_right);
}

test "mixed FIR arithmetic failure resets the complete pending block" {
    const Processor = Oversampler(f32, 256, 2);
    var processor = try Processor.init(&.{
        .{ .fir_equiripple = .{
            .up = .{ .stopband_attenuation_db = -60.0 },
            .down = .{ .stopband_attenuation_db = -60.0 },
        } },
    });
    var input: [256]f32 = @splat(std.math.floatMax(f32));
    try std.testing.expectError(
        error.NonFiniteOversamplingOutput,
        processor.upsample(&input),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        processor.pending_frames,
    );
    try std.testing.expect(processor.valid());
}
