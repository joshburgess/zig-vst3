const std = @import("std");
const plug = @import("zig-vst3-plugin");

const model_rate = 48_000.0;
const maximum_host_frames = 8_192;
const maximum_model_frames = maximum_host_frames * 8 + 2;

pub const Processor = struct {
    pub const component_state_maximum_encoded_size = 7;

    pipeline32: plug.dsp.FixedRatePipeline(f32),
    pipeline64: plug.dsp.FixedRatePipeline(f64),
    model32: [maximum_model_frames]f32,
    model64: [maximum_model_frames]f64,
    latency_samples: std.atomic.Value(u32),
    requested_fixed_rate: std.atomic.Value(bool),
    desired_fixed_rate: std.atomic.Value(bool),
    active_fixed_rate: bool,
    fixed_rate_latency: u32,
    host_requests: ?*plug.HostRequestSink,
    supported: bool,

    pub fn initInPlace(self: *Processor) void {
        self.* = .{
            .pipeline32 = .{},
            .pipeline64 = .{},
            .model32 = undefined,
            .model64 = undefined,
            .latency_samples = std.atomic.Value(u32).init(0),
            .requested_fixed_rate = std.atomic.Value(bool).init(true),
            .desired_fixed_rate = std.atomic.Value(bool).init(true),
            .active_fixed_rate = true,
            .fixed_rate_latency = 0,
            .host_requests = null,
            .supported = false,
        };
    }

    pub fn bindHostRequests(self: *Processor, requests: *plug.HostRequestSink) void {
        self.host_requests = requests;
    }

    pub fn prepare(self: *Processor, config: plug.plugin.PrepareConfig) void {
        self.supported = false;
        self.fixed_rate_latency = 0;
        self.latency_samples.store(0, .release);
        if (config.max_block_size > maximum_host_frames) return;
        self.pipeline32.configure(.{ .host_rate = config.sample_rate, .model_rate = model_rate }) catch return;
        self.pipeline64.configure(.{ .host_rate = config.sample_rate, .model_rate = model_rate }) catch return;
        self.fixed_rate_latency = self.pipeline32.latencySamples();
        const desired = self.desired_fixed_rate.load(.acquire);
        self.requested_fixed_rate.store(desired, .release);
        self.active_fixed_rate = desired;
        self.latency_samples.store(if (desired) self.fixed_rate_latency else 0, .release);
        self.supported = true;
    }

    pub fn reset(self: *Processor) void {
        if (!self.supported) return;
        self.pipeline32.reset();
        self.pipeline64.reset();
    }

    pub fn latencySamples(self: *const Processor) u32 {
        return self.latency_samples.load(.acquire);
    }

    pub fn requestFixedRate(self: *Processor, enabled: bool) bool {
        if (enabled and !self.supported) return false;
        const previous_desired = self.desired_fixed_rate.swap(enabled, .acq_rel);
        if (self.commitDesiredMode()) return true;
        self.desired_fixed_rate.store(previous_desired, .release);
        return false;
    }

    pub fn afterComponentStateRestore(self: *Processor) void {
        _ = self.commitDesiredMode();
    }

    pub fn componentConnectionReady(self: *Processor) void {
        _ = self.commitDesiredMode();
    }

    pub fn writeComponentState(self: *const Processor, writer: anytype) !void {
        try writer.writeAll("FXRT");
        try writer.writeInt(u16, 1, .little);
        try writer.writeByte(@intFromBool(self.desired_fixed_rate.load(.acquire)));
    }

    pub fn readComponentState(self: *Processor, reader: anytype) !void {
        var magic: [4]u8 = undefined;
        try reader.readSliceAll(&magic);
        if (!std.mem.eql(u8, &magic, "FXRT")) return error.InvalidFixedRateState;
        if (try reader.takeInt(u16, .little) != 1) return error.UnsupportedFixedRateState;
        const enabled = switch (try reader.takeByte()) {
            0 => false,
            1 => true,
            else => return error.InvalidFixedRateState,
        };
        if (reader.seek != reader.end) return error.InvalidFixedRateState;
        self.desired_fixed_rate.store(enabled, .release);
    }

    fn commitDesiredMode(self: *Processor) bool {
        const enabled = self.desired_fixed_rate.load(.acquire);
        if (enabled and !self.supported) return false;
        const previous = self.requested_fixed_rate.load(.acquire);
        if (previous == enabled) return true;
        self.latency_samples.store(if (enabled) self.fixed_rate_latency else 0, .release);
        if (self.host_requests) |requests| {
            requests.markLatencyChanged();
            if (!requests.dispatchPending()) {
                self.latency_samples.store(if (previous) self.fixed_rate_latency else 0, .release);
                return false;
            }
        }
        self.requested_fixed_rate.store(enabled, .release);
        return true;
    }

    pub fn process(
        self: *Processor,
        context: *plug.process.ProcessContext(f32),
    ) void {
        self.processSample(f32, context);
    }

    pub fn process64(
        self: *Processor,
        context: *plug.process.ProcessContext(f64),
    ) void {
        self.processSample(f64, context);
    }

    fn processSample(
        self: *Processor,
        comptime Sample: type,
        context: *plug.process.ProcessContext(Sample),
    ) void {
        var denormals = plug.dsp.DenormalScope.enter();
        defer denormals.leave();

        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        const requested = self.requested_fixed_rate.load(.acquire);
        if (requested != self.active_fixed_rate) {
            self.reset();
            self.active_fixed_rate = requested;
        }
        if (!self.supported or !self.active_fixed_rate or input.len > maximum_host_frames) {
            for (input, output) |sample, *destination| {
                destination.* = sample;
            }
            return;
        }
        const processed = if (Sample == f32)
            processBlock(f32, &self.pipeline32, &self.model32, input, output)
        else
            processBlock(f64, &self.pipeline64, &self.model64, input, output);
        if (!processed) {
            for (input, output) |sample, *destination| {
                destination.* = sample;
            }
            self.reset();
        }
    }

    fn processBlock(
        comptime Sample: type,
        pipeline: *plug.dsp.FixedRatePipeline(Sample),
        model: []Sample,
        input: []const Sample,
        output: []Sample,
    ) bool {
        const model_frames = pipeline.convertInput(input, model) catch return false;
        for (model[0..model_frames]) |*sample| sample.* *= 0.5;
        pipeline.convertOutput(model[0..model_frames], output) catch return false;
        return true;
    }
};

pub const RuntimeProcessor = struct {
    pub const latency_telemetry_source_id: u32 = 0;
    pub const name = "zig-vst3 Fixed Rate Processor";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .mono;
    pub const event_input = false;
    pub const Params = struct {};
    pub const component_state_maximum_encoded_size =
        Processor.component_state_maximum_encoded_size;

    allocator: std.mem.Allocator,
    engine: *Processor,

    pub fn init(allocator: std.mem.Allocator) !RuntimeProcessor {
        const engine = try allocator.create(Processor);
        engine.initInPlace();
        return .{
            .allocator = allocator,
            .engine = engine,
        };
    }

    pub fn bindHostRequests(
        self: *RuntimeProcessor,
        requests: *plug.HostRequestSink,
    ) void {
        self.engine.bindHostRequests(requests);
    }

    pub fn prepare(
        self: *RuntimeProcessor,
        config: plug.plugin.PrepareConfig,
    ) void {
        self.engine.prepare(config);
    }

    pub fn reset(self: *RuntimeProcessor) void {
        self.engine.reset();
    }

    pub fn latencySamples(self: *const RuntimeProcessor) u32 {
        return self.engine.latencySamples();
    }

    pub fn guiTelemetryLoad(
        self: *const RuntimeProcessor,
        source_id: u32,
    ) f64 {
        if (source_id != latency_telemetry_source_id) return 0.0;
        return @floatFromInt(self.latencySamples());
    }

    pub fn requestFixedRate(
        self: *RuntimeProcessor,
        enabled: bool,
    ) bool {
        return self.engine.requestFixedRate(enabled);
    }

    pub fn afterComponentStateRestore(
        self: *RuntimeProcessor,
    ) void {
        self.engine.afterComponentStateRestore();
    }

    pub fn componentConnectionReady(
        self: *RuntimeProcessor,
    ) void {
        self.engine.componentConnectionReady();
    }

    pub fn writeComponentState(
        self: *const RuntimeProcessor,
        writer: anytype,
    ) !void {
        try self.engine.writeComponentState(writer);
    }

    pub fn readComponentState(
        self: *RuntimeProcessor,
        reader: anytype,
    ) !void {
        try self.engine.readComponentState(reader);
    }

    pub fn process(
        self: *RuntimeProcessor,
        context: *plug.process.ProcessContext(f32),
    ) void {
        self.engine.process(context);
    }

    pub fn process64(
        self: *RuntimeProcessor,
        context: *plug.process.ProcessContext(f64),
    ) void {
        self.engine.process64(context);
    }

    pub fn deinit(self: *RuntimeProcessor) void {
        self.allocator.destroy(self.engine);
    }
};

pub const FixedRate = RuntimeProcessor;

test "fixed-rate runtime reports outer allocation failure" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        RuntimeProcessor.init(failing.allocator()),
    );
}

test "fixed-rate processor renders the model path at exact host latency" {
    const allocator = std.testing.allocator;
    const processor = try allocator.create(Processor);
    defer allocator.destroy(processor);
    processor.initInPlace();
    processor.prepare(.{ .sample_rate = 44_100, .max_block_size = 1024 });
    try std.testing.expectEqual(@as(u32, 31), processor.latencySamples());

    var input: [1024]f32 = @splat(0.0);
    input[0] = 1.0;
    var output: [1024]f32 = undefined;
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    var context = try plug.process.ProcessContext(f32).init(44_100, &inputs, &outputs);
    processor.process(&context);
    var peak_index: usize = 0;
    for (output, 0..) |sample, index| {
        if (@abs(sample) > @abs(output[peak_index])) peak_index = index;
    }
    try std.testing.expectEqual(@as(usize, processor.latencySamples()), peak_index);
    try std.testing.expect(output[peak_index] > 0.4);
    try std.testing.expect(output[peak_index] < 0.51);
}

test "fixed-rate processor falls back safely outside its bounded rate ratio" {
    const allocator = std.testing.allocator;
    const processor = try allocator.create(Processor);
    defer allocator.destroy(processor);
    processor.initInPlace();
    processor.prepare(.{ .sample_rate = 1_234_567.8, .max_block_size = 64 });
    try std.testing.expectEqual(@as(u32, 0), processor.latencySamples());
    const input = [_]f64{ 0.25, -0.5 };
    var output = [_]f64{ 0.0, 0.0 };
    const inputs = [_][]const f64{&input};
    const outputs = [_][]f64{&output};
    var context = try plug.process.ProcessContext(f64).init(1_234_567.8, &inputs, &outputs);
    processor.process64(&context);
    try std.testing.expectEqualSlices(f64, &input, &output);
}

test "fixed-rate fallback supports in-place audio buffers" {
    const allocator = std.testing.allocator;
    const processor = try allocator.create(Processor);
    defer allocator.destroy(processor);
    processor.initInPlace();
    processor.prepare(.{ .sample_rate = 1_234_567.8, .max_block_size = 64 });
    var samples = [_]f64{ 0.25, -0.5 };
    const expected = samples;
    const inputs = [_][]const f64{&samples};
    const outputs = [_][]f64{&samples};
    var context = try plug.process.ProcessContext(f64).init(
        1_234_567.8,
        &inputs,
        &outputs,
    );

    processor.process64(&context);

    try std.testing.expectEqualSlices(f64, &expected, &samples);
}

test "fixed-rate processor flushes subnormal output without leaking thread policy" {
    if (!plug.dsp.denormals.supported) return error.SkipZigTest;
    const Harness = struct {
        fn run(comptime Sample: type) !void {
            const allocator = std.testing.allocator;
            const processor = try allocator.create(Processor);
            defer allocator.destroy(processor);
            processor.initInPlace();
            processor.prepare(.{ .sample_rate = 48_000, .max_block_size = 128 });

            var input: [128]Sample = @splat(0.0);
            input[0] = std.math.floatMin(Sample) * 2.0;
            var output: [128]Sample = undefined;
            const inputs = [_][]const Sample{&input};
            const outputs = [_][]Sample{&output};
            var context = try plug.process.ProcessContext(Sample).init(48_000, &inputs, &outputs);
            const flush_before = plug.dsp.denormals.flushToZeroEnabled();
            if (Sample == f32)
                processor.process(&context)
            else
                processor.process64(&context);
            try std.testing.expectEqual(flush_before, plug.dsp.denormals.flushToZeroEnabled());
            for (output) |sample| {
                try std.testing.expect(sample == 0.0 or std.math.isNormal(sample));
            }
        }
    };

    try Harness.run(f32);
    try Harness.run(f64);
}

test "fixed-rate processor changes prepared latency before block-boundary activation" {
    const allocator = std.testing.allocator;
    const processor = try allocator.create(Processor);
    defer allocator.destroy(processor);
    processor.initInPlace();
    processor.prepare(.{ .sample_rate = 96_000, .max_block_size = 64 });
    try std.testing.expectEqual(@as(u32, 48), processor.latencySamples());
    try std.testing.expect(processor.requestFixedRate(false));
    try std.testing.expectEqual(@as(u32, 0), processor.latencySamples());

    const input = [_]f32{ 0.5, -0.25 };
    var output = [_]f32{ 0.0, 0.0 };
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    var context = try plug.process.ProcessContext(f32).init(96_000, &inputs, &outputs);
    processor.process(&context);
    try std.testing.expectEqualSlices(f32, &input, &output);
    try std.testing.expect(processor.requestFixedRate(true));
    try std.testing.expectEqual(@as(u32, 48), processor.latencySamples());
}

test "fixed-rate processor replaces stale latency during repeated preparation" {
    const allocator = std.testing.allocator;
    const processor = try allocator.create(Processor);
    defer allocator.destroy(processor);
    processor.initInPlace();
    processor.prepare(.{ .sample_rate = 96_000, .max_block_size = 64 });
    try std.testing.expectEqual(@as(u32, 48), processor.latencySamples());
    try std.testing.expect(processor.requestFixedRate(false));
    try std.testing.expectEqual(@as(u32, 0), processor.latencySamples());

    processor.prepare(.{ .sample_rate = 44_100, .max_block_size = 128 });
    try std.testing.expectEqual(@as(u32, 0), processor.latencySamples());
    try std.testing.expect(processor.requestFixedRate(false));
    try std.testing.expectEqual(@as(u32, 0), processor.latencySamples());
    try std.testing.expect(processor.requestFixedRate(true));
    try std.testing.expectEqual(@as(u32, 31), processor.latencySamples());
}

test "fixed-rate processor restores mode before preparation without stale latency" {
    var source: Processor = undefined;
    source.initInPlace();
    try std.testing.expect(source.requestFixedRate(false));
    var bytes: [Processor.component_state_maximum_encoded_size]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try source.writeComponentState(&writer);

    var restored: Processor = undefined;
    restored.initInPlace();
    var reader = std.Io.Reader.fixed(bytes[0..writer.end]);
    try restored.readComponentState(&reader);
    restored.prepare(.{ .sample_rate = 96_000, .max_block_size = 64 });
    try std.testing.expectEqual(@as(u32, 0), restored.latencySamples());
    try std.testing.expect(!restored.requested_fixed_rate.load(.acquire));
    try std.testing.expect(!restored.active_fixed_rate);
}
