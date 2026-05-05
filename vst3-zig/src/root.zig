const std = @import("std");

pub const funknown = @import("funknown.zig");
pub const multi_interface = @import("multi_interface.zig");
pub const tuid = @import("tuid.zig");
pub const version = "0.1.0-dev";

pub fn targetName() []const u8 {
    return @tagName(@import("builtin").target.os.tag);
}

test "vst3-zig module exposes a development version" {
    try std.testing.expect(std.mem.endsWith(u8, version, "-dev"));
}
