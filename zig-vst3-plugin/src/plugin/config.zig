const common = @import("../common.zig");
const process = @import("../process.zig");
const std = @import("std");

pub const PrepareConfig = struct {
    sample_rate: f64,
    max_block_size: u32,
    process_mode: process.ProcessMode = .realtime,

    pub fn validate(self: PrepareConfig) !void {
        if (!common.isPositiveFinite(self.sample_rate)) return error.InvalidSampleRate;
        if (self.max_block_size == 0) return error.InvalidMaxBlockSize;
    }
};

test "prepare config accepts positive finite sample rates and nonzero block sizes" {
    try (PrepareConfig{ .sample_rate = 44_100.0, .max_block_size = 1 }).validate();
    const offline = PrepareConfig{ .sample_rate = 192_000.0, .max_block_size = 4096, .process_mode = .offline };
    try offline.validate();
    try std.testing.expectEqual(process.ProcessMode.offline, offline.process_mode);
}

test "prepare config rejects invalid sample rates" {
    try std.testing.expectError(error.InvalidSampleRate, (PrepareConfig{ .sample_rate = 0.0, .max_block_size = 64 }).validate());
    try std.testing.expectError(error.InvalidSampleRate, (PrepareConfig{ .sample_rate = -44_100.0, .max_block_size = 64 }).validate());
    try std.testing.expectError(error.InvalidSampleRate, (PrepareConfig{ .sample_rate = std.math.inf(f64), .max_block_size = 64 }).validate());
    try std.testing.expectError(error.InvalidSampleRate, (PrepareConfig{ .sample_rate = std.math.nan(f64), .max_block_size = 64 }).validate());
}

test "prepare config rejects zero block size" {
    try std.testing.expectError(error.InvalidMaxBlockSize, (PrepareConfig{ .sample_rate = 48_000.0, .max_block_size = 0 }).validate());
}
