const implementation = @import("plugin/pipewire.zig");

pub const Backend = implementation.PipeWireBackend;
pub const BoundedBackend = implementation.BoundedPipeWireBackend;
pub const Statistics = implementation.Statistics;

test {
    _ = implementation;
}
