const implementation = @import("plugin/win_ump.zig");

pub const Backend = implementation.WinUmpBackend;
pub const InputStatistics = implementation.InputStatistics;
pub const OutputStatistics = implementation.OutputStatistics;

test {
    _ = implementation;
}
