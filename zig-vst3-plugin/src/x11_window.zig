const std = @import("std");
const implementation = @import("plugin/x11_window.zig");

pub const Backend = implementation.X11WindowBackend;

test {
    std.testing.refAllDecls(implementation);
}
