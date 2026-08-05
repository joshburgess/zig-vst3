const std = @import("std");
const plug_core = @import("zig-vst3-plugin-core");

pub const Error = error{
    InvalidChannelCount,
    InvalidFrameCount,
    InvalidBufferShape,
    NonFiniteInput,
    NonFiniteSpectrum,
    InvalidOverlapNormalization,
    InvalidTransformState,
};

pub fn LinearGain(
    comptime Sample: type,
    comptime fft_size: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("spectral gain supports f32 or f64");
    if (fft_size < 4 or !std.math.isPowerOfTwo(fft_size))
        @compileError("spectral gain size must be a power of two");

    return struct {
        const Self = @This();
        const Value = plug_core.dsp.Fft(Sample, fft_size).Value;

        low: Sample = 1,
        high: Sample = 1,

        pub fn validate(self: Self) Error!void {
            if (!std.math.isFinite(self.low) or
                !std.math.isFinite(self.high) or
                self.low < 0 or self.high < 0)
                return error.InvalidTransformState;
        }

        pub fn transform(
            self: *Self,
            comptime TransformType: type,
        ) TransformType {
            return .{
                .context = self,
                .process = process,
            };
        }

        pub fn encode(self: Self, destination: []u8) Error!usize {
            try self.validate();
            const encoded_size = 2 + 2 * @sizeOf(Sample);
            if (destination.len < encoded_size)
                return error.InvalidTransformState;
            destination[0] = 1;
            destination[1] = if (Sample == f32) 4 else 8;
            writeFloat(destination[2..], self.low);
            writeFloat(
                destination[2 + @sizeOf(Sample) ..],
                self.high,
            );
            return encoded_size;
        }

        pub fn decode(source: []const u8) Error!Self {
            const encoded_size = 2 + 2 * @sizeOf(Sample);
            if (source.len != encoded_size or
                source[0] != 1 or
                source[1] != @sizeOf(Sample))
                return error.InvalidTransformState;
            const value = Self{
                .low = readFloat(source[2..]),
                .high = readFloat(
                    source[2 + @sizeOf(Sample) ..],
                ),
            };
            try value.validate();
            return value;
        }

        fn process(
            context: ?*anyopaque,
            _: usize,
            _: usize,
            spectrum: []Value,
        ) Error!void {
            const self: *Self =
                @ptrCast(@alignCast(context orelse
                    return error.InvalidTransformState));
            try self.validate();
            const nyquist = fft_size / 2;
            for (spectrum, 0..) |*value, index| {
                const distance = @min(index, fft_size - index);
                const ratio = @as(Sample, @floatFromInt(distance)) /
                    @as(Sample, @floatFromInt(nyquist));
                const gain = self.low + (self.high - self.low) * ratio;
                value.real *= gain;
                value.imaginary *= gain;
            }
        }

        fn writeFloat(destination: []u8, value: Sample) void {
            const Bits = std.meta.Int(.unsigned, @bitSizeOf(Sample));
            std.mem.writeInt(
                Bits,
                destination[0..@sizeOf(Sample)],
                @bitCast(value),
                .little,
            );
        }

        fn readFloat(source: []const u8) Sample {
            const Bits = std.meta.Int(.unsigned, @bitSizeOf(Sample));
            return @bitCast(std.mem.readInt(
                Bits,
                source[0..@sizeOf(Sample)],
                .little,
            ));
        }
    };
}

pub fn Processor(
    comptime Sample: type,
    comptime fft_size: usize,
    comptime hop_size: usize,
    comptime maximum_channels: usize,
    comptime maximum_frames: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("ARA spectral transforms support f32 or f64");
    if (fft_size < 4 or !std.math.isPowerOfTwo(fft_size))
        @compileError("ARA spectral transform size must be a power of two");
    if (hop_size == 0 or hop_size >= fft_size or
        fft_size % hop_size != 0)
        @compileError(
            "ARA spectral hop must divide and be smaller than the transform size",
        );
    if (maximum_channels == 0 or maximum_frames == 0)
        @compileError("ARA spectral capacities must be nonzero");

    const Fft = plug_core.dsp.Fft(Sample, fft_size);

    return struct {
        const Self = @This();

        pub const Value = Fft.Value;
        pub const Transform = struct {
            context: ?*anyopaque = null,
            process: ?*const fn (
                ?*anyopaque,
                usize,
                usize,
                []Value,
            ) anyerror!void = null,
        };

        fft: Fft = Fft.init(),
        window: [fft_size]Sample = makeWindow(),
        time: [fft_size]Sample = undefined,
        spectrum: [fft_size]Value = undefined,
        accumulation: [maximum_channels][maximum_frames]Sample =
            @splat(@splat(0)),
        normalization: [maximum_frames]Sample = @splat(0),
        staged: [maximum_channels][maximum_frames]Sample =
            @splat(@splat(0)),

        pub fn process(
            self: *Self,
            input: []const []const Sample,
            output: []const []Sample,
            transform: Transform,
        ) anyerror!void {
            const frame_count = try validateBuffers(input, output);
            @memset(self.normalization[0..frame_count], 0);
            for (0..input.len) |channel| {
                @memset(self.accumulation[channel][0..frame_count], 0);
                try self.processChannel(
                    input[channel],
                    self.accumulation[channel][0..frame_count],
                    transform,
                    channel,
                );
            }
            for (0..frame_count) |frame| {
                const weight = self.normalization[frame];
                if (!std.math.isFinite(weight) or
                    weight <= std.math.floatEps(Sample))
                    return error.InvalidOverlapNormalization;
                for (0..input.len) |channel| {
                    const value =
                        self.accumulation[channel][frame] / weight;
                    if (!std.math.isFinite(value))
                        return error.NonFiniteSpectrum;
                    self.staged[channel][frame] = value;
                }
            }
            for (output, 0..) |destination, channel|
                @memcpy(
                    destination,
                    self.staged[channel][0..frame_count],
                );
        }

        fn processChannel(
            self: *Self,
            input: []const Sample,
            accumulation: []Sample,
            transform: Transform,
            channel: usize,
        ) anyerror!void {
            const negative_frames = fft_size / hop_size - 1;
            var frame_start =
                -@as(i64, @intCast(negative_frames * hop_size));
            var frame_index: usize = 0;
            while (frame_start <
                @as(i64, @intCast(input.len))) : ({
                frame_start += hop_size;
                frame_index += 1;
            }) {
                for (&self.time, 0..) |*sample, offset| {
                    const source_index =
                        frame_start + @as(i64, @intCast(offset));
                    const source = if (source_index >= 0 and
                        source_index < @as(i64, @intCast(input.len)))
                        input[@intCast(source_index)]
                    else
                        0;
                    if (!std.math.isFinite(source))
                        return error.NonFiniteInput;
                    sample.* = source * self.window[offset];
                }
                try self.fft.forwardReal(&self.time, &self.spectrum);
                if (transform.process) |callback|
                    try callback(
                        transform.context,
                        channel,
                        frame_index,
                        &self.spectrum,
                    );
                for (self.spectrum) |value| {
                    if (!value.valid()) return error.NonFiniteSpectrum;
                }
                try self.fft.inverseReal(&self.spectrum, &self.time);
                for (self.time, 0..) |sample, offset| {
                    const destination_index =
                        frame_start + @as(i64, @intCast(offset));
                    if (destination_index < 0 or
                        destination_index >=
                            @as(i64, @intCast(accumulation.len)))
                        continue;
                    const index: usize = @intCast(destination_index);
                    const window = self.window[offset];
                    accumulation[index] += sample * window;
                    if (channel == 0)
                        self.normalization[index] += window * window;
                }
            }
        }

        fn validateBuffers(
            input: []const []const Sample,
            output: []const []Sample,
        ) Error!usize {
            if (input.len == 0 or input.len > maximum_channels)
                return error.InvalidChannelCount;
            if (output.len != input.len)
                return error.InvalidBufferShape;
            const frame_count = input[0].len;
            if (frame_count == 0 or frame_count > maximum_frames)
                return error.InvalidFrameCount;
            for (input, output) |source, destination| {
                if (source.len != frame_count or
                    destination.len != frame_count)
                    return error.InvalidBufferShape;
            }
            for (output, 0..) |destination, index| {
                for (output[index + 1 ..]) |other| {
                    if (slicesOverlap(destination, other))
                        return error.InvalidBufferShape;
                }
            }
            return frame_count;
        }

        fn slicesOverlap(left: []Sample, right: []Sample) bool {
            const left_start = @intFromPtr(left.ptr);
            const right_start = @intFromPtr(right.ptr);
            const left_bytes = std.math.mul(
                usize,
                left.len,
                @sizeOf(Sample),
            ) catch return true;
            const right_bytes = std.math.mul(
                usize,
                right.len,
                @sizeOf(Sample),
            ) catch return true;
            const left_end =
                std.math.add(usize, left_start, left_bytes) catch
                    return true;
            const right_end =
                std.math.add(usize, right_start, right_bytes) catch
                    return true;
            return left_start < right_end and right_start < left_end;
        }

        fn makeWindow() [fft_size]Sample {
            var values: [fft_size]Sample = undefined;
            plug_core.dsp.fillWindow(
                Sample,
                &values,
                .hann,
                true,
                .none,
            ) catch @compileError("invalid spectral transform window declaration");
            for (&values) |*value| value.* = @sqrt(@max(0, value.*));
            return values;
        }
    };
}

pub fn PreparedSource(
    comptime ControllerType: type,
    comptime Sample: type,
    comptime fft_size: usize,
    comptime hop_size: usize,
    comptime maximum_channels: usize,
    comptime maximum_frames: usize,
    comptime publication_slots: usize,
) type {
    const Description = ControllerType.PlaybackRegionRenderDescription;
    const SourceId = @FieldType(Description, "audio_source");
    const empty_source_id: SourceId = std.mem.zeroes(SourceId);
    const Engine = Processor(
        Sample,
        fft_size,
        hop_size,
        maximum_channels,
        maximum_frames,
    );
    const State = struct {
        valid: bool = false,
        source_id: SourceId = empty_source_id,
        sample_rate: f64 = 0,
        channel_count: usize = 0,
        frame_count: usize = 0,
        samples: [maximum_channels][maximum_frames]Sample =
            @splat(@splat(0)),
    };
    const Publisher = plug_core.dsp.RealtimeReferencePublisher(
        State,
        publication_slots,
    );
    const Ready = *const fn (
        ?*anyopaque,
        *const Description,
    ) bool;
    const Read = *const fn (
        ?*anyopaque,
        SourceId,
        i64,
        []const []Sample,
    ) anyerror!void;

    return struct {
        const Self = @This();

        pub const SpectralEngine = Engine;

        publisher: Publisher = Publisher.init(.{}),
        engine: Engine = .{},
        input: [maximum_channels][maximum_frames]Sample =
            @splat(@splat(0)),
        fallback_context: ?*anyopaque = null,
        fallback_ready: ?Ready = null,
        fallback_read: ?Read = null,

        pub fn prepare(
            self: *Self,
            description: *const Description,
            upstream: anytype,
            transform: Engine.Transform,
        ) !u64 {
            if (description.source_channel_count <= 0 or
                description.source_channel_count > maximum_channels)
                return error.InvalidChannelCount;
            if (description.source_sample_count <= 0 or
                description.source_sample_count > maximum_frames)
                return error.InvalidFrameCount;
            if (!std.math.isFinite(description.source_sample_rate) or
                description.source_sample_rate <= 0)
                return error.InvalidSampleRate;
            if (!upstream.ready(upstream.context, description))
                return error.SourceUnavailable;

            const channel_count: usize =
                @intCast(description.source_channel_count);
            const frame_count: usize =
                @intCast(description.source_sample_count);
            var input_buffers: [maximum_channels][]Sample = undefined;
            for (0..channel_count) |channel|
                input_buffers[channel] =
                    self.input[channel][0..frame_count];
            try upstream.read(
                upstream.context,
                description.audio_source,
                0,
                input_buffers[0..channel_count],
            );

            var writer = try self.publisher.beginPublish();
            defer writer.cancel();
            const state = writer.value() orelse
                return error.SourceUnavailable;
            state.* = .{
                .source_id = description.audio_source,
                .sample_rate = description.source_sample_rate,
                .channel_count = channel_count,
                .frame_count = frame_count,
            };
            var output_buffers: [maximum_channels][]Sample = undefined;
            for (0..channel_count) |channel|
                output_buffers[channel] =
                    state.samples[channel][0..frame_count];
            try self.engine.process(
                input_buffers[0..channel_count],
                output_buffers[0..channel_count],
                transform,
            );
            state.valid = true;
            return writer.commit();
        }

        pub fn invalidate(self: *Self) !u64 {
            return self.publisher.publish(.{});
        }

        pub fn provider(
            self: *Self,
            comptime RendererType: type,
        ) RendererType.SourceProvider {
            return .{
                .context = self,
                .ready = providerReady,
                .read = providerRead,
            };
        }

        /// Configure the fallback before exposing the provider to realtime reads.
        pub fn providerWithFallback(
            self: *Self,
            comptime RendererType: type,
            fallback: RendererType.SourceProvider,
        ) RendererType.SourceProvider {
            self.fallback_context = fallback.context;
            self.fallback_ready = fallback.ready;
            self.fallback_read = fallback.read;
            return .{
                .context = self,
                .ready = overlayReady,
                .read = overlayRead,
            };
        }

        fn providerReady(
            context: ?*anyopaque,
            description: *const Description,
        ) bool {
            const self: *Self =
                @ptrCast(@alignCast(context orelse return false));
            var handle = self.publisher.tryAcquire() orelse return false;
            defer handle.release();
            const state = handle.value() orelse return false;
            return matches(state, description);
        }

        fn providerRead(
            context: ?*anyopaque,
            source_id: SourceId,
            sample_position: i64,
            buffers: []const []Sample,
        ) anyerror!void {
            const self: *Self =
                @ptrCast(@alignCast(context orelse
                    return error.SourceUnavailable));
            if (sample_position < 0) return error.InvalidAudioBuffer;
            var handle = self.publisher.tryAcquire() orelse
                return error.SourceUnavailable;
            defer handle.release();
            const state = handle.value() orelse
                return error.SourceUnavailable;
            if (!stateValid(state) or
                !std.meta.eql(state.source_id, source_id))
                return error.SourceUnavailable;
            return readState(state, sample_position, buffers);
        }

        fn overlayReady(
            context: ?*anyopaque,
            description: *const Description,
        ) bool {
            const self: *Self =
                @ptrCast(@alignCast(context orelse return false));
            if (providerReady(context, description)) return true;
            const ready = self.fallback_ready orelse return false;
            return ready(self.fallback_context, description);
        }

        fn overlayRead(
            context: ?*anyopaque,
            source_id: SourceId,
            sample_position: i64,
            buffers: []const []Sample,
        ) anyerror!void {
            const self: *Self =
                @ptrCast(@alignCast(context orelse
                    return error.SourceUnavailable));
            var handle = self.publisher.tryAcquire();
            if (handle) |*acquired| {
                defer acquired.release();
                if (acquired.value()) |state| {
                    if (stateValid(state) and
                        std.meta.eql(state.source_id, source_id))
                        return readState(
                            state,
                            sample_position,
                            buffers,
                        );
                }
            }
            const read = self.fallback_read orelse
                return error.SourceUnavailable;
            return read(
                self.fallback_context,
                source_id,
                sample_position,
                buffers,
            );
        }

        fn readState(
            state: *const State,
            sample_position: i64,
            buffers: []const []Sample,
        ) anyerror!void {
            if (!stateValid(state))
                return error.SourceUnavailable;
            if (sample_position < 0 or
                buffers.len != state.channel_count)
                return error.InvalidAudioBuffer;
            const start: usize = @intCast(sample_position);
            const count = if (buffers.len == 0) 0 else buffers[0].len;
            if (start > state.frame_count or
                count > state.frame_count - start)
                return error.InvalidAudioBuffer;
            for (buffers) |buffer| {
                if (buffer.len != count)
                    return error.InvalidAudioBuffer;
            }
            for (buffers, 0..) |buffer, index| {
                for (buffers[index + 1 ..]) |other| {
                    if (Engine.slicesOverlap(buffer, other))
                        return error.InvalidAudioBuffer;
                }
            }
            for (buffers, 0..) |buffer, channel| {
                @memcpy(
                    buffer,
                    state.samples[channel][start..][0..count],
                );
            }
        }

        fn matches(
            state: *const State,
            description: *const Description,
        ) bool {
            const channel_count = std.math.cast(
                usize,
                description.source_channel_count,
            ) orelse return false;
            const frame_count = std.math.cast(
                usize,
                description.source_sample_count,
            ) orelse return false;
            return stateValid(state) and
                std.meta.eql(state.source_id, description.audio_source) and
                state.sample_rate == description.source_sample_rate and
                state.channel_count == channel_count and
                state.frame_count == frame_count;
        }

        fn stateValid(state: *const State) bool {
            return state.valid and
                std.math.isFinite(state.sample_rate) and
                state.sample_rate > 0.0 and
                state.channel_count > 0 and
                state.channel_count <= maximum_channels and
                state.frame_count > 0 and
                state.frame_count <= maximum_frames;
        }
    };
}

test "ARA spectral overlap-add preserves finite multichannel audio" {
    const Engine = Processor(f64, 32, 8, 2, 257);
    var engine = Engine{};
    var left: [257]f64 = undefined;
    var right: [257]f64 = undefined;
    for (&left, &right, 0..) |*left_sample, *right_sample, index| {
        const time = @as(f64, @floatFromInt(index));
        left_sample.* = @sin(std.math.tau * time / 17.0);
        right_sample.* = 0.25 * @cos(std.math.tau * time / 29.0);
    }
    var output_left: [257]f64 = undefined;
    var output_right: [257]f64 = undefined;
    try engine.process(
        &.{ &left, &right },
        &.{ &output_left, &output_right },
        .{},
    );
    for (left, output_left) |expected, actual|
        try std.testing.expectApproxEqAbs(expected, actual, 1e-12);
    for (right, output_right) |expected, actual|
        try std.testing.expectApproxEqAbs(expected, actual, 1e-12);
}

test "ARA spectral gain state round trips and rejects malformed data" {
    const Gain = LinearGain(f64, 32);
    const expected = Gain{ .low = 0.25, .high = 1.75 };
    var encoded: [18]u8 = undefined;
    const size = try expected.encode(&encoded);
    try std.testing.expectEqual(encoded.len, size);
    const restored = try Gain.decode(&encoded);
    try std.testing.expectEqual(expected.low, restored.low);
    try std.testing.expectEqual(expected.high, restored.high);
    for (0..encoded.len) |truncated_size|
        try std.testing.expectError(
            error.InvalidTransformState,
            Gain.decode(encoded[0..truncated_size]),
        );
    var trailing: [19]u8 = undefined;
    @memcpy(trailing[0..encoded.len], &encoded);
    trailing[encoded.len] = 0;
    try std.testing.expectError(
        error.InvalidTransformState,
        Gain.decode(&trailing),
    );

    encoded[0] = 2;
    try std.testing.expectError(
        error.InvalidTransformState,
        Gain.decode(&encoded),
    );
    encoded[0] = 1;
    encoded[2] = 0xff;
    encoded[3] = 0xff;
    encoded[4] = 0xff;
    encoded[5] = 0xff;
    encoded[6] = 0xff;
    encoded[7] = 0xff;
    encoded[8] = 0xff;
    encoded[9] = 0x7f;
    try std.testing.expectError(
        error.InvalidTransformState,
        Gain.decode(&encoded),
    );
}

test "ARA spectral transforms publish output only after complete success" {
    const Engine = Processor(f32, 16, 8, 1, 64);
    const Reject = struct {
        fn process(
            _: ?*anyopaque,
            _: usize,
            frame: usize,
            spectrum: []Engine.Value,
        ) !void {
            if (frame == 2) {
                spectrum[0].real = std.math.nan(f32);
                return;
            }
        }
    };
    var engine = Engine{};
    var input: [64]f32 = @splat(0.5);
    var output: [64]f32 = @splat(7);
    try std.testing.expectError(
        error.NonFiniteSpectrum,
        engine.process(
            &.{&input},
            &.{&output},
            .{ .process = Reject.process },
        ),
    );
    try std.testing.expectEqualSlices(f32, &(@as([64]f32, @splat(7))), &output);
}

test "ARA spectral transforms reject malformed buffer contracts" {
    const Engine = Processor(f32, 16, 4, 2, 32);
    var engine = Engine{};
    var input: [16]f32 = @splat(0);
    var short: [15]f32 = @splat(0);
    var output: [16]f32 = undefined;
    try std.testing.expectError(
        error.InvalidChannelCount,
        engine.process(&.{}, &.{}, .{}),
    );
    try std.testing.expectError(
        error.InvalidBufferShape,
        engine.process(
            &.{ &input, &short },
            &.{ &output, &output },
            .{},
        ),
    );
    try std.testing.expectError(
        error.InvalidBufferShape,
        engine.process(
            &.{ &input, &input },
            &.{ &output, &output },
            .{},
        ),
    );
    input[3] = std.math.inf(f32);
    try std.testing.expectError(
        error.NonFiniteInput,
        engine.process(
            &.{&input},
            &.{&output},
            .{},
        ),
    );
}

const TestSourceId = struct {
    index: u16,
    generation: u16,
};

const TestDescription = struct {
    audio_source: TestSourceId,
    source_sample_rate: f64,
    source_channel_count: i32,
    source_sample_count: i64,
};

const TestController = struct {
    pub const PlaybackRegionRenderDescription = TestDescription;
};

const TestRenderer = struct {
    pub const SourceProvider = struct {
        context: ?*anyopaque = null,
        ready: *const fn (?*anyopaque, *const TestDescription) bool,
        read: *const fn (
            ?*anyopaque,
            TestSourceId,
            i64,
            []const []f32,
        ) anyerror!void,
    };
};

const TestUpstream = struct {
    samples: [64]f32,

    fn provider(self: *TestUpstream) TestRenderer.SourceProvider {
        return .{
            .context = self,
            .ready = ready,
            .read = read,
        };
    }

    fn ready(
        _: ?*anyopaque,
        description: *const TestDescription,
    ) bool {
        return description.audio_source.index == 0;
    }

    fn read(
        context: ?*anyopaque,
        _: TestSourceId,
        sample_position: i64,
        buffers: []const []f32,
    ) !void {
        const self: *TestUpstream =
            @ptrCast(@alignCast(context orelse
                return error.SourceUnavailable));
        if (sample_position < 0 or buffers.len != 1)
            return error.InvalidAudioBuffer;
        const start: usize = @intCast(sample_position);
        if (start > self.samples.len or
            buffers[0].len > self.samples.len - start)
            return error.InvalidAudioBuffer;
        @memcpy(
            buffers[0],
            self.samples[start..][0..buffers[0].len],
        );
    }
};

test "ARA prepared spectral source publishes and invalidates generations" {
    const Prepared = PreparedSource(
        TestController,
        f32,
        16,
        4,
        2,
        64,
        3,
    );
    const Half = struct {
        fn process(
            _: ?*anyopaque,
            _: usize,
            _: usize,
            spectrum: []Prepared.SpectralEngine.Value,
        ) !void {
            for (spectrum) |*value| {
                value.real *= 0.5;
                value.imaginary *= 0.5;
            }
        }
    };
    var upstream = TestUpstream{ .samples = undefined };
    for (&upstream.samples, 0..) |*sample, index|
        sample.* = @sin(
            std.math.tau * @as(f32, @floatFromInt(index)) / 13.0,
        );
    const description = TestDescription{
        .audio_source = .{ .index = 0, .generation = 4 },
        .source_sample_rate = 48_000,
        .source_channel_count = 1,
        .source_sample_count = upstream.samples.len,
    };
    var prepared = Prepared{};
    for (prepared.publisher.slots) |slot| {
        try std.testing.expect(!slot.value.valid);
        try std.testing.expectEqualDeep(
            TestSourceId{ .index = 0, .generation = 0 },
            slot.value.source_id,
        );
    }
    _ = try prepared.prepare(
        &description,
        upstream.provider(),
        .{ .process = Half.process },
    );
    const provider = prepared.provider(TestRenderer);
    try std.testing.expect(provider.ready(provider.context, &description));
    var output: [64]f32 = undefined;
    try provider.read(
        provider.context,
        description.audio_source,
        0,
        &.{&output},
    );
    for (upstream.samples, output) |expected, actual|
        try std.testing.expectApproxEqAbs(expected * 0.5, actual, 0.000_01);

    var mismatched_buffers =
        try prepared.publisher.beginUpdate();
    defer mismatched_buffers.cancel();
    const mismatched_state = mismatched_buffers.value() orelse
        return error.MissingPreparedSourceState;
    mismatched_state.channel_count = 2;
    _ = try mismatched_buffers.commit();
    var aliased_destination = [_]f32{-7.0} ** 2;
    const aliased_destinations = [_][]f32{
        &aliased_destination,
        &aliased_destination,
    };
    try std.testing.expectError(
        error.InvalidAudioBuffer,
        provider.read(
            provider.context,
            description.audio_source,
            0,
            &aliased_destinations,
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{-7.0} ** 2),
        &aliased_destination,
    );
    var first_destination = [_]f32{-11.0} ** 2;
    var short_destination = [_]f32{-13.0};
    const invalid_shape = [_][]f32{
        &first_destination,
        &short_destination,
    };
    try std.testing.expectError(
        error.InvalidAudioBuffer,
        provider.read(
            provider.context,
            description.audio_source,
            0,
            &invalid_shape,
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{-11.0} ** 2),
        &first_destination,
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{-13.0}),
        &short_destination,
    );

    _ = try prepared.prepare(
        &description,
        upstream.provider(),
        .{ .process = Half.process },
    );
    var invalid_channels =
        try prepared.publisher.beginUpdate();
    defer invalid_channels.cancel();
    const invalid_channel_state = invalid_channels.value() orelse
        return error.MissingPreparedSourceState;
    invalid_channel_state.channel_count = 3;
    _ = try invalid_channels.commit();
    first_destination = @splat(-17.0);
    var second_destination = [_]f32{-19.0} ** 2;
    var third_destination = [_]f32{-23.0} ** 2;
    const hostile_channels = [_][]f32{
        &first_destination,
        &second_destination,
        &third_destination,
    };
    try std.testing.expect(!provider.ready(
        provider.context,
        &description,
    ));
    try std.testing.expectError(
        error.SourceUnavailable,
        provider.read(
            provider.context,
            description.audio_source,
            0,
            &hostile_channels,
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{-17.0} ** 2),
        &first_destination,
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{-19.0} ** 2),
        &second_destination,
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{-23.0} ** 2),
        &third_destination,
    );

    _ = try prepared.prepare(
        &description,
        upstream.provider(),
        .{ .process = Half.process },
    );
    var invalid_frames =
        try prepared.publisher.beginUpdate();
    defer invalid_frames.cancel();
    const invalid_frame_state = invalid_frames.value() orelse
        return error.MissingPreparedSourceState;
    invalid_frame_state.frame_count = 65;
    _ = try invalid_frames.commit();
    first_destination = @splat(-29.0);
    try std.testing.expectError(
        error.SourceUnavailable,
        provider.read(
            provider.context,
            description.audio_source,
            0,
            &.{&first_destination},
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{-29.0} ** 2),
        &first_destination,
    );

    _ = try prepared.invalidate();
    try std.testing.expect(!provider.ready(provider.context, &description));
    var invalidated = prepared.publisher.tryAcquire() orelse
        return error.TestUnexpectedResult;
    defer invalidated.release();
    const invalidated_state = invalidated.value() orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(!invalidated_state.valid);
    try std.testing.expectEqualDeep(
        TestSourceId{ .index = 0, .generation = 0 },
        invalidated_state.source_id,
    );
    try std.testing.expectError(
        error.SourceUnavailable,
        provider.read(
            provider.context,
            description.audio_source,
            0,
            &.{&output},
        ),
    );
}

test "ARA prepared spectral source falls back and retains successful state" {
    const Prepared = PreparedSource(
        TestController,
        f32,
        16,
        4,
        1,
        64,
        3,
    );
    const Reject = struct {
        fn process(
            _: ?*anyopaque,
            _: usize,
            _: usize,
            _: []Prepared.SpectralEngine.Value,
        ) !void {
            return error.TransformRejected;
        }
    };
    var upstream = TestUpstream{ .samples = undefined };
    for (&upstream.samples, 0..) |*sample, index|
        sample.* = @floatFromInt(index);
    const description = TestDescription{
        .audio_source = .{ .index = 0, .generation = 2 },
        .source_sample_rate = 48_000,
        .source_channel_count = 1,
        .source_sample_count = upstream.samples.len,
    };
    var prepared = Prepared{};
    const fallback = upstream.provider();
    const provider = prepared.providerWithFallback(
        TestRenderer,
        fallback,
    );
    try std.testing.expect(provider.ready(provider.context, &description));
    var output: [8]f32 = undefined;
    try provider.read(
        provider.context,
        description.audio_source,
        4,
        &.{&output},
    );
    try std.testing.expectEqualSlices(
        f32,
        upstream.samples[4..12],
        &output,
    );

    var gain = LinearGain(f32, 16){ .low = 0.5, .high = 0.5 };
    _ = try prepared.prepare(
        &description,
        fallback,
        gain.transform(Prepared.SpectralEngine.Transform),
    );
    try std.testing.expectError(
        error.TransformRejected,
        prepared.prepare(
            &description,
            fallback,
            .{ .process = Reject.process },
        ),
    );
    try provider.read(
        provider.context,
        description.audio_source,
        4,
        &.{&output},
    );
    for (upstream.samples[4..12], output) |expected, actual|
        try std.testing.expectApproxEqAbs(
            expected * 0.5,
            actual,
            0.000_01,
        );

    var malformed = try prepared.publisher.beginUpdate();
    defer malformed.cancel();
    const malformed_state = malformed.value() orelse
        return error.MissingPreparedSourceState;
    malformed_state.channel_count = 2;
    _ = try malformed.commit();
    try provider.read(
        provider.context,
        description.audio_source,
        4,
        &.{&output},
    );
    try std.testing.expectEqualSlices(
        f32,
        upstream.samples[4..12],
        &output,
    );

    _ = try prepared.invalidate();
    try provider.read(
        provider.context,
        description.audio_source,
        4,
        &.{&output},
    );
    try std.testing.expectEqualSlices(
        f32,
        upstream.samples[4..12],
        &output,
    );
}

test "ARA prepared spectral source publishes coherent concurrent reads" {
    const Prepared = PreparedSource(
        TestController,
        f32,
        16,
        4,
        1,
        64,
        8,
    );
    const Shared = struct {
        provider: TestRenderer.SourceProvider,
        source_id: TestSourceId,
        done: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        reads: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),
        mixed: std.atomic.Value(u64) =
            std.atomic.Value(u64).init(0),

        fn read(self: *@This()) void {
            while (!self.done.load(.acquire)) {
                var output: [64]f32 = undefined;
                self.provider.read(
                    self.provider.context,
                    self.source_id,
                    0,
                    &.{&output},
                ) catch continue;
                const first = output[0];
                var coherent = true;
                for (output[1..]) |sample|
                    coherent = coherent and
                        @abs(sample - first) < 0.001;
                if (!coherent)
                    _ = self.mixed.fetchAdd(1, .monotonic);
                _ = self.reads.fetchAdd(1, .monotonic);
            }
        }
    };
    var upstream = TestUpstream{ .samples = @splat(0) };
    const description = TestDescription{
        .audio_source = .{ .index = 0, .generation = 7 },
        .source_sample_rate = 48_000,
        .source_channel_count = 1,
        .source_sample_count = upstream.samples.len,
    };
    var prepared = Prepared{};
    _ = try prepared.prepare(
        &description,
        upstream.provider(),
        .{},
    );
    var shared = Shared{
        .provider = prepared.provider(TestRenderer),
        .source_id = description.audio_source,
    };
    var readers: [2]std.Thread = undefined;
    for (&readers) |*reader|
        reader.* = try std.Thread.spawn(.{}, Shared.read, .{&shared});
    while (shared.reads.load(.acquire) == 0)
        std.Thread.yield() catch {};
    for (1..501) |generation| {
        upstream.samples = @splat(@floatFromInt(generation));
        _ = prepared.prepare(
            &description,
            upstream.provider(),
            .{},
        ) catch continue;
    }
    shared.done.store(true, .release);
    for (readers) |reader| reader.join();
    try std.testing.expectEqual(
        @as(u64, 0),
        shared.mixed.load(.acquire),
    );
    try std.testing.expect(shared.reads.load(.acquire) > 0);
}
