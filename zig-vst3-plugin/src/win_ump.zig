const implementation = @import("plugin/win_ump.zig");

pub const Backend = implementation.WinUmpBackend;
pub const InputStatistics = implementation.InputStatistics;
pub const OutputStatistics = implementation.OutputStatistics;
pub const maximum_input_words_per_callback =
    implementation.maximum_input_words_per_callback;

test {
    _ = implementation;
}
