const implementation = @import("plugin/alsa_midi.zig");

pub const Backend = implementation.AlsaMidiBackend;
pub const InputStatistics = implementation.InputStatistics;

test {
    _ = implementation;
}
