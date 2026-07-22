const std = @import("std");
const plug = @import("zig-vst3-plugin");

const maximum_model_bytes = 4096;
const maximum_path_bytes = 1024;
const maximum_metadata_bytes = 96;

pub const LinearModel = struct {
    gain: f32,
    sample_rate: u32,
};

pub const LoadFailure = enum {
    missing,
    too_large,
    malformed,
    unsupported,
    allocation_failed,
};

const ModelPath = plug.resource.BoundedPath(maximum_path_bytes);
const PreparedModel = plug.resource.PreparedResource(LinearModel, maximum_metadata_bytes);

const ModelRecovery = plug.resource.ResourceRecovery(struct {
    pub const Resource = LinearModel;
    pub const Failure = LoadFailure;
    pub const path_capacity = maximum_path_bytes;
    pub const metadata_capacity = maximum_metadata_bytes;
    pub const slot_capacity = 4;
    pub const maximum_work_units = maximum_model_bytes;
    pub const maximum_result_units = 1;
    pub const maximum_runtime_nanoseconds = 5 * std.time.ns_per_s;

    pub fn prepare(path: ModelPath, context: *plug.resource.job.WorkerContext) plug.resource.job.Outcome(PreparedModel, Failure) {
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

        const model = std.heap.page_allocator.create(LinearModel) catch return .{ .failure = .allocation_failed };
        model.* = .{
            .gain = parsed.value.gain,
            .sample_rate = parsed.value.sample_rate,
        };
        var metadata_bytes: [maximum_metadata_bytes]u8 = undefined;
        const metadata = std.fmt.bufPrint(&metadata_bytes, "Linear, {} Hz, gain {d:.3}", .{
            parsed.value.sample_rate,
            parsed.value.gain,
        }) catch {
            std.heap.page_allocator.destroy(model);
            return .{ .failure = .malformed };
        };
        return .{ .success = .{
            .value = .{
                .resource = model,
                .identity = plug.resource.Identity.fromBytes(bytes[0..count]),
                .resource_schema_version = parsed.value.version,
                .metadata = plug.resource.BoundedMetadata(maximum_metadata_bytes).init(metadata) catch {
                    std.heap.page_allocator.destroy(model);
                    return .{ .failure = .malformed };
                },
            },
            .result_units = 1,
        } };
    }

    pub fn destroy(model: *LinearModel) void {
        std.heap.page_allocator.destroy(model);
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

    pub fn initInPlace(self: *Processor) void {
        self.* = .{ .models = ModelRecovery.init() };
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

    pub fn waitForModel(self: *Processor) void {
        self.models.waitAndPoll();
    }

    pub fn maintain(self: *Processor) usize {
        self.models.poll();
        return self.models.reclaim();
    }

    pub fn resourceSnapshot(self: *const Processor) ModelRecovery.Snapshot {
        return self.models.snapshot();
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

    pub fn process(self: *Processor, _: anytype, comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
        _ = self.models.adoptPendingAtBlockBoundary();
        const model = self.models.active();
        for (0..context.outputChannelCount()) |channel| {
            const output = context.outputChannel(channel) orelse continue;
            if (model == null) {
                @memset(output, 0);
                continue;
            }
            const input = context.inputChannel(channel) orelse {
                @memset(output, 0);
                continue;
            };
            const gain: Sample = @floatCast(model.?.gain);
            for (input, output) |sample, *destination| destination.* = sample * gain;
        }
    }
};

pub const ModelShell = struct {
    pub const name = "zig-vst3 Model Shell";
    pub const vendor = "zig-vst3";
    pub const audio_input_layout: plug.plugin.AudioBusLayout = .mono;
    pub const audio_output_layout: plug.plugin.AudioBusLayout = .mono;
    pub const event_input = false;
    pub const Params = struct {};
};

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
    restored.models.preparation.wait();
    try std.testing.expectEqual(plug.resource.RecoveryStatus.ready, restored.resourceSnapshot().status);

    const input = [_]f32{ 0.25, -0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const inputs = [_][]const f32{&input};
    const outputs = [_][]f32{&output};
    var context = try plug.process.ProcessContext(f32).init(48_000, &inputs, &outputs);
    restored.process(undefined, f32, &context);
    try std.testing.expectEqualSlices(f32, &.{ 0.5, -1.0 }, &output);

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
