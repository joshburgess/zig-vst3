const std = @import("std");
const implementation = @import("plugin/wasapi.zig");

pub const Backend = implementation.WasapiBackend;
pub const BoundedBackend = implementation.BoundedWasapiBackend;
pub const Statistics = implementation.Statistics;

test {
    std.testing.refAllDecls(implementation);
}
