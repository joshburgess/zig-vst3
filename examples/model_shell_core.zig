const std = @import("std");
const plug = @import("zig-vst3-plugin");

const maximum_model_bytes = 4096;
const maximum_path_bytes = 1024;
const maximum_metadata_bytes = 96;
const maximum_host_frames = 4096;
const maximum_model_frames = maximum_host_frames * 8 + 2;

pub const resource_status_source_id = 0;
pub const resource_metadata_source_id = 1;
pub const resource_progress_source_id = 2;
pub const resource_can_cancel_source_id = 3;
pub const resource_can_retry_source_id = 4;
pub const resource_cancellation_pending_source_id = 5;

pub const LinearModel = struct {
    gain: f32,
    sample_rate: u32,
    state: f64,

    fn processSample(self: *LinearModel, comptime Sample: type, sample: Sample) Sample {
        self.state = 0.5 * self.state + 0.5 * @as(f64, @floatCast(sample));
        return @floatCast(@as(f64, self.gain) * self.state);
    }

    fn reset(self: *LinearModel) void {
        self.state = 0.0;
    }

    fn prewarm(self: *LinearModel) void {
        for (0..64) |index| _ = self.processSample(f64, if (index == 0) 1.0 else 0.0);
        self.reset();
    }
};

pub const ActivationQuality = enum {
    accurate,
    fast,
};

const ApprovalState = struct {
    host_rate_bits: std.atomic.Value(u64) = std.atomic.Value(u64).init(@bitCast(@as(f64, 48_000))),
    max_block_size: std.atomic.Value(u32) = std.atomic.Value(u32).init(maximum_host_frames),
    approved_generation: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    latency_samples: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    host_request_address: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    fn bindHostRequests(self: *ApprovalState, requests: *plug.HostRequestSink) void {
        self.host_request_address.store(@intFromPtr(requests), .release);
    }

    fn configure(self: *ApprovalState, host_rate: f64, max_block_size: u32) void {
        self.host_rate_bits.store(@bitCast(host_rate), .release);
        self.max_block_size.store(max_block_size, .release);
        self.approved_generation.store(0, .release);
        self.latency_samples.store(0, .release);
    }

    fn approve(self: *ApprovalState, generation: u64, metadata: RuntimePublication) void {
        if (self.host_rate_bits.load(.acquire) != @as(u64, @bitCast(metadata.host_rate)) or
            self.max_block_size.load(.acquire) != metadata.max_block_size)
        {
            return;
        }
        const previous_latency = self.latency_samples.swap(metadata.latency_samples, .acq_rel);
        if (previous_latency != metadata.latency_samples) {
            const address = self.host_request_address.load(.acquire);
            if (address != 0) {
                const requests: *plug.HostRequestSink = @ptrFromInt(address);
                requests.markLatencyChanged();
                if (!requests.dispatchPending()) {
                    self.latency_samples.store(previous_latency, .release);
                    return;
                }
            }
        }
        self.approved_generation.store(generation, .release);
    }
};

const HostPreparation = struct {
    host_rate: f64,
    max_block_size: u32,
    approval: ?*ApprovalState,
};

const RuntimePublication = struct {
    host_rate: f64,
    max_block_size: u32,
    latency_samples: u32,
};

pub const PreparedRuntime = struct {
    model: LinearModel,
    pipeline32: plug.dsp.FixedRatePipeline(f32),
    pipeline64: plug.dsp.FixedRatePipeline(f64),
    model32: [maximum_model_frames]f32,
    model64: [maximum_model_frames]f64,
    host_rate: f64,
    max_block_size: u32,
    latency_samples: u32,
    resampling: bool,
    activation_quality: ActivationQuality,

    fn setActivationQuality(self: *PreparedRuntime, quality: ActivationQuality) void {
        self.activation_quality = quality;
    }

    fn process(self: *PreparedRuntime, comptime Sample: type, input: []const Sample, output: []Sample) bool {
        if (input.len != output.len or input.len > self.max_block_size) return false;
        if (!self.resampling) {
            for (input, output) |sample, *destination| {
                destination.* = self.model.processSample(Sample, sample);
            }
            return true;
        }
        if (Sample == f32) {
            return self.processResampled(f32, &self.pipeline32, &self.model32, input, output);
        }
        return self.processResampled(f64, &self.pipeline64, &self.model64, input, output);
    }

    fn processResampled(
        self: *PreparedRuntime,
        comptime Sample: type,
        pipeline: *plug.dsp.FixedRatePipeline(Sample),
        scratch: []Sample,
        input: []const Sample,
        output: []Sample,
    ) bool {
        const model_frames = pipeline.convertInput(input, scratch) catch return false;
        for (scratch[0..model_frames]) |*sample| {
            sample.* = self.model.processSample(Sample, sample.*);
        }
        pipeline.convertOutput(scratch[0..model_frames], output) catch return false;
        return true;
    }

    fn reset(self: *PreparedRuntime) void {
        self.model.reset();
        self.pipeline32.reset();
        self.pipeline64.reset();
    }

    fn matches(self: *const PreparedRuntime, context: HostPreparation) bool {
        return self.host_rate == context.host_rate and self.max_block_size == context.max_block_size;
    }
};

pub const LoadFailure = enum {
    missing,
    too_large,
    malformed,
    unsupported,
    allocation_failed,
};

const ModelPath = plug.resource.BoundedPath(maximum_path_bytes);
const PreparedModel = plug.resource.PreparedResource(PreparedRuntime, maximum_metadata_bytes);

const ModelRecovery = plug.resource.ResourceRecovery(struct {
    pub const Resource = PreparedRuntime;
    pub const Failure = LoadFailure;
    pub const path_capacity = maximum_path_bytes;
    pub const metadata_capacity = maximum_metadata_bytes;
    pub const slot_capacity = 4;
    pub const maximum_work_units = maximum_model_bytes;
    pub const maximum_result_units = 1;
    pub const maximum_runtime_nanoseconds = 5 * std.time.ns_per_s;
    pub const mutable_active = true;
    pub const PreparationContext = HostPreparation;
    pub const initial_preparation_context: PreparationContext = .{
        .host_rate = 48_000,
        .max_block_size = maximum_host_frames,
        .approval = null,
    };
    pub const PublicationMetadata = RuntimePublication;

    pub fn prepare(path: ModelPath, preparation: PreparationContext, context: *plug.resource.job.WorkerContext) plug.resource.job.Outcome(PreparedModel, Failure) {
        const file = std.Io.Dir.cwd().openFile(context.io, path.slice(), .{}) catch return .{ .failure = .missing };
        defer file.close(context.io);
        var bytes: [maximum_model_bytes + 1]u8 = undefined;
        const count = file.readPositionalAll(context.io, &bytes, 0) catch return .{ .failure = .malformed };
        if (count > maximum_model_bytes) return .{ .failure = .too_large };
        context.setTotalUnits(@max(count, 1)) catch return .cancelled;
        context.setPhase(.loading) catch return .cancelled;
        context.advance(@max(count, 1), @max(count, 1)) catch return .cancelled;
        if (context.cancellationRequested()) return .cancelled;

        const Document = struct {
            version: u32,
            gain: f32,
            sample_rate: u32,
        };
        var parsed = std.json.parseFromSlice(Document, std.heap.page_allocator, bytes[0..count], .{}) catch return .{ .failure = .malformed };
        defer parsed.deinit();
        if (parsed.value.version != 1) return .{ .failure = .unsupported };
        if (!std.math.isFinite(parsed.value.gain) or parsed.value.gain < -16.0 or parsed.value.gain > 16.0) {
            return .{ .failure = .malformed };
        }
        if (parsed.value.sample_rate < 8_000 or parsed.value.sample_rate > 192_000) return .{ .failure = .unsupported };
        if (!std.math.isFinite(preparation.host_rate) or preparation.host_rate < 8_000 or preparation.host_rate > 768_000) {
            return .{ .failure = .unsupported };
        }
        if (preparation.max_block_size == 0 or preparation.max_block_size > maximum_host_frames) {
            return .{ .failure = .unsupported };
        }

        const runtime = std.heap.page_allocator.create(PreparedRuntime) catch return .{ .failure = .allocation_failed };
        const pipeline32 = plug.dsp.FixedRatePipeline(f32).init(.{
            .host_rate = preparation.host_rate,
            .model_rate = @floatFromInt(parsed.value.sample_rate),
        }) catch {
            std.heap.page_allocator.destroy(runtime);
            return .{ .failure = .unsupported };
        };
        const pipeline64 = plug.dsp.FixedRatePipeline(f64).init(.{
            .host_rate = preparation.host_rate,
            .model_rate = @floatFromInt(parsed.value.sample_rate),
        }) catch {
            std.heap.page_allocator.destroy(runtime);
            return .{ .failure = .unsupported };
        };
        const required_capacity = pipeline32.requiredModelCapacity(preparation.max_block_size) catch {
            std.heap.page_allocator.destroy(runtime);
            return .{ .failure = .unsupported };
        };
        if (required_capacity > maximum_model_frames) {
            std.heap.page_allocator.destroy(runtime);
            return .{ .failure = .unsupported };
        }
        const resampling = @abs(preparation.host_rate - @as(f64, @floatFromInt(parsed.value.sample_rate))) >= 0.5;
        runtime.* = .{
            .model = .{
                .gain = parsed.value.gain,
                .sample_rate = parsed.value.sample_rate,
                .state = 0.0,
            },
            .pipeline32 = pipeline32,
            .pipeline64 = pipeline64,
            .model32 = undefined,
            .model64 = undefined,
            .host_rate = preparation.host_rate,
            .max_block_size = preparation.max_block_size,
            .latency_samples = if (resampling) pipeline32.latencySamples() else 0,
            .resampling = resampling,
            .activation_quality = .accurate,
        };
        runtime.model.prewarm();
        var metadata_bytes: [maximum_metadata_bytes]u8 = undefined;
        const metadata = std.fmt.bufPrint(&metadata_bytes, "Linear, {} Hz, gain {d:.3}", .{
            parsed.value.sample_rate,
            parsed.value.gain,
        }) catch {
            std.heap.page_allocator.destroy(runtime);
            return .{ .failure = .malformed };
        };
        return .{ .success = .{
            .value = .{
                .resource = runtime,
                .identity = plug.resource.Identity.fromBytes(bytes[0..count]),
                .resource_schema_version = parsed.value.version,
                .metadata = plug.resource.BoundedMetadata(maximum_metadata_bytes).init(metadata) catch {
                    std.heap.page_allocator.destroy(runtime);
                    return .{ .failure = .malformed };
                },
            },
            .result_units = 1,
        } };
    }

    pub fn destroy(runtime: *PreparedRuntime) void {
        std.heap.page_allocator.destroy(runtime);
    }

    pub fn publicationMetadata(runtime: *const PreparedRuntime) PublicationMetadata {
        return .{
            .host_rate = runtime.host_rate,
            .max_block_size = runtime.max_block_size,
            .latency_samples = runtime.latency_samples,
        };
    }

    pub fn publicationReady(preparation: PreparationContext, generation: u64, metadata: PublicationMetadata) void {
        if (preparation.approval) |approval| approval.approve(generation, metadata);
    }

    pub fn failureStatus(failure: Failure) plug.resource.RecoveryStatus {
        return switch (failure) {
            .missing => .missing,
            .too_large, .unsupported => .unsupported,
            .malformed, .allocation_failed => .failed,
        };
    }
});

pub const Processor = struct {
    pub const component_state_maximum_encoded_size = ModelRecovery.component_state_maximum_encoded_size;

    models: ModelRecovery,
    approval: ApprovalState,
    preparation: HostPreparation,
    activation_quality_latch: plug.process.BlockParameterLatch,

    pub fn initInPlace(self: *Processor) void {
        self.* = .{
            .models = ModelRecovery.init(),
            .approval = .{},
            .preparation = .{ .host_rate = 48_000, .max_block_size = maximum_host_frames, .approval = null },
            .activation_quality_latch = .init(0, 0.0),
        };
        self.preparation.approval = &self.approval;
        _ = self.models.updatePreparationContext(self.preparation);
    }

    pub fn deinit(self: *Processor) void {
        self.models.deinit();
    }

    pub fn importModel(self: *Processor, path: []const u8) bool {
        return self.models.importPath(path);
    }

    pub fn relinkModel(self: *Processor, path: []const u8) bool {
        return self.models.relink(path);
    }

    pub fn resourcePathReceiver(self: *Processor) *ModelRecovery {
        return &self.models;
    }

    pub fn waitForModel(self: *Processor) void {
        self.models.waitAndPoll();
    }

    pub fn maintain(self: *Processor) usize {
        self.models.poll();
        return self.models.reclaim();
    }

    pub fn bindHostRequests(self: *Processor, requests: *plug.HostRequestSink) void {
        self.approval.bindHostRequests(requests);
    }

    pub fn prepare(self: *Processor, config: plug.plugin.PrepareConfig) void {
        self.preparation = .{
            .host_rate = config.sample_rate,
            .max_block_size = config.max_block_size,
            .approval = &self.approval,
        };
        self.approval.configure(config.sample_rate, config.max_block_size);
        _ = self.models.updatePreparationContext(self.preparation);
    }

    pub fn latencySamples(self: *const Processor) u32 {
        return self.approval.latency_samples.load(.acquire);
    }

    pub fn resourceSnapshot(self: *const Processor) ModelRecovery.Snapshot {
        return self.models.snapshot();
    }

    pub fn guiTelemetryLoad(self: *Processor, source_id: u32) f64 {
        _ = self.maintain();
        const presentation = self.models.presentationSnapshot();
        return switch (source_id) {
            resource_status_source_id => @floatFromInt(@intFromEnum(presentation.status)),
            resource_progress_source_id => presentation.progress.value,
            resource_can_cancel_source_id => @floatFromInt(@intFromBool(presentation.can_cancel)),
            resource_can_retry_source_id => @floatFromInt(@intFromBool(presentation.can_retry)),
            resource_cancellation_pending_source_id => @floatFromInt(@intFromBool(presentation.cancellation_pending)),
            else => 0.0,
        };
    }

    pub fn guiTelemetryLoadText(self: *Processor, source_id: u32, output: []u8) usize {
        _ = self.maintain();
        const presentation = self.models.presentationSnapshot();
        const text = switch (source_id) {
            resource_status_source_id => presentation.statusText(),
            resource_metadata_source_id => presentation.metadata(),
            else => "",
        };
        const count = @min(text.len, output.len);
        @memcpy(output[0..count], text[0..count]);
        return count;
    }

    pub fn componentStateEncodedSize(self: *const Processor) usize {
        return self.models.componentStateEncodedSize();
    }

    pub fn writeComponentState(self: *const Processor, writer: anytype) !void {
        try self.models.writeComponentState(writer);
    }

    pub fn readComponentState(self: *Processor, reader: anytype) !void {
        try self.models.readComponentState(reader);
    }

    pub fn process(self: *Processor, parameters: anytype, comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
        _ = self.models.adoptPendingThroughAtBlockBoundary(self.approval.approved_generation.load(.acquire));
        const runtime = self.models.activeMutable();
        const persisted_quality = fastActivationNormalized(parameters, self.activation_quality_latch.nextBlockValue());
        const block_quality = self.activation_quality_latch.beginBlock(context.parameterChanges(), persisted_quality);
        if (runtime) |active| {
            active.setActivationQuality(if (block_quality >= 0.5) .fast else .accurate);
        }
        for (0..context.outputChannelCount()) |channel| {
            const output = context.outputChannel(channel) orelse continue;
            if (runtime == null or !runtime.?.matches(self.preparation)) {
                @memset(output, 0);
                continue;
            }
            const input = context.inputChannel(channel) orelse {
                @memset(output, 0);
                continue;
            };
            if (!runtime.?.process(Sample, input, output)) {
                @memset(output, 0);
                runtime.?.reset();
            }
        }
    }

    pub fn reset(self: *Processor) void {
        if (self.models.activeMutable()) |runtime| runtime.reset();
    }

    fn fastActivationNormalized(parameters: anytype, fallback: f64) f64 {
        if (comptime @TypeOf(parameters) == @TypeOf(undefined)) return fallback;
        return parameters.values.view(parameters.set).loadNormalized("fast_activation");
    }
};

pub const ModelShell = struct {
    pub const name = "zig-vst3 Model Shell";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .mono;
    pub const event_input = false;
    pub const Params = struct {
        fast_activation: plug.parameters.BoolParam = .{
            .id = 0,
            .name = "Fast Activation",
            .default = false,
        },
    };
};

pub const RuntimeProcessor = struct {
    pub const name = ModelShell.name;
    pub const vendor = ModelShell.vendor;
    pub const audio_input_layout = ModelShell.audio_input_layout;
    pub const audio_output_layout = ModelShell.audio_output_layout;
    pub const event_input = ModelShell.event_input;
    pub const Params = ModelShell.Params;
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

    pub fn prepare(
        self: *RuntimeProcessor,
        config: plug.plugin.PrepareConfig,
    ) void {
        self.engine.prepare(config);
    }

    pub fn reset(self: *RuntimeProcessor) void {
        self.engine.reset();
    }

    pub fn bindHostRequests(
        self: *RuntimeProcessor,
        requests: *plug.HostRequestSink,
    ) void {
        self.engine.bindHostRequests(requests);
    }

    pub fn latencySamples(self: *const RuntimeProcessor) u32 {
        return self.engine.latencySamples();
    }

    pub fn resourcePathReceiver(
        self: *RuntimeProcessor,
    ) *ModelRecovery {
        return self.engine.resourcePathReceiver();
    }

    pub fn guiTelemetryLoad(
        self: *RuntimeProcessor,
        source_id: u32,
    ) f64 {
        return self.engine.guiTelemetryLoad(source_id);
    }

    pub fn guiTelemetryLoadText(
        self: *RuntimeProcessor,
        source_id: u32,
        output: []u8,
    ) usize {
        return self.engine.guiTelemetryLoadText(source_id, output);
    }

    pub fn componentStateEncodedSize(
        self: *const RuntimeProcessor,
    ) usize {
        return self.engine.componentStateEncodedSize();
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

    pub fn processWithParameterView(
        self: *RuntimeProcessor,
        context: *plug.process.ProcessContext(f32),
        parameters: plug.parameters.ParameterView(Params),
    ) void {
        self.engine.process(parameters, f32, context);
    }

    pub fn process64WithParameterView(
        self: *RuntimeProcessor,
        context: *plug.process.ProcessContext(f64),
        parameters: plug.parameters.ParameterView(Params),
    ) void {
        self.engine.process(parameters, f64, context);
    }

    pub fn importModel(
        self: *RuntimeProcessor,
        path: []const u8,
    ) bool {
        return self.engine.importModel(path);
    }

    pub fn relinkModel(
        self: *RuntimeProcessor,
        path: []const u8,
    ) bool {
        return self.engine.relinkModel(path);
    }

    pub fn waitForModel(self: *RuntimeProcessor) void {
        self.engine.waitForModel();
    }

    pub fn maintain(self: *RuntimeProcessor) usize {
        return self.engine.maintain();
    }

    pub fn resourceSnapshot(
        self: *const RuntimeProcessor,
    ) ModelRecovery.Snapshot {
        return self.engine.resourceSnapshot();
    }

    pub fn deinit(self: *RuntimeProcessor) void {
        self.engine.deinit();
        self.allocator.destroy(self.engine);
    }
};

pub const parameter_set = plug.parameters.ParameterSet(ModelShell.Params).init(.{});

test "model shell runtime reports outer allocation failure" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        RuntimeProcessor.init(failing.allocator()),
    );
}

test "model shell runtime preserves stable recovery ownership and both precisions" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "runtime.json",
        .data = "{\"version\":1,\"gain\":2.0,\"sample_rate\":48000}",
    });
    var path: [maximum_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(
        std.testing.io,
        "runtime.json",
        &path,
    );

    var runtime = try RuntimeProcessor.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectEqual(
        runtime.engine.resourcePathReceiver(),
        runtime.resourcePathReceiver(),
    );
    try std.testing.expect(runtime.importModel(path[0..path_length]));
    runtime.waitForModel();
    try std.testing.expectEqual(
        plug.resource.RecoveryStatus.ready,
        runtime.resourceSnapshot().status,
    );

    const Values = plug.parameters.ParameterValues(ModelShell.Params);
    var values = Values.init(&parameter_set);
    const parameters = values.view(&parameter_set);

    const input32 = [_]f32{ 0.25, -0.5 };
    var output32 = [_]f32{ 0.0, 0.0 };
    const inputs32 = [_][]const f32{&input32};
    const outputs32 = [_][]f32{&output32};
    var context32 = try plug.process.ProcessContext(f32).init(
        48_000,
        &inputs32,
        &outputs32,
    );
    runtime.processWithParameterView(&context32, parameters);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.25, -0.375 },
        &output32,
    );

    runtime.reset();
    const input64 = [_]f64{ 0.25, -0.5 };
    var output64 = [_]f64{ 0.0, 0.0 };
    const inputs64 = [_][]const f64{&input64};
    const outputs64 = [_][]f64{&output64};
    var context64 = try plug.process.ProcessContext(f64).init(
        48_000,
        &inputs64,
        &outputs64,
    );
    runtime.process64WithParameterView(&context64, parameters);
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.25, -0.375 },
        &output64,
    );
}

test "model shell activation quality is isolated per instance" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = "{\"version\":1,\"gain\":1.0,\"sample_rate\":48000}";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "linear.json", .data = fixture });
    var path_bytes: [maximum_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "linear.json", &path_bytes);

    var accurate: Processor = undefined;
    accurate.initInPlace();
    defer accurate.deinit();
    var fast: Processor = undefined;
    fast.initInPlace();
    defer fast.deinit();
    try std.testing.expect(accurate.importModel(path_bytes[0..path_length]));
    try std.testing.expect(fast.importModel(path_bytes[0..path_length]));
    accurate.waitForModel();
    fast.waitForModel();

    const Values = plug.parameters.ParameterValues(ModelShell.Params);
    const Parameters = struct {
        set: *const @TypeOf(parameter_set),
        values: Values,
    };
    var accurate_parameters = Parameters{ .set = &parameter_set, .values = Values.init(&parameter_set) };
    var fast_parameters = Parameters{ .set = &parameter_set, .values = Values.init(&parameter_set) };
    try std.testing.expect(fast_parameters.values.storeField(&parameter_set, "fast_activation", true));

    const input = [_]f32{0.25};
    var accurate_output = [_]f32{0.0};
    var fast_output = [_]f32{0.0};
    const inputs = [_][]const f32{&input};
    const accurate_outputs = [_][]f32{&accurate_output};
    const fast_outputs = [_][]f32{&fast_output};
    var accurate_context = try plug.process.ProcessContext(f32).init(48_000, &inputs, &accurate_outputs);
    var fast_context = try plug.process.ProcessContext(f32).init(48_000, &inputs, &fast_outputs);

    accurate.process(&accurate_parameters, f32, &accurate_context);
    fast.process(&fast_parameters, f32, &fast_context);
    try std.testing.expectEqual(ActivationQuality.accurate, accurate.models.activeMutable().?.activation_quality);
    try std.testing.expectEqual(ActivationQuality.fast, fast.models.activeMutable().?.activation_quality);

    try std.testing.expect(accurate_parameters.values.storeField(&parameter_set, "fast_activation", true));
    accurate.process(&accurate_parameters, f32, &accurate_context);
    try std.testing.expectEqual(ActivationQuality.fast, accurate.models.activeMutable().?.activation_quality);
    try std.testing.expectEqual(ActivationQuality.fast, fast.models.activeMutable().?.activation_quality);

    try std.testing.expect(fast_parameters.values.storeField(&parameter_set, "fast_activation", false));
    fast.process(&fast_parameters, f32, &fast_context);
    try std.testing.expectEqual(ActivationQuality.fast, accurate.models.activeMutable().?.activation_quality);
    try std.testing.expectEqual(ActivationQuality.accurate, fast.models.activeMutable().?.activation_quality);
}

test "model shell activation quality respects process block boundaries" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = "{\"version\":1,\"gain\":1.0,\"sample_rate\":48000}";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "linear.json", .data = fixture });
    var path_bytes: [maximum_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "linear.json", &path_bytes);

    var processor: Processor = undefined;
    processor.initInPlace();
    defer processor.deinit();
    try std.testing.expect(processor.importModel(path_bytes[0..path_length]));
    processor.waitForModel();

    const Values = plug.parameters.ParameterValues(ModelShell.Params);
    const Parameters = struct {
        set: *const @TypeOf(parameter_set),
        values: Values,
    };
    var parameters = Parameters{ .set = &parameter_set, .values = Values.init(&parameter_set) };

    const input = [_]f32{ 0.25, 0.25, 0.25, 0.25 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};

    var initial_context = try plug.process.ProcessContext(f32).init(48_000, &inputs, &outputs);
    processor.process(&parameters, f32, &initial_context);
    try std.testing.expectEqual(ActivationQuality.accurate, processor.models.activeMutable().?.activation_quality);

    try std.testing.expect(parameters.values.storeField(&parameter_set, "fast_activation", true));
    const deferred_changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 2, .normalized = 1.0 },
    };
    var deferred_context = try plug.process.ProcessContext(f32).initWith(48_000, &inputs, &outputs, .{
        .parameter_changes = &deferred_changes,
    });
    processor.process(&parameters, f32, &deferred_context);
    try std.testing.expectEqual(ActivationQuality.accurate, processor.models.activeMutable().?.activation_quality);

    processor.process(&parameters, f32, &initial_context);
    try std.testing.expectEqual(ActivationQuality.fast, processor.models.activeMutable().?.activation_quality);

    try std.testing.expect(parameters.values.storeField(&parameter_set, "fast_activation", false));
    const boundary_changes = [_]plug.process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.0 },
    };
    var boundary_context = try plug.process.ProcessContext(f32).initWith(48_000, &inputs, &outputs, .{
        .parameter_changes = &boundary_changes,
    });
    processor.process(&parameters, f32, &boundary_context);
    try std.testing.expectEqual(ActivationQuality.accurate, processor.models.activeMutable().?.activation_quality);
}

test "model shell restores asynchronously and stays silent when a resource is missing" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = "{\"version\":1,\"gain\":2.0,\"sample_rate\":48000}";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "linear.json", .data = fixture });
    var path_bytes: [maximum_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "linear.json", &path_bytes);

    var first: Processor = undefined;
    first.initInPlace();
    defer first.deinit();
    try std.testing.expect(first.importModel(path_bytes[0..path_length]));
    first.waitForModel();
    try std.testing.expectEqual(plug.resource.RecoveryStatus.ready, first.resourceSnapshot().status);

    var state_bytes: [Processor.component_state_maximum_encoded_size]u8 = undefined;
    var state_writer = std.Io.Writer.fixed(&state_bytes);
    try first.writeComponentState(&state_writer);

    var restored: Processor = undefined;
    restored.initInPlace();
    defer restored.deinit();
    var state_reader = std.Io.Reader.fixed(state_bytes[0..state_writer.end]);
    try restored.readComponentState(&state_reader);
    restored.waitForModel();
    try std.testing.expectEqual(plug.resource.RecoveryStatus.ready, restored.resourceSnapshot().status);
    try std.testing.expectEqual(restored.resourceSnapshot().generation, restored.approval.approved_generation.load(.acquire));
    try std.testing.expectEqual(@as(?u32, 0), if (restored.resourceSnapshot().publication_metadata) |metadata| metadata.latency_samples else null);

    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    var context = try plug.process.ProcessContext(f32).init(48_000, &inputs, &outputs);
    const realtime_scope = plug.realtime_audit.Scope.enter();
    restored.process(undefined, f32, &context);
    try std.testing.expect(restored.models.activeMutable() != null);
    try std.testing.expect(restored.models.activeMutable().?.matches(restored.preparation));
    const first_output = output;
    restored.process(undefined, f32, &context);
    const continued_output = output;
    restored.reset();
    restored.process(undefined, f32, &context);
    const reset_output = output;
    try std.testing.expect(realtime_scope.leave().clean());
    try std.testing.expectEqualSlices(f32, &.{ 0.25, -0.375 }, &first_output);
    try std.testing.expectEqualSlices(f32, &.{ 0.0625, -0.46875 }, &continued_output);
    try std.testing.expectEqualSlices(f32, &.{ 0.25, -0.375 }, &reset_output);

    try temporary.dir.deleteFile(std.testing.io, "linear.json");
    var missing: Processor = undefined;
    missing.initInPlace();
    defer missing.deinit();
    var missing_reader = std.Io.Reader.fixed(state_bytes[0..state_writer.end]);
    try missing.readComponentState(&missing_reader);
    missing.models.preparation.wait();
    try std.testing.expectEqual(plug.resource.RecoveryStatus.missing, missing.resourceSnapshot().status);
    @memset(&output, 1.0);
    missing.process(undefined, f32, &context);
    try std.testing.expectEqualSlices(f32, &.{ 0.0, 0.0 }, &output);
}

test "model shell rejects changed restored content and accepts a matching relink" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const original = "{\"version\":1,\"gain\":2.0,\"sample_rate\":48000}";
    const replacement = "{\"version\":1,\"gain\":3.0,\"sample_rate\":48000}";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "model.json", .data = original });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "moved.json", .data = original });
    var original_path: [maximum_path_bytes]u8 = undefined;
    const original_length = try temporary.dir.realPathFile(std.testing.io, "model.json", &original_path);
    var moved_path: [maximum_path_bytes]u8 = undefined;
    const moved_length = try temporary.dir.realPathFile(std.testing.io, "moved.json", &moved_path);

    var processor: Processor = undefined;
    processor.initInPlace();
    defer processor.deinit();
    try std.testing.expect(processor.importModel(original_path[0..original_length]));
    processor.waitForModel();
    var state_bytes: [Processor.component_state_maximum_encoded_size]u8 = undefined;
    var writer = std.Io.Writer.fixed(&state_bytes);
    try processor.writeComponentState(&writer);

    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "model.json", .data = replacement });
    var restored: Processor = undefined;
    restored.initInPlace();
    defer restored.deinit();
    var reader = std.Io.Reader.fixed(state_bytes[0..writer.end]);
    try restored.readComponentState(&reader);
    restored.models.preparation.wait();
    try std.testing.expectEqual(plug.resource.RecoveryStatus.changed, restored.resourceSnapshot().status);
    try std.testing.expect(restored.models.active() == null);
    try std.testing.expect(restored.relinkModel(moved_path[0..moved_length]));
    restored.waitForModel();
    try std.testing.expectEqual(plug.resource.RecoveryStatus.ready, restored.resourceSnapshot().status);
    try std.testing.expectEqual(plug.resource.RecoveryStatus.moved, restored.resourceSnapshot().resolution);
}

test "model shell prepares model-rate conversion before latency-approved adoption" {
    const HostProbe = struct {
        var marks: usize = 0;
        var dispatches: usize = 0;
        var callback_thread = std.atomic.Value(std.Thread.Id).init(0);

        fn mark(
            _: *anyopaque,
            change: plug.HostChange,
        ) void {
            if (change != .latency) return;
            marks += 1;
            callback_thread.store(std.Thread.getCurrentId(), .release);
        }

        fn dispatch(_: *anyopaque) bool {
            dispatches += 1;
            return true;
        }
    };

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const fixture = "{\"version\":1,\"gain\":1.0,\"sample_rate\":48000}";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "fixed-rate.json", .data = fixture });
    var path_bytes: [maximum_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "fixed-rate.json", &path_bytes);

    var processor: Processor = undefined;
    processor.initInPlace();
    defer processor.deinit();
    var sink_context: u8 = 0;
    var sink = plug.HostRequestSink{
        .context = &sink_context,
        .mark_change = HostProbe.mark,
        .dispatch = HostProbe.dispatch,
    };
    HostProbe.marks = 0;
    HostProbe.dispatches = 0;
    HostProbe.callback_thread.store(0, .release);
    processor.bindHostRequests(&sink);
    processor.prepare(.{ .sample_rate = 44_100, .max_block_size = 1024 });
    try std.testing.expect(processor.importModel(path_bytes[0..path_length]));
    processor.waitForModel();
    try std.testing.expectEqual(@as(u32, 31), processor.latencySamples());
    try std.testing.expectEqual(@as(usize, 1), HostProbe.marks);
    try std.testing.expectEqual(@as(usize, 1), HostProbe.dispatches);
    try std.testing.expectEqual(
        std.Thread.getCurrentId(),
        HostProbe.callback_thread.load(.acquire),
    );

    var input: [1024]f32 = @splat(0.0);
    input[0] = 1.0;
    var output: [1024]f32 = undefined;
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    var context = try plug.process.ProcessContext(f32).init(44_100, &inputs, &outputs);
    const scope = plug.realtime_audit.Scope.enter();
    processor.process(undefined, f32, &context);
    try std.testing.expect(scope.leave().clean());
    try std.testing.expect(processor.models.activeMutable().?.resampling);
    var has_output = false;
    for (output) |sample| has_output = has_output or sample != 0.0;
    try std.testing.expect(has_output);

    processor.prepare(.{ .sample_rate = 96_000, .max_block_size = 257 });
    var replacement_input: [257]f32 = @splat(0.0);
    replacement_input[0] = 1.0;
    var replacement_output: [257]f32 = @splat(1.0);
    const replacement_inputs = [_][]const f32{&replacement_input};
    const replacement_outputs = [_][]f32{&replacement_output};
    var mismatch_context = try plug.process.ProcessContext(f32).init(96_000, &replacement_inputs, &replacement_outputs);
    processor.process(undefined, f32, &mismatch_context);
    for (replacement_output) |sample| try std.testing.expectEqual(@as(f32, 0.0), sample);

    processor.waitForModel();
    try std.testing.expectEqual(@as(u32, 48), processor.latencySamples());
    try std.testing.expectEqual(@as(usize, 2), HostProbe.marks);
    try std.testing.expectEqual(@as(usize, 2), HostProbe.dispatches);
    processor.process(undefined, f32, &mismatch_context);
    const active = processor.models.activeMutable().?;
    try std.testing.expectEqual(@as(f64, 96_000), active.host_rate);
    try std.testing.expectEqual(@as(u32, 257), active.max_block_size);
}

test "model shell survives repeated preparation replacement and randomized blocks" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_bytes: [maximum_path_bytes]u8 = undefined;
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "replaced.json",
        .data = "{\"version\":1,\"gain\":1.0,\"sample_rate\":48000}",
    });
    const path_length = try temporary.dir.realPathFile(std.testing.io, "replaced.json", &path_bytes);

    var processor: Processor = undefined;
    processor.initInPlace();
    defer processor.deinit();
    var random = std.Random.DefaultPrng.init(0x4d4f_4445_4c53_484c);
    const host_rates = [_]f64{ 44_100, 48_000, 88_200, 96_000 };
    const model_rates = [_]u32{ 48_000, 44_100, 48_000, 96_000 };

    for (0..32) |iteration| {
        const host_rate = host_rates[iteration % host_rates.len];
        const model_rate = model_rates[iteration % model_rates.len];
        const max_block_size = random.random().intRangeAtMost(u32, 1, 257);
        var fixture_bytes: [128]u8 = undefined;
        const fixture = try std.fmt.bufPrint(&fixture_bytes, "{{\"version\":1,\"gain\":{d:.3},\"sample_rate\":{}}}", .{
            0.5 + @as(f64, @floatFromInt(iteration % 7)) * 0.125,
            model_rate,
        });
        try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "replaced.json", .data = fixture });
        processor.prepare(.{ .sample_rate = host_rate, .max_block_size = max_block_size });
        try std.testing.expect(processor.importModel(path_bytes[0..path_length]));
        processor.waitForModel();
        const snapshot = processor.resourceSnapshot();
        try std.testing.expectEqual(plug.resource.RecoveryStatus.ready, snapshot.status);
        try std.testing.expectEqual(snapshot.generation, processor.approval.approved_generation.load(.acquire));

        const frame_count = random.random().intRangeAtMost(usize, 1, max_block_size);
        if (iteration % 2 == 0) {
            var input: [257]f32 = undefined;
            var first: [257]f32 = undefined;
            var reset: [257]f32 = undefined;
            for (input[0..frame_count]) |*sample| sample.* = random.random().float(f32) * 2.0 - 1.0;
            const inputs = [_][]const f32{input[0..frame_count]};
            const first_outputs = [_][]f32{first[0..frame_count]};
            var first_context = try plug.process.ProcessContext(f32).init(host_rate, &inputs, &first_outputs);
            const scope = plug.realtime_audit.Scope.enter();
            processor.process(undefined, f32, &first_context);
            processor.reset();
            const reset_outputs = [_][]f32{reset[0..frame_count]};
            var reset_context = try plug.process.ProcessContext(f32).init(host_rate, &inputs, &reset_outputs);
            processor.process(undefined, f32, &reset_context);
            try std.testing.expect(scope.leave().clean());
            try std.testing.expectEqualSlices(f32, first[0..frame_count], reset[0..frame_count]);
            for (first[0..frame_count]) |sample| try std.testing.expect(std.math.isFinite(sample));
        } else {
            var input: [257]f64 = undefined;
            var first: [257]f64 = undefined;
            var reset: [257]f64 = undefined;
            for (input[0..frame_count]) |*sample| sample.* = random.random().float(f64) * 2.0 - 1.0;
            const inputs = [_][]const f64{input[0..frame_count]};
            const first_outputs = [_][]f64{first[0..frame_count]};
            var first_context = try plug.process.ProcessContext(f64).init(host_rate, &inputs, &first_outputs);
            const scope = plug.realtime_audit.Scope.enter();
            processor.process(undefined, f64, &first_context);
            processor.reset();
            const reset_outputs = [_][]f64{reset[0..frame_count]};
            var reset_context = try plug.process.ProcessContext(f64).init(host_rate, &inputs, &reset_outputs);
            processor.process(undefined, f64, &reset_context);
            try std.testing.expect(scope.leave().clean());
            try std.testing.expectEqualSlices(f64, first[0..frame_count], reset[0..frame_count]);
            for (first[0..frame_count]) |sample| try std.testing.expect(std.math.isFinite(sample));
        }

        const active = processor.models.activeMutable().?;
        try std.testing.expect(active.matches(processor.preparation));
        _ = processor.maintain();
    }
}

test "model shell joins pending preparation during repeated teardown" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "teardown.json",
        .data = "{\"version\":1,\"gain\":1.0,\"sample_rate\":48000}",
    });
    var path_bytes: [maximum_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPathFile(std.testing.io, "teardown.json", &path_bytes);

    for (0..32) |iteration| {
        var processor: Processor = undefined;
        processor.initInPlace();
        processor.prepare(.{
            .sample_rate = if (iteration % 2 == 0) 44_100 else 96_000,
            .max_block_size = 257,
        });
        try std.testing.expect(processor.importModel(path_bytes[0..path_length]));
        processor.deinit();
    }
}
