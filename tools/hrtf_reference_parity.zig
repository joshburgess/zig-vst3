const plugin = @import("zig-vst3-plugin");
const std = @import("std");

const ReferenceQuery = extern struct {
    azimuth_degrees: f64,
    elevation_degrees: f64,
};

comptime {
    if (@sizeOf(ReferenceQuery) != 16 or
        @offsetOf(ReferenceQuery, "elevation_degrees") != 8)
    {
        @compileError("unexpected HRTF reference query layout");
    }
}

extern fn hrtf_reference_render(
    path: [*:0]const u8,
    queries: [*]const ReferenceQuery,
    query_count: usize,
    maximum_frames: usize,
    output: [*]f32,
    output_count: usize,
    measurement_count_output: *usize,
    frame_count_output: *usize,
) c_int;

const DatasetKind = enum {
    viking,
    hutubs,
};

const maximum_queries = 4;
const method_count = 2;
const channel_count = 2;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.InvalidArguments;
    const kind = std.meta.stringToEnum(DatasetKind, args[1]) orelse
        return error.InvalidDatasetKind;
    switch (kind) {
        .viking => try compareDataset(
            1_513,
            128,
            allocator,
            init.io,
            args[2],
            .{
                .{ .azimuth_degrees = 0.0, .elevation_degrees = -45.0 },
                .{ .azimuth_degrees = -2.5, .elevation_degrees = -45.0 },
                .{ .azimuth_degrees = 37.5, .elevation_degrees = 12.5 },
                .{ .azimuth_degrees = 177.5, .elevation_degrees = 42.5 },
            },
        ),
        .hutubs => try compareDataset(
            440,
            256,
            allocator,
            init.io,
            args[2],
            .{
                .{ .azimuth_degrees = 0.0, .elevation_degrees = 90.0 },
                .{ .azimuth_degrees = 30.0, .elevation_degrees = 75.0 },
                .{ .azimuth_degrees = 12.0, .elevation_degrees = 65.0 },
                .{ .azimuth_degrees = -15.0, .elevation_degrees = -35.0 },
            },
        ),
    }
}

fn compareDataset(
    comptime maximum_measurements: usize,
    comptime maximum_frames: usize,
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    queries: [maximum_queries]ReferenceQuery,
) !void {
    const Loader = plugin.dsp.HrtfSofaLoader(
        maximum_measurements,
        maximum_frames,
    );
    var loader = try Loader.openDefault();
    defer loader.deinit();

    const Database = plugin.dsp.HrtfDatabase(
        maximum_measurements,
        maximum_frames,
    );
    const database = try allocator.create(Database);
    try loader.loadFileInto(allocator, path, database);

    const sample_count = std.math.mul(
        usize,
        queries.len * method_count * channel_count,
        database.response_frame_count,
    ) catch return error.ReferenceStorageOverflow;
    const reference = try allocator.alloc(f32, sample_count);
    const terminated_path = try allocator.dupeZ(u8, path);
    try verifyReferenceRejection(
        terminated_path,
        queries,
        maximum_frames,
        database.response_frame_count,
        reference,
    );
    var reference_measurements: usize = 0;
    var reference_frames: usize = 0;
    const status = hrtf_reference_render(
        terminated_path,
        &queries,
        queries.len,
        maximum_frames,
        reference.ptr,
        reference.len,
        &reference_measurements,
        &reference_frames,
    );
    if (status != 0) {
        std.debug.print("HRTF reference failed with status {d}\n", .{status});
        return error.HrtfReferenceFailed;
    }
    if (reference_measurements != database.measurement_count or
        reference_frames != database.response_frame_count)
    {
        return error.HrtfReferenceShapeMismatch;
    }

    var actual: [maximum_frames * channel_count]f32 = undefined;
    for (queries, 0..) |query, query_index| {
        const direction = plugin.dsp.HrtfDirection{
            .azimuth_degrees = query.azimuth_degrees,
            .elevation_degrees = query.elevation_degrees,
        };
        inline for (.{
            plugin.dsp.HrtfInterpolation.inverse_distance,
            plugin.dsp.HrtfInterpolation.spectral,
        }, 0..) |method, method_index| {
            const samples = actual[0 .. database.response_frame_count * 2];
            try database.interpolate(direction, method, samples);
            const reference_offset =
                (query_index * method_count + method_index) *
                database.response_frame_count * channel_count;
            try compareSamples(
                samples,
                reference[reference_offset .. reference_offset + samples.len],
            );
        }
    }

    var stdout = std.Io.File.stdout().writer(io, &.{});
    try stdout.interface.print(
        "matched {d} full-response HRTF comparisons across {d} measurements and {d} frames\n",
        .{
            queries.len * method_count,
            database.measurement_count,
            database.response_frame_count,
        },
    );
}

fn verifyReferenceRejection(
    path: [:0]const u8,
    queries: [maximum_queries]ReferenceQuery,
    maximum_frames: usize,
    frame_count: usize,
    storage: []f32,
) !void {
    const sentinel: f32 = 123.25;
    @memset(storage, sentinel);
    var measurement_output: usize = 41;
    var frame_output: usize = 43;
    const short_status = hrtf_reference_render(
        path,
        &queries,
        queries.len,
        maximum_frames,
        storage.ptr,
        storage.len - 1,
        &measurement_output,
        &frame_output,
    );
    if (short_status != 5 or
        measurement_output != 41 or
        frame_output != 43 or
        !allSamplesEqual(storage, sentinel))
    {
        return error.NonTransactionalHrtfReferenceRejection;
    }

    const invalid_queries = [1]ReferenceQuery{.{
        .azimuth_degrees = std.math.nan(f64),
        .elevation_degrees = 0.0,
    }};
    const invalid_storage_count = frame_count * method_count * channel_count;
    const invalid_status = hrtf_reference_render(
        path,
        &invalid_queries,
        invalid_queries.len,
        maximum_frames,
        storage.ptr,
        invalid_storage_count,
        &measurement_output,
        &frame_output,
    );
    if (invalid_status != 6 or
        measurement_output != 41 or
        frame_output != 43 or
        !allSamplesEqual(storage, sentinel))
    {
        return error.NonTransactionalHrtfReferenceRejection;
    }
}

fn allSamplesEqual(samples: []const f32, expected: f32) bool {
    for (samples) |sample| {
        if (sample != expected) return false;
    }
    return true;
}

fn compareSamples(actual: []const f32, reference: []const f32) !void {
    if (actual.len != reference.len) return error.HrtfReferenceShapeMismatch;
    for (actual, reference) |actual_sample, reference_sample| {
        if (!std.math.isFinite(actual_sample) or
            !std.math.isFinite(reference_sample))
        {
            return error.NonFiniteHrtfReferenceSample;
        }
        const tolerance = 2.0e-6 +
            2.0e-5 * @max(@abs(actual_sample), @abs(reference_sample));
        if (@abs(actual_sample - reference_sample) > tolerance)
            return error.HrtfReferenceMismatch;
    }
}
