const std = @import("std");

pub const Config = struct {
    sample_rate: f64,
    room_size: f64 = 0.5,
    damping: f64 = 0.5,
    width: f64 = 1.0,
    mix: f64 = 0.33,
};

pub fn StereoSample(comptime Sample: type) type {
    return struct {
        left: Sample,
        right: Sample,
    };
}

pub fn Reverb(comptime Sample: type, comptime maximum_delay_samples: usize) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Reverb supports f32 and f64 samples");
    if (maximum_delay_samples < 64)
        @compileError("Reverb delay capacity must be at least 64 samples");

    const comb_count = 4;
    const allpass_count = 2;
    const Lengths = struct {
        comb_left: [comb_count]usize,
        comb_right: [comb_count]usize,
        allpass_left: [allpass_count]usize,
        allpass_right: [allpass_count]usize,
    };
    const Channel = struct {
        comb_buffers: [comb_count][maximum_delay_samples]Sample =
            @splat(@splat(0.0)),
        allpass_buffers: [allpass_count][maximum_delay_samples]Sample =
            @splat(@splat(0.0)),
        comb_indices: [comb_count]usize = @splat(0),
        allpass_indices: [allpass_count]usize = @splat(0),
        filter_store: [comb_count]Sample = @splat(0.0),

        fn reset(self: *@This()) void {
            self.comb_buffers = @splat(@splat(0.0));
            self.allpass_buffers = @splat(@splat(0.0));
            self.comb_indices = @splat(0);
            self.allpass_indices = @splat(0);
            self.filter_store = @splat(0.0);
        }

        fn process(
            self: *@This(),
            input: Sample,
            comb_lengths: [comb_count]usize,
            allpass_lengths: [allpass_count]usize,
            feedback: Sample,
            damping: Sample,
        ) ?Sample {
            var sum: Sample = 0.0;
            for (
                &self.comb_buffers,
                &self.comb_indices,
                &self.filter_store,
                comb_lengths,
            ) |*buffer, *index, *filter, length| {
                const delayed = buffer[index.*];
                if (!std.math.isFinite(delayed)) return null;
                filter.* = delayed * (1.0 - damping) + filter.* * damping;
                buffer[index.*] = input + filter.* * feedback;
                sum += delayed;
                index.* = (index.* + 1) % length;
            }
            sum *= 0.25;
            for (
                &self.allpass_buffers,
                &self.allpass_indices,
                allpass_lengths,
            ) |*buffer, *index, length| {
                const delayed = buffer[index.*];
                if (!std.math.isFinite(delayed)) return null;
                const next = -sum + delayed;
                buffer[index.*] = sum + delayed * 0.5;
                index.* = (index.* + 1) % length;
                sum = next;
            }
            return if (std.math.isFinite(sum)) sum else null;
        }

        fn scalarValid(
            self: *const @This(),
            comb_lengths: [comb_count]usize,
            allpass_lengths: [allpass_count]usize,
        ) bool {
            for (self.comb_indices, comb_lengths) |index, length| {
                if (index >= length) return false;
            }
            for (self.allpass_indices, allpass_lengths) |index, length| {
                if (index >= length) return false;
            }
            for (self.filter_store) |sample| {
                if (!std.math.isFinite(sample)) return false;
            }
            return true;
        }

        fn buffersValid(self: *const @This()) bool {
            for (self.comb_buffers) |buffer| {
                for (buffer) |sample| {
                    if (!std.math.isFinite(sample)) return false;
                }
            }
            for (self.allpass_buffers) |buffer| {
                for (buffer) |sample| {
                    if (!std.math.isFinite(sample)) return false;
                }
            }
            return true;
        }
    };

    return struct {
        const Self = @This();

        config: Config,
        lengths: Lengths,
        left: Channel = .{},
        right: Channel = .{},

        pub fn init(config: Config) !Self {
            return .{
                .config = config,
                .lengths = try calculateLengths(config),
            };
        }

        pub fn configure(self: *Self, config: Config) !void {
            const lengths = try calculateLengths(config);
            const delay_changed = !std.meta.eql(lengths, self.lengths);
            self.config = config;
            self.lengths = lengths;
            if (delay_changed) self.reset();
        }

        pub fn reset(self: *Self) void {
            self.left.reset();
            self.right.reset();
        }

        pub fn processSample(
            self: *Self,
            input_left: Sample,
            input_right: Sample,
        ) StereoSample(Sample) {
            const dry_left =
                if (std.math.isFinite(input_left)) input_left else 0.0;
            const dry_right =
                if (std.math.isFinite(input_right)) input_right else 0.0;
            validateConfig(self.config) catch {
                self.reset();
                return .{ .left = dry_left, .right = dry_right };
            };
            if (!lengthsValid(self.lengths) or
                !self.left.scalarValid(
                    self.lengths.comb_left,
                    self.lengths.allpass_left,
                ) or
                !self.right.scalarValid(
                    self.lengths.comb_right,
                    self.lengths.allpass_right,
                ))
            {
                self.lengths = calculateLengths(self.config) catch {
                    self.reset();
                    return .{ .left = dry_left, .right = dry_right };
                };
                self.reset();
                return .{ .left = dry_left, .right = dry_right };
            }

            const feedback: Sample = @floatCast(
                0.7 + self.config.room_size * 0.28,
            );
            const damping: Sample = @floatCast(self.config.damping * 0.4);
            const excitation = (dry_left + dry_right) * 0.015;
            const wet_left = self.left.process(
                excitation,
                self.lengths.comb_left,
                self.lengths.allpass_left,
                feedback,
                damping,
            ) orelse {
                self.reset();
                return .{ .left = dry_left, .right = dry_right };
            };
            const wet_right = self.right.process(
                excitation,
                self.lengths.comb_right,
                self.lengths.allpass_right,
                feedback,
                damping,
            ) orelse {
                self.reset();
                return .{ .left = dry_left, .right = dry_right };
            };
            const mix: Sample = @floatCast(self.config.mix);
            const width: Sample = @floatCast(self.config.width);
            const wet_direct = mix * (0.5 + width * 0.5);
            const wet_cross = mix * (0.5 - width * 0.5);
            const dry_gain = 1.0 - mix;
            const output = StereoSample(Sample){
                .left = dry_left * dry_gain +
                    wet_left * wet_direct +
                    wet_right * wet_cross,
                .right = dry_right * dry_gain +
                    wet_right * wet_direct +
                    wet_left * wet_cross,
            };
            if (!std.math.isFinite(output.left) or
                !std.math.isFinite(output.right))
            {
                self.reset();
                return .{ .left = 0.0, .right = 0.0 };
            }
            return output;
        }

        pub fn process(
            self: *Self,
            input_left: []const Sample,
            input_right: []const Sample,
            output_left: []Sample,
            output_right: []Sample,
        ) !void {
            if (input_left.len != input_right.len or
                input_left.len != output_left.len or
                input_left.len != output_right.len)
                return error.ReverbBufferLengthMismatch;
            for (
                input_left,
                input_right,
                output_left,
                output_right,
            ) |left_sample, right_sample, *left_output, *right_output| {
                const result = self.processSample(left_sample, right_sample);
                left_output.* = result.left;
                right_output.* = result.right;
            }
        }

        pub fn valid(self: *const Self) bool {
            const expected = calculateLengths(self.config) catch return false;
            return std.meta.eql(expected, self.lengths) and
                self.left.scalarValid(
                    self.lengths.comb_left,
                    self.lengths.allpass_left,
                ) and
                self.right.scalarValid(
                    self.lengths.comb_right,
                    self.lengths.allpass_right,
                ) and
                self.left.buffersValid() and
                self.right.buffersValid();
        }

        fn calculateLengths(config: Config) !Lengths {
            try validateConfig(config);
            const comb_base = [_]usize{ 1_116, 1_188, 1_277, 1_356 };
            const allpass_base = [_]usize{ 556, 441 };
            var result: Lengths = undefined;
            for (
                comb_base,
                &result.comb_left,
                &result.comb_right,
            ) |base, *left_length, *right_length| {
                left_length.* = try scaledLength(config.sample_rate, base);
                right_length.* = try scaledLength(
                    config.sample_rate,
                    base + 23,
                );
            }
            for (
                allpass_base,
                &result.allpass_left,
                &result.allpass_right,
            ) |base, *left_length, *right_length| {
                left_length.* = try scaledLength(config.sample_rate, base);
                right_length.* = try scaledLength(
                    config.sample_rate,
                    base + 23,
                );
            }
            return result;
        }

        fn validateConfig(config: Config) !void {
            if (!std.math.isFinite(config.sample_rate) or
                config.sample_rate < 1_000.0 or
                config.sample_rate > 768_000.0 or
                !std.math.isFinite(config.room_size) or
                config.room_size < 0.0 or
                config.room_size > 1.0 or
                !std.math.isFinite(config.damping) or
                config.damping < 0.0 or
                config.damping > 1.0 or
                !std.math.isFinite(config.width) or
                config.width < 0.0 or
                config.width > 1.0 or
                !std.math.isFinite(config.mix) or
                config.mix < 0.0 or
                config.mix > 1.0)
                return error.InvalidReverbConfig;
        }

        fn lengthsValid(lengths: Lengths) bool {
            for (lengths.comb_left) |length| {
                if (length == 0 or length > maximum_delay_samples)
                    return false;
            }
            for (lengths.comb_right) |length| {
                if (length == 0 or length > maximum_delay_samples)
                    return false;
            }
            for (lengths.allpass_left) |length| {
                if (length == 0 or length > maximum_delay_samples)
                    return false;
            }
            for (lengths.allpass_right) |length| {
                if (length == 0 or length > maximum_delay_samples)
                    return false;
            }
            return true;
        }

        fn scaledLength(sample_rate: f64, base: usize) !usize {
            const scaled = @round(
                @as(f64, @floatFromInt(base)) * sample_rate / 44_100.0,
            );
            if (!std.math.isFinite(scaled) or
                scaled < 1.0 or
                scaled > @as(f64, @floatFromInt(maximum_delay_samples)))
                return error.InvalidReverbConfig;
            return @intFromFloat(scaled);
        }
    };
}

test "reverb produces a finite stereo tail" {
    const Effect = Reverb(f32, 2_048);
    var reverb = try Effect.init(.{
        .sample_rate = 48_000.0,
        .room_size = 0.8,
        .damping = 0.3,
        .width = 1.0,
        .mix = 1.0,
    });
    var tail_energy: f64 = 0.0;
    var stereo_difference: f64 = 0.0;
    for (0..6_000) |index| {
        const input: f32 = if (index == 0) 1.0 else 0.0;
        const output = reverb.processSample(input, input);
        if (index > 1_000) {
            tail_energy += @as(f64, output.left) * output.left;
            stereo_difference += @abs(
                @as(f64, output.left) - output.right,
            );
        }
    }
    try std.testing.expect(tail_energy > 0.000001);
    try std.testing.expect(stereo_difference > 0.000001);
    try std.testing.expect(reverb.valid());
}

test "reverb processing is independent of block partitioning" {
    const Effect = Reverb(f32, 2_048);
    const config = Config{
        .sample_rate = 48_000.0,
        .room_size = 0.7,
        .damping = 0.4,
        .width = 0.8,
        .mix = 0.5,
    };
    var left: [256]f32 = @splat(0.0);
    var right: [256]f32 = @splat(0.0);
    left[0] = 1.0;
    right[17] = -0.5;
    var whole = try Effect.init(config);
    var whole_left: [256]f32 = undefined;
    var whole_right: [256]f32 = undefined;
    try whole.process(&left, &right, &whole_left, &whole_right);

    var split = try Effect.init(config);
    var split_left: [256]f32 = undefined;
    var split_right: [256]f32 = undefined;
    try split.process(
        left[0..73],
        right[0..73],
        split_left[0..73],
        split_right[0..73],
    );
    try split.process(
        left[73..],
        right[73..],
        split_left[73..],
        split_right[73..],
    );
    try std.testing.expectEqualSlices(f32, &whole_left, &split_left);
    try std.testing.expectEqualSlices(f32, &whole_right, &split_right);
}

test "reverb configuration is transactional and hostile state resets" {
    const Effect = Reverb(f32, 2_048);
    var reverb = try Effect.init(.{ .sample_rate = 48_000.0 });
    const original = reverb.config;
    try std.testing.expectError(
        error.InvalidReverbConfig,
        reverb.configure(.{
            .sample_rate = 192_000.0,
        }),
    );
    try std.testing.expectEqual(original, reverb.config);
    reverb.left.filter_store[0] = std.math.nan(f32);
    const output = reverb.processSample(0.25, -0.5);
    try std.testing.expectEqual(@as(f32, 0.25), output.left);
    try std.testing.expectEqual(@as(f32, -0.5), output.right);
    try std.testing.expect(reverb.valid());
}
