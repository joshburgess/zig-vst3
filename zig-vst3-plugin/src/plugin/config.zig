const std = @import("std");

pub const PrepareConfig = struct {
    sample_rate: f64,
    max_block_size: u32,

    pub fn validate(self: PrepareConfig) !void {
        if (self.sample_rate <= 0.0 or !std.math.isFinite(self.sample_rate)) return error.InvalidSampleRate;
        if (self.max_block_size == 0) return error.InvalidMaxBlockSize;
    }
};
