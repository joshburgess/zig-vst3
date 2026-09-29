const implementation = @import("plugin/alsa_midi.zig");

pub const Backend = implementation.AlsaMidiBackend;
pub const InputStatistics = implementation.InputStatistics;
pub const maximum_input_bytes_per_callback =
    implementation.maximum_input_bytes_per_callback;

test {
    _ = implementation;
}
