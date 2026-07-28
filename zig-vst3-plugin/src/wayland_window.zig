const std = @import("std");
const implementation = @import("plugin/wayland_window.zig");

pub const Backend = implementation.WaylandWindowBackend;

test {
    std.testing.refAllDecls(implementation);
}
