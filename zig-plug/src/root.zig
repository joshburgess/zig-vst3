const std = @import("std");
const vst3 = @import("vst3-zig");

pub const core = @import("core.zig");
pub const parameters = core.parameters;
pub const plugin = core.plugin;
pub const process = core.process;
pub const version = "0.1.0-dev";

pub fn backendVersion() []const u8 {
    return vst3.version;
}

test "zig-plug sees vst3-zig" {
    try std.testing.expectEqualStrings("0.1.0-dev", backendVersion());
}
