const std = @import("std");
const implementation = @import("plugin/core_midi.zig");

pub const Backend = implementation.CoreMidiBackend;
pub const InputStatistics = implementation.InputStatistics;
pub const Timebase = implementation.Timebase;
pub const maximum_input_bytes_per_callback =
    implementation.maximum_input_bytes_per_callback;

test {
    std.testing.refAllDecls(implementation);
}
