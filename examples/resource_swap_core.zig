const std = @import("std");
const plug = @import("zig-vst3-plugin");

pub const PreparedGraph = struct {
    gain: f64,
};

const GraphExchange = plug.resource.exchange.Exchange(struct {
    pub const Resource = PreparedGraph;
    pub const slot_capacity = 4;

    pub fn destroy(resource: *PreparedGraph) void {
        std.heap.page_allocator.destroy(resource);
    }
});

const PreparationRequest = struct {
    exchange: *GraphExchange,
    generation: u64,
    gain: f64,
    work_units: usize,
};

const PreparationJob = plug.resource.job.Job(struct {
    pub const Request = PreparationRequest;
    pub const Result = u64;
    pub const Failure = enum { allocation_failed, publication_failed };
    pub const maximum_work_units = 4_096;
    pub const maximum_result_units = 1;
    pub const maximum_runtime_nanoseconds = 5 * std.time.ns_per_s;

    pub fn run(request: Request, context: *plug.resource.job.WorkerContext) plug.resource.job.Outcome(Result, Failure) {
        context.setTotalUnits(request.work_units) catch return .cancelled;
        for (0..request.work_units) |index| {
            if (context.cancellationRequested()) return .cancelled;
            context.advance(index + 1, request.work_units) catch return .cancelled;
        }
        const graph = std.heap.page_allocator.create(PreparedGraph) catch return .{ .failure = .allocation_failed };
        graph.* = .{ .gain = request.gain };
        request.exchange.publish(request.generation, graph) catch {
            std.heap.page_allocator.destroy(graph);
            return .{ .failure = .publication_failed };
        };
        return .{ .success = .{ .value = request.generation, .result_units = 1 } };
    }
});

pub const Processor = struct {
    exchange: GraphExchange,
    preparation: PreparationJob,
    next_generation: u64,

    pub fn initInPlace(self: *Processor) void {
        self.* = .{
            .exchange = .{},
            .preparation = PreparationJob.init(),
            .next_generation = 1,
        };
        _ = self.preparation.submit(.{
            .exchange = &self.exchange,
            .generation = 1,
            .gain = 1.0,
            .work_units = 1,
        });
    }

    pub fn deinit(self: *Processor) void {
        self.preparation.deinit();
        self.exchange.retireAllAfterProcessingStops();
        self.exchange.deinit();
    }

    pub fn requestGain(self: *Processor, gain: f64, work_units: usize) bool {
        if (!std.math.isFinite(gain) or work_units == 0) return false;
        self.next_generation +%= 1;
        if (self.next_generation == 0) self.next_generation = 1;
        return self.preparation.submit(.{
            .exchange = &self.exchange,
            .generation = self.next_generation,
            .gain = gain,
            .work_units = work_units,
        });
    }

    pub fn waitForPreparation(self: *Processor) bool {
        self.preparation.wait();
        const snapshot = self.preparation.snapshot();
        if (snapshot.status != .ready) return false;
        return self.preparation.takeResult(snapshot.generation) != null;
    }

    pub fn reclaimRetired(self: *Processor) usize {
        return self.exchange.reclaim();
    }

    pub fn process(self: *Processor, _: anytype, comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
        self.processBlock(Sample, context);
    }

    pub fn processBlock(self: *Processor, comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
        _ = self.exchange.adoptPending();
        const gain: Sample = @floatCast(if (self.exchange.active()) |active| active.resource.gain else 1.0);
        for (0..@min(context.inputChannelCount(), context.outputChannelCount())) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (input, output) |sample, *destination| destination.* = sample * gain;
        }
    }
};

pub const ResourceSwap = struct {
    pub const name = "zig-vst3 Resource Swap";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .mono;
    pub const event_input = false;
    pub const Params = struct {};
};

test "resource swap processor adopts prepared graphs at block boundaries" {
    var processor: Processor = undefined;
    processor.initInPlace();
    defer processor.deinit();
    try std.testing.expect(processor.waitForPreparation());

    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    var context = try plug.process.ProcessContext(f32).init(48_000, &inputs, &outputs);
    processor.processBlock(f32, &context);
    try std.testing.expectEqualSlices(f32, &input, &output);

    try std.testing.expect(processor.requestGain(2.0, 32));
    try std.testing.expect(processor.waitForPreparation());
    processor.processBlock(f32, &context);
    try std.testing.expectEqualSlices(f32, &.{ 0.5, -1.0 }, &output);
    try std.testing.expectEqual(@as(usize, 1), processor.reclaimRetired());
}
