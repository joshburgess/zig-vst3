const std = @import("std");
const implementation = @import("plugin/core_midi.zig");

pub const Backend = implementation.CoreMidiBackend;
pub const InputStatistics = implementation.InputStatistics;
pub const Timebase = implementation.Timebase;

test {
    std.testing.refAllDecls(implementation);
}
