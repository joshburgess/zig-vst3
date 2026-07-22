const std = @import("std");
const plug = @import("zig-vst3-plugin");

const model_rate = 48_000.0;
const maximum_host_frames = 8_192;
const maximum_model_frames = maximum_host_frames * 8 + 2;

pub const Processor = struct {
    pipeline32: plug.dsp.FixedRatePipeline(f32),
    pipeline64: plug.dsp.FixedRatePipeline(f64),
    model32: [maximum_model_frames]f32,
    model64: [maximum_model_frames]f64,
    latency_samples: std.atomic.Value(u32),
    requested_fixed_rate: std.atomic.Value(bool),
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
        self.requested_fixed_rate.store(true, .release);
        self.active_fixed_rate = true;
        self.latency_samples.store(self.fixed_rate_latency, .release);
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

    pub fn process(self: *Processor, _: anytype, comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
        const input = context.inputChannel(0) orelse return;
        const output = context.outputChannel(0) orelse return;
        const requested = self.requested_fixed_rate.load(.acquire);
        if (requested != self.active_fixed_rate) {
            self.reset();
            self.active_fixed_rate = requested;
        }
        if (!self.supported or !self.active_fixed_rate or input.len > maximum_host_frames) {
            @memcpy(output, input);
            return;
        }
        const processed = if (Sample == f32)
            processBlock(f32, &self.pipeline32, &self.model32, input, output)
        else
            processBlock(f64, &self.pipeline64, &self.model64, input, output);
        if (!processed) {
            @memcpy(output, input);
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

pub const FixedRate = struct {
    pub const name = "zig-vst3 Fixed Rate Processor";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .mono;
    pub const event_input = false;
    pub const Params = struct {};
};

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
    processor.process({}, f32, &context);
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
    processor.process({}, f64, &context);
    try std.testing.expectEqualSlices(f64, &input, &output);
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
    processor.process({}, f32, &context);
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
    try std.testing.expectEqual(@as(u32, 31), processor.latencySamples());
    try std.testing.expect(processor.requestFixedRate(false));
    try std.testing.expectEqual(@as(u32, 0), processor.latencySamples());
    try std.testing.expect(processor.requestFixedRate(true));
    try std.testing.expectEqual(@as(u32, 31), processor.latencySamples());
}
