const implementation = @import("zig-vst3-native-ump");

pub const Backend = implementation.AlsaUmpBackend;
pub const InputStatistics = implementation.InputStatistics;
pub const OutputStatistics = implementation.OutputStatistics;
pub const maximum_input_words_per_callback =
    implementation.maximum_input_words_per_callback;

test {
    _ = implementation;
}
