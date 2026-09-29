const std = @import("std");
const implementation = @import("plugin/win_midi.zig");

pub const Backend = implementation.WinMidiBackend;
pub const InputStatistics = implementation.InputStatistics;

test {
    std.testing.refAllDecls(implementation);
}
