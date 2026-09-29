const implementation = @import("plugin/alsa.zig");

pub const Backend = implementation.AlsaBackend;
pub const BoundedBackend = implementation.BoundedAlsaBackend;
pub const Statistics = implementation.Statistics;

test {
    _ = implementation;
}
