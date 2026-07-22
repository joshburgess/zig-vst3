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
