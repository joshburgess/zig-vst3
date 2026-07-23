const plugin = @import("zig-vst3-plugin");
const std = @import("std");

const GainModel = struct {
    gain: f32,

    pub fn reset(_: *GainModel) void {}

    pub fn processBlock(self: *GainModel, input: []const f32, output: []f32) void {
        for (input, output) |sample, *destination| destination.* = sample * self.gain;
    }
};

const Runtime = struct { state: f32 };
const RuntimeExchange = plugin.resource.exchange.Exchange(struct {
    pub const Resource = Runtime;
    pub const slot_capacity = 2;
    pub const mutable_active = true;

    pub fn destroy(runtime: *Runtime) void {
        std.testing.allocator.destroy(runtime);
    }
});

const InstalledRecovery = plugin.resource.ResourceRecovery(struct {
    pub const Resource = u8;
    pub const Failure = enum { unavailable };
    pub const path_capacity = 64;
    pub const metadata_capacity = 32;
    pub const slot_capacity = 2;
    pub const maximum_work_units = 1;
    pub const maximum_result_units = 1;

    pub fn prepare(_: plugin.resource.BoundedPath(path_capacity), _: *plugin.resource.job.WorkerContext) plugin.resource.job.Outcome(
        plugin.resource.PreparedResource(Resource, metadata_capacity),
        Failure,
    ) {
        return .{ .failure = .unavailable };
    }

    pub fn destroy(resource: *Resource) void {
        std.testing.allocator.destroy(resource);
    }

    pub fn failureStatus(_: Failure) plugin.resource.RecoveryStatus {
        return .failed;
    }
});

test "installed package exposes DSP fixture rendering and comparison" {
    const input = [_]f32{ -1.0, -0.5, 0.0, 0.5, 1.0 };
    const expected = [_]f32{ -0.25, -0.125, 0.0, 0.125, 0.25 };
    var output: [input.len]f32 = undefined;
    var model = GainModel{ .gain = 0.25 };
    const processor = plugin.dsp.BlockProcessor(f32).init(GainModel, &model);

    try plugin.dsp.fixture_runner.renderFixed(f32, processor, &input, &output, 2);
    const comparison = try plugin.dsp.fixture_runner.compare(f32, &expected, &output, .{
        .maximum_absolute = 0.0,
        .maximum_relative = 0.0,
        .maximum_rms = 0.0,
    });
    try std.testing.expect(comparison.passed);
}

test "installed package exposes exclusive mutable runtime adoption" {
    var exchange: RuntimeExchange = .{};
    defer exchange.deinit();
    const runtime = try std.testing.allocator.create(Runtime);
    runtime.* = .{ .state = 0.0 };
    try exchange.publish(1, runtime);
    _ = exchange.adoptPending();
    exchange.activeMutable().?.resource.state = 0.5;
    try std.testing.expectEqual(@as(f32, 0.5), exchange.activeMutable().?.resource.state);
    try std.testing.expect(exchange.retireActiveAtBlockBoundary());
}

test "installed package exposes bounded resource presentation" {
    var recovery = InstalledRecovery.init();
    defer recovery.deinit();
    const presentation = recovery.presentationSnapshot();
    try std.testing.expectEqual(plugin.resource.RecoveryStatus.empty, presentation.status);
    try std.testing.expectEqual(plugin.gui_progress.State.idle, presentation.progress.state);
    try std.testing.expectEqualStrings("empty", presentation.statusText());
    try std.testing.expectEqualStrings("", presentation.metadata());
    try presentation.progress.validate();
}

test "installed package exposes validated DSP and telemetry state" {
    var filter = plugin.dsp.SmoothedBiquad(f64){};
    filter.setImmediate(.{ .b0 = std.math.nan(f64) });
    try std.testing.expect(filter.current.valid());
    try std.testing.expectEqual(@as(f64, 0.5), filter.process(0.5));

    const Resampler = plugin.dsp.StreamingResampler(f64);
    var resampler = try Resampler.init(.{ .input_rate = 48_000, .output_rate = 48_000 });
    try std.testing.expect(resampler.validState());
    resampler.next_output_index = plugin.dsp.resampler.maximum_timeline_index;
    resampler.input_rate = 2_000_000;
    resampler.output_rate = 1_000;
    try std.testing.expect(!resampler.validState());

    const Pipeline = plugin.dsp.FixedRatePipeline(f64);
    var pipeline = try Pipeline.init(.{ .host_rate = 48_000, .model_rate = 48_000 });
    try std.testing.expect(pipeline.validState());
    pipeline.latency_samples +%= 1;
    try std.testing.expect(!pipeline.validState());

    var snapshot = plugin.gui_telemetry.ScalarSnapshot(f64).init(std.math.nan(f64));
    try std.testing.expectEqual(@as(f64, 0.0), snapshot.load());
    snapshot.store(0.75);
    snapshot.store(std.math.inf(f64));
    try std.testing.expectEqual(@as(f64, 0.75), snapshot.load());
}

test "installed package exposes validated IR editor snapshots" {
    const snapshot = plugin.gui_ir_editor.Snapshot{
        .import = .{
            .status = .ready,
            .entry_point = .picker,
            .path_count = 1,
            .completed_units = 4,
            .total_units = 4,
            .generation = 1,
            .cancellation_pending = false,
        },
        .sample_rate = 48_000,
        .channels = 1,
        .sample_frames = 4,
        .decoded_frames = 4,
        .original_frames = 4,
        .original_peak = 0.5,
        .edited_peak = 0.5,
        .edited = false,
    };
    try snapshot.validate(4);
    try std.testing.expect(snapshot.valid(4));

    var malformed = snapshot;
    malformed.original_frames = 3;
    try std.testing.expect(!malformed.valid(4));
}

test "installed package exposes bounded audio handoff metadata" {
    const sample = plugin.gui_audio_sample_store.Metadata{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 2,
        .frames = 32,
    };
    try sample.validate(32);
    try std.testing.expect(sample.valid(32));

    const impulse = plugin.gui_ir_convolution.Metadata{
        .generation = 1,
        .sample_rate = 48_000,
        .channels = 1,
        .frames = 64,
    };
    try impulse.validate(64);
    try std.testing.expect(impulse.valid(64));
}

test "installed package exposes coherent audio import snapshots" {
    const snapshot = plugin.gui_audio_file_importer.Snapshot{
        .import = .{
            .status = .ready,
            .entry_point = .picker,
            .path_count = 1,
            .completed_units = 16,
            .total_units = 16,
            .generation = 1,
            .cancellation_pending = false,
        },
        .failure = .none,
        .sample_rate = 48_000,
        .channels = 2,
        .sample_frames = 8,
        .preview_points = 8,
        .decoded_frames = 8,
    };
    try snapshot.validate();
    try std.testing.expect(snapshot.valid());

    var malformed = snapshot;
    malformed.failure = .truncated;
    try std.testing.expect(!malformed.valid());
    try std.testing.expect(snapshot.import.valid());
}
