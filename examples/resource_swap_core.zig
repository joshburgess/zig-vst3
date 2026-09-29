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
    running_generation: *std.atomic.Value(u64),
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
        request.running_generation.store(request.generation, .release);
        defer {
            _ = request.running_generation.cmpxchgStrong(
                request.generation,
                0,
                .acq_rel,
                .acquire,
            );
        }
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
    running_generation: std.atomic.Value(u64),
    latest_requested_generation: std.atomic.Value(u64),
    next_generation: u64,

    pub fn initInPlace(self: *Processor) void {
        self.* = .{
            .exchange = .{},
            .preparation = PreparationJob.init(),
            .running_generation = std.atomic.Value(u64).init(0),
            .latest_requested_generation = std.atomic.Value(u64).init(1),
            .next_generation = 1,
        };
        _ = self.preparation.submit(.{
            .exchange = &self.exchange,
            .running_generation = &self.running_generation,
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
        if (!plug.realtime_audit.observe(.allocation)) return false;
        if (!std.math.isFinite(gain) or work_units == 0) return false;
        const generation = self.nextGeneration();
        self.latest_requested_generation.store(generation, .release);
        return self.preparation.submit(.{
            .exchange = &self.exchange,
            .running_generation = &self.running_generation,
            .generation = generation,
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

    fn nextGeneration(self: *Processor) u64 {
        const running = self.running_generation.load(.acquire);
        const requested = self.latest_requested_generation.load(.acquire);
        const exchange_latest = self.exchange.latest_generation.load(.acquire);
        const exchange_active = self.exchange.activeGeneration();
        var candidate = self.next_generation;
        while (true) {
            candidate +%= 1;
            if (candidate == 0) candidate = 1;
            if (candidate == running or
                candidate == requested or
                candidate == exchange_latest or
                candidate == exchange_active)
            {
                continue;
            }
            self.next_generation = candidate;
            return candidate;
        }
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

pub const RuntimeProcessor = struct {
    pub const name = ResourceSwap.name;
    pub const vendor = ResourceSwap.vendor;
    pub const audio_input_layout =
        ResourceSwap.audio_input_layout;
    pub const audio_output_layout =
        ResourceSwap.audio_output_layout;
    pub const event_input = ResourceSwap.event_input;
    pub const Params = ResourceSwap.Params;

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

    pub fn process(
        self: *RuntimeProcessor,
        context: *plug.process.ProcessContext(f32),
    ) void {
        self.engine.processBlock(f32, context);
    }

    pub fn process64(
        self: *RuntimeProcessor,
        context: *plug.process.ProcessContext(f64),
    ) void {
        self.engine.processBlock(f64, context);
    }

    pub fn waitForPreparation(self: *RuntimeProcessor) bool {
        return self.engine.waitForPreparation();
    }

    pub fn requestGain(
        self: *RuntimeProcessor,
        gain: f64,
        work_units: usize,
    ) bool {
        return self.engine.requestGain(gain, work_units);
    }

    pub fn reclaimRetired(self: *RuntimeProcessor) usize {
        return self.engine.reclaimRetired();
    }

    pub fn deinit(self: *RuntimeProcessor) void {
        self.engine.deinit();
        self.allocator.destroy(self.engine);
    }
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

test "resource swap requests reject realtime use before generation publication" {
    var processor: Processor = undefined;
    processor.initInPlace();
    defer processor.deinit();
    try std.testing.expect(processor.waitForPreparation());
    const generation = processor.next_generation;

    const scope = plug.realtime_audit.Scope.enter();
    try std.testing.expect(!processor.requestGain(2.0, 32));
    const report = scope.leave();

    try std.testing.expectEqual(plug.realtime_audit.Operation.allocation, report.first_violation.?);
    try std.testing.expectEqual(@as(u32, 1), report.count(.allocation));
    try std.testing.expectEqual(generation, processor.next_generation);
    try std.testing.expectEqual(generation, processor.latest_requested_generation.load(.acquire));
}

test "resource swap runtime owns the self-referential engine at a stable address" {
    var runtime = try RuntimeProcessor.init(std.testing.allocator);
    defer runtime.deinit();

    try std.testing.expect(runtime.waitForPreparation());
    try std.testing.expect(runtime.requestGain(0.5, 16));
    try std.testing.expect(runtime.waitForPreparation());

    const input = [_]f64{ 0.5, -1.0 };
    var output = [_]f64{ 0.0, 0.0 };
    const inputs = [_][]const f64{&input};
    const outputs = [_][]f64{&output};
    var context = try plug.process.ProcessContext(f64).init(
        48_000,
        &inputs,
        &outputs,
    );
    runtime.process64(&context);

    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.25, -0.5 },
        &output,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        runtime.reclaimRetired(),
    );
}

test "resource swap runtime reports outer allocation failure" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        RuntimeProcessor.init(failing.allocator()),
    );
}

test "resource swap publication generation skips retained identities" {
    var processor: Processor = undefined;
    processor.initInPlace();
    defer processor.deinit();
    try std.testing.expect(processor.waitForPreparation());

    processor.next_generation = std.math.maxInt(u64);
    processor.running_generation.store(1, .release);
    processor.latest_requested_generation.store(2, .release);
    processor.exchange.latest_generation.store(3, .release);
    processor.exchange.active_generation.store(4, .release);
    try std.testing.expectEqual(@as(u64, 5), processor.nextGeneration());
}
