const std = @import("std");
const implementation = @import("plugin/win_window.zig");

pub const Backend = implementation.Win32WindowBackend;

test {
    std.testing.refAllDecls(implementation);
}
