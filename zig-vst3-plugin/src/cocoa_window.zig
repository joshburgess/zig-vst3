const std = @import("std");
const implementation = @import("plugin/cocoa_window.zig");

pub const Backend = implementation.CocoaWindowBackend;

test {
    std.testing.refAllDecls(implementation);
}
